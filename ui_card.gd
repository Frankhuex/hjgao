class_name UICard
extends ColorRect

@onready var card_database: CardDatabase = get_node("/root/Game/CardDatabase")

var card_ID: int
const IS_SOLID_WHITE = "is_solid_white"

# 定义一个信号，告诉 UI 主控板“我被按下了”
signal drag_started(card: UICard)

func _ready():
	# 将材质独立化，防止修改 Shader 时影响到其他所有卡牌
	if material:
		material = material.duplicate()
	card_database.is_front_updated.connect(func():
		set_shader()
		set_text()
	)

func set_text():
	var is_front := card_database.is_front(card_ID)
	var card_name := card_database.get_card_name(card_ID)
	if is_front:
		$Label.text = card_name
	else:
		$Label.text = ""

func set_shader():
	material.set_shader_parameter(IS_SOLID_WHITE, card_database.is_front(card_ID))

func flip():
	card_database.flip(card_ID)
	set_shader()
	set_text()

func flip_to(is_front: bool):
	card_database.flip_to(card_ID, is_front)
	set_shader()
	set_text()

func setup(id: int):
	name = str(id)
	card_ID = id
	set_shader()
	set_text()

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# 触发拖拽信号
			drag_started.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			flip()
			
