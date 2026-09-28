class_name Counter
extends StaticBody3D

signal state_changed

@onready var _value_label: Label3D = $ValueLabel
@onready var owner_mux: OwnerMux   = $OwnerMux
@onready var dragger: Dragger      = $Dragger
@onready var accessor: CounterAccessor = $Accessor

const DRAGGING_Y       = 0.0
const UP_DOWN_DURATION = 0.1
const MAX_DECIMALS     = 6

# 根 body 上 3 个 CollisionShape3D 的索引（顺序与 Counter.tscn 子节点顺序一致）
const SHAPE_BASE  = 0
const SHAPE_MINUS = 1
const SHAPE_PLUS  = 2

# 按钮区域（用于 event_position 兜底校验，与场景尺寸对应）
const BUTTON_CENTER_X  = 0.6
const BUTTON_HALF_SIZE = 0.15

var value: float  = 0.0   # 当前数值，允许负数
var step: float   = 1.0   # 步长 > 0
var decimals: int = 0     # 小数位数 [0, MAX_DECIMALS]

func _ready():
	dragger.config(owner_mux, UP_DOWN_DURATION, DRAGGING_Y)
	accessor.config()
	_update_visuals()
	if Util.not_server(self):
		request_sync_counter_state()

###################################
# 状态同步
func request_sync_counter_state():
	server_sync_counter_state.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_sync_counter_state():
	if Util.not_server(self): return
	sync_counter_state.rpc(value, step, decimals)

@rpc("any_peer", "call_local", "reliable")
func sync_counter_state(new_value: float, new_step: float, new_decimals: int):
	value = new_value
	step = new_step
	decimals = new_decimals
	_update_visuals()
	state_changed.emit()

###################################
# 格式化与工具
func format_value() -> String:
	return _fixed_num(value)

func format_step() -> String:
	return _fixed_num(step)

# 固定小数位数格式化（String.num 会裁剪末尾零，不符合需求）
func _fixed_num(x: float) -> String:
	var rounded := round_to_decimals(x, decimals)
	if rounded == 0.0:
		rounded = 0.0 # 消除 -0
	return ("%." + str(decimals) + "f") % rounded

static func round_to_decimals(x: float, digits: int) -> float:
	var factor := pow(10.0, digits)
	return roundf(x * factor) / factor

func _update_visuals():
	if not is_node_ready(): return
	_value_label.text = format_value()

func _sender_or_host() -> int:
	var sender := Util.sender_id(self)
	return 1 if sender == 0 else sender # 服务器本地调用时 remote_sender 为 0

func _is_active_viewer(sender: int) -> bool:
	return owner_mux.is_owned() \
		and owner_mux.get_owner_id() == sender \
		and owner_mux.purpose == Const.Purpose.COUNTER_VIEW

###################################
# Inputs（仅打牌模式可交互，见设计文档 Q8）
func _local_can_interact() -> bool:
	var game: GameSession = get_node_or_null("/root/Game")
	if game == null or not game.session_active: return false
	if game.local_player == null or not game.local_player.is_card_mode(): return false
	return true

func _input_event(_camera, event: InputEvent, event_position: Vector3, _normal, shape_idx: int):
	if not _local_can_interact(): return
	if Util.is_left_mouse_down(event):
		if dragger.i_am_dragging(): return # 拖动中点击任意处都由 _input 统一处理放下
		match shape_idx:
			SHAPE_BASE:
				if dragger.request_drag():
					get_viewport().set_input_as_handled()
			SHAPE_MINUS:
				if _is_button_position(shape_idx, event_position) and request_apply_step(-1):
					get_viewport().set_input_as_handled()
			SHAPE_PLUS:
				if _is_button_position(shape_idx, event_position) and request_apply_step(1):
					get_viewport().set_input_as_handled()
	elif Util.is_right_mouse_down(event):
		if shape_idx != SHAPE_BASE: return
		if accessor.request_open_viewer():
			get_viewport().set_input_as_handled()

func _input(event: InputEvent):
	if Util.is_left_mouse_down(event):
		if dragger.request_drop():
			get_viewport().set_input_as_handled()

func _is_button_position(shape_idx: int, event_position: Vector3) -> bool:
	var local := to_local(event_position)
	var target_x := -BUTTON_CENTER_X if shape_idx == SHAPE_MINUS else BUTTON_CENTER_X
	return absf(local.x - target_x) <= BUTTON_HALF_SIZE and absf(local.z) <= BUTTON_HALF_SIZE

func _process(_delta):
	dragger.process_drag()

func release_local_interaction():
	if owner_mux.i_am_owner():
		dragger.suspend_local_interaction()
		owner_mux.request_release()

###################################
# 客户端申请入口
func request_apply_step(direction: int) -> bool:
	if Util.board_locked(self): return false
	if owner_mux.is_owned() and not owner_mux.i_am_owner(): return false # 他人占用中
	if Util.is_server(self):
		_server_apply_step(1, direction)
	else:
		server_apply_step.rpc_id(1, direction)
	return true

func request_apply_value(new_value: float):
	if Util.is_server(self):
		server_apply_value(new_value)
	else:
		server_apply_value.rpc_id(1, new_value)

func request_apply_step_value(new_step: float):
	if Util.is_server(self):
		server_apply_step_value(new_step)
	else:
		server_apply_step_value.rpc_id(1, new_step)

func request_apply_decimals(new_decimals: int):
	if Util.is_server(self):
		server_apply_decimals(new_decimals)
	else:
		server_apply_decimals.rpc_id(1, new_decimals)

func request_delete():
	if Util.is_server(self):
		server_delete_counter()
	else:
		server_delete_counter.rpc_id(1)

###################################
# 服务器权威逻辑
# ±步长（3D 按钮 / 查看器 ±step 按钮共用）：瞬时占用事务，仿 PileCardReceiver
@rpc("any_peer", "call_remote", "reliable")
func server_apply_step(direction: int):
	if Util.not_server(self): return
	_server_apply_step(_sender_or_host(), direction)

func _server_apply_step(sender: int, direction: int):
	if Util.board_locked(self): return
	var viewer_edit := _is_active_viewer(sender)
	if owner_mux.is_owned() and not viewer_edit: return
	if not viewer_edit:
		var purpose := Const.Purpose.COUNTER_ADD if direction > 0 else Const.Purpose.COUNTER_SUBTRACT
		owner_mux.server_set_owner(purpose, sender)
	value = round_to_decimals(value + direction * step, decimals)
	sync_counter_state.rpc(value, step, decimals)
	if not viewer_edit:
		owner_mux.server_reset_owner()

@rpc("any_peer", "call_remote", "reliable")
func server_apply_value(new_value: float):
	if Util.not_server(self): return
	if Util.board_locked(self): return
	if not _is_active_viewer(_sender_or_host()): return
	value = round_to_decimals(new_value, decimals)
	sync_counter_state.rpc(value, step, decimals)

@rpc("any_peer", "call_remote", "reliable")
func server_apply_step_value(new_step: float):
	if Util.not_server(self): return
	if Util.board_locked(self): return
	if not _is_active_viewer(_sender_or_host()): return
	var rounded := round_to_decimals(new_step, decimals)
	if rounded <= 0.0: return # 步长必须为正（按当前小数位取整后校验，见设计文档 Q5）
	step = rounded
	sync_counter_state.rpc(value, step, decimals)

@rpc("any_peer", "call_remote", "reliable")
func server_apply_decimals(new_decimals: int):
	if Util.not_server(self): return
	if Util.board_locked(self): return
	if not _is_active_viewer(_sender_or_host()): return
	var d := clampi(new_decimals, 0, MAX_DECIMALS)
	var rounded_step := round_to_decimals(step, d)
	if rounded_step <= 0.0: return # 步长按新位数取整后 ≤0 则拒绝，保证 step 恒为正
	decimals = d
	step = rounded_step
	value = round_to_decimals(value, decimals)
	sync_counter_state.rpc(value, step, decimals)

# 删除：仅房主或当前占用者（见设计文档 Q1）
@rpc("any_peer", "call_remote", "reliable")
func server_delete_counter():
	if Util.not_server(self): return
	if Util.board_locked(self): return
	var sender := _sender_or_host()
	var can_delete := sender == 1 or (owner_mux.is_owned() and owner_mux.get_owner_id() == sender)
	if not can_delete: return
	queue_free() # MultiplayerSpawner 会自动全网销毁；Accessor 出树时关闭查看器
