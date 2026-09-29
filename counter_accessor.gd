class_name CounterAccessor
extends Node

const VIEWER = preload("res://CounterViewerUI.tscn")

@onready var _parent: Counter = get_parent()

var _viewer: CounterViewerUI

func config():
	_parent.owner_mux.on_owner_change.connect(check_and_show_viewer)

func request_open_viewer() -> bool:
	return _parent.owner_mux.request_own(Const.Purpose.COUNTER_VIEW)

func check_and_show_viewer():
	if i_am_viewing():
		_open_viewer()
	else:
		_close_viewer()

func _open_viewer():
	_viewer = VIEWER.instantiate()
	get_tree().root.add_child(_viewer) # 与 DeckViewerUI 一致，挂在 /root 而非 Game 子树
	_viewer.open_for(_parent)
	_viewer.close_confirmed.connect(_on_close)
	_viewer.delete_confirmed.connect(_on_delete)

func _close_viewer():
	if is_instance_valid(_viewer):
		_viewer.queue_free()
	_viewer = null

func _exit_tree():
	_close_viewer() # 计数器被删除/清场时，连带关闭本端查看器

func _on_close():
	if not i_am_viewing(): return
	_parent.owner_mux.request_release()

func _on_delete():
	if not _parent.owner_mux.i_am_owner(): return
	_parent.request_delete()

func i_am_viewing() -> bool:
	return _parent.owner_mux.i_am_owner() and _parent.owner_mux.purpose == Const.Purpose.COUNTER_VIEW

func is_being_viewed() -> bool:
	return _parent.owner_mux.is_owned() and _parent.owner_mux.purpose == Const.Purpose.COUNTER_VIEW
