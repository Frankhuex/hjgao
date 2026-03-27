# CardManager.gd
class_name CardSorter  # 定义类名，方便子节点识别
extends Node3D

# 存储当前容器下所有卡牌的有序列表
var cards_stack: Array[Card] = []

# 层间距（1毫米）
const Y_STEP = 0.002 

# 核心功能：将某张牌提到数组末尾（即最高处）
func bring_to_front(card: Node3D):
	var index := cards_stack.find(card)
	if index != -1:
		cards_stack.remove_at(index)
		cards_stack.append(card)
		_reorder_all_cards()

# 内部逻辑：重新分配所有牌的 Y 坐标
func _reorder_all_cards():
	for i in range(cards_stack.size()):
		var card := cards_stack[i]
		var target_y := i * Y_STEP
		card.update_target_y(target_y)

# 子节点登记处
func register_card(card: Node3D):
	if not cards_stack.has(card):
		cards_stack.append(card)
		_reorder_all_cards()

# 子节点注销处（场景切换或牌被删除时自动触发）
func unregister_card(card: Node3D):
	cards_stack.erase(card)
	_reorder_all_cards()
