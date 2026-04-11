class_name Util

static func is_left_mouse_down(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var event_mouse_button: InputEventMouseButton = event
		return event_mouse_button.button_index == MOUSE_BUTTON_LEFT and event_mouse_button.pressed
	return false
	
static func is_right_mouse_down(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var event_mouse_button: InputEventMouseButton = event
		return event_mouse_button.button_index == MOUSE_BUTTON_RIGHT and event_mouse_button.pressed
	return false

static func tween_y(node: Node, target_y: float, duration: float):
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "global_position:y", target_y, duration)

static func tween_rot_x(node: Node, target_rot_x: float, duration: float):
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(node, "rotation_degrees:x", target_rot_x, duration)

static func is_server(node: Node):
	return node.multiplayer.is_server()

static func not_server(node: Node):
	return not node.multiplayer.is_server()
	
static func my_id(node: Node):
	return node.multiplayer.get_unique_id()
	
static func sender_id(node: Node):
	return node.multiplayer.get_remote_sender_id()

static func get_mouse_intersect_horizontal_plane(node: Node, y: float) -> Vector3:
	var camera     := node.get_viewport().get_camera_3d()
	var mouse_pos  := node.get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_normal := camera.project_ray_normal(mouse_pos)
	var plane      := Plane(Vector3.UP, y)
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_normal)
	if intersection == null:
		return Vector3.ZERO
	return intersection
	
static func is_pile_input_purpose(purpose: Const.Purpose) -> bool:
	return purpose in Const.INPUT_SOURCE_TO_PURPOSE.values()
	
static func is_pile_output_purpose(purpose: Const.Purpose) -> bool:
	return purpose in Const.OUTPUT_SOURCE_TO_PURPOSE.values()

static func is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
