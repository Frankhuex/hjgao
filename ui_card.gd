class_name UICard
extends ColorRect

var card_name: String = ""

# 定义一个信号，告诉 UI 主控板“我被按下了”
signal drag_started(card: UICard)

func setup(c_name: String):
	card_name = c_name
	$Label.text = c_name

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# 触发拖拽信号
			drag_started.emit(self)
