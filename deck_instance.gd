class_name DeckInstance
extends Resource

@export var deck_template: DeckTemplate
@export var card_ID_to_card_name: Dictionary[int,String]

func _init(deck_template: DeckTemplate, card_ID_to_card_name: Dictionary[int,String]):
	self.deck_template = deck_template
	self.card_ID_to_card_name = card_ID_to_card_name

# 将整个卡组转为 JSON 字符串
func serialize_to_json() -> String:
	var output: Dictionary[String,Variant] = {}
	output["deck_template"] = deck_template.to_dict()
	output["card_ID_to_card_name"] = card_ID_to_card_name
	return JSON.stringify(output, "\t") # "\t" 让输出的 JSON 带缩进，方便阅读
