class_name PileCardReceiver
extends Node

@onready var _card_sorter: CardSorter     = get_node("/root/Game/CardSorter")
@onready var _card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _parent: Pile = get_parent()

var _owner_mux: OwnerMux

func config(owner_mux: OwnerMux):
	_owner_mux = owner_mux
	#_owner_mux.on_owner_change.connect()
