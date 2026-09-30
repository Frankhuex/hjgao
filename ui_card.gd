class_name UICard
extends Control

@onready var _card_db: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _visual: ColorRect = $Visual
@onready var _label: Label = $Visual/Label
@onready var _description_tooltip: CardDescriptionTooltip = get_node("/root/Game/CardDescriptionTooltip")

const IS_SOLID_WHITE = "is_solid_white"
signal drag_started(card: UICard)
signal orientation_requested(card_id: int)
var _is_mouse_hovering := false
var _last_is_front := false
var _flip_sound_armed_at := -1  # msec，>0 表示等待自己的翻面广播（2 秒过期）

func preready(id: int):
	name = str(id)

func _ready():
	# 将材质独立化，防止修改 Shader 时影响到其他所有卡牌
	if _visual.material:
		_visual.material = _visual.material.duplicate()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_last_is_front = _card_db.is_front(card_ID())
	update_ui()
	update_orientation()
	_card_db.on_flip.connect(update_ui)
	_card_db.orientation_changed.connect(update_orientation)

func _exit_tree() -> void:
	if is_instance_valid(_description_tooltip):
		_description_tooltip.hide_for(self)

func _on_mouse_entered() -> void:
	_is_mouse_hovering = true
	SfxManager.I.play(SfxManager.Snd.HOVER)   # R1b：2D 牌悬停，仅本端
	_refresh_description_tooltip()

func _on_mouse_exited() -> void:
	_is_mouse_hovering = false
	_description_tooltip.hide_for(self)

func _refresh_description_tooltip() -> void:
	if not _is_mouse_hovering:
		return
	if not _card_db.is_front(card_ID()):
		_description_tooltip.hide_for(self)
		return
	_description_tooltip.show_for(self, card_ID())

func _gui_input(event: InputEvent):
	if Util.is_left_mouse_down(event):
		_description_tooltip.hide_for(self)
		drag_started.emit(self)
		get_viewport().set_input_as_handled()
	elif Util.is_right_mouse_down(event):
		var right_click := event as InputEventMouseButton
		if right_click.shift_pressed:
			orientation_requested.emit(card_ID())
		else:
			_flip_sound_armed_at = Time.get_ticks_msec()   # 武装：等自己右键申请的翻面落地
			request_flip()
		get_viewport().set_input_as_handled()

func update_ui():
	var is_front := _card_db.is_front(card_ID())
	if is_front != _last_is_front:
		if _flip_sound_armed_at > 0 and Time.get_ticks_msec() - _flip_sound_armed_at <= 2000:
			_flip_sound_armed_at = -1
			SfxManager.I.play(SfxManager.Snd.FLIP)   # R5-2D：自己右键申请的那次翻面真正落地，仅本端
		_last_is_front = is_front
	var card_name := _card_db.get_card_name(card_ID())
	if is_front:
		_label.text = card_name
	else:
		_label.text = ""
	(_visual.material as ShaderMaterial).set_shader_parameter(IS_SOLID_WHITE, is_front)
	_refresh_description_tooltip()

func update_orientation(_updates: Dictionary = {}) -> void:
	_visual.pivot_offset = custom_minimum_size * 0.5
	_visual.rotation_degrees = 180.0 if not _card_db.is_upright(card_ID()) else 0.0

# Flipping
func request_flip():
	_card_db.request_flip(card_ID())

func request_flip_to(is_front: bool):
	_card_db.request_flip_to(card_ID(), is_front)

func request_orientation_toggle() -> void:
	orientation_requested.emit(card_ID())

# Util
func card_ID() -> int:
	return int(name)
