class_name Util

static func is_left_mouse_down(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		return mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed
	return false
	
static func is_right_mouse_down(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		return mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed
	return false
	
static func is_left_mouse_up(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		return mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed
	return false
	
static func is_mouse_wheel_scroll(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		return mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	return false
	
static func get_mouse_wheel_direction(event: InputEvent) -> int:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		match mouse_event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN: return 1
			MOUSE_BUTTON_WHEEL_UP: return -1
			_: return 0
	return 0

static func tween_y(node: Node, target_y: float, duration: float):
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "global_position:y", target_y, duration)

static func tween_rot_x(node: Node, target_rot_x: float, duration: float):
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(node, "rotation_degrees:x", target_rot_x, duration)

static func is_server(node: Node) -> bool:
	return node.multiplayer.is_server()

static func not_server(node: Node) -> bool:
	return not node.multiplayer.is_server()
	
static func my_id(node: Node) -> int:
	return node.multiplayer.get_unique_id()
	
static func sender_id(node: Node) -> int:
	return node.multiplayer.get_remote_sender_id()

static func is_online(node: Node, peer_id: int) -> bool:
	return peer_id == my_id(node) or node.multiplayer.get_peers().has(peer_id)

static func is_offline(node: Node, peer_id: int) -> bool:
	return not is_online(node, peer_id)

static func get_mouse_intersect_horizontal_plane(node: Node, y: float) -> Variant:
	var camera     := node.get_viewport().get_camera_3d()
	var mouse_pos  := node.get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_normal := camera.project_ray_normal(mouse_pos)
	var plane      := Plane(Vector3.UP, y)
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_normal)
	return intersection
	
static func is_pile_input_purpose(purpose: Const.Purpose) -> bool:
	return purpose in Const.INPUT_SOURCE_TO_PURPOSE.values()
	
static func is_pile_output_purpose(purpose: Const.Purpose) -> bool:
	return purpose in Const.OUTPUT_SOURCE_TO_PURPOSE.values()

static func is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func safe_call_float(c: Callable) -> float:
	var res = c.call()
	var res_float := 0.0
	if typeof(res) == TYPE_FLOAT:
		res_float = res
	elif typeof(res) == TYPE_INT:
		var res_int: int = res
		res_float = float(res_int)
	print("safe_call_float: ", res_float)
	return res_float
