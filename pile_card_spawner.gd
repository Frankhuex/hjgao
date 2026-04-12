class_name PileCardSpawner
extends Node

const CARD = preload("res://Card.tscn")
@onready var _card_sorter: CardSorter     = get_node("/root/Game/CardSorter")
@onready var _card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _parent: Pile = get_parent()

func config():
	_parent.owner_mux.on_owner_change.connect(server_spawn_card_from_source)
	
func request_spawn_card(source: Const.CardSource) -> bool:
	return _parent.owner_mux.request_own(Const.OUTPUT_SOURCE_TO_PURPOSE[source])

func server_spawn_card_from_source():
	if Util.not_server(self): return
	if not Util.is_pile_output_purpose(_parent.owner_mux.purpose): return
	if len(_parent.card_ID_stack) == 0: 
		_parent.owner_mux.server_reset_owner()
		return
	var card_ID: int
	var source := Const.PURPOSE_TO_SOURCE[_parent.owner_mux.purpose]
	match source:
		Const.CardSource.BOTTOM:
			card_ID = _parent.card_ID_stack.pop_back()
		Const.CardSource.TOP:
			card_ID = _parent.card_ID_stack.pop_front()
		Const.CardSource.RANDOM:
			var random_index := randi() % _parent.card_ID_stack.size()
			card_ID = _parent.card_ID_stack.pop_at(random_index)
	server_spawn_card_by_IDs([card_ID])
	_parent.server_sync_card_ID_stack()
	_parent.owner_mux.server_reset_owner()

func server_spawn_card_by_IDs(card_IDs: Array[int]):
	if Util.not_server(self): return
	var card_ID_to_spawn_pos := _parent.calc_spawn_pos(card_IDs)
	for card_ID in card_ID_to_spawn_pos:
		var spawn_pos := card_ID_to_spawn_pos[card_ID]
		var card: Card = CARD.instantiate()
		card.preready(card_ID, spawn_pos)
		_card_sorter.add_child(card)
		_card_sorter.server_register_card(card.card_ID())
