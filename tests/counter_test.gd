extends SceneTree

# --headless --path . --script res://tests/counter_test.gd -- parser|host|client|late_join
const TEST_PORT: int = 28129
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

	create_timer(60.0).timeout.connect(func() -> void: _check(false, "test timeout"))
	game = (load("res://Game.tscn") as PackedScene).instantiate() as GameSession
	game.set_script(load("res://tests/deck_test_game.gd"))
	game.name = "Game"
	root.add_child(game)

	if role == "host":
		await _run_host()
	elif role == "client":
		await _run_client()
	elif role == "late_join":
		await _run_late_join()
	else:
		_check(false, "unknown test role: " + role)

	game._return_to_main_menu("测试完成")
	await process_frame
	quit(1 if failed else 0)

###################################
# 公共
func _wait_counter() -> Counter:
	var found: Counter = null
	while found == null:
		for child in game.counters.get_children():
			found = child as Counter
			if found != null:
				break
		if found == null:
			await process_frame
	return found

func _wait_value(counter: Counter, target: float) -> void:
	while not is_equal_approx(counter.value, target):
		await process_frame

func _key_event(keycode: Key, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.shift_pressed = shift
	return event

func _left_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event

###################################
# 房主：创建计数器，校验互斥与最终状态，收尾清计数器
func _run_host() -> void:
	game.input_player_name.text = "房主"
	game.set("suppress_auto_host", false)
	game.start_server(TEST_PORT, false)
	_check(game.session_active, "host starts")
	game.add_counter(Vector3(2.6, 0, 0))
	print("HOST_READY")

	while game.multiplayer.get_peers().is_empty():
		await process_frame
	var counter := await _wait_counter()
	_check(is_equal_approx(counter.value, 0.0), "counter starts at zero")

	# 等客户端完成两次 ±step
	await _wait_value(counter, 2.0)
	# 等客户端占用（拖动或查看器），随后验证服务器端互斥
	while not counter.owner_mux.is_owned():
		await process_frame
	counter.request_apply_step(1)
	await create_timer(0.3).timeout
	_check(is_equal_approx(counter.value, 2.0), "occupied counter rejects host step")
	_check(not counter.dragger.request_drag(), "occupied counter rejects host drag")
	print("HOST_MUTEX_OK")

	# 等查看器编辑结果：7.3 / 0.5 / 1 位小数
	while not (is_equal_approx(counter.value, 7.3) and is_equal_approx(counter.step, 0.5) and counter.decimals == 1):
		await process_frame
	while counter.owner_mux.is_owned():
		await process_frame
	print("HOST_PHASE1_OK")

	# 等待玩家二离开、玩家三（晚加入）进出
	while not game.multiplayer.get_peers().is_empty():
		await process_frame
	while game.multiplayer.get_peers().is_empty():
		await process_frame
	while not game.multiplayer.get_peers().is_empty():
		await process_frame
	_check(is_equal_approx(counter.value, 7.3), "state persists after late joiner leaves")

	# 一键清计数器
	game._on_clear_counters_button_pressed()
	_check(game.clear_counters_confirmation.visible, "clear counters dialog shows")
	game._on_clear_counters_confirmed()
	while game.counters.get_child_count() > 0:
		await process_frame
	_check(not game.clear_table_in_progress, "clear counters finishes")
	_check(game.piles.get_child_count() > 0, "piles survive counter clear")
	print("HOST_COUNTERS_OK")
	print("HOST_ALL_OK")

###################################
# 玩家二：3D 按钮 / 拖动 / 查看器全流程
func _run_client() -> void:
	game.input_player_name.text = "玩家二"
	game.input_join_IP.text = "127.0.0.1"
	game.input_join_port.text = str(TEST_PORT)
	game._on_join_button_pressed()
	while not game.session_active or not is_instance_valid(game.local_player):
		await process_frame
	var counter := await _wait_counter()

	# 移动模式下 3D 交互被拒（设计文档 Q8）
	game.local_player._input(_key_event(KEY_SPACE))
	_check(not game.local_player.is_card_mode(), "switch to move mode")
	_check(not counter._local_can_interact(), "move mode blocks interactions")
	counter._input_event(null, _left_click(), Vector3(3.2, 0.06, 0), Vector3.UP, Counter.SHAPE_PLUS)
	await create_timer(0.3).timeout
	_check(is_equal_approx(counter.value, 0.0), "no step in move mode")
	game.local_player._input(_key_event(KEY_SPACE))
	_check(game.local_player.is_card_mode(), "back to card mode")

	# shape_idx 路由 + 位置兜底校验
	counter._input_event(null, _left_click(), Vector3(3.2, 0.06, 0), Vector3.UP, Counter.SHAPE_PLUS)
	await _wait_value(counter, 1.0)
	counter._input_event(null, _left_click(), Vector3(2.0, 0.06, 0), Vector3.UP, Counter.SHAPE_MINUS)
	await _wait_value(counter, 0.0)
	counter._input_event(null, _left_click(), Vector3(3.2, 0.06, 0), Vector3.UP, Counter.SHAPE_PLUS)
	await _wait_value(counter, 1.0)
	counter._input_event(null, _left_click(), Vector3(3.2, 0.06, 0), Vector3.UP, Counter.SHAPE_PLUS)
	await _wait_value(counter, 2.0)
	counter._input_event(null, _left_click(), Vector3(2.6, 0.06, 0), Vector3.UP, Counter.SHAPE_PLUS)
	await create_timer(0.3).timeout
	_check(is_equal_approx(counter.value, 2.0), "button click at wrong position ignored")

	# 拖动占用：占用中无法打开查看器
	_check(counter.dragger.request_drag(), "drag accepted")
	while not counter.dragger.i_am_dragging():
		await process_frame
	_check(not counter.accessor.request_open_viewer(), "dragging blocks viewer")
	_check(counter.dragger.request_drop(), "drop accepted")
	while counter.owner_mux.is_owned():
		await process_frame

	# 右键查看器：持续占用 + 编辑广播
	_check(counter.accessor.request_open_viewer(), "viewer accepted")
	while not counter.accessor.i_am_viewing():
		await process_frame
	var viewer := counter.accessor._viewer
	_check(viewer != null, "viewer ui created")
	_check(viewer.btn_delete.visible, "occupier can delete")
	_check(viewer.btn_plus.text == "+1", "plus label starts at +1")
	_check(not counter.dragger.request_drag(), "viewing blocks drag")
	await create_timer(0.8).timeout # 留出房主端互斥断言窗口

	counter.request_apply_decimals(2)
	while counter.decimals != 2:
		await process_frame
	_check(is_equal_approx(counter.value, 2.0), "value survives decimals change")

	counter.request_apply_step_value(0.5)
	while not is_equal_approx(counter.step, 0.5):
		await process_frame
	_check(viewer.btn_plus.text == "+0.50", "plus label follows step at 2 decimals")
	_check(viewer.btn_minus.text == "-0.50", "minus label follows step at 2 decimals")

	counter.request_apply_step(1) # 查看器内 +0.5
	await _wait_value(counter, 2.5)

	viewer.value_edit.text = "7.256"
	viewer._submit_value()
	await _wait_value(counter, 7.26)
	_check(viewer.value_edit.text == "7.26", "value field refreshes")

	viewer.step_edit.text = "-1"
	viewer._submit_step()
	await create_timer(0.3).timeout
	_check(is_equal_approx(counter.step, 0.5), "negative step rejected")
	_check(viewer.step_edit.text == "0.50", "step field restored")

	viewer.decimals_edit.text = "1"
	viewer._submit_decimals()
	while counter.decimals != 1:
		await process_frame
	_check(is_equal_approx(counter.value, 7.3), "value rounds to 1 decimal")
	_check(is_equal_approx(counter.step, 0.5), "step keeps 0.5 at 1 decimal")

	viewer.decimals_edit.text = "10"
	viewer._submit_decimals()
	while counter.decimals != 6:
		await process_frame
	_check(viewer.decimals_edit.text == "6", "decimals clamped to max")

	viewer.decimals_edit.text = "1"
	viewer._submit_decimals()
	while counter.decimals != 1:
		await process_frame

	# 关闭查看器 → 释放占用
	viewer.btn_close.pressed.emit()
	while counter.owner_mux.is_owned():
		await process_frame
	print("CLIENT_OK")
	await create_timer(0.4).timeout

###################################
# 玩家三：晚加入补齐状态
func _run_late_join() -> void:
	game.input_player_name.text = "玩家三"
	game.input_join_IP.text = "127.0.0.1"
	game.input_join_port.text = str(TEST_PORT)
	game._on_join_button_pressed()
	while not game.session_active or not is_instance_valid(game.local_player):
		await process_frame
	var counter := await _wait_counter()
	while not (is_equal_approx(counter.value, 7.3) and is_equal_approx(counter.step, 0.5) and counter.decimals == 1):
		await process_frame
	_check(not counter.owner_mux.is_owned(), "late joiner sees free counter")
	print("CLIENT_OK")
	await create_timer(0.4).timeout

###################################
# 解析与纯函数
func _test_parser() -> void:
	_check(Const.Purpose.COUNTER_VIEW == 9, "COUNTER_VIEW id")
	_check(Const.Purpose.COUNTER_ADD == 10, "COUNTER_ADD id")
	_check(Const.Purpose.COUNTER_SUBTRACT == 11, "COUNTER_SUBTRACT id")
	_check(Const.PURPOSE_STR[Const.Purpose.COUNTER_VIEW] == "COUNTER_VIEW", "purpose str entry")

	_check(is_equal_approx(Counter.round_to_decimals(7.256, 2), 7.26), "round half up")
	_check(is_equal_approx(Counter.round_to_decimals(0.5, 0), 1.0), "step rounds away from zero")
	_check(is_equal_approx(Counter.round_to_decimals(-2.5, 0), -3.0), "negative round away from zero")

	var counter := (load("res://Counter.tscn") as PackedScene).instantiate() as Counter
	_check(counter != null, "counter scene instantiates")
	counter.value = 2.5
	counter.step = 0.5
	counter.decimals = 2
	_check(counter.format_value() == "2.50", "value keeps trailing zeros")
	_check(counter.format_step() == "0.50", "step keeps trailing zeros")
	counter.decimals = 0
	_check(counter.format_value() == "3", "value rounds at 0 decimals")
	counter.value = -0.001
	_check(counter.format_value() == "0", "negative zero displays as 0")
	root.add_child(counter)
	await process_frame
	_check(counter.format_value() == "0", "counter displays zero")
	_check(counter.format_step() == "1", "default step displays 1")
	var shape_count := 0
	for child in counter.get_children():
		if child is CollisionShape3D:
			shape_count += 1
	_check(shape_count == 3, "counter has 3 collision shapes")
	counter.queue_free()

	var viewer := (load("res://CounterViewerUI.tscn") as PackedScene).instantiate() as CounterViewerUI
	_check(viewer != null, "viewer scene instantiates")
	root.add_child(viewer)
	await process_frame
	_check(viewer.value_edit != null and viewer.step_edit != null and viewer.decimals_edit != null, "viewer fields resolve")
	_check(viewer.btn_plus != null and viewer.btn_minus != null, "viewer step buttons resolve")
	_check(viewer.btn_dec_plus != null and viewer.btn_dec_minus != null, "viewer decimals buttons resolve")
	viewer.queue_free()
	print("PARSER_OK")
