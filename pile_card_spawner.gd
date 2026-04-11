class_name PileCardSpawner
extends Node

const CARD = preload("res://Card.tscn")
@onready var _card_sorter: CardSorter     = get_node("/root/Game/CardSorter")
@onready var _card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _parent: Pile = get_parent()

var _owner_mux: OwnerMux

func config(owner_mux: OwnerMux):
	_owner_mux = owner_mux
	_owner_mux.on_owner_change.connect(server_spawn_card)
	
func request_spawn_card(source: Const.CardSource) -> bool:
	return _owner_mux.request_own(Const.INPUT_SOURCE_TO_PURPOSE[source])

func server_spawn_card():
	if Util.not_server(self): return
	if not Util.is_pile_output_purpose(_owner_mux.purpose): return
	var card_ID: int
	var spawn_pos := _parent.calc_spawn_pos([card_ID])[card_ID]
	var source := Const.PURPOSE_TO_SOURCE[_owner_mux.purpose]
	match source:
		Const.CardSource.BOTTOM:
			card_ID = _parent.card_ID_stack.pop_back()
		Const.CardSource.TOP:
			card_ID = _parent.card_ID_stack.pop_front()
		Const.CardSource.RANDOM:
			var random_index := randi() % _parent.card_ID_stack.size()
			card_ID = _parent.card_ID_stack.pop_at(random_index)
	var card: Card = CARD.instantiate()
	var camera := get_viewport().get_camera_3d()
	card.preready(card_ID, spawn_pos, camera.global_rotation.y)
	_card_sorter.add_child(card)
	_card_sorter.server_register_card(card.card_ID())
