extends SceneTree

const PORT := 28814
var game: GameSession
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("TEST FAILED: " + message)
		quit(1)

func _run() -> void:
	create_timer(40).timeout.connect(func() -> void: _check(false, "timeout"))
	var role: String = OS.get_cmdline_user_args()[0]
	game = (load("res://Game.tscn") as PackedScene).instantiate() as GameSession
	game.set_script(load("res://tests/deck_test_game.gd"))
	game.name = "Game"
	root.add_child(game)
	if role == "parser":
		await _local_tests()
	elif role == "host":
		await _host()
	else:
		await _client(role == "late_join")
	game._return_to_main_menu("测试完成")
	await process_frame
	print(role.to_upper() + "_OK")
	quit(1 if failed else 0)

func _start() -> void:
	game.set("suppress_auto_host", false)
	game.start_server(PORT, false)
	await process_frame

func _pile() -> Pile:
	return game.piles.get_node("公共牌堆") as Pile

func _counter() -> Counter:
	return game.counters.get_child(0) as Counter

func _viewer() -> DeckViewerUI:
	for child: Node in root.get_children():
		if child is DeckViewerUI:
			return child as DeckViewerUI
	return null

func _local_tests() -> void:
	_check(NameEditor.clean_name(" \t生命\n 值 😀  ") == "生命 值 😀", "unicode whitespace cleaning")
	_check(NameEditor.clean_name(" \n\t ") == "", "empty name")
	await _start()
	var pile := _pile()
	var old_path: NodePath = pile.get_path()
	_check(pile.display_name == "未分类" and pile._name_label.visible, "initial untyped name")
	pile.name_editor.server_apply_name("非法", 1)
	_check(pile.display_name == "未分类", "no viewer rejected")
	pile.owner_mux.server_set_owner(Const.Purpose.DRAG, 1)
	pile.name_editor.server_apply_name("拖动中", 4)
	_check(pile.display_name == "未分类", "wrong owner purpose rejected")
	pile.owner_mux.server_reset_owner()
	pile.accessor.request_open_viewer()
	await process_frame
	var viewer := _viewer()
	_check(viewer != null, "pile viewer")
	await _test_name_input_movement(viewer.name_row)
	await _test_pile_selection(pile, viewer)
	viewer.name_row.edit.text = "  弃牌堆 😀  "
	viewer.name_row.button.pressed.emit()
	_check(pile.display_name == "弃牌堆 😀" and pile._name_label.visible, "button submits immediately")
	_check(pile.get_path() == old_path and pile.owner_mux.purpose == Const.Purpose.PILE_VIEW, "identity and ownership preserved")
	viewer.name_row.edit.text = "名".repeat(64)
	viewer.name_row._submit()
	_check(pile.display_name.length() == 64, "64 character boundary accepted")
	viewer.name_row.edit.text = "回车名称"
	viewer.name_row.edit.text_submitted.emit("回车名称")
	_check(pile.display_name == "回车名称", "enter submits")
	viewer.name_row.edit.text = "x".repeat(65)
	viewer.name_row._submit()
	_check(pile.display_name == "回车名称", "long name rejected locally")
	pile.name_editor.server_apply_name("x".repeat(65), 2)
	_check(pile.display_name == "回车名称", "long name rejected on server")
	game.clear_table_in_progress = true
	pile.name_editor.server_apply_name("锁定", 3)
	_check(pile.display_name == "回车名称", "board lock")
	game.clear_table_in_progress = false
	viewer.name_row.edit.text = " "
	viewer.name_row._submit()
	_check(pile.display_name == "" and not pile._name_label.visible, "clear hides label")
	viewer.name_row.edit.text = "保留名称"
	viewer.name_row._submit()
	viewer.name_row.edit.text = "未提交"
	viewer.name_row.edit.grab_focus()
	_press_movement()
	pile.owner_mux.server_reset_owner()
	await process_frame
	_check(pile.display_name == "保留名称", "closing discards draft")
	_check_movement_cleared("closing pile viewer")
	_check_stationary_after_mode_switch()
	pile.detail_viewer._enter(pile.get_instance_id())
	_check(game.card_description_tooltip._panel.visible, "named pile hover")
	_check(game.card_description_tooltip._label.text == "保留名称", "hover only name")
	game.card_description_tooltip.set_tooltip_enabled(false)
	_check(not game.card_description_tooltip._panel.visible, "toggle hides")
	game.card_description_tooltip.set_tooltip_enabled(true)
	_check(game.card_description_tooltip._panel.visible, "toggle restores generic name")
	pile.detail_viewer._leave(pile.get_instance_id())
	await process_frame
	game.add_counter(Vector3(3, 0, 0))
	var counter := _counter()
	counter.accessor.request_open_viewer()
	await process_frame
	var counter_viewer: CounterViewerUI = counter.accessor._viewer
	await _test_name_input_movement(counter_viewer.name_row)
	for field: LineEdit in [counter_viewer.value_edit, counter_viewer.step_edit, counter_viewer.decimals_edit]:
		field.grab_focus()
		_press_movement()
		field.release_focus()
		_check_movement_cleared("counter parameter blur")
		_check_stationary_after_mode_switch()
	counter_viewer.name_row.edit.text = "生命"
	counter_viewer.name_row._submit()
	counter.request_apply_value(12)
	_check(counter.display_name == "生命" and counter.value == 12, "counter name independent of value")
	counter_viewer.name_row.edit.text = "草稿"
	counter.request_apply_value(13)
	_check(counter_viewer.name_row.edit.text == "草稿", "numeric refresh preserves name draft")
	counter_viewer.name_row.edit.grab_focus()
	_check(game._counter_viewer_editing(), "name input focus guard")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	counter_viewer.name_row._input(escape)
	_check(game.pause_overlay.visible, "escape opens pause while editing name")
	game._close_pause_menu()

	_press_movement()
	counter.owner_mux.server_reset_owner()
	await process_frame
	_check_movement_cleared("closing counter viewer")
	_check_stationary_after_mode_switch()
	counter.detail_viewer._enter(counter.get_instance_id())
	_check(game.card_description_tooltip._label.text == "生命", "counter hover")
	counter.queue_free()
	await process_frame
	await process_frame
	_check(not game.card_description_tooltip._panel.visible, "deleted source hides hover")

func _host() -> void:
	await _start()
	game.add_counter(Vector3(3, 0, 0))
	print("HOST_READY")
	while _pile().display_name != "客户端牌堆" or _counter().display_name != "客户端计数器":
		await process_frame
	_check(_pile().name_editor.get_multiplayer_authority() == 1, "pile authority remains server")
	_check(_counter().name_editor.get_multiplayer_authority() == 1, "counter authority remains server")
	while not game.multiplayer.get_peers().is_empty():
		await process_frame
	print("HOST_PHASE_OK")
	while game.multiplayer.get_peers().is_empty():
		await process_frame
	await create_timer(1.5).timeout

func _client(late: bool) -> void:
	game.input_join_IP.text = "127.0.0.1"
	game.input_join_port.text = str(PORT)
	game._on_join_button_pressed()
	while not game.session_active or game.local_player == null or game.counters.get_child_count() == 0 or not game.piles.has_node("公共牌堆"):
		await process_frame
	var pile := _pile()
	var counter := _counter()
	if late:
		while pile.display_name != "客户端牌堆" or counter.display_name != "客户端计数器":
			await process_frame
		_check(pile._name_label.visible and counter._name_label.visible, "late join labels")
		return
	pile.name_editor.request_apply_name("未占用", 1)
	await create_timer(0.15).timeout
	_check(pile.display_name == "未分类", "remote unowned request rejected")
	pile.accessor.request_open_viewer()
	while _viewer() == null:
		await process_frame
	var viewer := _viewer()
	viewer.name_row.edit.text = "客户端牌堆"
	viewer.name_row.button.pressed.emit()
	while pile.display_name != "客户端牌堆" or viewer.name_row._pending:
		await process_frame
	_check(viewer.name_row.status.text == "已修改", "client success acknowledgment")
	_check(pile.name_editor.get_multiplayer_authority() == 1, "client cannot own name broadcaster")
	pile.owner_mux.request_release()
	await create_timer(0.1).timeout
	counter.accessor.request_open_viewer()
	while counter.accessor._viewer == null:
		await process_frame
	counter.accessor._viewer.name_row.edit.text = "客户端计数器"
	counter.accessor._viewer.name_row.edit.text_submitted.emit("客户端计数器")
	while counter.display_name != "客户端计数器" or counter.accessor._viewer.name_row._pending:
		await process_frame
	counter.owner_mux.request_release()
	await create_timer(0.15).timeout

func _press_movement() -> void:
	Input.action_press("move_left")
	Input.action_press("move_down")
	game.local_player.velocity = Vector3(5, 0, 5)

func _check_movement_cleared(reason: String) -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		_check(not Input.is_action_pressed(action), reason + ": " + action)

func _check_stationary_after_mode_switch() -> void:
	game.local_player.player_status = Player.PlayerStatus.CARD
	_press_movement() # 模拟焦点退出之后仍到达的残留输入；模式切换再次清理。
	game.local_player.toggle_status()
	game.local_player._physics_process(0.016)
	_check(game.local_player.velocity.is_zero_approx(), "no movement after leaving text input")
	# 新按键仍能正常驱动移动，避免清理逻辑持续吞掉真实操作。
	Input.action_press("move_right")
	game.local_player._physics_process(0.016)
	_check(game.local_player.velocity.length() > 0, "new movement press still works")
	Input.action_release("move_right")
	game.local_player.toggle_status()

func _test_name_input_movement(row: NameEditorUI) -> void:
	row.edit.grab_focus()
	_press_movement()
	row.edit.release_focus()
	_check_movement_cleared("name input blur")
	_check(game.local_player.velocity.is_zero_approx(), "name blur resets velocity")
	_check_stationary_after_mode_switch()
	await process_frame

func _ids(list: Node) -> Array[int]:
	var ids: Array[int] = []
	for child: Node in list.get_children():
		var card: UICard = child as UICard
		ids.append(card.card_ID())
	return ids

func _test_pile_selection(pile: Pile, viewer: DeckViewerUI) -> void:
	var original: Array[int] = _ids(viewer.list_top)
	var stack_before: Array[int] = pile.card_ID_stack.duplicate()
	for button: Button in [viewer.btn_all_front, viewer.btn_all_back, viewer.btn_all_flip,
		viewer.btn_random_face, viewer.btn_all_upright, viewer.btn_all_inverted,
		viewer.btn_all_invert, viewer.btn_random_upright, viewer.btn_sort_ascend,
		viewer.btn_sort_descend, viewer.btn_shuffle, viewer.btn_reverse,
		viewer.btn_select_front, viewer.btn_select_bottom, viewer.btn_select_random,
		viewer.btn_cancel, viewer.btn_draw, viewer.btn_delete]:
		_check(is_instance_valid(button) and button.pressed.has_connections(), "button path and scene signal: " + button.name)
	viewer.btn_reverse.pressed.emit()
	var reversed: Array[int] = original.duplicate()
	reversed.reverse()
	_check(_ids(viewer.list_top) == reversed, "reverse local order")
	viewer.btn_reverse.pressed.emit()
	viewer.input_number.text = "2"
	viewer.btn_select_front.pressed.emit()
	_check(_ids(viewer.list_top) == original.slice(2), "top selection leaves suffix")
	_check(_ids(viewer.list_bottom) == original.slice(0, 2), "top selection preserves order")
	viewer.btn_select_bottom.pressed.emit()
	var prefix: Array[int] = original.slice(0, 2)
	prefix.append_array(original.slice(original.size() - 2))
	_check(_ids(viewer.list_bottom) == prefix, "bottom selection appended in original order")
	var remaining: Array[int] = _ids(viewer.list_top)
	viewer.btn_select_random.pressed.emit()
	var selected: Array[int] = _ids(viewer.list_bottom).slice(prefix.size())
	_check(selected.size() == 2 and selected[0] != selected[1], "random sampling without replacement")
	_check(remaining.find(selected[0]) < remaining.find(selected[1]), "random selected subsequence order")
	var expected: Array[int] = remaining.duplicate()
	for id: int in selected:
		expected.erase(id)
	_check(_ids(viewer.list_top) == expected, "random selection preserves remaining order")
	_check(_ids(viewer.list_bottom).slice(0, prefix.size()) == prefix, "existing pending order preserved")
	for invalid: String in ["", "0", "-1", "1.5", "abc", "中文"]:
		viewer.input_number.text = invalid
		viewer.btn_select_front.pressed.emit()
		_check(_ids(viewer.list_top) == expected, "invalid count ignored: " + invalid)
	viewer.dragging_card = viewer.list_top.get_child(0) as UICard
	viewer.input_number.text = "1"
	viewer.btn_select_front.pressed.emit()
	viewer.btn_reverse.pressed.emit()
	_check(_ids(viewer.list_top) == expected, "batch operations do not alter active drag")
	viewer.dragging_card = null
	viewer.input_number.text = "9999"
	var pending: Array[int] = _ids(viewer.list_bottom)
	pending.append_array(expected)
	viewer.btn_select_front.pressed.emit()
	_check(viewer.list_top.get_child_count() == 0 and _ids(viewer.list_bottom) == pending, "oversized count takes all remaining")
	_check(viewer.btn_draw.visible and viewer.btn_draw.text == "保存顺序并取出", "pending cards show save-and-draw button")
	viewer.btn_select_random.pressed.emit()
	viewer.btn_reverse.pressed.emit()
	_check(_ids(viewer.list_bottom) == pending, "empty source safe")
	_check(pile.card_ID_stack == stack_before, "selection and reversal do not sync server stack")
	viewer.input_number.grab_focus()
	_press_movement()
	_check(game._counter_viewer_editing(), "quantity field guards text input")
	viewer.input_number.release_focus()
	_check_movement_cleared("quantity field blur")
	_check_stationary_after_mode_switch()
	for card: Node in viewer.list_bottom.get_children():
		card.free()
	viewer.load_deck(original)
	viewer.input_number.text = "1"
	await process_frame
	_check(viewer.btn_draw.visible and viewer.btn_draw.text == "保存顺序", "empty pending keeps save-order button visible")
