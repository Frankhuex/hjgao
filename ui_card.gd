class_name UICard
extends ColorRect

@onready var _card_db: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _label: Label = $Label

const IS_SOLID_WHITE = "is_solid_white"
signal drag_started(card: UICard)

func preready(id: int):
	name = str(id)

func _ready():
	# 将材质独立化，防止修改 Shader 时影响到其他所有卡牌
	if material:
		material = material.duplicate()
	update_ui()
	_card_db.on_flip.connect(update_ui)

func _gui_input(event: InputEvent):
	if Util.is_left_mouse_down(event):
		drag_started.emit(self)
		get_viewport().set_input_as_handled()
	elif Util.is_right_mouse_down(event):
		request_flip()
		get_viewport().set_input_as_handled() 

func update_ui():
	var is_front := _card_db.is_front(card_ID())
	var card_name := _card_db.get_card_name(card_ID())
	if is_front:
		_label.text = card_name
	else:
		_label.text = ""
	(material as ShaderMaterial).set_shader_parameter(IS_SOLID_WHITE, is_front)

# Flipping
func request_flip():
	_card_db.request_flip(card_ID())

func request_flip_to(is_front: bool):
	_card_db.request_flip_to(card_ID(), is_front)

# Util
func card_ID() -> int:
	return int(name)
