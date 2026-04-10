class_name Util
extends Node

static func is_left_mouse_down(event: InputEvent):
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	
static func is_right_mouse_down(event: InputEvent):
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed

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
	return plane.intersects_ray(ray_origin, ray_normal) as Vector3

static func map_dict_values(dict: Dictionary, function: Callable) -> Dictionary:
	var result = {}
	for key in dict:
		var func_result = function.call(dict[key])
		if not func_result:
			print("map_dict_values: function call failed for key " + key)
			continue
		result[key] = func_result
	return result

static func is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func is_string_array(v: Variant) -> bool:
	# 1. 首先必须是一个数组
	if typeof(v) != TYPE_ARRAY:
		return false
	
	# 2. 检查数组的内置类型约束
	# TYPE_STRING 的枚举值是 4
	return v.get_typed_builtin() == TYPE_STRING
