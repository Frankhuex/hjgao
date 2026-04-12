extends Node

# public signal
signal on_dragger_change

# public config
var dragging_y       = 0.5
var up_down_duration = 0.1
func config(_dragging_y: float, _up_down_duration: float):
	dragging_y = _dragging_y
	up_down_duration = _up_down_duration

# private variables
@onready var _parent: Node3D = get_parent()
var _dragger := 0 #必须保留dragger变量，因为authority没有0

func is_dragged() -> bool:
	return is_dragged()
	
func _i_am_dragger() -> bool:
	return _dragger == Util.my_id(_parent)

func _ready():
	on_dragger_change.connect(check_and_float_up)

func _request_drag():
	_server_set_dragger.rpc_id(1)

func _request_release():
	_server_reset_dragger.rpc_id(1)

func request_drag_or_release():
	if not is_dragged():
		_request_drag()
	elif _dragger == multiplayer.get_unique_id():
		_request_release()

@rpc("any_peer", "call_remote", "reliable")
func _server_set_dragger():
	if Util.not_server(_parent): return
	if is_dragged():          return
	_set_dragger.rpc(Util.sender_id(_parent))

@rpc("any_peer", "call_remote", "reliable")
func _server_reset_dragger():
	if Util.not_server(_parent): return
	if not is_dragged():          return
	_set_dragger.rpc(0)
	
@rpc("any_peer", "call_local", "reliable")
func _set_dragger(new_dragger: int):
	_dragger = new_dragger
	if new_dragger == 0:
		set_multiplayer_authority(1)
		_check_and_drop_down() #服务器来统一落下
	else:
		set_multiplayer_authority(new_dragger)
	on_dragger_change.emit() #发信号，新dragger收到信号判断自己是新dragger再统一升起

var _drag_offset := Vector3.ZERO
func check_and_float_up(): #玩家接到拖牌权后调用
	if _i_am_dragger():
		_drag_offset = _parent.global_position - Util.get_mouse_intersect_horizontal_plane(_parent, dragging_y)
		Util.tween_y(_parent, dragging_y, up_down_duration)

func _check_and_drop_down(): #只有服务器能调用，无须rpc
	if not is_dragged() and multiplayer.is_server():
		Util.tween_y(_parent, 0, up_down_duration)

func process_drag():
	if _i_am_dragger():
		var intersection = Util.get_mouse_intersect_horizontal_plane(self, dragging_y)
		if intersection == null: return
		var target_pos = intersection + _drag_offset
		_parent.global_position.x = target_pos.x
		_parent.global_position.z = target_pos.z
