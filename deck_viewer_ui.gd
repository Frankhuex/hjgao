class_name DeckViewerUI
extends CanvasLayer

signal draw_confirmed(updated_card_ID_stack: Array[int], drawn_cards: Array[int])
signal cancel_confirmed
signal viewer_closed

# 1. 节点引用：严格匹配最新的 Margin/VBox 层级结构
@onready var margin: MarginContainer        = $Margin
@onready var scroll_top: ScrollContainer    = $Margin/VBox/Scroll_Top
@onready var list_top: HBoxContainer        = $Margin/VBox/Scroll_Top/List_Top
@onready var separator: HSeparator          = $Margin/VBox/HSeparator
@onready var scroll_bottom: ScrollContainer = $Margin/VBox/Scroll_Bottom
@onready var list_bottom: HBoxContainer     = $Margin/VBox/Scroll_Bottom/List_Bottom
@onready var btn_sort_ascend: Button  = $Margin/VBox/Top_Btns/Btn_SortAscend
@onready var btn_sort_descend: Button = $Margin/VBox/Top_Btns/Btn_SortDescend
@onready var btn_shuffle: Button      = $Margin/VBox/Top_Btns/Btn_Shuffle
@onready var btn_all_front: Button    = $Margin/VBox/Top_Btns/Btn_AllFront
@onready var btn_all_back: Button     = $Margin/VBox/Top_Btns/Btn_AllBack
@onready var btn_all_flip: Button     = $Margin/VBox/Top_Btns/Btn_AllFlip
@onready var btn_cancel: Button       = $Margin/VBox/BottomBar/Btn_Cancel
@onready var btn_draw: Button         = $Margin/VBox/BottomBar/Btn_Draw

@onready var drag_preview: Control = $DragPreview
@onready var _card_db: CardDatabase = get_node("/root/Game/CardDatabase")

# 载入你的 UI 卡牌场景
var ui_card_scene := preload("res://UICard.tscn")

# 拖拽状态数据
var dragging_card: UICard
var drag_offset: Vector2

# 【新增】光标与目标索引
var insert_cursor: ColorRect
var target_list: Control
var target_index: int

func _ready() -> void:
	btn_sort_ascend.pressed.connect(_on_sort_ascend_pressed)
	btn_sort_descend.pressed.connect(_on_sort_descend_pressed)
	btn_shuffle.pressed.connect(_on_shuffle_pressed)
	btn_all_front.pressed.connect(_on_all_front_pressed)
	btn_all_back.pressed.connect(_on_all_back_pressed)
	btn_all_flip.pressed.connect(_on_all_flip_pressed)
	btn_cancel.pressed.connect(_on_cancel_pressed)
	btn_draw.pressed.connect(_on_confirm_pressed)
	
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	
	insert_cursor = ColorRect.new()
	insert_cursor.color = Color(1.0, 0.8, 0.2, 0.8) # 半透明橘黄色
	insert_cursor.custom_minimum_size = Vector2(6, 140) # 宽度6，高度建议跟你卡牌高度差不多
	insert_cursor.hide()
	insert_cursor.top_level = true # 设置为顶级节点，不受任何容器排版影响，随便飞
	add_child(insert_cursor)

func load_deck(deck_list: Array[int]) -> void:
	# 1. 先正常加载已有的牌堆
	for card_ID in deck_list:
		var card := ui_card_scene.instantiate() as UICard
		card.preready(card_ID)
		list_top.add_child(card)
		card.drag_started.connect(_on_card_drag_started)
		
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
	children.sort_custom(func(a: Node, b: Node) -> bool:
		return _card_db.get_priority(int(a.name)) < _card_db.get_priority(int(b.name)))
	for i in range(children.size()):
		list_top.move_child(children[i], i)

func _on_sort_descend_pressed():
	var children := list_top.get_children()
	children.sort_custom(func(a: Node, b: Node) -> bool:
		return _card_db.get_priority(int(a.name)) > _card_db.get_priority(int(b.name)))
	for i in range(children.size()):
		list_top.move_child(children[i], i)

func _on_shuffle_pressed():
	var children := list_top.get_children()
	children.shuffle()
	for i in range(children.size()):
		list_top.move_child(children[i], i)

func _on_all_front_pressed():
	for child in list_top.get_children():
		var card := child as UICard
		card.request_flip_to(true)

func _on_all_back_pressed():
	for child in list_top.get_children():
		var card := child as UICard
		card.request_flip_to(false)

func _on_all_flip_pressed():
	for child in list_top.get_children():
		var card := child as UICard
		card.request_flip()

func _on_card_drag_started(card: UICard) -> void:
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

func _on_cancel_pressed():
	cancel_confirmed.emit()
	queue_free()

func _on_confirm_pressed():
	var drawn_card_IDs: Array[int] = []
	for child in list_bottom.get_children() as Array[UICard]:
		drawn_card_IDs.append(child.card_ID())
			
	var deck_card_IDs: Array[int] = []
	for child in list_top.get_children() as Array[UICard]:
		deck_card_IDs.append(child.card_ID())
		
	draw_confirmed.emit(deck_card_IDs, drawn_card_IDs)

func _input(event: InputEvent) -> void:
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
