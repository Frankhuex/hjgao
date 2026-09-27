class_name ChatBanner
extends Control

const ENTER_DURATION := 0.18
const EXIT_DURATION := 0.12
const REPACK_DURATION := 0.12
const ENTER_OFFSET_Y := 16.0
const EXIT_OFFSET_Y := -8.0
const PREVIEW_MAX_LENGTH := 44

@onready var visual: PanelContainer = $Visual
@onready var message_label: Label = $Visual/Margin/MessageLabel

var _active_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message_label.max_lines_visible = 2
	visual.position = Vector2.ZERO
	visual.modulate.a = 1.0

func setup(sender_name: String, content: String) -> void:
	var preview := content.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	preview = preview.strip_edges()
	while preview.contains("  "):
		preview = preview.replace("  ", " ")
	if preview.length() > PREVIEW_MAX_LENGTH:
		preview = preview.left(PREVIEW_MAX_LENGTH) + "…"
	message_label.text = sender_name + ": " + preview

func play_enter(extra_offset_y := 0.0) -> Tween:
	_kill_active_tween()
	visual.position = Vector2(0.0, ENTER_OFFSET_Y + extra_offset_y)
	visual.modulate.a = 0.0
	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(visual, "position:y", 0.0, ENTER_DURATION)
	_active_tween.tween_property(visual, "modulate:a", 1.0, ENTER_DURATION)
	return _active_tween

func play_exit() -> Tween:
	_kill_active_tween()
	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(visual, "position:y", EXIT_OFFSET_Y, EXIT_DURATION)
	_active_tween.tween_property(visual, "modulate:a", 0.0, EXIT_DURATION)
	return _active_tween

func slide_to_vertical_offset(offset_y: float) -> Tween:
	_kill_active_tween()
	_active_tween = create_tween()
	_active_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_active_tween.tween_property(visual, "position:y", offset_y, REPACK_DURATION)
	return _active_tween

func snap_to_slot() -> void:
	_kill_active_tween()
	visual.position = Vector2.ZERO
	visual.modulate.a = 1.0

func stop_animation() -> void:
	_kill_active_tween()

func _kill_active_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
