class_name CardDatabase
extends Node

static var inst: CardDatabase
static func instance() -> CardDatabase:
	if inst == null:
		inst = CardDatabase.new()
	return inst

var njk_tmpl  := CardTemplate.new("你居垦", 5, "一个AI")
var mcqx_tmpl := CardTemplate.new("梅川千夏", 3, "一个女孩")
var deck_tmpl := DeckTemplate.new(
	{
		njk_tmpl.name: njk_tmpl,
		mcqx_tmpl.name: mcqx_tmpl
	},
	[njk_tmpl.name, mcqx_tmpl.name]
)
var deck_instance1 := DeckInstance.new(
	deck_tmpl,
	{
		1: njk_tmpl.name,
		2: njk_tmpl.name,
		3: njk_tmpl.name,
		4: njk_tmpl.name,
		5: njk_tmpl.name,
		6: mcqx_tmpl.name,
		7: mcqx_tmpl.name,
		8: mcqx_tmpl.name
	}
)

var deck_instance := load_deck_instance_from_json("res://bfc.json")

func load_deck_instance_from_json(file_path: String) -> DeckInstance:
	return DeckInstance.load_from_json(load_json_file(file_path))

func load_json_file(file_path: String) -> Variant:
	# 1. 检查文件是否存在
	if not FileAccess.file_exists(file_path):
		print("文件不存在！")
		return null
	# 2. 打开并读取内容
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close() # 养成好习惯，读完关闭
	
	# 3. 解析 JSON 字符串
	var json = JSON.new()
	var error = json.parse(content)

	if error == OK:
		# 解析成功，返回数据（通常是 Dictionary 或 Array）
		return json.data
	else:
		print("JSON 解析失败: ", json.get_error_message(), " 行数: ", json.get_error_line())
		return null

func export_deck_instance() -> String:
	return deck_instance.serialize_to_json()

func get_all_IDs() -> Array[int]:
	return deck_instance.card_ID_to_card_name.keys()

func get_card_name(id: int) -> String:
	return deck_instance.card_ID_to_card_name[id]

func is_front(id: int) -> bool:
	return deck_instance.card_ID_to_is_front[id]

func flip(id: int) -> bool:
	var is_front := is_front(id)
	deck_instance.card_ID_to_is_front[id] = not is_front
	return not is_front

func flip_to(id: int, is_front: bool):
	deck_instance.card_ID_to_is_front[id] = is_front

func get_card_template(id: int) -> CardTemplate:
	var card_name := deck_instance.card_ID_to_card_name[id]
	return deck_instance.deck_template.card_name_to_card_template[card_name]
