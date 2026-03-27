class_name DeckViewerUI
extends CanvasLayer

signal draw_confirmed(new_deck_list: Array[String], drawn_cards: Array[String])
signal viewer_closed

# 1. 节点引用：严格匹配最新的 Margin/VBox 层级结构
@onready var scroll_top    := $Margin/VBox/Scroll_Top
@onready var list_top      := $Margin/VBox/Scroll_Top/List_Top
@onready var scroll_bottom := $Margin/VBox/Scroll_Bottom
@onready var list_bottom   := $Margin/VBox/Scroll_Bottom/List_Bottom
@onready var drag_preview  := $DragPreview
@onready var separator     := $Margin/VBox/HSeparator

# 载入你的 UI 卡牌场景
var ui_card_scene := preload("res://UICard.tscn")

# 拖拽状态数据
var dragging_card: UICard = null
var drag_offset := Vector2.ZERO

# 【新增】光标与目标索引
var insert_cursor: ColorRect = null
var target_list  : Control   = null
var target_index : int       = 0

func _ready() -> void:
	$Margin/VBox/BottomBar/Btn_Draw.pressed.connect(confirm_draw)
	
	$Margin.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# 【新增】：动态创建插入光标（一根发光的竖线）
	insert_cursor = ColorRect.new()
	insert_cursor.color = Color(1.0, 0.8, 0.2, 0.8) # 半透明橘黄色
	insert_cursor.custom_minimum_size = Vector2(6, 140) # 宽度6，高度建议跟你卡牌高度差不多
	insert_cursor.hide()
	
	# 设置为顶级节点，不受任何容器排版影响，随便飞
	insert_cursor.top_level = true 
	add_child(insert_cursor)

# 初始化牌堆
func load_deck(deck_list: Array[String], injected_card_name: String = "") -> void:
	# 1. 先正常加载已有的牌堆
	for c_name in deck_list:
		var card := ui_card_scene.instantiate() as UICard
		list_top.add_child(card)
		card.setup(c_name)
		card.drag_started.connect(_on_card_drag_started)
		
	# 2. 处理从 3D 强行塞入的牌
	if injected_card_name != "":
		var injected_card := ui_card_scene.instantiate() as UICard
		# 先隐身，防止在排版完成前在屏幕上闪烁一下
		injected_card.modulate.a = 0.0 
		list_top.add_child(injected_card)
		injected_card.setup(injected_card_name)
		injected_card.drag_started.connect(_on_card_drag_started)
		
		# 【绝杀修复】：交出当前帧的控制权，等 Godot 的 UI 容器完成真实排版！
		await get_tree().process_frame 
		
		# 确保 UI 没被玩家光速关掉
		if is_instance_valid(injected_card): 
			# 恢复可见度，并强行启动拖拽
			injected_card.modulate.a = 1.0
			_force_start_drag(injected_card)
	
# _force_start_drag 也是同理，只设 offset，隐藏本体，创建替身，不建占位符
func _force_start_drag(card: UICard) -> void:
	dragging_card = card
	var c_size := card.size if card.size != Vector2.ZERO else card.custom_minimum_size
	if c_size == Vector2.ZERO: c_size = Vector2(100, 140) 
	drag_offset = c_size / 2.0 
	
	card.hide()
	
	var visual_copy := card.duplicate() as Control
	visual_copy.show()
	visual_copy.modulate.a = 0.7
	visual_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_copy.size = c_size
	
	for child in drag_preview.get_children():
		child.queue_free()
	drag_preview.add_child(visual_copy)
	drag_preview.show()
			
# --- 核心 1：开始拖拽 ---
func _on_card_drag_started(card: UICard) -> void:
	dragging_card = card
	drag_offset = drag_preview.get_global_mouse_position() - card.global_position
	
	# 隐藏真实卡牌，不创建任何占位符！
	card.hide()
	
	var visual_copy := card.duplicate() as Control
	visual_copy.show()
	visual_copy.modulate.a = 0.7
	visual_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	
	for child in drag_preview.get_children():
		child.queue_free()
	drag_preview.add_child(visual_copy)
	drag_preview.show()	
# --- 核心 2：系统输入监控（松手与滚轮） ---
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		
		# 松开左键 -> 结算放置
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			if dragging_card:
				_drop_card()
				
		# 拖动时允许鼠标滚轮分别滚动上下排
		elif dragging_card and (mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var dir          := -1 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			var mouse_pos    := get_viewport().get_mouse_position()
			var scroll_speed := 8
			if scroll_top.get_global_rect().has_point(mouse_pos):
				scroll_top.scroll_horizontal += scroll_speed * dir
			elif scroll_bottom.get_global_rect().has_point(mouse_pos):
				scroll_bottom.scroll_horizontal += scroll_speed * dir

# --- 核心 3：每帧更新占位符（实时排版） ---
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
		var child := target_list.get_child(i)
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
	
# --- 核心 4：放置并恢复卡牌 ---
func _drop_card() -> void:
	# 1. 隐藏光标，清理替身
	insert_cursor.hide()
	for child in drag_preview.get_children():
		child.queue_free()
	drag_preview.hide()
	
	# 2. 拔出原卡并插入到目标索引
	if dragging_card.get_parent():
		dragging_card.get_parent().remove_child(dragging_card)
		
	target_list.add_child(dragging_card)
	target_list.move_child(dragging_card, target_index)
	
	# 3. 恢复显示
	dragging_card.show()
	dragging_card = null

func confirm_draw() -> void:
	var drawn_names: Array[String] = []
	for child in list_bottom.get_children():
		if child is UICard:
			drawn_names.append(child.card_name)
			
	var deck_names: Array[String] = []
	for child in list_top.get_children():
		if child is UICard:
			deck_names.append(child.card_name)
			
	# 发出信号：同时传回更新后的牌堆、以及抽出来的牌
	draw_confirmed.emit(deck_names, drawn_names)
	
	queue_free()
