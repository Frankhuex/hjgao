class_name DeckTemplate
extends Resource

@export var card_name_to_card_template: Dictionary[String, CardTemplate]
@export var ordered_card_names: Array[String]

func _init(card_name_to_card_template: Dictionary[String, CardTemplate], ordered_card_names: Array[String]):
	self.card_name_to_card_template = card_name_to_card_template
	self.ordered_card_names = ordered_card_names

func to_dict() -> Dictionary[String,Variant]:
	var output: Dictionary[String,Variant] = {}
	var card_name_to_card_template_dict: Dictionary[String, Dictionary] = {}
	for key in card_name_to_card_template:
		card_name_to_card_template_dict[key] = card_name_to_card_template[key].to_dict()
	
	output["card_name_to_card_template"] = card_name_to_card_template_dict
	output["ordered_card_names"] = ordered_card_names
	return output

func serialize_to_json() -> String:
	return JSON.stringify(to_dict(), "\t") # "\t" 让输出的 JSON 带缩进，方便阅读

static func load_from_json(input: Variant) -> DeckTemplate:
	if not (input is Dictionary):
		push_error("Failed to load DeckTemplate: input must be Dictionary")
	
	var dict: Dictionary = input
		
	# 1. 获取子字典
	var raw_card_map = dict.get("card_name_to_card_template", {})
	if not (raw_card_map is Dictionary):
		push_error("Failed to load DeckTemplate: card_name_to_card_template must be Dictionary")
		return null
	
	# 2. 初始化字典（必须赋值为 {}，否则它是 null）
	var card_name_to_card_template: Dictionary[String, Variant] = {} 
	
	for card_name in raw_card_map:
		var card_tmpl_data = raw_card_map[card_name]
		if not (card_tmpl_data is Dictionary):
			push_error("Failed to load DeckTemplate: card_template must be Dictionary")		
			return null
			
		# 调用 CardTemplate 的加载逻辑
		var tmpl = CardTemplate.load_from_json(card_tmpl_data)
		if not tmpl:
			push_error("Failed to load DeckTemplate: card_template 格式错误")
			return null
		card_name_to_card_template[card_name] = tmpl
		
	# 3. 处理有序列表
	var ordered_card_names: Array[String] = []
	if not dict.has("ordered_card_names"):
		ordered_card_names = card_name_to_card_template.keys()
		ordered_card_names.sort()
	elif dict["ordered_card_names"] is Array:
		# 关键：必须用 assign，因为 JSON 读出来的是 Array (Variant)
		ordered_card_names.assign(dict["ordered_card_names"])
	else:
		push_error("Failed: ordered_card_names must be Array[String]")
		return null
	
	return DeckTemplate.new(card_name_to_card_template, ordered_card_names)
