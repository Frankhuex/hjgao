extends SceneTree

const TEST_PORT := 28804
var game: GameSession
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failed = true
		push_error("PILE TEST FAILED: " + reason)
		quit(1)

func _run() -> void:
	create_timer(40.0).timeout.connect(func(): _check(false, "timeout"))
	game = (load("res://Game.tscn") as PackedScene).instantiate() as GameSession
	game.set_script(load("res://tests/deck_test_game.gd"))
	root.add_child(game)
	var args := OS.get_cmdline_user_args()
	var role := args[0] if not args.is_empty() else "parser"
	if role == "parser" or role == "host":
		game.set("suppress_auto_host", false)
		game.start_server(TEST_PORT, false)
		while not is_instance_valid(game.local_player):
			await process_frame
		if role == "parser":
			await _local_tests()
		else:
			await _host()
	else:
		game.input_join_IP.text = "127.0.0.1"
		game.input_join_port.text = str(TEST_PORT)
		game._on_join_button_pressed()
		while not game.session_active or not is_instance_valid(game.local_player):
			await process_frame
		if role == "client":
			await _client()
		else:
			await _late_join()
	game._return_to_main_menu("测试完成")
	await process_frame
	quit(1 if failed else 0)

func _pile(pile_name: String) -> Pile:
	return game.piles.get_node_or_null(pile_name) as Pile

func _local_tests() -> void:
	game._open_pause_menu()
	game.add_pile_button.pressed.emit()
	var pile := _pile("extra_pile_1")
	_check(pile != null and pile.card_ID_stack.is_empty(), "pause button creates empty pile")
	_check(game.pause_overlay.visible, "pause remains open")
	game._close_pause_menu()
	pile.accessor.request_open_viewer()
	await process_frame
	var viewer := pile.accessor._viewer
	_check(viewer != null and viewer.btn_delete.visible, "empty pile shows delete")
	viewer.btn_delete.pressed.emit()
	_check(viewer.delete_confirmation.visible, "delete confirmation opens")
	viewer.delete_confirmation.hide()
	_check(not pile.is_queued_for_deletion(), "cancel preserves pile")
	game.set_clear_table_busy(true)
	_check(game.add_pile_button.disabled, "busy disables creation")
	game.server_add_pile()
	pile.server_delete_pile()
	_check(_pile("extra_pile_2") == null and not pile.is_queued_for_deletion(), "busy rejects mutations")
	game.set_clear_table_busy(false)
	viewer.delete_confirmation.confirmed.emit()
	await process_frame
	await process_frame
	_check(not is_instance_valid(pile) and not is_instance_valid(viewer), "delete closes viewer")
	var public_pile := _pile("公共牌堆")
	public_pile.accessor.request_open_viewer()
	await process_frame
	viewer = public_pile.accessor._viewer
	_check(not viewer.btn_delete.visible, "nonempty delete hidden")
	for card: Node in viewer.list_top.get_children():
		card.reparent(viewer.list_bottom)
	viewer._refresh_delete_button()
	_check(not viewer.btn_delete.visible, "pending draws do not make pile empty")
	public_pile.server_delete_pile()
	_check(not public_pile.is_queued_for_deletion(), "server rejects nonempty deletion")
	_check(viewer.btn_draw.visible, "pending cards show draw button")
	viewer.btn_draw.pressed.emit()
	await process_frame
	await process_frame
	_check(not is_instance_valid(viewer), "drawing cards frees populated viewer safely")
	_check(public_pile.card_ID_stack.is_empty() and game.card_sorter.get_child_count() > 0, "draw commits cards to table")
	game.server_add_pile()
	game.server_add_pile()
	_check(_pile("extra_pile_2") != null and _pile("extra_pile_3") != null, "unique names after deletion")
	_check(_pile("extra_pile_2").position.distance_to(_pile("extra_pile_3").position) >= 2.0, "free positions")
	var kept_ids: Array[int] = [game.card_db.get_all_IDs()[0]]
	var kept := game.add_pile(kept_ids, "nonempty_test")
	var counter := game.add_counter(Vector3(5, 0, 0))
	var card_count := game.card_sorter.get_child_count()
	game._on_clear_empty_piles_button_pressed()
	_check(game.clear_empty_piles_confirmation.visible, "bulk clear confirmation opens")
	game.clear_empty_piles_confirmation.hide()
	await game.server_clear_empty_piles()
	_check(game.piles.get_child_count() == 1 and is_instance_valid(kept), "bulk clear keeps nonempty pile only")
	_check(is_instance_valid(counter) and game.card_sorter.get_child_count() == card_count, "bulk clear preserves counters and loose cards")
	_check(not game.clear_table_in_progress, "bulk clear unlocks board")
	print("PARSER_OK")

func _host() -> void:
	game.server_add_pile()
	print("HOST_READY")
	while _pile("extra_pile_2") == null or _pile("extra_pile_1") != null:
		await process_frame
	_check(_pile("extra_pile_2").card_ID_stack.is_empty(), "server receives client creation")
	_pile("extra_pile_2").position = Vector3(7, 0, 3)
	while game.player_names.size() > 1:
		await process_frame
	print("HOST_PHASE_OK")
	while game.player_names.size() < 2:
		await process_frame
	while game.player_names.size() > 1:
		await process_frame
	_check(game.piles.get_child_count() == 1, "server sees client's bulk empty-pile deletion")
	print("HOST_OK")

func _client() -> void:
	while _pile("extra_pile_1") == null:
		await process_frame
	var pile := _pile("extra_pile_1")
	await create_timer(0.2).timeout
	_check(pile.position.distance_to(Vector3(3.3, 0, 2.6)) < 0.01, "spawn position replicated")
	pile.request_delete_pile()
	await create_timer(0.2).timeout
	_check(is_instance_valid(pile), "nonowner rejected")
	pile.accessor.request_open_viewer()
	while not pile.accessor.i_am_viewing():
		await process_frame
	var viewer := pile.accessor._viewer
	_check(viewer.btn_delete.visible, "client empty delete visible")
	game.server_add_pile.rpc_id(1)
	while _pile("extra_pile_2") == null:
		await process_frame
	viewer.delete_confirmation.confirmed.emit()
	while is_instance_valid(pile):
		await process_frame
	await process_frame
	_check(not is_instance_valid(viewer), "client viewer cleaned")
	var public_pile := _pile("公共牌堆")
	public_pile.request_delete_pile()
	await create_timer(0.2).timeout
	_check(is_instance_valid(public_pile), "client cannot delete nonempty pile")
	print("CLIENT_OK")

func _late_join() -> void:
	while _pile("extra_pile_2") == null:
		await process_frame
	await create_timer(0.2).timeout
	_check(_pile("extra_pile_1") == null, "deleted pile stays absent")
	_check(_pile("extra_pile_2").card_ID_stack.is_empty(), "late join empty stack")
	_check(_pile("extra_pile_2").position.distance_to(Vector3(7, 0, 3)) < 0.01, "late join position")
	game._on_clear_empty_piles_confirmed()
	while game.piles.get_child_count() != 1 or game.clear_table_in_progress:
		await process_frame
	_check(_pile("公共牌堆") != null and not _pile("公共牌堆").card_ID_stack.is_empty(), "client bulk clear preserves public cards")
	print("LATE_JOIN_OK")
