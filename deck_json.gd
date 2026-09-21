class_name DeckJson
extends RefCounted

const MAX_BYTES: int = 1024 * 1024
const MAX_CARDS: int = 1000
var deck: DeckInstance
var error: String = ""

# 本地预检、服务器校验和认证加载共用；成功前不修改活动牌库。
static func parse(text: String) -> DeckJson:
	var result := DeckJson.new()
	if text.to_utf8_buffer().size() > MAX_BYTES:
		result.error = "卡组文件不能超过 1 MiB。"
		return result
	var json := JSON.new()
	if json.parse(text) != OK:
		result.error = "JSON 第 %d 行：%s" % [json.get_error_line(), json.get_error_message()]
		return result
	result.error = validate(json.data)
	if result.error.is_empty():
		result.deck = DeckInstance.load_from_json(json.data)
		if result.deck == null:
			result.error = "无法加载卡组。"
	return result

static func validate(data: Variant) -> String:
	if not data is Dictionary:
		return "JSON 顶层必须是对象。"
	var root: Dictionary = data
	var template: Variant = root.get("deck_template")
	if not template is Dictionary:
		return "deck_template 必须是对象。"
	var template_dict: Dictionary = template
	var raw_entries: Variant = template_dict.get("ordered_card_templates")
	if not raw_entries is Array:
		return "ordered_card_templates 必须是数组。"
	var entries: Array = raw_entries
	if entries.is_empty() or entries.size() > MAX_CARDS:
		return "ordered_card_templates 必须包含 1～1000 种牌。"
	var counts: Dictionary[String, int] = {}
	var total: int = 0
	for entry: Variant in entries:
		if not entry is Dictionary:
			return "每张卡牌模板必须是对象。"
		var entry_dict: Dictionary = entry
		var raw_name: Variant = entry_dict.get("name")
		var raw_description: Variant = entry_dict.get("description", "")
		var count: Variant = entry_dict.get("count", 1)
		if not raw_name is String or not raw_description is String:
			return "name 和 description 必须是字符串。"
		var card_name: String = raw_name
		var description: String = raw_description
		if card_name.length() > 64:
			return "name 必须是长度不超过 64 的字符串。"
		if counts.has(card_name):
			return "卡牌名称重复：%s" % card_name
		if description.length() > 1000:
			return "description 必须是长度不超过 1000 的字符串。"
		if not Util.is_number(count):
			return "count 必须是正整数。"
		var numeric_count: float = count
		if not is_finite(numeric_count) or numeric_count < 1 or numeric_count > MAX_CARDS or floor(numeric_count) != numeric_count:
			return "count 必须是 1～1000 的整数。"
		counts[card_name] = int(numeric_count)
		total += int(numeric_count)
		if total > MAX_CARDS:
			return "卡牌总数不能超过 1000。"
	var ids: Dictionary[int, bool] = {}
	if root.has("card_ID_to_card_name"):
		var raw_map: Variant = root["card_ID_to_card_name"]
		if not raw_map is Dictionary:
			return "card_ID_to_card_name 必须是对象。"
		var id_map: Dictionary = raw_map
		if id_map.size() != total:
			return "card_ID_to_card_name 数量与模板总数不一致。"
		var actual: Dictionary[String, int] = {}
		for key: Variant in id_map:
			if not _valid_id(key):
				return "卡牌 ID 必须是规范的正整数字符串，例如 1；不接受 01。"
			var value: Variant = id_map[key]
			if not value is String or not counts.has(value):
				return "ID %s 对应的卡牌名称不在模板中。" % key
			ids[str(key).to_int()] = true
			actual[value] = actual.get(value, 0) + 1
		for card_name: String in counts:
			if actual.get(card_name, 0) != counts[card_name]:
				return "卡牌 %s 的数量与模板不一致。" % card_name
	else:
		for id: int in range(1, total + 1):
			ids[id] = true
	var fronts: Variant = root.get("card_ID_to_is_front", {})
	if not fronts is Dictionary:
		return "card_ID_to_is_front 必须是对象。"
	for key: Variant in fronts:
		if not _valid_id(key) or not ids.has(str(key).to_int()):
			return "正反面映射包含无效或未知 ID：%s" % str(key)
		if not fronts[key] is bool:
			return "ID %s 的正反面必须是 true 或 false。" % key
	return ""

static func _valid_id(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	return text.is_valid_int() and text.to_int() > 0 and str(text.to_int()) == text
