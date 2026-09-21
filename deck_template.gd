class_name DeckTemplate
extends Resource

@export var card_name_to_card_template: Dictionary[String, CardTemplate]
@export var ordered_card_names: Array[String]
var card_name_to_priority: Dictionary[String, int] = {}

func _init(_card_name_to_card_template: Dictionary[String, CardTemplate], _ordered_card_names: Array[String]):
	self.card_name_to_card_template = _card_name_to_card_template
	self.ordered_card_names = _ordered_card_names
	for i in range(_ordered_card_names.size()):
		card_name_to_priority[_ordered_card_names[i]] = i

func to_dict() -> Dictionary[String,Variant]:
	var output: Dictionary[String,Variant] = {}
	var ordered_card_templates: Array[Dictionary] = []
	for name in ordered_card_names:
		ordered_card_templates.append(card_name_to_card_template[name].to_dict())
	output["ordered_card_templates"] = ordered_card_templates
	return output

func serialize_to_json() -> String:
	return JSON.stringify(to_dict(), "\t") # "\t" 让输出的 JSON 带缩进，方便阅读

static func load_from_json(input: Variant) -> DeckTemplate:
	if not (input is Dictionary):
		push_error("Failed to load DeckTemplate: input must be Dictionary")
		return null
	
	var dict: Dictionary = input

	var ordered_card_templates_raw = dict.get("ordered_card_templates", [])
	if not (ordered_card_templates_raw is Array):
		push_error("Failed to load DeckTemplate: ordered_card_templates must be Array")
		return null
	
	# 初始化字典（必须赋值为 {}，否则它是 null）
	var _card_name_to_card_template: Dictionary[String, CardTemplate] = {} 
	var _ordered_card_names: Array[String] = []

	for card_template_raw in ordered_card_templates_raw:
		if not (card_template_raw is Dictionary):
			push_error("Failed to load DeckTemplate: card_template_raw must be Dictionary")		
			return null

		var card_template := CardTemplate.load_from_json(card_template_raw)
		if not card_template:
			push_error("Failed to load DeckTemplate: card_template_raw 格式错误")
			return null
		_card_name_to_card_template[card_template.name] = card_template
		_ordered_card_names.append(card_template.name)

	return DeckTemplate.new(_card_name_to_card_template, _ordered_card_names)
