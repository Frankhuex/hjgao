class_name DeckInstance
extends Resource

@export var deck_template: DeckTemplate
@export var card_ID_to_card_name: Dictionary[int,String]
@export var card_ID_to_is_front: Dictionary[int, bool]

func _init(deck_template: DeckTemplate, card_ID_to_card_name: Dictionary[int,String]):
	self.deck_template = deck_template
	self.card_ID_to_card_name = card_ID_to_card_name
	self.card_ID_to_is_front = {}
	for card_ID in card_ID_to_card_name.keys():
		self.card_ID_to_is_front[card_ID] = false

# 将整个卡组转为 JSON 字符串
func serialize_to_json() -> String:
	var output: Dictionary[String,Variant] = {}
	output["deck_template"] = deck_template.to_dict()
	output["card_ID_to_card_name"] = card_ID_to_card_name
	output["card_ID_to_is_front"] = card_ID_to_is_front
	return JSON.stringify(output, "\t") # "\t" 让输出的 JSON 带缩进，方便阅读
