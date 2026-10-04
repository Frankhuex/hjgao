class_name NameEditorUI
extends HBoxContainer

@onready var edit: LineEdit = $NameEdit
@onready var button: Button = $Apply
@onready var status: Label = $Status
var _name_editor: NameEditor
var _request_id := 0
var _pending := false

func open_for(name_editor: NameEditor) -> void:
	_name_editor = name_editor
	edit.text = name_editor.display_name
	name_editor.name_changed.connect(_refresh)
	name_editor.submission_finished.connect(_result)

func _refresh() -> void:
	if not is_queued_for_deletion() and not edit.has_focus() and not _pending:
		edit.text = _name_editor.display_name

func _submit() -> void:
	if _pending or not is_instance_valid(_name_editor):
		return
	if not _name_editor.can_edit():
		status.text = "当前无法修改名称"
		return
	if edit.text.length() > NameEditor.MAX_LENGTH:
		status.text = "名称最多 64 个字符"
		return
	_pending = true
	_request_id = _name_editor.next_request_id()
	button.disabled = true
	edit.editable = false
	status.text = "修改中…"
	_name_editor.request_apply_name(edit.text, _request_id)

func _result(request_id: int, accepted: bool, message: String) -> void:
	if is_queued_for_deletion() or not _pending or request_id != _request_id:
		return
	_pending = false
	button.disabled = false
	edit.editable = true
	edit.text = _name_editor.display_name
	status.text = "已修改" if accepted and message.is_empty() else message

func is_editing_text() -> bool:
	return _pending or (is_instance_valid(edit) and edit.has_focus())

func _local_player() -> Player:
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return null
	var player: Variant = game.get("local_player")
	return player if player is Player else null

func _focus_entered() -> void:
	Util.clear_pending_move_input()
	var player := _local_player()
	if is_instance_valid(player):
		player.set_input_enabled(false)

func _focus_exited() -> void:
	Util.clear_pending_move_input()
	var game: Node = get_node_or_null("/root/Game")
	var player := _local_player()
	if game == null or not is_instance_valid(player):
		return
	var overlay: Control = game.get_node("PauseCanvasLayer/PauseOverlay") as Control
	if game.get("session_active") == true and not overlay.visible and not Util.board_locked(self):
		player.set_input_enabled(true)

func _exit_tree() -> void:
	_focus_exited()

func _text_submitted(_text: String) -> void:
	if not _pending and is_instance_valid(_name_editor) and _name_editor.can_edit() and edit.text.length() <= NameEditor.MAX_LENGTH:
		SfxManager.I.play(SfxManager.Snd.CONFIRM)
	_submit()

func _input(event: InputEvent) -> void:
	if not is_editing_text() or not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed:
		return
	if key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE:
		var game: Node = get_node_or_null("/root/Game")
		if game != null:
			game.call("_open_pause_menu")
		get_viewport().set_input_as_handled()
