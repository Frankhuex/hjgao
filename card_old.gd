extends StaticBody3D

const DRAGGING_Y       = 0.5
const TAKE_UP_DURATION = 0.1
const FLIP_DURATION    = 0.3

@onready var card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var card_sorter: CardSorter = get_node("/root/Game/CardSorter")
@onready var camera := get_viewport().get_camera_3d()
@onready var label  := $Pivot/Label3D
@onready var pivot  := $Pivot

var flip_tween : Tween

@export var card_ID: int
@export var is_dragging  := false
@export var drag_offset  := Vector3.ZERO
@export var fixed_y      := 0.0 
@export var target_rot_x := 0.0

### Initialization (done)

func server_preprocess(_card_ID: int):
	name = str(_card_ID)
	card_ID = card_ID
	
func _ready():
	if not multiplayer.is_server(): return
	multiplayer.peer_connected.connect(func(id: int): 
		if multiplayer.is_server():
			broadcast_unauto_sync_attrs.rpc(card_ID, global_rotation.y))
	self_got_authority.connect(func(): 
		if not multiplayer.is_server(): 
			set_is_dragging(true))
	self_lost_authority.connect(func(): 
		set_is_dragging(false))
	
func server_postprocess(spawn_global_position: Vector3, global_rotation_y: float, reorder: bool):
	server_set_autosync_attrs(spawn_global_position, reorder)
	broadcast_unauto_sync_attrs.rpc(card_ID, global_rotation_y)

func server_set_autosync_attrs(spawn_global_position: Vector3, reorder: bool):
	card_ID = int(name)
	card_sorter.server_register_card(self.card_ID, true)
	global_position = spawn_global_position

@rpc("any_peer", "call_local", "reliable")
func broadcast_unauto_sync_attrs(id: int, global_rotation_y):
	card_ID = id
	global_rotation.y = global_rotation_y
	fixed_y = Card.DRAGGING_Y
	label.text = card_database.get_card_name(id)
	var is_front := card_database.is_front(id)
	pivot.rotation_degrees.x = 0.0 if is_front else 180.0

### Authority System for dragging (done)
signal authority_changed(id: int)
signal self_got_authority
signal self_lost_authority
func request_authority():
	if not is_multiplayer_authority():
		server_give_authority.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_give_authority():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if get_multiplayer_authority() == 1:
		broadcast_set_authority.rpc(sender_id)
	else:
		print("拒绝来自 " + str(sender_id) + " 的请求，权限已被占用")

@rpc("authority", "call_local", "reliable")
func broadcast_set_authority(new_id: int):
	set_multiplayer_authority(new_id)
	authority_changed.emit(new_id)
	print(str(card_ID) + "权限已更新为: " + str(new_id))
	if is_multiplayer_authority():
		self_got_authority.emit()
	else:
		self_lost_authority.emit()

func return_authority():
	if is_multiplayer_authority():
		server_withdraw_authority.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_withdraw_authority():
	if not multiplayer.is_server(): return
	if get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		broadcast_set_authority.rpc(1)

func set_is_dragging(_is_dragging: bool):
	is_dragging = _is_dragging
	input_ray_pickable = not is_dragging

### card_sorter requests (done)

func request_bring_to_front():
	card_sorter.bring_to_front.rpc_id(1, card_ID)

func request_register_card(reorder: bool):
	card_sorter.server_register_card.rpc_id(1, card_ID, reorder)

func request_unregister_card():
	card_sorter.server_unregister_card.rpc_id(1, card_ID)















##########################################################################
# Not done

###
	
@rpc("any_peer", "call_local", "unreliable")
func broadcast_global_rotation_y(rot_y: float):
	global_rotation.y = rot_y

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


### Inputs

func _input_event(camera, event, _position, _normal, _shape_idx):
	#print("is_draggable: ",is_draggable())
	if event is InputEventMouseButton:
		if event.pressed:
			sync_rotation_y.rpc(camera.global_rotation.y)
			label.text = card_database.get_card_name(card_ID)

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
				handle_put_into_pile()

func handle_put_into_pile():
	var pile := will_fall_on_pile()
	if pile:
		var submitted := pile.request_receive_card_access()
		if submitted: 
			pile.self_got_access.connect(func(usage: Pile.Usage):
				if usage == Pile.Usage.RECEIVE_CARD:
					pile.let_server_receive_card(card_ID, Pile.CardSource.TOP))
			#server_destroy_card.rpc_id(1) # 销毁卡牌
			return
	set_is_dragging(false)
	request_bring_to_front()



func _process(_delta):
	if is_dragging:
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



func update_target_y(new_y: float):
	var t = create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "global_position:y", new_y, TAKE_UP_DURATION)

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
