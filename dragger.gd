class_name Dragger
extends Node

var dragging_y       := 0.5
var up_down_duration := 0.1
var _sound_profile   := "object"   # "card"：拿起/放下用卡牌音；"object"：牌堆/计数器用物体音
var _was_being_dragged := false    # 边沿检测：全端各自跟踪同一条所有权广播
static var auto_orientation_enabled := true   # 本地偏好；朝向结果仍由 _sync_rot_y 全端同步

@onready var _parent: Node3D = get_parent()
var _owner_mux: OwnerMux
var _ground_y_getter := func(): return 0.0

func config(owner_mux: OwnerMux, _up_down_duration: float, _dragging_y: float, ground_y_getter: Callable = func(): return 0.0, sound_profile: String = "object"):
	_owner_mux = owner_mux
	_owner_mux.on_owner_change.connect(check_and_up_down)
	_owner_mux.on_owner_change.connect(_reset_request_status)
	dragging_y = _dragging_y
	up_down_duration = _up_down_duration
	_ground_y_getter = ground_y_getter
	_sound_profile = sound_profile

var _requested_drag := false
var _requested_release := false
var _interaction_suspended := false
func _reset_request_status():
	_requested_drag = false
	_requested_release = false
	_interaction_suspended = false
	print("D=",_requested_drag,",R=",_requested_release,",A=",i_am_dragging(),",S=",should_animate_drag())

func suspend_local_interaction():
	_interaction_suspended = true

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
	var being_dragged := is_being_dragged()
	if being_dragged and not _was_being_dragged:
		SfxManager.I.play(SfxManager.Snd.PICKUP_CARD if _sound_profile == "card" else SfxManager.Snd.PICKUP_OBJECT)
	elif not being_dragged and _was_being_dragged and not Util.board_locked(self):
		SfxManager.I.play(SfxManager.Snd.DROP_CARD if _sound_profile == "card" else SfxManager.Snd.DROP_OBJECT)
	_was_being_dragged = being_dragged
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
		if auto_orientation_enabled:
			_sync_rot_y.rpc(get_viewport().get_camera_3d().global_rotation.y)

func should_animate_drag():
	if _interaction_suspended:
		return false
	var D := _requested_drag
	var R := _requested_release
	var A := i_am_dragging()
	return ((not D) and (not R) and A) or (D and (not R)) or (D and A)

func i_am_dragging() -> bool:
	return _owner_mux.i_am_owner() and _owner_mux.purpose == Const.Purpose.DRAG

func is_being_dragged() -> bool:   # "有任何人正在拖动"（全端语义一致）
	return _owner_mux.is_owned() and _owner_mux.purpose == Const.Purpose.DRAG

@rpc("authority", "call_local", "unreliable")
func _sync_rot_y(global_rot_y: float):
	_parent.global_rotation.y = global_rot_y
