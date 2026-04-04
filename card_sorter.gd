# CardManager.gd
class_name CardSorter  # 定义类名，方便子节点识别
extends Node3D

# 存储当前容器下所有卡牌的有序列表
var card_ID_stack: Array[int] = []
var card_ID_to_obj: Dictionary[int, Node3D] = {}

func _ready():
	sorter_stack_updated.connect(_reorder_all_cards)

# 层间距（1毫米）
const Y_STEP = 0.002 

signal sorter_stack_updated
func call_server_to_broadcast_card_ID_stack():
	if multiplayer.is_server():
		broadcast_card_ID_stack.rpc(card_ID_stack)
	else:
		server_broadcast_card_ID_stack.rpc_id(1, card_ID_stack)

@rpc("any_peer", "call_local", "reliable")
func server_broadcast_card_ID_stack(new_data: Array):
	card_ID_stack = Array(new_data, TYPE_INT, &"", null)
	broadcast_card_ID_stack.rpc(card_ID_stack)

@rpc("authority", "call_local", "reliable")
func broadcast_card_ID_stack(data: Array):
	card_ID_stack = Array(data, TYPE_INT, &"", null)
	sorter_stack_updated.emit()
	print("card_sorter.card_ID_stack长度: ", card_ID_stack.size())

# 核心功能：将某张牌提到数组末尾（即最高处）
func bring_to_front(card_ID: int):
	var index := card_ID_stack.find(card_ID)
	if index != -1:
		card_ID_stack.remove_at(index)
		card_ID_stack.append(card_ID)
		call_server_to_broadcast_card_ID_stack()

# 内部逻辑：重新分配所有牌的 Y 坐标
func _reorder_all_cards():
	for i in range(card_ID_stack.size()):
		var card_ID := card_ID_stack[i]
		if not card_ID_to_obj.has(card_ID):
			printerr("card_sorter未找到card_ID: ",card_ID)
			continue
		var card := card_ID_to_obj[card_ID]
		var target_y := i * Y_STEP
		card.update_target_y(target_y)
		
# 子节点登记处
func register_card(card: Node3D, reorder: bool):
	if not card_ID_stack.has(card.card_ID):
		card_ID_stack.append(card.card_ID)
		card_ID_to_obj[card.card_ID] = card
		if reorder:
			call_server_to_broadcast_card_ID_stack()

# 子节点注销处（场景切换或牌被删除时自动触发）
func unregister_card(card_ID: int):
	card_ID_stack.erase(card_ID)
	card_ID_to_obj.erase(card_ID)
	call_server_to_broadcast_card_ID_stack()
