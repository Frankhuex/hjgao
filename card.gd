class_name Card
extends StaticBody3D

const DRAGGING_Y       = 0.5
const TAKE_UP_DURATION = 0.1
const FLIP_DURATION    = 0.3

@onready var card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var camera := get_viewport().get_camera_3d()
@onready var label  := $Pivot/Label3D
@onready var pivot  := $Pivot

var flip_tween : Tween
var card_sorter: CardSorter

@export var card_ID    : int
#@export var is_dragged_from_pile := false

@export var is_dragging  := false
@export var drag_offset  := Vector3.ZERO
@export var fixed_y      := 0.0 
@export var target_rot_x := 0.0

func _ready():
	if not card_sorter:
		var p = get_parent()
		while p != null and not (p is CardSorter):
			p = p.get_parent()
		if p is CardSorter:
			card_sorter = p
			#if not is_dragged_from_pile:
				#card_sorter.register_card(self)
	multiplayer.peer_connected.connect(func(id: int): 
		if multiplayer.is_server():
			broadcast_global_rotation_y.rpc(global_rotation.y))

@rpc("any_peer", "call_local", "reliable")
func broadcast_global_rotation_y(rot_y: float):
	global_rotation.y = rot_y

@rpc("any_peer", "call_local", "reliable")
func postprocess_from_pile(id: int, spawn_global_position: Vector3, global_rotation_y: float, reorder: bool):
	global_position = spawn_global_position
	global_rotation.y = global_rotation_y
	fixed_y = Card.DRAGGING_Y
	
	set_card(id)
	card_sorter.register_card(self, reorder)

@rpc("any_peer", "call_local", "reliable")
func set_is_dragging(_is_dragging: bool):
	is_dragging = _is_dragging
	input_ray_pickable = not is_dragging
	
func set_card(id: int):
	card_ID = id
	label.text = card_database.get_card_name(id)
	var is_front := card_database.is_front(id)
	rotation_degrees.x = 0.0 if is_front else 180.0

func update_target_y(new_y: float):
	#if fixed_y == new_y:
		#return 
	#fixed_y = new_y
	var t = create_tween()
	# 可选：加上 ease_out 会让动画在快到位时更平滑
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "global_position:y", new_y, TAKE_UP_DURATION)
	
func _input_event(camera, event, _position, _normal, _shape_idx):
	#print("is_draggable: ",is_draggable())
	if event is InputEventMouseButton:
		if event.pressed:
			card_sorter.register_card(self, false)
			sync_rotation_y.rpc(camera.global_rotation.y)

		#左键按到牌
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and is_draggable():
			request_authority.rpc_id(1, multiplayer.get_unique_id())
			input_ray_pickable = false
			fixed_y = DRAGGING_Y
			update_target_y(DRAGGING_Y)
			is_dragging = true
			var intersection = get_mouse_position_on_plane()
			if intersection != null:
				drag_offset = global_position - intersection
			get_viewport().set_input_as_handled() 
		#右键按到牌
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			flip_box.rpc()
			get_viewport().set_input_as_handled()

func _input(event):
	if event is InputEventMouseButton:
		#右键按下
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: 
			if is_dragging:
				var hovered_pile := get_hovered_pile()
				if hovered_pile: # 这个空指针判断要留下，用于区分是否有正在拖的牌
					# 通知牌堆接管这张牌
					var success := hovered_pile.insert_card_to_viewer(self)
					if not success:
						flip_box.rpc()
				else:
					flip_box.rpc()
				get_viewport().set_input_as_handled()
		#左键松开
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: 
			if is_dragging:
				is_dragging = false
				input_ray_pickable = true 
				var pile := will_fall_on_pile()
				if pile:
					var success := pile.receive_card_and_call_server_to_broadcast(card_ID, Pile.CardSource.TOP)
					if success:
						server_destroy_card.rpc_id(1) # 销毁卡牌
						return
				server_bring_to_front.rpc_id(1)
				release_authority.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func sync_rotation_y(new_y_rot: float):
	global_rotation.y = new_y_rot
	print("sync_rotation_y: ", new_y_rot)

@rpc("any_peer", "call_local", "reliable")
func flip_box():
	card_database.flip(card_ID)
	var is_animating := flip_tween and flip_tween.is_valid()
	if not is_animating:
		target_rot_x = pivot.rotation_degrees.x
	target_rot_x += 180.0
	if is_animating:
		flip_tween.kill()
	flip_tween = create_tween()
	flip_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(pivot, "rotation_degrees:x", target_rot_x, FLIP_DURATION)

@rpc("any_peer", "call_local", "reliable")
func server_destroy_card():
	card_sorter.unregister_card(card_ID)
	queue_free()

@rpc("any_peer", "call_local", "reliable")
func server_bring_to_front():
	card_sorter.bring_to_front(card_ID)

func _process(_delta):
	#print(is_multiplayer_authority())
	if is_dragging and is_multiplayer_authority():
		var pile := will_fall_on_pile()
		if pile:
			update_target_y(pile.get_y_when_over_pile())
		else:		
			update_target_y(DRAGGING_Y)
		var intersection = get_mouse_position_on_plane()
		if intersection != null:
			var target_pos = intersection + drag_offset
			global_position.x = target_pos.x
			global_position.z = target_pos.z

func get_hovered_pile() -> Pile:
	if not camera: return null
	var space_state := get_world_3d().direct_space_state
	var mouse_pos   := get_viewport().get_mouse_position()
	var ray_origin  := camera.project_ray_origin(mouse_pos)
	var ray_end     := ray_origin + camera.project_ray_normal(mouse_pos) * 100
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	
	var result := space_state.intersect_ray(query)
	if result and result.collider is Pile:
		return result.collider as Pile
	return null

func will_fall_on_pile() -> Pile:
	if not camera: return null
	
	# 射线检测鼠标下方的物体
	var space_state := get_world_3d().direct_space_state
	var mouse_pos   := get_viewport().get_mouse_position()
	var ray_origin  := camera.project_ray_origin(mouse_pos)
	var ray_end     := ray_origin + camera.project_ray_normal(mouse_pos) * 100
	
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [get_rid()] # 排除自己，避免射线撞到正在拖拽的牌
	query.collide_with_areas = true # 开启区域检测
	
	var result := space_state.intersect_ray(query)
	if result:
		var hit_obj = result.collider
		if hit_obj is Pile:
			return hit_obj
		elif hit_obj is Hotspot:
			return hit_obj.parent_pile
	return null

func get_mouse_position_on_plane() -> Variant:
	if not camera: return null
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_normal := camera.project_ray_normal(mouse_pos)
	var plane := Plane(Vector3.UP, fixed_y)
	return plane.intersects_ray(ray_origin, ray_normal)

func is_draggable() -> bool:
	return (get_multiplayer_authority() == 1 or multiplayer.is_server()) and not is_dragging

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
	print("peer_id "+str(peer_id)+" gets authority for card_id "+str(card_ID))
