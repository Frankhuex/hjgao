class_name CardDatabase
extends Node

static var inst: CardDatabase
static func instance() -> CardDatabase:
	if inst == null:
		inst = CardDatabase.new()
	return inst

var njk_tmpl  := CardTemplate.new("你居垦", 5, "一个AI")
var mcqx_tmpl := CardTemplate.new("梅川千夏", 3, "一个女孩")
var deck_tmpl := DeckTemplate.new(
	{
		njk_tmpl.name: njk_tmpl,
		mcqx_tmpl.name: mcqx_tmpl
	},
	[njk_tmpl.name, mcqx_tmpl.name]
)
var deck_instance := DeckInstance.new(
	deck_tmpl,
	{
		1: njk_tmpl.name,
		2: njk_tmpl.name,
		3: njk_tmpl.name,
		4: njk_tmpl.name,
		5: njk_tmpl.name,
		6: mcqx_tmpl.name,
		7: mcqx_tmpl.name,
		8: mcqx_tmpl.name
	}
)

func get_all_IDs() -> Array[int]:
	return deck_instance.card_ID_to_card_name.keys()

func get_card_name(id: int) -> String:
	return deck_instance.card_ID_to_card_name[id]

func is_front(id: int) -> bool:
	return deck_instance.card_ID_to_is_front[id]

func flip(id: int) -> bool:
	var is_front := is_front(id)
	deck_instance.card_ID_to_is_front[id] = not is_front
	return not is_front

func get_card_template(id: int) -> CardTemplate:
	var card_name := deck_instance.card_ID_to_card_name[id]
	return deck_instance.deck_template.card_name_to_card_template[card_name]
