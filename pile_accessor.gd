class_name PileAccessor
extends Node

const DECK_VIEWER = preload("res://DeckViewerUI.tscn")

@onready var _card_sorter: CardSorter     = get_node("/root/Game/CardSorter")
@onready var _card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var _parent: Pile = get_parent()

var _card_ID_stack: Array[int] = []
var _viewer: DeckViewerUI
var _owner_mux: OwnerMux

func config(owner_mux: OwnerMux):
	_owner_mux = owner_mux
	_owner_mux.on_owner_change.connect(check_and_show_viewer)

func request_open_viewer() -> bool:
	return _owner_mux.request_own(Const.Purpose.PILE_VIEW)

func check_and_show_viewer():
	if i_am_viewing():
		_open_deck_viewer(-1)
	else:
		_close_deck_viewer()
		
func _open_deck_viewer(injected_card_ID: int = -1):
	_viewer = DECK_VIEWER.instantiate()
	get_tree().root.add_child(_viewer)
	_viewer.load_deck(_card_ID_stack, injected_card_ID) # 内有-1判断逻辑
	_viewer.draw_confirmed.connect(_on_draw_confirmed)
	_viewer.cancel_confirmed.connect(_on_cancel)

func _close_deck_viewer():
	_viewer.queue_free()
	
func _on_draw_confirmed(updated_card_ID_stack: Array[int], drawn_card_IDs: Array[int]):
	return
	
func _on_cancel():
	_close_deck_viewer()

func i_am_viewing() -> bool:
	return _owner_mux.i_am_owner() and _owner_mux.purpose == Const.Purpose.PILE_VIEW
