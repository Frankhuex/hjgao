extends SceneTree

# --headless --path . --script res://tests/deck_change_test.gd -- parser|host|upload|late
const TEST_PORT: int = 28789
const NEW_DECK: String = '{"deck_template":{"ordered_card_templates":[{"name":"杀","count":2,"description":"测试说明"},{"name":"闪","count":1}]},"card_ID_to_card_name":{"101":"杀","205":"闪","303":"杀"},"card_ID_to_is_front":{"101":true,"205":false,"303":true}}'
var game: GameSession
var failed: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, reason: String) -> void:
	if not condition:
		failed = true
		push_error("TEST FAILED: " + reason)
		quit(1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var role: String = args[0] if not args.is_empty() else "parser"
	if role == "parser":
		await _test_parser()
		quit(1 if failed else 0)
		return
	create_timer(35.0).timeout.connect(func() -> void: _check(false, "test timeout"))
	game = (load("res://Game.tscn") as PackedScene).instantiate() as GameSession
	game.set_script(load("res://tests/deck_test_game.gd"))
	game.name = "Game"
	root.add_child(game)
	if role == "host":
		game.set("suppress_auto_host", false)
		game.start_server(TEST_PORT, true)
		_check(game.session_active, "host starts")
		# 留一张旧散牌，验证换库前旧对象全部移除。
		var pile: Pile = game.piles.get_child(0) as Pile
		pile.spawner.server_spawn_card_by_IDs([1])
		print("HOST_READY")
		while not game.card_db.deck_instance.card_ID_to_card_name.has(101) or game.clear_table_in_progress:
			await process_frame
		_check_board(false)
		print("HOST_CHANGE_OK")
		game.card_db.deck_instance.card_ID_to_is_front[101] = false
		game.card_db.deck_instance.card_ID_to_is_upright[101] = false
		await game.server_clear_table()
		_check_board()
		# 为后续重连/迟加入客户端留出验证窗口。
		await create_timer(12.0).timeout
	else:
		game.input_join_IP.text = "127.0.0.1"
		game.input_join_port.text = str(TEST_PORT)
		game._on_join_button_pressed()
		while not game.session_active or game.piles.get_child_count() == 0:
			await process_frame
		if role == "upload":
			await create_timer(0.5).timeout
			var old_deck: DeckInstance = game.card_db.deck_instance
			game.deck_change._file_selected("res://deck_instances/poker.json")
			_check(game.card_db.deck_instance == old_deck and game.deck_change.confirmation.visible, "local preview is non-mutating")
			game.deck_change.confirmation.hide()
			game.deck_change.server_change.rpc_id(1, "{}")
			await create_timer(0.3).timeout
			_check(game.card_db.deck_instance == old_deck, "invalid upload leaves active deck intact")
			var pile: Pile = game.piles.get_child(0) as Pile
			pile.accessor.request_open_viewer()
			await create_timer(0.3).timeout
			# 单独覆盖已有的查看/释放流程，便于区分 OwnerMux 权限切换日志。
			pile.release_local_interaction()
			await create_timer(0.3).timeout
			pile.accessor.request_open_viewer()
			await create_timer(0.3).timeout
			game.deck_change.candidate_json = NEW_DECK
			game.deck_change._submit()
			while not game.card_db.deck_instance.card_ID_to_card_name.has(101) or game.clear_table_in_progress:
				await process_frame
		elif role == "watch":
			print("WATCH_CONNECTED")
			while not game.card_db.deck_instance.card_ID_to_card_name.has(101) or game.clear_table_in_progress:
				await process_frame
		await create_timer(0.5).timeout
		_check_board()
		print(role.to_upper() + "_OK")
		if role == "upload":
			game._return_to_main_menu("测试重连")
			await process_frame
			game._on_join_button_pressed()
			while not game.session_active or game.piles.get_child_count() == 0:
				await process_frame
			await create_timer(0.5).timeout
			_check_board()
			print("RECONNECT_OK")
	game._return_to_main_menu("测试完成")
	await process_frame
	quit(1 if failed else 0)

func _check_board(faces_reset: bool = true) -> void:
	_check(game.card_db.get_all_IDs().size() == 3, "new card count")
	_check(game.card_db.is_front(101) and game.card_db.is_front(205) == faces_reset, "faces reset after clear" if faces_reset else "faces preserved after install")
	_check(game.card_db.is_upright(101), "orientation reset after clear")
	_check(game.card_db.get_card_tooltip_text(101) == "杀: 测试说明", "description loaded")
	_check(game.card_sorter.get_child_count() == 0, "old scattered cards removed")
	var full_piles: int = 0
	for node: Node in game.piles.get_children():
		var pile: Pile = node as Pile
		if not pile.card_ID_stack.is_empty():
			full_piles += 1
			_check(pile.card_ID_stack == [101, 303, 205], "sorted complete public pile")
		else:
			_check(is_zero_approx(pile.global_position.y), "empty pile on table")
	_check(full_piles == 1, "exactly one full pile")

func _test_parser() -> void:
	var source: String = FileAccess.get_file_as_string("res://deck_instances/poker.json")
	var original := DeckJson.parse(source)
	_check(original.deck != null, "poker parses")
	var parsed := DeckJson.parse(NEW_DECK)
	_check(parsed.deck != null, "custom IDs parse")
	var round_trip := DeckJson.parse(parsed.deck.serialize_to_json())
	_check(round_trip.deck.card_ID_to_is_front == parsed.deck.card_ID_to_is_front, "face round trip")
	for text: String in ["{}", "[]", "{", NEW_DECK.replace('"count":2', '"count":2.5'), NEW_DECK.replace('"303":"杀"', '"303":"未知"'), NEW_DECK.replace('"101":"杀"', '"0101":"杀"'), NEW_DECK.replace('"101":true', '"101":"true"'), NEW_DECK.replace('"count":2', '"count":1000000'), NEW_DECK.replace('"name":"闪"', '"name":"杀"')]:
		_check(DeckJson.parse(text).deck == null, "reject invalid deck: " + text)
	var minimal := DeckJson.parse('{"deck_template":{"ordered_card_templates":[{"name":"","count":1}]}}')
	_check(minimal.deck != null and not minimal.deck.card_ID_to_is_front[1], "optional maps and blank-name compatibility")
	var oriented := DeckJson.parse('{"deck_template":{"ordered_card_templates":[{"name":"A","count":2}]},"card_ID_to_is_upright":{"1":true,"2":false}}')
	_check(oriented.deck != null and oriented.deck.card_ID_to_is_upright[1] and not oriented.deck.card_ID_to_is_upright[2], "orientation parses")
	var orientation_round_trip := DeckJson.parse(oriented.deck.serialize_to_json())
	_check(orientation_round_trip.deck.card_ID_to_is_upright == oriented.deck.card_ID_to_is_upright, "orientation round trip")
	for invalid_orientation: String in [
		'{"deck_template":{"ordered_card_templates":[{"name":"A","count":1}]},"card_ID_to_is_upright":{"2":true}}',
		'{"deck_template":{"ordered_card_templates":[{"name":"A","count":1}]},"card_ID_to_is_upright":{"1":"true"}}',
		'{"deck_template":{"ordered_card_templates":[{"name":"A","count":1}]},"card_ID_to_is_upright":{"01":true}}',
	]:
		_check(DeckJson.parse(invalid_orientation).deck == null, "reject invalid orientation")
	await _test_orientation_ui(oriented.deck)
	print("PARSER_OK")

func _test_orientation_ui(deck: DeckInstance) -> void:
	var game := Node.new()
	game.name = "Game"
	root.add_child(game)
	var card_db := CardDatabase.new()
	card_db.name = "CardDatabase"
	game.add_child(card_db)
	card_db.deck_instance = deck
	var tooltip := (load("res://CardDescriptionTooltip.tscn") as PackedScene).instantiate() as CardDescriptionTooltip
	tooltip.name = "CardDescriptionTooltip"
	game.add_child(tooltip)

	var viewer := (load("res://DeckViewerUI.tscn") as PackedScene).instantiate() as DeckViewerUI
	root.add_child(viewer)
	viewer.load_deck([1, 2])
	await process_frame
	_check(viewer.list_top.get_child_count() == 2, "orientation viewer loads cards")
	_check(viewer.btn_all_upright != null and viewer.btn_all_inverted != null and viewer.btn_all_invert != null, "orientation buttons load")
	var upright_card := viewer.list_top.get_child(0) as UICard
	var inverted_card := viewer.list_top.get_child(1) as UICard
	_check(upright_card._visual.rotation == 0.0, "upright card displays upright")
	_check(absf(inverted_card._visual.rotation - PI) < 0.01, "inverted card displays rotated")

	var shift_right_click := InputEventMouseButton.new()
	shift_right_click.button_index = MOUSE_BUTTON_RIGHT
	shift_right_click.pressed = true
	shift_right_click.shift_pressed = true
	var requested_card_ids: Array[int] = []
	upright_card.orientation_requested.connect(func(card_id: int): requested_card_ids.append(card_id))
	upright_card._gui_input(shift_right_click)
	_check(requested_card_ids == [upright_card.card_ID()], "shift right click requests orientation toggle")

	deck.card_ID_to_is_upright[1] = false
	card_db.orientation_changed.emit({1: false})
	await process_frame
	_check(absf(upright_card._visual.rotation - PI) < 0.01, "orientation update rotates card")

	seed(12345)
	card_db.apply_orientation_operation(Const.PileOrientationOperation.RANDOM_FACE, [1, 2])
	await process_frame
	_check(card_db.is_front(1) is bool and card_db.is_front(2) is bool, "random face keeps booleans")
	card_db.apply_orientation_operation(Const.PileOrientationOperation.RANDOM_UPRIGHT, [1, 2])
	await process_frame
	_check(card_db.is_upright(1) is bool and card_db.is_upright(2) is bool, "random upright keeps booleans")

	viewer.queue_free()
	game.queue_free()
	await process_frame
