class_name CounterViewerUI
extends CanvasLayer

signal close_confirmed
signal delete_confirmed

@onready var value_edit: LineEdit     = $Margin/Center/Panel/InnerMargin/VBox/ValueRow/ValueEdit
@onready var btn_minus: Button        = $Margin/Center/Panel/InnerMargin/VBox/ValueRow/Btn_Minus
@onready var btn_plus: Button         = $Margin/Center/Panel/InnerMargin/VBox/ValueRow/Btn_Plus
@onready var step_edit: LineEdit      = $Margin/Center/Panel/InnerMargin/VBox/StepRow/StepEdit
@onready var decimals_edit: LineEdit  = $Margin/Center/Panel/InnerMargin/VBox/DecimalsRow/DecimalsEdit
@onready var btn_dec_minus: Button    = $Margin/Center/Panel/InnerMargin/VBox/DecimalsRow/Btn_DecMinus
@onready var btn_dec_plus: Button     = $Margin/Center/Panel/InnerMargin/VBox/DecimalsRow/Btn_DecPlus
@onready var btn_close: Button        = $Margin/Center/Panel/InnerMargin/VBox/BottomBar/Btn_Close
@onready var btn_delete: Button       = $Margin/Center/Panel/InnerMargin/VBox/BottomBar/Btn_Delete
@onready var delete_confirmation: ConfirmationDialog = $DeleteConfirmation

var _counter: Counter

func open_for(counter: Counter) -> void:
	_counter = counter
	_counter.state_changed.connect(_refresh_fields)
	btn_delete.visible = Util.my_id(self) == 1 or _counter.owner_mux.i_am_owner() # 房主或占用者可删
	_refresh_fields()

func _on_plus_pressed() -> void:
	if _counter != null:
		_counter.request_apply_step(1)

func _on_minus_pressed() -> void:
	if _counter != null:
		_counter.request_apply_step(-1)

func _on_dec_plus_pressed() -> void:
	if _counter != null:
		_counter.request_apply_decimals(_counter.decimals + 1)

func _on_dec_minus_pressed() -> void:
	if _counter != null:
		_counter.request_apply_decimals(_counter.decimals - 1)

func _ready() -> void:
	btn_close.pressed.connect(_on_close_pressed)
	btn_delete.pressed.connect(delete_confirmation.popup_centered)
	delete_confirmation.confirmed.connect(_on_delete_confirmed)
	value_edit.text_submitted.connect(func(_t: String): _submit_value())
	value_edit.focus_exited.connect(_submit_value)
	step_edit.text_submitted.connect(func(_t: String): _submit_step())
	decimals_edit.text_submitted.connect(func(_t: String): _submit_decimals())
	for edit: LineEdit in [value_edit, step_edit, decimals_edit]:
		edit.focus_entered.connect(_on_edit_focus_entered)
		edit.focus_exited.connect(_on_edit_focus_exited)

# 打开期间拦截键盘，避免 T/Q/空格/ESC 穿透到游戏逻辑；
# 编辑输入框时放行（交给 GUI），由 game.gd 的输入焦点守卫兜底。
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not is_editing_text():
			get_viewport().set_input_as_handled()

func is_editing_text() -> bool:
	return value_edit.has_focus() or step_edit.has_focus() or decimals_edit.has_focus()

func _exit_tree() -> void:
	_restore_player_input() # 编辑中查看器被外部关闭（如删除/断线）时恢复玩家输入

###################################
# 字段刷新（state_changed 驱动；编辑中的输入框不被覆盖）
func _refresh_fields() -> void:
	if _counter == null or not is_instance_valid(_counter): return
	var step_text := _counter.format_step()
	btn_plus.text = "+%s" % step_text
	btn_minus.text = "-%s" % step_text
	if not value_edit.has_focus():
		value_edit.text = _counter.format_value()
	if not step_edit.has_focus():
		step_edit.text = step_text
	if not decimals_edit.has_focus():
		decimals_edit.text = str(_counter.decimals)

###################################
# 提交（逐项即时生效，非法输入恢复原显示）
func _submit_value() -> void:
	if _counter == null or not is_instance_valid(_counter): return
	var new_value := _parse_float(value_edit.text)
	if is_nan(new_value):
		value_edit.text = _counter.format_value()
		return
	if Counter.round_to_decimals(new_value, _counter.decimals) == _counter.value: return
	_counter.request_apply_value(new_value)

func _submit_step() -> void:
	if _counter == null or not is_instance_valid(_counter): return
	var new_step := _parse_float(step_edit.text)
	if is_nan(new_step):
		step_edit.text = _counter.format_step()
		return
	# 步长必须为正；非法值本地恢复显示（服务器拒绝不回包，等不来刷新）。
	if new_step <= 0.0:
		step_edit.text = _counter.format_step()
		return
	_counter.request_apply_step_value(new_step)

func _submit_decimals() -> void:
	if _counter == null or not is_instance_valid(_counter): return
	var new_decimals := _parse_nonnegative_int(decimals_edit.text)
	if new_decimals < 0:
		decimals_edit.text = str(_counter.decimals)
		return
	_counter.request_apply_decimals(new_decimals)

###################################
# 解析（非法输入返回 NaN / -1）
func _parse_float(text: String) -> float:
	var t := text.strip_edges()
	if t.is_empty() or not t.is_valid_float(): return NAN
	return t.to_float()

func _parse_nonnegative_int(text: String) -> int:
	var t := text.strip_edges()
	if not t.is_valid_int(): return -1
	return t.to_int()

###################################
# 按钮与关闭
func _on_close_pressed() -> void:
	close_confirmed.emit()
	queue_free()

func _on_delete_confirmed() -> void:
	delete_confirmed.emit()
	queue_free()

###################################
# 输入框聚焦期间禁用本地玩家键鼠（仿聊天输入框处理）
func _on_edit_focus_entered() -> void:
	var game: GameSession = get_node_or_null("/root/Game")
	if game != null and is_instance_valid(game.local_player):
		game.local_player.set_input_enabled(false)

func _on_edit_focus_exited() -> void:
	_restore_player_input()

func _restore_player_input() -> void:
	var game: GameSession = get_node_or_null("/root/Game")
	if game == null or not game.session_active: return
	if game.pause_overlay.visible or game.clear_table_in_progress: return # 暂停/清场期间由菜单接管输入
	if is_instance_valid(game.local_player):
		game.local_player.set_input_enabled(true)
		game.local_player.apply_mouse_mode()
