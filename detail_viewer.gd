class_name DetailViewer
extends Node

var _source: Node
var _content: Callable
var _tooltip: CardDescriptionTooltip
var _hovered: Dictionary = {}

func configure(source: Node, content: Callable, targets: Array[Node]) -> void:
	_source = source
	_content = content
	_tooltip = get_node("/root/Game/CardDescriptionTooltip") as CardDescriptionTooltip
	for target: Node in targets:
		target.connect("mouse_entered", _enter.bind(target.get_instance_id()))
		target.connect("mouse_exited", _leave.bind(target.get_instance_id()))

func _enter(id: int) -> void:
	_hovered[id] = true
	refresh()

func _leave(id: int) -> void:
	_hovered.erase(id)
	_hide_if_empty.call_deferred()

func _hide_if_empty() -> void:
	if _hovered.is_empty() and is_instance_valid(_tooltip):
		_tooltip.hide_for(_source)

func refresh() -> void:
	if not _hovered.is_empty() and is_instance_valid(_tooltip):
		_tooltip.show_content_for(_source, _content)

func _exit_tree() -> void:
	if is_instance_valid(_tooltip) and is_instance_valid(_source):
		_tooltip.hide_for(_source)
