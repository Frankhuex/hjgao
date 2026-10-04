class_name DeckViewerUI
extends CanvasLayer

signal draw_confirmed(updated_card_ID_stack: Array[int], drawn_cards: Array[int])
signal draw_to_new_pile_confirmed(remaining_ids: Array[int], extracted_ids: Array[int], submission_id: int)
static var _next_submission_id: int = 0
var _submission_id: int = 0
var _submission_pending := false
@onready var btn_draw_to_pile: Button = $Margin/VBox/BottomBar/Btn_DrawToPile
@onready var submission_status: Label = $Margin/VBox/SubmissionStatus
@onready var submission_blocker: Control = $SubmissionBlocker

signal cancel_confirmed
signal delete_confirmed
@onready var name_row: NameEditorUI = $Margin/VBox/NameRow
var _pile: Pile
@onready var btn_delete: Button = $Margin/VBox/BottomBar/Btn_Delete
@onready var delete_confirmation: ConfirmationDialog = $DeleteConfirmation

func open_for(pile: Pile) -> void:
	_pile = pile
	name_row.open_for(pile.get_node("NameEditor") as NameEditor)
	_pile.stack_changed.connect(_refresh_delete_button)
	_refresh_delete_button()

func _refresh_delete_button() -> void:
	if is_queued_for_deletion() or not is_instance_valid(btn_delete):
		return
	btn_delete.visible = is_instance_valid(_pile) and _pile.card_ID_stack.is_empty()
	if not btn_delete.visible and is_instance_valid(delete_confirmation):
		delete_confirmation.hide()

func _on_delete_pressed() -> void:
	_refresh_delete_button()
	if btn_delete.visible and _pile.accessor.i_am_viewing():
		delete_confirmation.popup_centered()

func _on_delete_confirmed() -> void:
	_refresh_delete_button()
	if btn_delete.visible and _pile.accessor.i_am_viewing():
		delete_confirmed.emit()
signal viewer_closed
signal orientation_operation_requested(operation: Const.PileOrientationOperation, card_IDs: Array[int])

# 1. 节点引用：严格匹配最新的 Margin/VBox 层级结构
@onready var margin: MarginContainer        = $Margin
@onready var scroll_top: ScrollContainer    = $Margin/VBox/Scroll_Top
@onready var list_top: HBoxContainer        = $Margin/VBox/Scroll_Top/List_Top
@onready var separator: HSeparator          = $Margin/VBox/HSeparator
@onready var scroll_bottom: ScrollContainer = $Margin/VBox/Scroll_Bottom
@onready var list_bottom: HBoxContainer     = $Margin/VBox/Scroll_Bottom/List_Bottom
@onready var btn_sort_ascend: Button  = $Margin/VBox/Top_Btns2/SortSection/Btn_SortAscend
@onready var btn_sort_descend: Button = $Margin/VBox/Top_Btns2/SortSection/Btn_SortDescend
@onready var btn_shuffle: Button      = $Margin/VBox/Top_Btns2/SortSection/Btn_Shuffle
@onready var btn_all_front: Button    = $Margin/VBox/Top_Btns/FlipSection/Btn_AllFront
@onready var btn_all_back: Button     = $Margin/VBox/Top_Btns/FlipSection/Btn_AllBack
@onready var btn_all_flip: Button     = $Margin/VBox/Top_Btns/FlipSection/Btn_AllFlip
@onready var btn_all_upright: Button  = $Margin/VBox/Top_Btns/DirectionSection/Btn_AllUpright
@onready var btn_all_inverted: Button = $Margin/VBox/Top_Btns/DirectionSection/Btn_AllInverted
@onready var btn_all_invert: Button   = $Margin/VBox/Top_Btns/DirectionSection/Btn_AllInvert
@onready var btn_random_face: Button  = $Margin/VBox/Top_Btns/FlipSection/Btn_RandomFace
@onready var btn_random_upright: Button = $Margin/VBox/Top_Btns/DirectionSection/Btn_RandomUpright
@onready var btn_reverse: Button = $Margin/VBox/Top_Btns2/SortSection/Btn_Reverse
@onready var btn_select_front: Button = $Margin/VBox/Top_Btns2/SelectSection/Btn_Front
@onready var btn_select_bottom: Button = $Margin/VBox/Top_Btns2/SelectSection/Btn_Bottom
@onready var btn_select_random: Button = $Margin/VBox/Top_Btns2/SelectSection/Btn_Random
@onready var input_number: LineEdit = $Margin/VBox/Top_Btns2/SelectSection/Input_Number
@onready var btn_cancel: Button       = $Margin/VBox/BottomBar/Btn_Cancel
@onready var btn_draw: Button         = $Margin/VBox/BottomBar/Btn_Draw

@onready var drag_preview: Control = $DragPreview
@onready var _card_db: CardDatabase = get_node("/root/Game/CardDatabase")

# 载入你的 UI 卡牌场景
var ui_card_scene := preload("res://UICard.tscn")

# 拖拽状态数据
var dragging_card: UICard
var drag_offset: Vector2
var _shuffle_sound_armed_at := -1   # R2：等待翻面类按钮操作的落地广播（2 秒过期）

# 【新增】光标与目标索引
var insert_cursor: ColorRect
var target_list: Control
var target_index: int

func _ready() -> void:
	_refresh_draw_button()
	# R6 排除：六大理牌按钮有自己的成功音，按下不响确认音（悬停音保留）；
	# node_added 连接确认音回调早于本 _ready 执行，因此回调内点击时检查组而非连接时检查
	for btn: Button in [btn_sort_ascend, btn_sort_descend, btn_shuffle, btn_reverse,
			btn_all_front, btn_all_back, btn_all_flip,
			btn_random_face, btn_random_upright]:
		btn.add_to_group(SfxManager.GROUP_NO_CONFIRM)

	_card_db.on_flip.connect(_check_flip_sound)
	_card_db.orientation_changed.connect(_on_orientation_changed)

	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	
	insert_cursor = ColorRect.new()
	insert_cursor.color = Color(1.0, 0.8, 0.2, 0.8) # 半透明橘黄色
	insert_cursor.custom_minimum_size = Vector2(6, 140) # 宽度6，高度建议跟你卡牌高度差不多
	insert_cursor.hide()
	insert_cursor.top_level = true # 设置为顶级节点，不受任何容器排版影响，随便飞
	add_child(insert_cursor)

func _refresh_draw_button() -> void:
	if is_queued_for_deletion() or not is_instance_valid(btn_draw) or not is_instance_valid(list_bottom):
		return
	btn_draw.visible = list_bottom.get_child_count() > 0
	if is_instance_valid(btn_draw_to_pile):
		btn_draw_to_pile.visible = btn_draw.visible

func load_deck(deck_list: Array[int]) -> void:
	# 1. 先正常加载已有的牌堆
	for card_ID in deck_list:
		var card := ui_card_scene.instantiate() as UICard
		card.preready(card_ID)
		list_top.add_child(card)
		card.drag_started.connect(_on_card_drag_started)
		card.orientation_requested.connect(_on_card_orientation_requested)
		
	# 2. 处理从 3D 强行塞入的牌
	#if injected_card_ID != -1:
		#var injected_card := ui_card_scene.instantiate() as UICard
		#injected_card.modulate.a = 0.0 # 先隐身，防止在排版完成前在屏幕上闪烁一下
		#list_top.add_child(injected_card)
		#injected_card.preready(injected_card_ID)
		#injected_card.drag_started.connect(_on_card_drag_started)
		#await get_tree().process_frame # 【绝杀修复】：交出当前帧的控制权，等 Godot 的 UI 容器完成真实排版！
		#if is_instance_valid(injected_card): # 确保 UI 没被玩家光速关掉
			#injected_card.modulate.a = 1.0 # 恢复可见度，并强行启动拖拽
			#_force_start_drag(injected_card)

func _on_sort_ascend_pressed():
	var children := list_top.get_children()
	if children.is_empty(): return   # 空列表无可"成功"的操作，不响
	children.sort_custom(func(a: Node, b: Node) -> bool:
		return _card_db.get_priority(int(a.name)) < _card_db.get_priority(int(b.name)))
	for i in range(children.size()):
		list_top.move_child(children[i], i)
	SfxManager.I.play(SfxManager.Snd.SHUFFLE_OK)   # R2：纯本地重排，回调结束即成功

func _on_sort_descend_pressed():
	var children := list_top.get_children()
	if children.is_empty(): return
	children.sort_custom(func(a: Node, b: Node) -> bool:
		return _card_db.get_priority(int(a.name)) > _card_db.get_priority(int(b.name)))
	for i in range(children.size()):
		list_top.move_child(children[i], i)
	SfxManager.I.play(SfxManager.Snd.SHUFFLE_OK)

func _on_shuffle_pressed():
	var children := list_top.get_children()
	if children.is_empty(): return
	children.shuffle()
	for i in range(children.size()):
		list_top.move_child(children[i], i)
	SfxManager.I.play(SfxManager.Snd.SHUFFLE_OK)

func _on_reverse_pressed() -> void:
	if dragging_card != null or list_top.get_child_count() < 2:
		return
	var children: Array[Node] = list_top.get_children()
	children.reverse()
	for index in range(children.size()):
		list_top.move_child(children[index], index)
	SfxManager.I.play(SfxManager.Snd.SHUFFLE_OK)

func _on_select_front_pressed() -> void:
	_select_cards(Const.CardSource.TOP)

func _on_select_bottom_pressed() -> void:
	_select_cards(Const.CardSource.BOTTOM)

func _on_select_random_pressed() -> void:
	_select_cards(Const.CardSource.RANDOM)

func _select_cards(source: Const.CardSource) -> void:
	if dragging_card != null:
		return
	var text: String = input_number.text.strip_edges()
	if not text.is_valid_int() or text.to_int() <= 0:
		return
	var children: Array[Node] = list_top.get_children()
	var count: int = mini(text.to_int(), children.size())
	if count == 0:
		return
	var indices: Array[int] = []
	for index in range(children.size()):
		indices.append(index)
	if source == Const.CardSource.BOTTOM:
		indices = indices.slice(children.size() - count)
	elif source == Const.CardSource.RANDOM:
		indices.shuffle()
		indices.resize(count)
		indices.sort() # 随机选子序列，仍按原牌列顺序追加。
	else:
		indices.resize(count)
	for index: int in indices:
		children[index].reparent(list_bottom, false)
	_refresh_draw_button()

func _on_number_focus_entered() -> void:
	Util.clear_pending_move_input()
	var game: GameSession = get_node_or_null("/root/Game") as GameSession
	if game != null and is_instance_valid(game.local_player):
		game.local_player.set_input_enabled(false)

func _on_number_focus_exited() -> void:
	Util.clear_pending_move_input()
	var game: GameSession = get_node_or_null("/root/Game") as GameSession
	if game != null and game.session_active and not game.pause_overlay.visible and not Util.board_locked(self) and is_instance_valid(game.local_player):
		game.local_player.set_input_enabled(true)

func _exit_tree() -> void:
	_on_number_focus_exited()

func _on_all_front_pressed():
	_arm_shuffle_sound()
	for child in list_top.get_children():
		var card := child as UICard
		card.request_flip_to(true)

func _on_all_back_pressed():
	_arm_shuffle_sound()
	for child in list_top.get_children():
		var card := child as UICard
		card.request_flip_to(false)

func _on_all_flip_pressed():
	_arm_shuffle_sound()
	for child in list_top.get_children():
		var card := child as UICard
		card.request_flip()

func _on_all_upright_pressed():
	_arm_shuffle_sound()
	_emit_orientation_operation(Const.PileOrientationOperation.ALL_UPRIGHT)

func _on_all_inverted_pressed():
	_arm_shuffle_sound()
	_emit_orientation_operation(Const.PileOrientationOperation.ALL_INVERTED)

func _on_all_invert_pressed():
	_arm_shuffle_sound()
	_emit_orientation_operation(Const.PileOrientationOperation.ALL_TOGGLE)

func _on_random_face_pressed():
	_arm_shuffle_sound()
	_emit_orientation_operation(Const.PileOrientationOperation.RANDOM_FACE)

func _on_random_upright_pressed():
	_arm_shuffle_sound()
	_emit_orientation_operation(Const.PileOrientationOperation.RANDOM_UPRIGHT)

func _on_card_orientation_requested(card_id: int) -> void:
	if _submission_pending:
		return
	var card_IDs: Array[int] = [card_id]
	orientation_operation_requested.emit(Const.PileOrientationOperation.SINGLE_TOGGLE, card_IDs)

func _emit_orientation_operation(operation: Const.PileOrientationOperation) -> void:
	var card_IDs: Array[int] = []
	for child in list_top.get_children() as Array[UICard]:
		card_IDs.append(child.card_ID())
	orientation_operation_requested.emit(operation, card_IDs)

func _on_orientation_changed(_updates: Dictionary) -> void:
	_check_flip_sound()
	for child in drag_preview.get_children():
		var preview := child as UICard
		if preview != null:
			preview.update_orientation()

func _arm_shuffle_sound():
	_shuffle_sound_armed_at = Time.get_ticks_msec()

func _check_flip_sound():
	if _shuffle_sound_armed_at > 0 and Time.get_ticks_msec() - _shuffle_sound_armed_at <= 2000:
		_shuffle_sound_armed_at = -1
		SfxManager.I.play(SfxManager.Snd.SHUFFLE_OK)   # R2：翻面类操作的落地广播到达，仅本端响一次

func _on_card_drag_started(card: UICard) -> void:
	if _submission_pending:
		return
	dragging_card = card
	drag_offset = drag_preview.get_global_mouse_position() - card.global_position
	
	card.hide() # 隐藏真实卡牌，不创建任何占位符！
	for child in drag_preview.get_children():
		child.queue_free()
	
	var visual_copy := card.duplicate() as UICard
	visual_copy.preready(card.card_ID())
	drag_preview.add_child(visual_copy)
	visual_copy.show()
	visual_copy.modulate.a = 0.7
	visual_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.show()
	SfxManager.I.play(SfxManager.Snd.PICKUP_CARD)   # 2D 理牌拖起，仅本端

func _on_cancel_pressed():
	if _submission_pending:
		return
	cancel_confirmed.emit()
	queue_free()

func _on_confirm_pressed():
	if _submission_pending:
		return
	var drawn_card_IDs: Array[int] = []
	for child in list_bottom.get_children() as Array[UICard]:
		drawn_card_IDs.append(child.card_ID())
			
	var deck_card_IDs: Array[int] = []
	for child in list_top.get_children() as Array[UICard]:
		deck_card_IDs.append(child.card_ID())
		
	draw_confirmed.emit(deck_card_IDs, drawn_card_IDs)

func _input(event: InputEvent) -> void:
	if _submission_pending:
		return
	if input_number.has_focus() and event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and key.keycode == KEY_ESCAPE:
			var game: GameSession = get_node_or_null("/root/Game") as GameSession
			if game != null:
				game._open_pause_menu()
			get_viewport().set_input_as_handled()
		return
	if Util.is_left_mouse_up(event):
		if dragging_card:
			_drop_card()

	elif Util.is_mouse_wheel_scroll(event):
		if not dragging_card: return
		var dir          := Util.get_mouse_wheel_direction(event)
		var mouse_pos    := get_viewport().get_mouse_position()
		var scroll_speed := 8
		if scroll_top.get_global_rect().has_point(mouse_pos):
			scroll_top.scroll_horizontal += scroll_speed * dir
		elif scroll_bottom.get_global_rect().has_point(mouse_pos):
			scroll_bottom.scroll_horizontal += scroll_speed * dir
				
	elif Util.is_right_mouse_down(event): # 拖拽时按下右键 -> 翻面
		if not dragging_card: return
		var right_click := event as InputEventMouseButton
		if right_click.shift_pressed:
			dragging_card.request_orientation_toggle()
		else:
			dragging_card._flip_sound_armed_at = Time.get_ticks_msec()   # R5-2D：拖拽翻面也是本端右键申请，武装音效
			dragging_card.request_flip()
		# 找到鼠标底下正在拖拽的“替身”，让它的视觉也同步刷新
		if drag_preview.get_child_count() > 0:
			var visual_copy = drag_preview.get_child(0) as UICard
			if visual_copy:
				visual_copy.update_ui()
				get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not dragging_card: return
	
	var mouse_pos = drag_preview.get_global_mouse_position()
	drag_preview.global_position = mouse_pos - drag_offset
	
	# 1. 判定在上方还是下方
	var sep_mid_y: float = separator.global_position.y + (separator.size.y / 2.0)
	target_list = list_top if mouse_pos.y < sep_mid_y else list_bottom
	
	var local_x := target_list.get_local_mouse_position().x
	target_index = target_list.get_child_count()
	var cursor_local_x: float = 0.0
	
	# 2. 遍历目标容器，找到鼠标插入点
	var child_count := target_list.get_child_count()
	for i in range(child_count):
		var child := target_list.get_child(i) as UICard
		# 忽略被隐藏的原卡
		if child == dragging_card or not child.visible: continue
		
		# 卡牌的中心点
		var center_x = child.position.x + (child.size.x / 2.0)
		if local_x < center_x:
			target_index = i
			# 光标定位在这张牌的左边缘稍微靠左一点
			cursor_local_x = child.position.x - 4.0 
			break
			
	# 3. 如果鼠标在所有牌的右侧，插在最后面
	if target_index == child_count:
		if child_count > 0:
			var last_child = target_list.get_child(-1)
			if last_child == dragging_card and child_count > 1:
				last_child = target_list.get_child(-2)
			# 光标定位在最后一张牌的右边缘
			cursor_local_x = last_child.position.x + last_child.size.x + 4.0
		else:
			cursor_local_x = 0.0 # 列表为空的情况
			
	# 4. 把光标放到计算好的位置并显示
	# 【修复报错】：UI 节点直接用 global_position 加上局部偏移即可
	var global_cursor_x: float = target_list.global_position.x + cursor_local_x
	insert_cursor.global_position = Vector2(global_cursor_x, target_list.global_position.y)
	
	# 让光标的高度跟容器对齐
	if target_list.size.y > 0:
		insert_cursor.size.y = target_list.size.y 
		
	insert_cursor.show()

func _drop_card() -> void:
	# 1. 隐藏光标，清理替身
	insert_cursor.hide()
	for child in drag_preview.get_children():
		child.queue_free()
	drag_preview.hide()
	
	# 【修复新增】：先记录卡牌原来的父节点和索引位置
	var original_parent = dragging_card.get_parent()
	var original_index = dragging_card.get_index()
	
	# 2. 拔出原卡
	if original_parent:
		original_parent.remove_child(dragging_card)
		
	# 【修复新增】：如果是同列表内从左往右拖，拔出原卡会导致后面的牌左移一位，目标索引必须减 1 修正
	if original_parent == target_list and original_index < target_index:
		target_index -= 1
		
	# 插入到目标索引
	target_list.add_child(dragging_card)
	target_list.move_child(dragging_card, target_index)
	
	# 3. 恢复显示
	dragging_card.show()
	dragging_card = null
	SfxManager.I.play(SfxManager.Snd.DROP_CARD)   # 2D 理牌放下，仅本端

#func _force_start_drag(card: UICard) -> void:
	#dragging_card = card
	#var c_size := card.size if card.size != Vector2.ZERO else card.custom_minimum_size
	#if c_size == Vector2.ZERO: c_size = Vector2(100, 140) 
	#drag_offset = c_size / 2.0 
	#
	#card.hide()
	#
	#for child in drag_preview.get_children():
		#child.queue_free()
		#
	#var visual_copy := card.duplicate() as UICard
	#drag_preview.add_child(visual_copy)
	#visual_copy.preready(card.card_ID()) #setup必须在add_child之后
	#visual_copy.show()
	#visual_copy.modulate.a = 0.7
	#visual_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#visual_copy.size = c_size
	#drag_preview.show()

func is_editing_text() -> bool:
	return name_row.is_editing_text() or input_number.has_focus()

func _on_draw_to_pile_pressed() -> void:
	if _submission_pending or dragging_card != null or not is_instance_valid(_pile):
		return
	if Util.board_locked(self) or not _pile.accessor.i_am_viewing():
		return
	var remaining_ids: Array[int] = []
	var extracted_ids: Array[int] = []
	for card: UICard in list_top.get_children():
		remaining_ids.append(card.card_ID())
	for card: UICard in list_bottom.get_children():
		extracted_ids.append(card.card_ID())
	if extracted_ids.is_empty():
		return
	_next_submission_id += 1
	_submission_id = _next_submission_id
	_submission_pending = true
	get_viewport().gui_release_focus()
	submission_blocker.show()
	submission_status.text = "正在取出到新牌堆…"
	submission_status.show()
	Util.clear_pending_move_input()
	draw_to_new_pile_confirmed.emit(remaining_ids, extracted_ids, _submission_id)

func extract_to_pile_failed(submission_id: int, reason: String) -> void:
	if is_queued_for_deletion() or not _submission_pending or submission_id != _submission_id:
		return
	_submission_pending = false
	submission_blocker.hide()
	submission_status.text = reason
	submission_status.show()
