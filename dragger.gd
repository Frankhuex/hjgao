class_name Dragger
extends Node

var dragging_y       := 0.5
var up_down_duration := 0.1

@onready var _parent: Node3D = get_parent()
var _owner_mux: OwnerMux

func config(owner_mux: OwnerMux, _dragging_y: float, _up_down_duration: float):
	_owner_mux = owner_mux
	_owner_mux.on_owner_change.connect(check_and_up_down)
	dragging_y = _dragging_y
	up_down_duration = _up_down_duration

func request_drag() -> bool:
	return _owner_mux.request_own(Const.Purpose.DRAG)
	
func request_drop() -> bool:
	return _owner_mux.request_release()
	
var _drag_offset := Vector3.ZERO
func check_and_up_down(): #玩家接到拖牌权后调用
	if i_am_dragging():
		_drag_offset = _parent.global_position - Util.get_mouse_intersect_horizontal_plane(_parent, dragging_y)
		Util.tween_y(_parent, dragging_y, up_down_duration)
	elif not _owner_mux.is_owned() and Util.is_server(self):
		Util.tween_y(_parent, 0, up_down_duration)

func process_drag():
	if i_am_dragging():
		var intersection = Util.get_mouse_intersect_horizontal_plane(self, dragging_y)
		if intersection == null: return
		var target_pos = intersection + _drag_offset
		_parent.global_position.x = target_pos.x
		_parent.global_position.z = target_pos.z

func i_am_dragging() -> bool:
	return _owner_mux.i_am_owner() and _owner_mux.purpose == Const.Purpose.DRAG
