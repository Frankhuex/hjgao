extends Node3D

const Y_STEP = 0.002 

var card_ID_stack: Array[int] = []
#var card_ID_to_obj: Dictionary[int, Node3D] = {}

signal sorter_stack_updated

func _ready():
	sorter_stack_updated.connect(_reorder_all_cards)

@rpc("authority", "call_remote", "reliable")
func _broadcast_card_ID_stack(data: Array):
	card_ID_stack = Array(data, TYPE_INT, &"", null)
	sorter_stack_updated.emit()
	print("card_sorter.card_ID_stack长度: ", card_ID_stack.size())

@rpc("any_peer", "call_remote", "reliable")
func bring_to_front(card_ID: int):
	if not multiplayer.is_server(): return
	var index := card_ID_stack.find(card_ID)
	if index != -1:
		card_ID_stack.remove_at(index)
		card_ID_stack.append(card_ID)
		_broadcast_card_ID_stack.rpc(card_ID_stack)
		_reorder_all_cards()

func _reorder_all_cards():
	for i in range(card_ID_stack.size()):
		var card_ID := card_ID_stack[i]
		var card_node := get_node(str(card_ID))
		if not card_node:
			printerr("card_node "+str(card_ID)+" not found")
		var target_y := i * Y_STEP
		card_node.update_target_y(target_y)

@rpc("any_peer", "call_remote", "reliable")
func server_register_card(card_ID: int, reorder: bool):
	if not multiplayer.is_server(): return
	if not card_ID_stack.has(card_ID):
		card_ID_stack.append(card_ID)
		_broadcast_card_ID_stack.rpc(card_ID_stack)
		if reorder:
			_reorder_all_cards()

@rpc("any_peer", "call_remote", "reliable")	
func server_unregister_card(card_ID: int):
	if not multiplayer.is_server(): return
	card_ID_stack.erase(card_ID)
	_broadcast_card_ID_stack.rpc(card_ID_stack)
	var card_node := get_node(str(card_ID))
	if card_node:
		card_node.queue_free()
	_reorder_all_cards()
