class_name PileCardReceiver
extends Node

@onready var _card_sorter: CardSorter     = get_node("/root/Game/CardSorter")
@onready var _card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _parent: Pile = get_parent()

func config():
	return

func request_receive_card(card_ID: int, source: Const.CardSource) -> bool:
	if _parent.owner_mux.is_owned(): return false
	if Util.is_server(self):
		server_receive_card(card_ID, source)
	else:
		server_receive_card.rpc_id(1, card_ID, source)
	return true
	
@rpc("any_peer", "call_remote", "reliable")
func server_receive_card(card_ID: int, source: Const.CardSource):
	if Util.not_server(self): return
	_parent.owner_mux.server_set_owner(Const.INPUT_SOURCE_TO_PURPOSE[source], Util.sender_id(self))
	match source:
		Const.CardSource.BOTTOM:
			_parent.card_ID_stack.push_back(card_ID)
		Const.CardSource.TOP:
			_parent.card_ID_stack.push_front(card_ID)
		Const.CardSource.RANDOM:
			var idx := randi() % (_parent.card_ID_stack.size() + 1)
			_parent.card_ID_stack.insert(idx, card_ID)
	_parent.server_sync_card_ID_stack()
	_card_sorter.server_collect_card_into_pile(card_ID)
	_parent.owner_mux.server_reset_owner()
	
	
