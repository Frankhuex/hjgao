class_name DeckTemplate
extends Resource

@export var card_name_to_card_template: Dictionary[String, CardTemplate]
@export var ordered_card_names: Array[String]

func _init(card_name_to_card_template: Dictionary[String, CardTemplate], ordered_card_names: Array[String]):
	self.card_name_to_card_template = card_name_to_card_template
	self.ordered_card_names = ordered_card_names

func to_dict() -> Dictionary[String,Variant]:
	var output: Dictionary[String,Variant] = {}
	var card_name_to_card_template_dict: Dictionary[String,Dictionary] = {}
	for key in card_name_to_card_template:
		card_name_to_card_template_dict[key] = card_name_to_card_template[key].to_dict()
	
	output["card_name_to_card_template"] = card_name_to_card_template_dict
	output["ordered_card_names"] = ordered_card_names
	return output

func serialize_to_json() -> String:
	return JSON.stringify(to_dict(), "\t") # "\t" 让输出的 JSON 带缩进，方便阅读
