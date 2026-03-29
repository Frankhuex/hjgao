class_name DeckInstance
extends Resource

@export var deck_template: DeckTemplate
@export var card_ID_to_card_name: Dictionary[int, String]
@export var card_ID_to_is_front: Dictionary[int, bool]

func _init(deck_template: DeckTemplate, card_ID_to_card_name: Dictionary[int,String], card_ID_to_is_front: Dictionary[int, bool] = {}):
	self.deck_template = deck_template
	self.card_ID_to_card_name = card_ID_to_card_name
	self.card_ID_to_is_front = card_ID_to_is_front
	for card_ID in card_ID_to_card_name.keys():
		if not card_ID_to_is_front.has(card_ID):
			self.card_ID_to_is_front[card_ID] = false

# 将整个卡组转为 JSON 字符串
func serialize_to_json() -> String:
	var output: Dictionary[String,Variant] = {}
	output["deck_template"] = deck_template.to_dict()
	output["card_ID_to_card_name"] = card_ID_to_card_name # Dictionary[String, String], int变String了
	output["card_ID_to_is_front"] = card_ID_to_is_front # Dictionary[String, bool]
	return JSON.stringify(output, "\t") # "\t" 让输出的 JSON 带缩进，方便阅读

static func load_from_json(input: Variant) -> DeckInstance:
	if not (input is Dictionary):
		push_error("Failed to load DeckInstance: input must be Dictionary.")
		return null # 记得补上 return null
		
	var dict: Dictionary = input
	
	# 1. 加载模板
	if not dict.has("deck_template"):
		push_error("Failed to load DeckInstance: deck_template not found.")
		return null
	
	# 注意这里你写的是 load_from_json，如果它接收的是 dict，建议确认方法名
	var deck_template: DeckTemplate = DeckTemplate.load_from_json(dict["deck_template"])
	if not deck_template:
		push_error("Failed to load DeckInstance: deck_template wrong format.")
		return null
	
	# 2. 解析 Card ID 映射
	var card_ID_to_card_name: Dictionary[int, String] = {} # 键存 int
	var card_name_to_count: Dictionary[String, int] = {}
	
	var raw_id_map = dict.get("card_ID_to_card_name")
	
	if raw_id_map == null:
		# 情况 A：没有映射，根据模板自动生成 ID
		var cur_ID := 1
		for card_name in deck_template.card_name_to_card_template:
			var card_tmpl = deck_template.card_name_to_card_template[card_name]
			for i in range(card_tmpl.count):
				card_ID_to_card_name[cur_ID] = card_name
				cur_ID += 1
	elif not (raw_id_map is Dictionary):
		push_error("Failed to load DeckInstance: card_ID_to_card_name must be Dictionary.")
		return null
	else:
		# 情况 B：从 JSON 恢复映射
		for card_ID_str in raw_id_map:
			if not card_ID_str.is_valid_int():
				push_error("Failed to load DeckInstance: card_ID must be integer string.")
				return null
			
			var card_name = str(raw_id_map[card_ID_str])
			card_ID_to_card_name[int(card_ID_str)] = card_name
			
			card_name_to_count[card_name] = card_name_to_count.get(card_name, 0) + 1
		
		# 校验数量是否匹配模板
		for card_name in card_name_to_count:
			var tmpl_map = deck_template.card_name_to_card_template
			if not card_name in tmpl_map or card_name_to_count[card_name] != tmpl_map[card_name].count:
				push_error("Failed to load DeckInstance: count doesn't match deck_template for " + card_name)
				return null

	# 3. 解析正反面状态
	var card_ID_to_is_front: Dictionary[int, bool] = {}
	var raw_front_map = dict.get("card_ID_to_is_front", {})

	if not (raw_front_map is Dictionary):
		push_error("Failed to load DeckInstance: card_ID_to_is_front must be Dictionary.")
		return null
		
	for card_ID in card_ID_to_card_name:
		var val = raw_front_map.get(str(card_ID), false) # JSON key 是字符串
		if not (val is bool): # 修正语法错误
			push_error("Failed to load DeckInstance: is_front value must be bool.")
			return null
		card_ID_to_is_front[card_ID] = val

	return DeckInstance.new(deck_template, card_ID_to_card_name, card_ID_to_is_front)		
