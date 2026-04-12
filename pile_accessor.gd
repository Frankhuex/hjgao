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
	_viewer.load_deck(_parent.card_ID_stack) # 内有-1判断逻辑
	_viewer.draw_confirmed.connect(_on_draw_confirmed)
	_viewer.cancel_confirmed.connect(_on_cancel)

func _close_deck_viewer():
	if _viewer:
		_viewer.queue_free()
	
func _on_draw_confirmed(updated_card_ID_stack: Array[int], drawn_card_IDs: Array[int]):
	if not i_am_viewing(): return
	request_viewer_operation(updated_card_ID_stack, drawn_card_IDs)

func request_viewer_operation(updated_card_ID_stack: Array[int], drawn_card_IDs: Array[int]):
	if Util.is_server(self): 
		server_viewer_operation(updated_card_ID_stack, drawn_card_IDs)
	else:
		server_viewer_operation.rpc_id(1, updated_card_ID_stack, drawn_card_IDs)

@rpc("any_peer", "call_remote", "reliable")
func server_viewer_operation(updated_card_ID_stack: Array[int], drawn_card_IDs: Array[int]):
	if Util.not_server(self): return
	if not is_being_viewed(): return
	_parent.spawner.server_spawn_card_by_IDs(drawn_card_IDs)
	_parent.card_ID_stack = updated_card_ID_stack
	_parent.server_sync_card_ID_stack()
	_parent.owner_mux.server_reset_owner()
	
func _on_cancel():
	if not i_am_viewing(): return
	_parent.owner_mux.request_release()

func i_am_viewing() -> bool:
	return _parent.owner_mux.i_am_owner() and _parent.owner_mux.purpose == Const.Purpose.PILE_VIEW

func is_being_viewed() -> bool:
	return _parent.owner_mux.is_owned() and _parent.owner_mux.purpose == Const.Purpose.PILE_VIEW
