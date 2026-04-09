# CardSorter节点本身用于当MultiplayerSynchronizer容器
# CardSorter内节点authority始终为1，重排高度时自动同步给所有端
# CardSorter内card_ID_stack用于维护地面的Card对象高度
# 当牌被抓起/放下时，card_ID_stack删除/加入此牌ID，放弃/开始维护此牌高度
# 当牌进入/离开牌堆时，CardSorter删除/生成此牌节点，card_ID_stack始终没有此牌ID，因为牌出入牌堆时在空中

class_name CardSorter
extends Node3D

var card_ID_stack: Array[int] #从低到高

# Setup
func preready(_card_ID_stack: Array[int]):
	card_ID_stack = _card_ID_stack
	
# Util
func get_card(id: int) -> Card:
	return get_node(str(id))

# Reorder Cards
const CARD_THICKNESS = 0.002 
func server_reorder_cards():
	if Util.not_server(self): return
	for i in range(card_ID_stack.size()):
		var id   := card_ID_stack[i]
		var card := get_card(id)
		card.global_position.y = i * CARD_THICKNESS

# Drag/Drop Card
func server_drag_card(id: int):
	if Util.not_server(self): return
	card_ID_stack.erase(id)
	server_reorder_cards()
	
func server_drop_card(id: int):
	if Util.not_server(self): return
	if card_ID_stack.has(id): return
	card_ID_stack.append(id)
	server_reorder_cards()
	
# Into/From Pile
func server_card_collect_into_pile(id: int): #被Pile内的rpc函数调用
	if Util.not_server(self): return
	get_card(id).queue_free() #此时牌在空中，ID不在栈内，因此直接删除即可

const CARD = preload("res://Card.tscn")
func server_card_spawn_from_pile(id: int) -> Card:
	if Util.not_server(self): return
	var card: Card = CARD.instantiate()
	card.preready(str(id))
	add_child(card)
	return card
