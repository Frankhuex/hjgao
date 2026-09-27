extends SceneTree

# --headless --path . --script res://tests/chat_test.gd -- parser|host|client|late
const TEST_PORT: int = 28791
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
		await _run_host()
	elif role == "client":
		await _run_client()
	else:
		await _run_late_client()

	game._return_to_main_menu("测试完成")
	await process_frame
	quit(1 if failed else 0)

func _run_host() -> void:
	game.input_player_name.text = "房主"
	game.set("suppress_auto_host", false)
	game.start_server(TEST_PORT, false)
	_check(game.session_active, "host starts")
	print("HOST_READY")

	while game.chat_history.size() < 1:
		await process_frame
	var first_entry := _history_entry(0)
	_check(str(first_entry.get("sender_name", "")) == "玩家二", "host receives sender name")
	_check(str(first_entry.get("content", "")) == "你好", "host receives chat content")
	_check(game.chat_ui.get_notification_count() == 1, "remote message shows host notification")
	print("HOST_CHAT_OK")

	while not game.multiplayer.get_peers().is_empty():
		await process_frame
	await process_frame
	print("HOST_CLIENT_LEFT")

	while game.chat_history.size() < 2:
		await process_frame
	var late_entry := _history_entry(1)
	_check(str(late_entry.get("sender_name", "")) == "玩家三", "late sender name")
	_check(str(late_entry.get("content", "")) == "晚到消息", "late chat content")
	print("HOST_LATE_OK")

func _run_client() -> void:
	game.input_player_name.text = "玩家二"
	game.input_join_IP.text = "127.0.0.1"
	game.input_join_port.text = str(TEST_PORT)
	game._on_join_button_pressed()

	while not game.session_active or not is_instance_valid(game.local_player):
		await process_frame
	_check(not game.chat_ui.is_open(), "chat starts closed")
	game._input(_key_event(KEY_T))
	_check(game.chat_ui.is_open(), "T opens chat")

	game.chat_ui.message_input.grab_focus()
	await process_frame
	_check(game.chat_ui.is_input_focused(), "card mode can focus chat")
	_check(not game.local_player.input_enabled, "chat focus pauses player input")

	var status_before: int = game.local_player.player_status
	var tooltip_before := game.card_description_tooltip.is_tooltip_enabled()
	game._input(_key_event(KEY_Q))
	game.local_player._input(_key_event(KEY_SPACE))
	game._input(_key_event(KEY_T))
	_check(game.chat_ui.is_open(), "T typing does not close chat")
	_check(game.local_player.player_status == status_before, "space typing does not switch mode")
	_check(game.card_description_tooltip.is_tooltip_enabled() == tooltip_before, "Q typing does not toggle tooltip")

	game.chat_ui.message_input.text = "你好"
	game._input(_key_event(KEY_ENTER))
	while not game.chat_ui.get_history_text().contains("玩家二: 你好"):
		await process_frame
	_check(game.chat_ui.get_notification_count() == 0, "own message has no notification")

	var history_before := game.chat_ui.get_history_text()
	game.chat_ui.message_input.text = "草稿"
	game._input(_key_event(KEY_ENTER, true))
	_check(game.chat_ui.get_history_text() == history_before, "shift enter does not send")

	game._input(_key_event(KEY_ESCAPE))
	_check(game.pause_overlay.visible, "escape opens pause while typing")
	_check(game.chat_ui.is_open(), "escape does not close chat")
	_check(not game.chat_ui.is_input_focused(), "escape releases chat focus")
	game._input(_key_event(KEY_ESCAPE))
	_check(not game.pause_overlay.visible, "escape closes pause")

	game.chat_ui.message_input.grab_focus()
	await process_frame
	_check(game.chat_ui.is_input_focused(), "chat can refocus after pause")
	game._input(_mouse_click(Vector2.ZERO))
	_check(not game.chat_ui.is_input_focused(), "outside click releases focus")
	_check(game.local_player.input_enabled, "outside click restores player input")
	_check(game.local_player.player_status == status_before, "outside click does not switch mode")
	game._input(_key_event(KEY_T))
	_check(not game.chat_ui.is_open(), "T closes unfocused chat")

	game.local_player._input(_key_event(KEY_SPACE))
	_check(not game.local_player.is_card_mode(), "space restores mode switching")
	game._input(_key_event(KEY_T))
	game.chat_ui.message_input.grab_focus()
	await process_frame
	_check(not game.chat_ui.is_input_focused(), "move mode cannot focus chat")
	print("CLIENT_OK")
	await create_timer(0.4).timeout

func _run_late_client() -> void:
	game.input_player_name.text = "玩家三"
	game.input_join_IP.text = "127.0.0.1"
	game.input_join_port.text = str(TEST_PORT)
	game._on_join_button_pressed()

	while not game.session_active or not is_instance_valid(game.local_player):
		await process_frame
	while not game.chat_ui.get_history_text().contains("玩家二: 你好"):
		await process_frame
	await process_frame
	_check(game.chat_ui.get_notification_count() == 0, "history snapshot has no notification")
	await create_timer(0.3).timeout
	game.chat_ui.message_input.text = "晚到消息"
	game.chat_ui.submit_current_input()
	while not game.chat_ui.get_history_text().contains("玩家三: 晚到消息"):
		await process_frame
	print("LATE_OK")
	await create_timer(0.4).timeout

func _key_event(keycode: Key, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	return event

func _mouse_click(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event

func _history_entry(index: int) -> Dictionary:
	var value: Variant = game.chat_history[index]
	if value is Dictionary:
		return value
	return {}

func _test_parser() -> void:
	_check(Util.sanitize_chat_message("你好") == "你好", "plain message")
	_check(Util.sanitize_chat_message("a\r\nb\tc") == "a\nb c", "normalize message")
	_check(Util.sanitize_chat_message("  ") == "", "blank message")
	_check(Util.sanitize_chat_message("a\nb\nc", 500, 2) == "", "line limit")
	_check(Util.sanitize_chat_message("😀😀") == "😀😀", "emoji message")
	_check(Util.sanitize_chat_message("x".repeat(501)) == "", "length limit")

	var banner := (load("res://ChatBanner.tscn") as PackedScene).instantiate() as ChatBanner
	root.add_child(banner)
	await process_frame
	var label := banner.get_node("Visual/Margin/MessageLabel") as Label
	_check(label.get_theme_font_size("font_size") == 12, "notification font size")
	_check(label.max_lines_visible == 2, "notification limits preview lines")
	banner.queue_free()

	var chat := (load("res://ChatPanel.tscn") as PackedScene).instantiate() as ChatPanel
	root.add_child(chat)
	await process_frame
	chat.show_notification("玩家一", "测试消息")
	_check(chat.get_notification_count() == 1, "notification can show while chat closed")
	chat.show_notification("玩家一", "第二条消息")
	chat.show_notification("玩家一", "第三条消息")
	await create_timer(0.3).timeout
	_check(chat.get_notification_count() == ChatPanel.MAX_VISIBLE_NOTIFICATIONS, "notification limit")
	chat.show_notification("玩家一", "第四条消息")
	chat.show_notification("玩家一", "第五条消息")
	await create_timer(0.7).timeout
	_check(chat.get_notification_count() == ChatPanel.MAX_VISIBLE_NOTIFICATIONS, "queued notification limit")
	await create_timer(10.8).timeout
	_check(chat.get_notification_count() == 0, "notification expires")
	chat.queue_free()
	print("PARSER_OK")
