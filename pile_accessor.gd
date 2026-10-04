class_name PileAccessor
extends Node

const DECK_VIEWER = preload("res://DeckViewerUI.tscn")

@onready var _card_sorter: CardSorter     = get_node("/root/Game/CardSorter")
@onready var _card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _parent: Pile = get_parent()

var _viewer: DeckViewerUI

func config():
	_parent.owner_mux.on_owner_change.connect(check_and_show_viewer)

func request_open_viewer() -> bool:
	return _parent.owner_mux.request_own(Const.Purpose.PILE_VIEW)

func check_and_show_viewer():
	if i_am_viewing():
		_open_deck_viewer()
	else:
		_close_deck_viewer()
		
func _open_deck_viewer():
	_viewer = DECK_VIEWER.instantiate()
	get_tree().root.add_child(_viewer)
	_viewer.open_for(_parent)
	_viewer.load_deck(_parent.card_ID_stack) # 内有-1判断逻辑
	_viewer.delete_confirmed.connect(_on_delete)
	_viewer.draw_confirmed.connect(_on_draw_confirmed)
	_viewer.draw_to_new_pile_confirmed.connect(request_extract_to_new_pile)
	_viewer.cancel_confirmed.connect(_on_cancel)
	_viewer.orientation_operation_requested.connect(_on_orientation_operation_requested)

func _close_deck_viewer():
	if is_instance_valid(_viewer):
		_viewer.queue_free()
	_viewer = null

func _exit_tree() -> void:
	_close_deck_viewer()

func _on_delete() -> void:
	if i_am_viewing():
		_parent.request_delete_pile()
	
func _on_draw_confirmed(updated_card_ID_stack: Array[int], drawn_card_IDs: Array[int]):
	if not i_am_viewing(): return
	request_viewer_operation(updated_card_ID_stack, drawn_card_IDs)

func request_viewer_operation(updated_card_ID_stack: Array[int], drawn_card_IDs: Array[int]):
	if Util.is_server(self): 
		server_viewer_operation(updated_card_ID_stack, drawn_card_IDs)
	else:
		server_viewer_operation.rpc_id(1, updated_card_ID_stack, drawn_card_IDs)

func request_orientation_operation(operation: Const.PileOrientationOperation, card_IDs: Array[int]) -> void:
	if Util.is_server(self):
		server_orientation_operation(operation, card_IDs)
	else:
		server_orientation_operation.rpc_id(1, operation, card_IDs)

func _on_orientation_operation_requested(operation: Const.PileOrientationOperation, card_IDs: Array[int]) -> void:
	if not i_am_viewing():
		return
	request_orientation_operation(operation, card_IDs)

@rpc("any_peer", "call_remote", "reliable")
func server_viewer_operation(updated_card_ID_stack: Array[int], drawn_card_IDs: Array[int]):
	if Util.not_server(self): return
	var sender := Util.sender_id(self)
	if sender == 0:
		sender = 1
	if not _viewer_partition_error(updated_card_ID_stack, drawn_card_IDs, sender).is_empty():
		return
	_parent.spawner.server_spawn_card_by_IDs(drawn_card_IDs)
	_parent.card_ID_stack = updated_card_ID_stack
	_parent.server_sync_card_ID_stack()
	_parent.owner_mux.server_reset_owner()

@rpc("any_peer", "call_remote", "reliable")
func server_orientation_operation(operation: Const.PileOrientationOperation, card_IDs: Array[int]):
	if Util.not_server(self) or Util.board_locked(self):
		return
	if not is_being_viewed():
		return
	var sender := Util.sender_id(self)
	if sender == 0:
		sender = 1
	if _parent.owner_mux.get_owner_id() != sender:
		return
	var valid_card_IDs: Array[int] = []
	for card_id: int in card_IDs:
		if _parent.card_ID_stack.has(card_id):
			valid_card_IDs.append(card_id)
	if valid_card_IDs.is_empty():
		return
	_card_database.apply_orientation_operation(operation, valid_card_IDs)
	
func _on_cancel():
	if not i_am_viewing(): return
	_parent.owner_mux.request_release()

func i_am_viewing() -> bool:
	return _parent.owner_mux.i_am_owner() and _parent.owner_mux.purpose == Const.Purpose.PILE_VIEW

func is_being_viewed() -> bool:
	return _parent.owner_mux.is_owned() and _parent.owner_mux.purpose == Const.Purpose.PILE_VIEW

func _viewer_partition_error(remaining_ids: Array[int], extracted_ids: Array[int], sender: int) -> String:
	var game := get_node("/root/Game") as GameSession
	if not game.session_active or _card_database.deck_instance == null or Util.board_locked(self):
		return "当前无法操作牌堆。"
	if _parent.is_queued_for_deletion() or _parent.get_parent() != game.piles:
		return "牌堆已失效。"
	if not is_being_viewed() or _parent.owner_mux.get_owner_id() != sender:
		return "已经失去牌堆查看权限。"
	if sender != 1 and not game.player_names.has(sender):
		return "玩家已离开房间。"
	if remaining_ids.size() + extracted_ids.size() != _parent.card_ID_stack.size():
		return "牌堆内容已变化，请重新打开查看器。"
	var seen: Dictionary[int, bool] = {}
	var source: Dictionary[int, bool] = {}
	for id: int in _parent.card_ID_stack:
		source[id] = true
	for ids: Array[int] in [remaining_ids, extracted_ids]:
		for id: int in ids:
			if seen.has(id) or not source.has(id) or not _card_database.deck_instance.card_ID_to_card_name.has(id):
				return "牌堆内容已变化，请重新打开查看器。"
			seen[id] = true
	return ""

func request_extract_to_new_pile(remaining_ids: Array[int], extracted_ids: Array[int], submission_id: int) -> void:
	if Util.is_server(self):
		server_extract_to_new_pile(remaining_ids, extracted_ids, submission_id)
	else:
		server_extract_to_new_pile.rpc_id(1, remaining_ids, extracted_ids, submission_id)

@rpc("any_peer", "call_remote", "reliable")
func server_extract_to_new_pile(remaining_ids: Array[int], extracted_ids: Array[int], submission_id: int) -> void:
	if Util.not_server(self):
		return
	var sender := Util.sender_id(self)
	if sender == 0:
		sender = 1
	var reason := _viewer_partition_error(remaining_ids, extracted_ids, sender)
	if reason.is_empty() and extracted_ids.is_empty():
		reason = "待取区没有牌。"
	if not reason.is_empty():
		_reply_extract_failure(sender, submission_id, reason)
		return
	var game := get_node("/root/Game") as GameSession
	var position: Vector3 = _parent.calc_spawn_pos([extracted_ids[0]])[extracted_ids[0]]
	position.y = 0.0
	var target := game.prepare_extra_pile(extracted_ids, position, _parent.global_rotation)
	if target == null:
		_reply_extract_failure(sender, submission_id, "创建牌堆失败，请重试。")
		return
	var previous_ids := _parent.card_ID_stack.duplicate()
	_parent.card_ID_stack = remaining_ids.duplicate()
	game.piles.add_child(target, true)
	if target.get_parent() != game.piles:
		_parent.card_ID_stack = previous_ids
		target.free()
		_reply_extract_failure(sender, submission_id, "创建牌堆失败，请重试。")
		return
	_parent.server_sync_card_ID_stack()
	# 最后释放：同步 on_owner_change 会关闭主机查看器。
	_parent.owner_mux.server_reset_owner()

func _reply_extract_failure(sender: int, submission_id: int, reason: String) -> void:
	if sender == 1:
		extract_to_pile_failed(submission_id, reason)
	elif multiplayer.get_peers().has(sender):
		extract_to_pile_failed.rpc_id(sender, submission_id, reason)

@rpc("any_peer", "call_remote", "reliable")
func extract_to_pile_failed(submission_id: int, reason: String) -> void:
	if not Util.is_server(self) and Util.sender_id(self) != 1:
		return
	if is_instance_valid(_viewer):
		_viewer.extract_to_pile_failed(submission_id, reason)
