class_name CardDescriptionTooltip
extends CanvasLayer

const POINTER_OFFSET := Vector2(32.0, -12.0)
const EDGE_MARGIN := 8.0
const MAX_CHARACTERS_PER_LINE := 18
const LINE_START_PUNCTUATION := "，。！？；：、,.!?;:)]}》」』"

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Description
@onready var _card_db: CardDatabase = get_node("/root/Game/CardDatabase")

var _source_instance_id := 0
var _card_id := -1
var _content: Callable
var _last_text := ""
var _tooltip_enabled := true

func _ready() -> void:
	_panel.hide()

func _process(_delta: float) -> void:
	if _source_instance_id != 0 and not is_instance_id_valid(_source_instance_id):
		hide_all()
		return
	if _source_instance_id != 0:
		_refresh_current_source()
	if _panel.visible:
		_update_position()

func show_for(source: Object, card_id: int) -> void:
	if not is_instance_valid(source):
		return
	_card_id = card_id
	show_content_for(source, _card_text.bind(card_id))

func _card_text(card_id: int) -> String:
	return _card_db.get_card_tooltip_text(card_id) if _card_db.is_front(card_id) else ""

func show_content_for(source: Object, content: Callable) -> void:
	if not is_instance_valid(source):
		return
	_source_instance_id = source.get_instance_id()
	_content = content
	_refresh_current_source()

func _can_show(source: Object) -> bool:
	if not _tooltip_enabled or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return false
	var game: Node = get_node_or_null("/root/Game")
	if game == null or Util.board_locked(self):
		return false
	var overlay: Control = game.get_node_or_null("PauseCanvasLayer/PauseOverlay") as Control
	if overlay != null and overlay.visible:
		return false
	if source is Control:
		return true
	var player: Variant = game.get("local_player")
	if not player is Player:
		return false
	var local_player: Player = player
	if not local_player.is_card_mode():
		return false
	for child: Node in get_tree().root.get_children():
		if child.is_in_group("object_viewer"):
			return false
	return true

func hide_for(source: Object) -> void:
	if not is_instance_valid(source):
		return
	if source.get_instance_id() == _source_instance_id:
		hide_all()

func hide_all() -> void:
	_source_instance_id = 0
	_card_id = -1
	_content = Callable()
	_last_text = ""
	_panel.hide()

func set_tooltip_enabled(enabled: bool) -> void:
	_tooltip_enabled = enabled
	if not _tooltip_enabled:
		_panel.hide()
		return
	_refresh_current_source()

func toggle_tooltip_enabled() -> void:
	set_tooltip_enabled(not _tooltip_enabled)

func is_tooltip_enabled() -> bool:
	return _tooltip_enabled

func _refresh_current_source() -> void:
	if _source_instance_id == 0 or not is_instance_id_valid(_source_instance_id) or not _content.is_valid():
		return
	var source: Object = instance_from_id(_source_instance_id)
	if not _can_show(source):
		_panel.hide()
		return
	var text_value: Variant = _content.call()
	if not text_value is String:
		_panel.hide()
		return
	var tooltip_text: String = text_value
	if tooltip_text.is_empty():
		_panel.hide()
		return
	if tooltip_text != _last_text:
		_last_text = tooltip_text
		_set_text_and_size(tooltip_text)
	_panel.show()
	_update_position()

func _set_text_and_size(text: String) -> void:
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size = Vector2.ZERO
	_label.text = _wrap_text(text)
	_panel.reset_size()

func _wrap_text(text: String) -> String:
	var wrapped_lines: Array[String] = []
	for paragraph: String in text.split("\n", true):
		if paragraph.is_empty():
			wrapped_lines.append("")
			continue
		var start := 0
		while start < paragraph.length():
			var line_length := mini(MAX_CHARACTERS_PER_LINE, paragraph.length() - start)
			while start + line_length < paragraph.length() and LINE_START_PUNCTUATION.contains(paragraph.substr(start + line_length, 1)):
				line_length += 1
			wrapped_lines.append(paragraph.substr(start, line_length))
			start += line_length
	return "\n".join(wrapped_lines)

func _update_position() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_position := get_viewport().get_mouse_position()
	var tooltip_size := _panel.size
	var target_position := mouse_position + POINTER_OFFSET

	if target_position.x + tooltip_size.x > viewport_size.x - EDGE_MARGIN:
		target_position.x = mouse_position.x - tooltip_size.x - POINTER_OFFSET.x
	if target_position.y + tooltip_size.y > viewport_size.y - EDGE_MARGIN:
		target_position.y = mouse_position.y - tooltip_size.y - absf(POINTER_OFFSET.y)

	target_position.x = clampf(target_position.x, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.x - tooltip_size.x - EDGE_MARGIN))
	target_position.y = clampf(target_position.y, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.y - tooltip_size.y - EDGE_MARGIN))
	_panel.position = target_position
