class_name CardTemplate
extends Resource

@export var name: String
@export var count: int
@export var description: String
@export var type: String = UNTYPED

const UNTYPED: String = ""
const MAX_TYPE_LENGTH: int = 64

func _init(_name: String, _count: int, _description: String, _type: String = UNTYPED):
	self.name = _name
	self.count = _count
	self.description = _description
	self.type = normalize_type(_type)

func to_dict() -> Dictionary[String, Variant]:
	return {
		"name": name,
		"count": count,
		"description": description,
		"type": type
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
	var raw_type: Variant = dict.get("type", UNTYPED)
	var error := validate_type(raw_type)
	if not error.is_empty():
		push_error(error)
		return null
	return CardTemplate.new(_name, _count, _description, normalize_type(raw_type))

static func normalize_type(raw_type: Variant) -> String:
	if raw_type is String:
		var text: String = raw_type
		return text.strip_edges()
	return UNTYPED

static func validate_type(raw_type: Variant) -> String:
	if raw_type != null and not raw_type is String:
		return "type 必须是字符串或 null。"
	var normalized := normalize_type(raw_type)
	if normalized.length() > MAX_TYPE_LENGTH:
		return "type 必须是长度不超过 64 的字符串。"
	for character: String in normalized:
		var code := character.unicode_at(0)
		if code < 32 or (code >= 127 and code < 160):
			return "type 不能包含换行或控制字符。"
	return ""
