class_name Dragger
extends Node

var dragging_y       := 0.5
var up_down_duration := 0.1

@onready var _parent: Node3D = get_parent()
var _owner_mux: OwnerMux
var _ground_y_getter := func(): return 0.0



func config(owner_mux: OwnerMux, _up_down_duration: float, _dragging_y: float, ground_y_getter: Callable = func(): return 0.0):
	_owner_mux = owner_mux
	_owner_mux.on_owner_change.connect(check_and_up_down)
	_owner_mux.on_owner_change.connect(_reset_request_status)
	dragging_y = _dragging_y
	up_down_duration = _up_down_duration
	_ground_y_getter = ground_y_getter

var _requested_drag := false
var _requested_release := false
func _reset_request_status():
	_requested_drag = false
	_requested_release = false
	print("D=",_requested_drag,",R=",_requested_release,",A=",i_am_dragging(),",S=",should_animate_drag())

func request_drag() -> bool:
	_requested_drag = _owner_mux.request_own(Const.Purpose.DRAG)
	print("D=",_requested_drag,",R=",_requested_release,",A=",i_am_dragging(),",S=",should_animate_drag())
	return _requested_drag
	
func request_drop() -> bool:
	if not i_am_dragging(): return false
	_requested_release = _owner_mux.request_release()
	print("D=",_requested_drag,",R=",_requested_release,",A=",i_am_dragging(),",S=",should_animate_drag())
	return _requested_release
	
#var _drag_offset := Vector3.ZERO
func check_and_up_down(): #玩家接到拖牌权后调用
	if i_am_dragging():
		#_drag_offset = _parent.global_position - Util.get_mouse_intersect_horizontal_plane(_parent, dragging_y)
		Util.tween_y(_parent, dragging_y, up_down_duration)
	elif Util.is_server(self) and not _owner_mux.is_owned():
		Util.tween_y(_parent, Util.safe_call_float(_ground_y_getter), up_down_duration)

func process_drag():
	if should_animate_drag():
		var intersection = Util.get_mouse_intersect_horizontal_plane(self, dragging_y)
		if intersection == null: return
		#var target_pos = intersection + _drag_offset
		var target_pos: Vector3 = intersection
		_parent.global_position.x = target_pos.x
		_parent.global_position.z = target_pos.z
		_sync_rot_y.rpc(get_viewport().get_camera_3d().global_rotation.y)

func should_animate_drag():
	var D := _requested_drag
	var R := _requested_release
	var A := i_am_dragging()
	return ((not D) and (not R) and A) or (D and (not R)) or (D and A)

func i_am_dragging() -> bool:
	return _owner_mux.i_am_owner() and _owner_mux.purpose == Const.Purpose.DRAG

@rpc("authority", "call_local", "unreliable")
func _sync_rot_y(global_rot_y: float):
	_parent.global_rotation.y = global_rot_y
