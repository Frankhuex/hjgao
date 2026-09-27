extends SceneTree

# --headless --path . --script res://tests/player_name_test.gd -- parser|host|client
const TEST_PORT: int = 28790
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
		_test_sanitize()
		quit(1 if failed else 0)
		return

	create_timer(25.0).timeout.connect(func() -> void: _check(false, "test timeout"))
	game = (load("res://Game.tscn") as PackedScene).instantiate() as GameSession
	game.set_script(load("res://tests/deck_test_game.gd"))
	game.name = "Game"
	root.add_child(game)

	if role == "host":
		await _run_host()
	else:
		await _run_client()

	game._return_to_main_menu("测试完成")
	await process_frame
	quit(1 if failed else 0)

func _run_host() -> void:
	game.input_player_name.text = " 房主 "
	game.set("suppress_auto_host", false)
	game.start_server(TEST_PORT, false)
	_check(game.session_active, "host starts")
	_check(str(game.player_names.get(1, "")) == "房主", "host name is sanitized")
	print("HOST_READY")

	while game.player_names.size() < 2:
		await process_frame
	_check(game.player_names.values().has("玩家二"), "server associates client name")

	game._open_pause_menu()
	await process_frame
	_check(game.player_list.item_count == 2, "host pause list has two players")
	_check(_item_texts().has("房主  [ID 1]  [房主]  [我]"), "host row")
	_check(_find_item_index("玩家二  [ID ") >= 0, "client row")
	print("HOST_JOIN_OK")

	while game.player_names.size() > 1:
		await process_frame
	await process_frame
	_check(game.player_list.item_count == 1, "pause list removes disconnected player")
	print("HOST_DISCONNECT_OK")

func _run_client() -> void:
	game.input_player_name.text = " 玩家二 "
	game.input_join_IP.text = "127.0.0.1"
	game.input_join_port.text = str(TEST_PORT)
	game._on_join_button_pressed()

	while not game.session_active or not is_instance_valid(game.local_player):
		await process_frame
	while game.player_roster_cache.size() < 2:
		await process_frame
	var client_id := Util.my_id(game)
	_check(game.local_player.display_name == "玩家二", "client player name")
	_check(client_id > 1, "client peer id")
	_check(game.player_roster_cache.size() == 2, "client receives full roster")

	game._open_pause_menu()
	while game.player_list.item_count < 2:
		await process_frame
	_check(_item_texts().has("玩家二  [ID %d]  [我]" % client_id), "client row")
	_check(_find_item_index("房主  [ID 1]  [房主]") >= 0, "host row")
	print("CLIENT_OK")
	await create_timer(0.5).timeout

func _item_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for index in range(game.player_list.item_count):
		texts.append(game.player_list.get_item_text(index))
	return texts

func _find_item_index(fragment: String) -> int:
	for index in range(game.player_list.item_count):
		if game.player_list.get_item_text(index).begins_with(fragment):
			return index
	return -1

func _test_sanitize() -> void:
	_check(Util.sanitize_player_name("  Alice  ", 2) == "Alice", "trim name")
	_check(Util.sanitize_player_name("A\t\nB", 2) == "A B", "normalize whitespace")
	_check(Util.sanitize_player_name("", 7) == "玩家7", "blank fallback")
	_check(Util.sanitize_player_name("你 好", 2) == "你 好", "chinese name")
	_check(Util.sanitize_player_name("😀😀", 2) == "😀😀", "emoji name")
	var long_name := "123456789012345678901234567890"
	_check(Util.sanitize_player_name(long_name, 2, 24).length() == 24, "max length")
	print("PARSER_OK")
