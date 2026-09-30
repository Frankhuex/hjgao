class_name ChatPanel
extends CanvasLayer

signal send_requested(content: String)
signal input_focus_entered
signal input_focus_exited

const BANNER_SCENE := preload("res://ChatBanner.tscn")
const NOTIFICATION_DURATION_MSEC := 10_000
const MAX_VISIBLE_NOTIFICATIONS := 2

@onready var panel: PanelContainer = $ChatPanel
@onready var message_history: RichTextLabel = $ChatPanel/Margin/VBox/MessageHistory
@onready var message_input: TextEdit = $ChatPanel/Margin/VBox/InputRow/MessageInput
@onready var send_button: Button = $ChatPanel/Margin/VBox/InputRow/SendButton
@onready var close_button: Button = $ChatPanel/Margin/VBox/TitleRow/CloseButton
@onready var notification_stack: VBoxContainer = $NotificationStack

var _notifications: Array[Dictionary] = []
var _transitioning := false
var _pending_notifications: Array[Dictionary] = []
var _slid_banner: ChatBanner

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.hide()
	message_input.focus_mode = Control.FOCUS_CLICK
	send_button.focus_mode = Control.FOCUS_NONE
	close_button.focus_mode = Control.FOCUS_NONE
	message_history.bbcode_enabled = false
	message_history.scroll_following = false
	notification_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if _notifications.is_empty() or _transitioning:
		return
	for entry: Dictionary in _notifications:
		if entry.get("entering", false) == true or entry.get("exiting", false) == true:
			return
	var oldest_entry: Dictionary = _notifications[0]
	var expires_at := int(str(oldest_entry.get("expires_at", "0")).to_int())
	if Time.get_ticks_msec() >= expires_at:
		_start_notification_exit(oldest_entry)

func is_open() -> bool:
	return panel.visible

func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()

func open() -> void:
	panel.show()

func close() -> void:
	release_input_focus()
	panel.hide()

func is_input_focused() -> bool:
	return message_input.has_focus()

func get_history_text() -> String:
	return message_history.get_parsed_text()

func get_notification_count() -> int:
	return _notifications.size()

func is_point_in_input(global_position: Vector2) -> bool:
	return message_input.get_global_rect().has_point(global_position)

func release_input_focus() -> void:
	if message_input.has_focus():
		message_input.release_focus()

func clear_input() -> void:
	message_input.clear()
	message_input.set_caret_line(0)
	message_input.set_caret_column(0)

func submit_current_input() -> void:
	var message := Util.sanitize_chat_message(message_input.text)
	if message.is_empty():
		return
	send_requested.emit(message)
	clear_input()

func append_message(sender_name: String, content: String) -> void:
	_append_text(sender_name, content)

func replace_history(history: Array) -> void:
	message_history.clear()
	for item: Variant in history:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		_append_text(str(entry.get("sender_name", "")), str(entry.get("content", "")), false)
	_scroll_history_to_bottom.call_deferred()

func show_notification(sender_name: String, content: String) -> void:
	if _transitioning or _has_entering_notification():
		_pending_notifications.append({
			"sender_name": sender_name,
			"content": content,
		})
		return
	var enter_slot_shift := 0.0
	if _notifications.size() >= MAX_VISIBLE_NOTIFICATIONS:
		enter_slot_shift = _start_notification_transition()
	var banner := BANNER_SCENE.instantiate() as ChatBanner
	notification_stack.add_child(banner)
	banner.setup(sender_name, content)
	var entry := {
		"banner": banner,
		"expires_at": 0,
		"entering": true,
		"exiting": false,
	}
	_notifications.append(entry)
	var tween := banner.play_enter(enter_slot_shift)
	tween.finished.connect(_on_notification_entered.bind(banner))

func clear_notifications() -> void:
	for entry: Dictionary in _notifications:
		var banner := _banner_from_entry(entry)
		if banner != null and is_instance_valid(banner):
			banner.stop_animation()
			banner.queue_free()
	_notifications.clear()
	_transitioning = false
	_pending_notifications.clear()
	_slid_banner = null

func reset() -> void:
	close()
	clear_input()
	message_history.clear()
	clear_notifications()

func _append_text(sender_name: String, content: String, autoscroll := true) -> void:
	if sender_name.is_empty() or content.is_empty():
		return
	var was_at_bottom := _is_history_at_bottom()
	var block := sender_name + ": " + content
	if not block.ends_with("\n"):
		block += "\n"
	message_history.add_text(block)
	if autoscroll and was_at_bottom:
		_scroll_history_to_bottom.call_deferred()

func _is_history_at_bottom() -> bool:
	var scroll_bar := message_history.get_v_scroll_bar()
	return scroll_bar.value >= scroll_bar.max_value - scroll_bar.page - 4.0

func _scroll_history_to_bottom() -> void:
	var scroll_bar := message_history.get_v_scroll_bar()
	scroll_bar.value = maxf(0.0, scroll_bar.max_value - scroll_bar.page)

func _on_input_focus_entered() -> void:
	input_focus_entered.emit()

func _on_input_focus_exited() -> void:
	input_focus_exited.emit()

func _on_send_button_pressed() -> void:
	submit_current_input()

func _on_close_button_pressed() -> void:
	release_input_focus()
	close()

func _on_notification_entered(banner: ChatBanner) -> void:
	for entry: Dictionary in _notifications:
		if entry.get("banner") == banner:
			entry["entering"] = false
			entry["expires_at"] = Time.get_ticks_msec() + NOTIFICATION_DURATION_MSEC
			_drain_pending_notification()
			return

func _start_notification_exit(entry: Dictionary) -> void:
	var banner := _banner_from_entry(entry)
	if banner == null or not is_instance_valid(banner):
		_notifications.erase(entry)
		return
	entry["exiting"] = true
	_transitioning = true
	_slid_banner = null
	var entry_index := _notifications.find(entry)
	if entry_index >= 0 and entry_index + 1 < _notifications.size():
		var next_entry: Dictionary = _notifications[entry_index + 1]
		var next_banner := _banner_from_entry(next_entry)
		if next_banner != null and is_instance_valid(next_banner) and next_entry.get("entering", false) != true:
			_slid_banner = next_banner
			next_banner.slide_to_vertical_offset(-_notification_slide_distance())
	var tween := banner.play_exit()
	tween.finished.connect(_on_notification_exited.bind(banner))

func _on_notification_exited(banner: ChatBanner) -> void:
	for entry: Dictionary in _notifications:
		if entry.get("banner") == banner:
			_notifications.erase(entry)
			break
	if is_instance_valid(banner):
		banner.queue_free()
	_finish_notification_transition.call_deferred()

func _finish_notification_transition() -> void:
	await get_tree().process_frame
	var slid_banner := _slid_banner
	_slid_banner = null
	if slid_banner != null and is_instance_valid(slid_banner):
		slid_banner.snap_to_slot()
	_transitioning = false
	_drain_pending_notification()

func _start_notification_transition() -> float:
	if _notifications.is_empty():
		return 0.0
	_start_notification_exit(_notifications[0])
	return _notification_slide_distance()

func _notification_slide_distance() -> float:
	if _notifications.size() < 2:
		return 0.0
	var next_banner := _banner_from_entry(_notifications[1])
	if next_banner == null or not is_instance_valid(next_banner):
		return 0.0
	return float(next_banner.size.y + notification_stack.get_theme_constant("separation"))

func _has_entering_notification() -> bool:
	for entry: Dictionary in _notifications:
		if entry.get("entering", false) == true:
			return true
	return false

func _drain_pending_notification() -> void:
	if _pending_notifications.is_empty():
		return
	var pending: Dictionary = _pending_notifications.pop_front()
	show_notification(str(pending.get("sender_name", "")), str(pending.get("content", "")))

func _banner_from_entry(entry: Dictionary) -> ChatBanner:
	var value: Variant = entry.get("banner")
	if value is ChatBanner:
		return value
	return null
