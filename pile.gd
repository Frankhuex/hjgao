@tool
class_name Pile
extends StaticBody3D

@onready var mesh      := $CSGBox3D
@onready var collision := $CollisionShape3D 
@onready var label     := $Label3D
@onready var camera    := get_viewport().get_camera_3d()
@onready var card_sorter: CardSorter = get_node("/root/Game/CardSorter")
@onready var card_database: CardDatabase = get_node("/root/Game/CardDatabase")

const CARD        = preload("res://Card.tscn")
const DECK_VIEWER = preload("res://DeckViewerUI.tscn")

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
	#card_ID_stack = card_database.get_all_IDs()
	stack_updated.connect(_update_visuals)
	multiplayer.peer_connected.connect(func(id: int): 
		if multiplayer.is_server():
			broadcast_card_ID_stack.rpc(card_ID_stack)
			broadcast_global_rotation_y.rpc(global_rotation.y)
	)
	_update_visuals(	)
	
@rpc("any_peer", "call_local", "reliable")
func broadcast_global_rotation_y(rot_y: float):
	global_rotation.y = rot_y
	
#################################################################
var card_ID_stack: Array[int]
signal stack_updated
func call_server_to_broadcast_card_ID_stack():
	server_broadcast_card_ID_stack.rpc_id(1, card_ID_stack)

@rpc("any_peer", "call_local", "reliable")
func server_broadcast_card_ID_stack(new_data: Array):
	card_ID_stack = Array(new_data, TYPE_INT, &"", null)
	broadcast_card_ID_stack.rpc(card_ID_stack)

@rpc("authority", "call_local", "reliable")
func broadcast_card_ID_stack(data: Array):
	card_ID_stack = Array(data, TYPE_INT, &"", null)
	stack_updated.emit()
	print("pile.broadcast_card_ID_stack: ", card_ID_stack.size())

#################################################################
var is_being_accessed := false
func sync_set_is_being_accessed(_is_being_accessed):
	print("sync_set_is_being_accessed: ",_is_being_accessed)
	server_broadcast_accessibility.rpc_id(1, _is_being_accessed)

@rpc("any_peer", "call_local", "reliable")
func server_broadcast_accessibility(_is_being_accessed: bool):
	if multiplayer.is_server():
		broadcast_accessibility.rpc(_is_being_accessed)

@rpc("authority", "call_local", "reliable")
func broadcast_accessibility(_is_being_accessed: bool):
	is_being_accessed = _is_being_accessed
	print("broadcast_accessibility: ",is_being_accessed)

#################################################################
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
		#按下左键
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if card_ID_stack.size() > 0:
				spawn_and_drag_card(CardSource.TOP)
			get_viewport().set_input_as_handled()
		#按下右键
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			open_deck_viewer()
			get_viewport().set_input_as_handled()

func _on_hotspot_bottom_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if is_being_accessed: return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if card_ID_stack.size() > 0:
				spawn_and_drag_card(CardSource.BOTTOM)
			get_viewport().set_input_as_handled()

func _on_hotspot_random_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if is_being_accessed: return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if card_ID_stack.size() > 0:
				spawn_and_drag_card(CardSource.RANDOM)
			get_viewport().set_input_as_handled()

func spawn_and_drag_card(card_source: CardSource):
	if card_ID_stack.is_empty(): return
	if is_being_accessed: return
	
	var drawn_card_ID: int
	var spawn_y: float
	match card_source:
		CardSource.BOTTOM:
			drawn_card_ID = card_ID_stack.pop_back()
			spawn_y = get_y_when_over_pile()
		CardSource.TOP:
			drawn_card_ID = card_ID_stack.pop_front()
			spawn_y = Card.DRAGGING_Y
		CardSource.RANDOM:
			var random_index = randi() % card_ID_stack.size()
			drawn_card_ID = card_ID_stack.pop_at(random_index)
			spawn_y = Card.DRAGGING_Y
	call_server_to_broadcast_card_ID_stack()
	
	var spawn_global_position := global_position
	spawn_global_position.y = spawn_y
	server_init_card.rpc_id(1, drawn_card_ID, spawn_global_position, camera.global_rotation.y, multiplayer.get_unique_id(), true)
	#_update_visuals()

@rpc("any_peer", "call_local", "reliable")
func server_init_card(drawn_card_ID: int, spawn_global_position: Vector3, global_rotation_y: float, client_ID: int, is_dragging: bool):
	var new_card: Card = CARD.instantiate()
	new_card.name = str(drawn_card_ID)
	card_sorter.add_child(new_card)
	new_card.postprocess_from_pile.rpc(drawn_card_ID, spawn_global_position, global_rotation_y, not is_dragging)
	new_card.set_is_dragging.rpc_id(client_ID, is_dragging)
	if is_dragging:
		new_card.broadcast_set_authority_to.rpc(client_ID)
	else:
		new_card.broadcast_set_authority_to.rpc(1)

#func postprocess_card(new_card: Card, id: int, card_source: CardSource):
	#var spawn_y: float
	#match card_source:
		#CardSource.TOP:
			#spawn_y = get_y_when_over_pile()
		#_:
			#spawn_y = Card.DRAGGING_Y
	#new_card.global_position = self.global_position
	#new_card.global_position.y = spawn_y
	#new_card.fixed_y = Card.DRAGGING_Y
	#new_card.is_dragging = true
	#new_card.input_ray_pickable = false
	#new_card.set_card(id)

# 【回收】：供卡牌调用
func receive_card_and_call_server_to_broadcast(returned_card_ID: int, card_source: CardSource) -> bool:
	if is_being_accessed: return false
	sync_set_is_being_accessed(true)
	match card_source:
		CardSource.BOTTOM:
			card_ID_stack.push_back(returned_card_ID)
		CardSource.TOP:
			card_ID_stack.push_front(returned_card_ID)
		CardSource.RANDOM:
			var idx = randi() % (card_ID_stack.size() + 1)
			card_ID_stack.insert(idx, returned_card_ID)
	call_server_to_broadcast_card_ID_stack()
	#_update_visuals()
	sync_set_is_being_accessed(false)
	return true
	
func get_y_when_over_pile() -> float:
	return BASE_THICKNESS + card_ID_stack.size() * CARD_THICKNESS + HEIGHT_ABOVE_PILE


func _on_base_area_input_event(camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		#底座按下左键
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not is_dragging_pile:
			sync_rotation_y.rpc(camera.global_rotation.y)
			request_authority.rpc_id(1, multiplayer.get_unique_id())
			is_dragging_pile = true
			
			# 计算鼠标偏移量，防止牌堆中心瞬间瞬移到鼠标上
			var intersection = get_mouse_position_on_plane()
			if intersection != null:
				drag_offset = global_position - intersection
			
			get_viewport().set_input_as_handled()

@rpc("any_peer", "call_local", "reliable")
func sync_rotation_y(new_y_rot: float):
	global_rotation.y = new_y_rot
		
# 【新增】：全局鼠标松开事件，用于停止拖拽
func _input(event):
	# ⚠️ 重要：因为你有 @tool，这行能防止你在编辑器里乱点把牌堆拖走
	if Engine.is_editor_hint(): return 
	if event is InputEventMouseButton:
		#（底座）松开左键
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_dragging_pile:
				release_authority.rpc_id(1)
				is_dragging_pile = false

func _process(_delta):
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
	if is_being_accessed: return
	sync_set_is_being_accessed(true)
	var viewer: DeckViewerUI = DECK_VIEWER.instantiate()
	get_tree().root.add_child(viewer)
	viewer.load_deck(card_ID_stack, injected_card_ID) # 内有-1判断逻辑
	viewer.draw_confirmed.connect(_on_draw_confirmed)
	viewer.cancel_confirmed.connect(_on_cancel)

func insert_card_to_viewer(dragged_card: Card) -> bool:
	if is_being_accessed: return false
	open_deck_viewer(dragged_card.card_ID)
	
	dragged_card.server_destroy_card.rpc_id(1)
	dragged_card.visible = false # 客户端本地瞬间隐藏，手感更好
	return true

func _on_draw_confirmed(new_deck_cards: Array[int], drawn_cards: Array[int]):
	sync_set_is_being_accessed(false)
	card_ID_stack = new_deck_cards
	call_server_to_broadcast_card_ID_stack()
	#_update_visuals()
	if drawn_cards.is_empty(): return
	
	# 如果牌堆在屏幕左边，牌往右排（X轴正方向）；如果在右边，牌往左排（X轴负方向）
	var is_on_left_side := global_position.x < 0
	var spawn_direction := 1.0 if is_on_left_side else -1.0
	var main_offset     := 1.0
	var spacing         := 0.12 # 每张牌的间距
	
	# 依次生成选出的牌
	for i in range(drawn_cards.size()):
		var card_ID   := drawn_cards[i]
		var offset_x  := spawn_direction * ((i + 1) * spacing + main_offset)
		var spawn_global_position := self.global_position + Vector3(offset_x, Card.DRAGGING_Y, 0)
		server_init_card.rpc_id(1, card_ID, spawn_global_position, camera.global_rotation.y, multiplayer.get_unique_id(), false)
	


func _on_cancel():
	sync_set_is_being_accessed(false)

@rpc("any_peer", "call_local", "reliable")
func request_authority(peer_id: int):
	if multiplayer.is_server():
		broadcast_set_authority_to.rpc(peer_id)

@rpc("any_peer", "call_local", "reliable")
func release_authority():
	if multiplayer.is_server():
		broadcast_set_authority_to.rpc(1)

@rpc("any_peer", "call_local", "reliable")
func broadcast_set_authority_to(peer_id: int):
	set_multiplayer_authority(peer_id)
