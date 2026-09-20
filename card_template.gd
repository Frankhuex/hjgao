class_name CardTemplate
extends Resource

@export var name: String
@export var count: int
@export var description: String

func _init(_name: String, _count: int, _description: String):
	self.name = _name
	self.count = _count
	self.description = _description

func to_dict() -> Dictionary[String, Variant]:
	return {
		"name": name,
		"count": count,
		"description": description
	}

static func load_from_json(input: Variant) -> CardTemplate:
	if not (input is Dictionary):
		push_error("Failed to load CardTemplate from JSON. Input must be Dictionary[String, Variant].")
		return null
	var dict: Dictionary = input
	if not dict.has("name"):
		push_error("Failed to load CardTemplate from JSON. Field '_name' not found.")
		return null
	
	var raw_count: int = dict.get("count", 1)
	if not (Util.is_number(raw_count)):
		push_error("CardTemplate 加载失败：'_count' 必须是数字")
		return null
		
	var _name: String = str(dict["name"])
	var _count: int = int(raw_count) # 强制转为 int
	var _description: String = str(dict.get("description", ""))
	return CardTemplate.new(_name, _count, _description)
