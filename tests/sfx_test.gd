extends SceneTree

# --headless --path . --script res://tests/sfx_test.gd -- parser|host|client
# 音效系统测试（设计文档 docs/sound-effects-design.md 第 9 节）：
#   parser：Sfx 单例/播放记录/音高区间/同帧合并/按钮双钩子/确认音组排除
#   host  ：作为服务器断言全端音效（拖动/抽牌/入堆/翻牌广播边沿）
#   client：悬停音、查看器理牌音、2D 翻牌音（本端）+ 全流程驱动
const TEST_PORT: int = 28794
var game: GameSession
var sfx: SfxManager
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
	sfx = root.get_node("Sfx")

	if role == "host":
		await _run_host()
	elif role == "client":
		await _run_client()
	else:
		_check(false, "unknown test role: " + role)

	game._return_to_main_menu("测试完成")
	await process_frame
	quit(1 if failed else 0)

###################################
# 公共
func _count(tag: String) -> int:
	var n := 0
	for entry in sfx._history:
		if entry.begins_with(tag):
			n += 1
	return n

func _clear() -> void:
	sfx._history.clear()

func _pitch_of(tag: String) -> float:
	for entry in sfx._history:
		if entry.begins_with(tag + "|"):
			return float(entry.get_slice("|", 1))
	return -1.0

func _find_pile(pile_name: String) -> Pile:
	for child in game.piles.get_children():
		if child.name == pile_name:
			return child as Pile
	return null

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

func _wait_picked_card() -> Card:   # 等任意一张 3D 牌被（任意人）拖起
	while true:
		for child in game.card_sorter.get_children():
			var card := child as Card
			if card != null and card._dragger.is_being_dragged():
				return card
		await process_frame
	return null

func _right_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	return event

###################################
# 房主：作为服务器断言"全端"音效（广播边沿触达每个端）
func _run_host() -> void:
	game.input_player_name.text = "房主"
	game.set("suppress_auto_host", false)
	game.start_server(TEST_PORT, false)
	_check(game.session_active, "host starts")
	game.add_counter(Vector3(2.6, 0, 0))
	print("HOST_READY")

	while game.multiplayer.get_peers().is_empty():
		await process_frame
	var pile := _find_pile("公共牌堆")
	_check(pile != null, "public pile exists")

	# R4 拖动牌堆（client 拖起/放下 → 两端）
	while not pile.owner_mux.is_owned():
		await process_frame
	_check(_count("CONFIRM") == 2, "host hears both counter steps once")
	_check(_count("PICKUP_OBJECT") == 1, "host hears pile pickup")
	_check(_count("PICKUP_CARD") == 0, "pile pickup uses object sound")
	_clear()
	while pile.owner_mux.is_owned():
		await process_frame
	_check(_count("DROP_OBJECT") == 1, "host hears pile drop")
	_clear()

	# R8 抽 1 张（client 点牌堆顶 → 两端一声放下音）
	while game.card_sorter.get_child_count() < 1:
		await process_frame
	_check(_count("SPAWN") == 1, "host hears single draw")
	_clear()

	# 查看器阶段（理牌/2D 翻牌为客户端私有；批量抽 3 张合并一声）
	while not (pile.owner_mux.is_owned() and pile.owner_mux.purpose == Const.Purpose.PILE_VIEW):
		await process_frame
	_clear()
	while pile.owner_mux.is_owned():
		await process_frame
	_check(_count("SHUFFLE_OK") == 0, "host hears no viewer sort sound")
	_check(_count("FLIP") == 0, "host hears no 2D flip sound")
	_check(_count("SPAWN") == 1, "host hears batch draw as one spawn sound")
	_check(game.card_sorter.get_child_count() == 4, "3 cards drawn")
	_clear()

	# R3 拿起/放下 3D 卡牌（client → 两端）
	var card := await _wait_picked_card()
	_check(_count("PICKUP_CARD") == 1, "host hears card pickup")
	_clear()
	while card._dragger.is_being_dragged():
		await process_frame
	_check(_count("DROP_CARD") == 1, "host hears card drop")
	_clear()

	# R5-3D 翻 3D 牌（client → 两端）
	var flipped := [false]
	game.card_db.on_flip.connect(func() -> void: flipped[0] = true)
	while not flipped[0]:
		await process_frame
	_check(_count("FLIP") == 1, "host hears 3D flip")
	_clear()

	# R7 塞回牌堆（client 拖起 → 收牌事务删节点 → 两端洗牌音，无放下边沿）
	card = await _wait_picked_card()
	_check(_count("PICKUP_CARD") == 1, "host hears re-pickup")
	_clear()
	var drop_base := _count("DROP_CARD")
	while game.card_sorter.get_child_count() != 3:
		await process_frame
	_check(_count("PILE_IN") == 1, "host hears pile-in shuffle")
	_check(_count("DROP_CARD") == drop_base, "no drop edge on pile-in")
	_clear()

	# 拒绝不响：房主占用牌堆，客户端申请被拒（无广播边沿 → 静默）
	_check(pile.dragger.request_drag(), "host takes pile")
	while not pile.dragger.i_am_dragging():
		await process_frame
	_check(_count("PICKUP_OBJECT") == 1, "host pickup heard")
	_clear()
	await create_timer(1.5).timeout   # 留出客户端被拒申请的静默窗口
	_check(_count("PICKUP_OBJECT") == 0, "rejected client drag is silent on host")
	_check(_count("DROP_OBJECT") == 0, "no drop during rejection window")
	_clear()
	pile.dragger.request_drop()
	while pile.owner_mux.is_owned():
		await process_frame
	_check(_count("DROP_OBJECT") == 1, "host drop heard")
	print("HOST_SFX_OK")
	print("HOST_ALL_OK")

###################################
# 玩家二：本端音效 + 全流程驱动
func _run_client() -> void:
	game.input_player_name.text = "玩家二"
	game.input_join_IP.text = "127.0.0.1"
	game.input_join_port.text = str(TEST_PORT)
	game._on_join_button_pressed()
	while not game.session_active or not is_instance_valid(game.local_player):
		await process_frame
	var pile := _find_pile("公共牌堆")
	_check(pile != null, "public pile exists")
	var counter := await _wait_counter()

	# R1b UICard 悬停（本端）
	var ui_card := (load("res://UICard.tscn") as PackedScene).instantiate() as UICard
	_check(ui_card != null, "ui card instantiates")
	ui_card.preready(game.card_db.get_all_IDs()[0])
	root.add_child(ui_card)
	await process_frame
	_clear()
	ui_card.mouse_entered.emit()
	_check(_count("HOVER") == 1, "ui card hover plays")
	ui_card.queue_free()

	# R1c 计数器 +/- 悬停（本端，shape 边沿跟踪）
	_clear()
	counter._update_button_hover(Counter.SHAPE_PLUS)
	_check(_count("HOVER") == 1, "counter plus hover plays")
	counter._update_button_hover(Counter.SHAPE_PLUS)
	_check(_count("HOVER") == 1, "same shape does not replay")
	counter._update_button_hover(Counter.SHAPE_BASE)
	counter._update_button_hover(Counter.SHAPE_MINUS)
	_check(_count("HOVER") == 2, "re-enter after base reset replays")

	# 3D 加减成功后各播放一次普通确认音。
	_clear()
	for direction: int in [1, -1]:
		var expected_value := counter.value + direction * counter.step
		_check(counter.request_apply_step(direction), "counter step requested")
		_check(_count("CONFIRM") == 0, "counter waits for server success")
		while counter.value != expected_value or counter.owner_mux.is_owned():
			await process_frame
		_check(_count("CONFIRM") == 1, "counter step confirms once")
		_check(is_equal_approx(_pitch_of("CONFIRM"), 1.0), "counter confirm pitch fixed")
		_clear()

	# R4 拖动牌堆（全端）
	_clear()
	_check(pile.dragger.request_drag(), "pile drag accepted")
	while not pile.dragger.i_am_dragging():
		await process_frame
	_check(_count("PICKUP_OBJECT") == 1, "client hears pile pickup")
	_clear()
	_check(pile.dragger.request_drop(), "pile drop accepted")
	while pile.owner_mux.is_owned():
		await process_frame
	_check(_count("DROP_OBJECT") == 1, "client hears pile drop")
	_clear()

	# R8 抽 1 张（全端）
	_check(pile.spawner.request_spawn_card(Const.CardSource.TOP), "draw 1 accepted")
	while game.card_sorter.get_child_count() < 1:
		await process_frame
	_check(_count("SPAWN") == 1, "client hears single draw")
	_clear()

	# 查看器阶段（本端私有音效）
	_check(pile.accessor.request_open_viewer(), "open viewer accepted")
	while not pile.accessor.i_am_viewing():
		await process_frame
	var viewer := pile.accessor._viewer
	_check(viewer != null, "viewer ui created")

	viewer.btn_shuffle.pressed.emit()   # 组排除 + 理牌成功音直响
	_check(_count("SHUFFLE_OK") == 1, "shuffle button plays sort sound")
	_check(_count("CONFIRM") == 0, "sort buttons excluded from confirm sound")

	var ui_list_card := viewer.list_top.get_child(0) as UICard
	_check(ui_list_card != null, "viewer card exists")
	_clear()
	ui_list_card._gui_input(_right_click())   # R5-2D：右键武装 → 落地仅本端响 FLIP
	var base_front: bool = game.card_db.is_front(ui_list_card.card_ID())
	while game.card_db.is_front(ui_list_card.card_ID()) == base_front:
		await process_frame
	_check(_count("FLIP") == 1, "2D flip plays only locally")
	_clear()

	var shift_right_click := _right_click()
	shift_right_click.shift_pressed = true
	var base_upright := game.card_db.is_upright(ui_list_card.card_ID())
	ui_list_card._gui_input(shift_right_click)
	_check(_count("FLIP") == 0, "2D orientation waits for server success")
	while game.card_db.is_upright(ui_list_card.card_ID()) == base_upright:
		await process_frame
	_check(_count("FLIP") == 1, "2D Shift-right-click plays one local flip sound")
	_check(_count("SHUFFLE_OK") == 0, "single orientation has no sort sound")
	ui_list_card.update_orientation()
	_check(_count("FLIP") == 1, "orientation refresh does not repeat sound")
	_clear()

	viewer.btn_all_front.pressed.emit()   # R2：武装 → 第一次落地广播响一声
	await create_timer(0.5).timeout
	_check(_count("SHUFFLE_OK") == 1, "all-front plays one sort sound")
	_check(_count("CONFIRM") == 0, "flip buttons excluded from confirm sound")
	_clear()

	for button: Button in [viewer.btn_all_inverted, viewer.btn_all_upright, viewer.btn_all_invert]:
		button.pressed.emit()
		await create_timer(0.5).timeout
		_check(_count("SHUFFLE_OK") == 1, "orientation button plays one sort sound: " + button.name)
		_check(_count("CONFIRM") == 0, "orientation button excludes confirm sound: " + button.name)
		_check(_count("FLIP") == 0, "batch orientation has no single-card flip sound")
		_clear()

	# 批量抽 3 张 → 两端一声（同帧合并）；Btn_Draw 不排除确认音
	for i in range(3):
		var drawn := viewer.list_top.get_child(0)
		viewer.list_top.remove_child(drawn)
		viewer.list_bottom.add_child(drawn)
	viewer.btn_draw.pressed.emit()
	while game.card_sorter.get_child_count() < 4:
		await process_frame
	while pile.owner_mux.is_owned():
		await process_frame
	_check(_count("SPAWN") == 1, "client hears batch draw as one spawn sound")
	_check(_count("CONFIRM") == 1, "draw button confirms (not excluded)")
	_clear()

	# R3 拿起/放下 3D 卡牌（全端）
	var card: Card = null
	for child in game.card_sorter.get_children():
		card = child as Card
		if card != null:
			break
	_check(card != null, "3d card exists")
	_check(card._dragger.request_drag(), "card drag accepted")
	while not card._dragger.i_am_dragging():
		await process_frame
	_check(_count("PICKUP_CARD") == 1, "client hears card pickup")
	_clear()
	_check(card._dragger.request_drop(), "card drop accepted")
	while card._owner_mux.is_owned():
		await process_frame
	_check(_count("DROP_CARD") == 1, "client hears card drop")
	_clear()

	# R5-3D 翻 3D 牌（全端）
	var card_front: bool = game.card_db.is_front(card.card_ID())
	card.request_flip()
	while game.card_db.is_front(card.card_ID()) == card_front:
		await process_frame
	_check(_count("FLIP") == 1, "client hears 3D flip")
	_clear()

	# R7 塞回牌堆（全端）
	_check(card._dragger.request_drag(), "re-pickup accepted")
	while not card._dragger.i_am_dragging():
		await process_frame
	_check(_count("PICKUP_CARD") == 1, "client hears re-pickup")
	_clear()
	var drop_base := _count("DROP_CARD")
	_check(pile.receiver.request_receive_card(card.card_ID(), Const.CardSource.TOP), "put into pile accepted")
	while is_instance_valid(card):
		await process_frame
	_check(_count("PILE_IN") == 1, "pile-in plays shuffle sound")
	_check(_count("DROP_CARD") == drop_base, "no drop edge on pile-in")
	_clear()

	# 拒绝不响：房主占用牌堆，本端申请被拒
	while not pile.owner_mux.is_owned():
		await process_frame
	_clear()
	_check(not pile.dragger.request_drag(), "rejected while host occupies")
	await create_timer(0.3).timeout
	_check(_count("PICKUP_OBJECT") == 0, "rejected request is silent")
	print("CLIENT_OK")
	await create_timer(0.4).timeout

###################################
# 解析与纯本地行为
func _test_parser() -> void:
	sfx = root.get_node_or_null("Sfx") as SfxManager
	_check(sfx != null, "Sfx autoload exists")

	# 播放记录 + 音高：HOVER/CONFIRM 固定，其余 ±1 半音
	_clear()
	sfx.play(SfxManager.Snd.CONFIRM)
	sfx.play(SfxManager.Snd.HOVER)
	sfx.play(SfxManager.Snd.PICKUP_CARD)
	_check(_count("CONFIRM") == 1 and _count("HOVER") == 1 and _count("PICKUP_CARD") == 1, "history records")
	_check(is_equal_approx(_pitch_of("CONFIRM"), 1.0), "confirm pitch fixed")
	_check(is_equal_approx(_pitch_of("HOVER"), 1.0), "hover pitch fixed")
	var pitch := _pitch_of("PICKUP_CARD")
	_check(pitch >= 1.0 / SfxManager.SEMITONE and pitch <= SfxManager.SEMITONE, "vary pitch within semitone")
	_check(sfx.history_contains("PICKUP_CARD"), "history_contains")

	# SPAWN 同帧合并（Q10）
	_clear()
	sfx.play(SfxManager.Snd.SPAWN)
	sfx.play(SfxManager.Snd.SPAWN)
	sfx.play(SfxManager.Snd.SPAWN)
	_check(_count("SPAWN") == 1, "same-frame spawn coalesces")

	# R1a/R6 按钮双钩子
	var button := Button.new()
	root.add_child(button)
	_clear()
	button.mouse_entered.emit()
	_check(_count("HOVER") == 1, "button hover hooked")
	button.pressed.emit()
	_check(_count("CONFIRM") == 1, "button press hooked")

	var disabled := Button.new()
	disabled.disabled = true
	root.add_child(disabled)
	_clear()
	disabled.mouse_entered.emit()
	_check(_count("HOVER") == 0, "disabled button silent on hover")

	# R6 组排除（六个理牌按钮的排除机制）
	_check(SfxManager.GROUP_NO_CONFIRM == &"sfx_no_confirm", "group name")
	button.add_to_group(SfxManager.GROUP_NO_CONFIRM)
	button.pressed.emit()
	_check(_count("CONFIRM") == 0, "group-excluded button silent")
	button.queue_free()
	disabled.queue_free()

	# 回归：启动时已在树内的按钮（大厅/暂停菜单）也必须被挂钩。
	# 真机上 autoload 的 _ready 晚于主场景入树，node_added 早已错过，
	# 靠 _ready 时的全树扫描补挂；此处用第二个 SfxManager 复现"按钮先于管理器就绪"。
	# 原单例对该按钮也有一份连接，但各自记录历史，不影响对 sfx2 的断言。
	var pre_existing := Button.new()
	root.add_child(pre_existing)
	var sfx2 := SfxManager.new()
	root.add_child(sfx2)
	pre_existing.mouse_entered.emit()
	var hooked := 0
	for entry in sfx2._history:
		if entry.begins_with("HOVER"):
			hooked += 1
	_check(hooked == 1, "pre-existing button hooked by startup scan")
	sfx2.queue_free()
	SfxManager.I = sfx
	pre_existing.queue_free()

	# 真实暂停菜单确认框的按钮是 internal children；重复弹出不能重复绑定。
	var menu_game := (load("res://Game.tscn") as PackedScene).instantiate() as GameSession
	menu_game.set_script(load("res://tests/deck_test_game.gd"))
	root.add_child(menu_game)
	for dialog: ConfirmationDialog in [menu_game.clear_table_confirmation, menu_game.clear_counters_confirmation, menu_game.clear_empty_piles_confirmation]:
		for attempt in range(2):
			dialog.popup_centered()
			await process_frame
			for dialog_button: Button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
				_clear()
				dialog_button.mouse_entered.emit()
				_check(_count("HOVER") == 1, "pause confirmation hover bound exactly once")
				dialog_button.pressed.emit()
				_check(_count("CONFIRM") == 1, "pause confirmation press bound exactly once")
			dialog.hide()
	menu_game.queue_free()
	await process_frame
	print("SFX_PARSER_OK")
