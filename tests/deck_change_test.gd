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
		_test_parser()
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
		_check_board()
		print("HOST_CHANGE_OK")
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
			game.deck_change._file_selected("res://poker.json")
			_check(game.card_db.deck_instance == old_deck and game.deck_change.confirmation.visible, "local preview is non-mutating")
			game.deck_change.confirmation.hide()
			game.deck_change.request_change.rpc_id(1, "{}")
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

func _check_board() -> void:
	_check(game.card_db.get_all_IDs().size() == 3, "new card count")
	_check(game.card_db.is_front(101) and not game.card_db.is_front(205), "faces preserved")
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
	var source: String = FileAccess.get_file_as_string("res://poker.json")
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
	print("PARSER_OK")
