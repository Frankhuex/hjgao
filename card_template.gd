class_name CardTemplate
extends Resource

@export var name: String
@export var count: int
@export var description: String

func _init(name: String, count: int, description: String):
	self.name = name
	self.count = count
	self.description = description

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
		push_error("Failed to load CardTemplate from JSON. Field 'name' not found.")
		return null
	
	var raw_count = dict.get("count", 1)
	if not (Util.is_number(raw_count)):
		push_error("CardTemplate 加载失败：'count' 必须是数字")
		return null
		
	var name: String = str(dict["name"])
	var count: int = int(raw_count) # 强制转为 int
	var description: String = str(dict.get("description", ""))
	return CardTemplate.new(name, count, description)
