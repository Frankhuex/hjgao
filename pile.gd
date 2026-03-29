@tool
class_name Pile
extends StaticBody3D

@onready var mesh      := $CSGBox3D
@onready var collision := $CollisionShape3D 
@onready var label     := $Label3D
@onready var camera    := get_viewport().get_camera_3d()

@export var card_sorter      : CardSorter
@export var card_scene       : PackedScene
@export var deck_viewer_scene: PackedScene

var card_ID_stack: Array[int]

var is_dragging_pile := false
var drag_offset      := Vector3.ZERO

const HEIGHT_ABOVE_PILE = 0.02
const CARD_THICKNESS    = 0.01
const SMALL_LENGTH      = 0.001
const BASE_THICKNESS    = 0.05

enum CardSource {
	TOP = 0,
	BOTTOM = 1,
	RANDOM = 2,
}

func _ready():
	card_ID_stack = CardDatabase.instance().get_all_IDs().duplicate()
	_update_visuals()

func _update_visuals():
	if not is_node_ready(): return
	var h := card_ID_stack.size() * CARD_THICKNESS
	label.text = str(len(card_ID_stack))
	label.position.y = h + SMALL_LENGTH + BASE_THICKNESS
	mesh.size.y = max(h, SMALL_LENGTH)
	mesh.position.y = h / 2.0 + BASE_THICKNESS
	collision.shape = collision.shape.duplicate() # 独立化资源
	collision.shape.size.y = max(h, SMALL_LENGTH)
	collision.position.y = h / 2.0 + BASE_THICKNESS

func _input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		# 【抽牌】：左键按下且有牌
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if card_ID_stack.size() > 0:
				spawn_and_drag_card(CardSource.TOP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			open_deck_viewer()
			get_viewport().set_input_as_handled()

func _on_hotspot_bottom_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if card_ID_stack.size() > 0:
				spawn_and_drag_card(CardSource.BOTTOM)
			get_viewport().set_input_as_handled()

func _on_hotspot_random_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if card_ID_stack.size() > 0:
				spawn_and_drag_card(CardSource.RANDOM)
			get_viewport().set_input_as_handled()

func spawn_and_drag_card(card_source: CardSource):
	if card_ID_stack.is_empty(): return
	
	var drawn_card_ID: int
	match card_source:
		CardSource.TOP:
			drawn_card_ID = card_ID_stack.pop_back()
		CardSource.BOTTOM:
			drawn_card_ID = card_ID_stack.pop_front()
		CardSource.RANDOM:
			var random_index = randi() % card_ID_stack.size()
			drawn_card_ID = card_ID_stack.pop_at(random_index)
	
	var new_card := card_scene.instantiate()
	
	new_card.is_dragged_from_pile = true
	card_sorter.add_child(new_card) 
	
	var spawn_y: float
	match card_source:
		CardSource.TOP:
			spawn_y = get_y_when_over_pile()
		_:
			spawn_y = Card.DRAGGING_Y
			
	new_card.global_position = self.global_position
	new_card.global_position.y = spawn_y
	new_card.fixed_y = Card.DRAGGING_Y
	new_card.is_dragging = true
	new_card.input_ray_pickable = false
	new_card.set_card(drawn_card_ID)
		
	_update_visuals()

# 【回收】：供卡牌调用
func receive_card(returned_card_ID: int, card_source: CardSource):
	match card_source:
		CardSource.TOP:
			card_ID_stack.push_back(returned_card_ID)
		CardSource.BOTTOM:
			card_ID_stack.push_front(returned_card_ID)
		CardSource.RANDOM:
			var idx = randi() % (card_ID_stack.size() + 1)
			card_ID_stack.insert(idx, returned_card_ID)
	_update_visuals()
	
func get_y_when_over_pile() -> float:
	return BASE_THICKNESS + card_ID_stack.size() * CARD_THICKNESS + HEIGHT_ABOVE_PILE


func _on_base_area_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			is_dragging_pile = true
			
			# 计算鼠标偏移量，防止牌堆中心瞬间瞬移到鼠标上
			var intersection = get_mouse_position_on_plane()
			if intersection != null:
				drag_offset = global_position - intersection
			
			get_viewport().set_input_as_handled()
			
# 【新增】：全局鼠标松开事件，用于停止拖拽
func _input(event):
	# ⚠️ 重要：因为你有 @tool，这行能防止你在编辑器里乱点把牌堆拖走
	if Engine.is_editor_hint(): return 
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_dragging_pile:
				is_dragging_pile = false

# 【新增】：每帧更新牌堆位置
func _process(delta):
	if Engine.is_editor_hint(): return # 防止在编辑器里执行
	
	if is_dragging_pile:
		var intersection = get_mouse_position_on_plane()
		var target_pos = intersection + drag_offset
		
		# 拖牌堆只改变 X 和 Z，Y 轴（高度）保持不变
		global_position.x = target_pos.x
		global_position.z = target_pos.z

# 【新增】：获取鼠标在牌堆底面上的三维坐标
func get_mouse_position_on_plane() -> Variant:
	if not camera: return null
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_normal := camera.project_ray_normal(mouse_pos)
	
	# 以牌堆当前的 Y 坐标作为拖拽平面
	var plane := Plane(Vector3.UP, global_position.y)
	return plane.intersects_ray(ray_origin, ray_normal)

func open_deck_viewer(injected_card_ID: int = -1):
	var viewer := deck_viewer_scene.instantiate()
	get_tree().root.add_child(viewer)
	viewer.load_deck(card_ID_stack, injected_card_ID) # 内有-1判断逻辑
	viewer.draw_confirmed.connect(_on_draw_confirmed)

# 【新增】供 Card 调用的方法：接管 3D 卡牌
func insert_card_to_viewer(dragged_card: Card):
	open_deck_viewer(dragged_card.card_ID)
	
	# 彻底销毁 3D 卡牌，完成交接
	card_sorter.unregister_card(dragged_card)
	dragged_card.queue_free()

func _on_draw_confirmed(new_deck_cards: Array[int], drawn_cards: Array[int]):
	card_ID_stack = new_deck_cards
	_update_visuals()
	if drawn_cards.is_empty(): return
	
	# 如果牌堆在屏幕左边，牌往右排（X轴正方向）；如果在右边，牌往左排（X轴负方向）
	var is_on_left_side := global_position.x < 0
	var spawn_direction := 1.0 if is_on_left_side else -1.0
	var main_offset     := 1.0
	var spacing         := 0.12 # 每张牌的间距
	
	# 依次生成选出的牌
	for i in range(drawn_cards.size()):
		var card_ID   := drawn_cards[i]
		var new_card := card_scene.instantiate()
		card_sorter.add_child(new_card)
		
		# 位置偏移
		var offset_x  := spawn_direction * ((i + 1) * spacing + main_offset)
		var spawn_pos := self.global_position + Vector3(offset_x, Card.DRAGGING_Y, 0)
		
		new_card.global_position = spawn_pos
		new_card.fixed_y = Card.DRAGGING_Y
		new_card.set_card(card_ID)
		
		# 因为是取出到桌面，直接算作非拖拽状态并注册
		new_card.is_dragging = false
		new_card.is_dragged_from_pile = false
		card_sorter.register_card(new_card)

#func shuffle():
	#card_ID_stack.shuffle()
