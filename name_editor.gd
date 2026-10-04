class_name NameEditor
extends Node

signal name_changed
signal submission_finished(request_id: int, accepted: bool, message: String)

const MAX_LENGTH := 64
var display_name: String = ""
var _mux: OwnerMux
var _purpose: Const.Purpose
var _next_request_id := 0

# 生成入树前注入初始状态；运行时修改仍需查看占用。
func initialize_name(initial_name: String) -> void:
	if is_inside_tree():
		push_error("NameEditor initialization must happen before entering the tree")
		return
	display_name = initial_name

func configure(mux: OwnerMux, purpose: Const.Purpose) -> void:
	_mux = mux
	_purpose = purpose
	_mux.on_owner_change.connect(_restore_authority)
	_restore_authority()
	if not multiplayer.is_server():
		request_sync_name.call_deferred()

func _restore_authority() -> void:
	set_multiplayer_authority(1)

static func clean_name(text: String) -> String:
	var result := ""
	var space := false
	for character in text:
		if character.unicode_at(0) <= 32 or character.unicode_at(0) in range(127, 160) or character.strip_edges().is_empty():
			space = not result.is_empty()
		else:
			if space:
				result += " "
			result += character
			space = false
	return result

func next_request_id() -> int:
	_next_request_id += 1
	return _next_request_id

func can_edit() -> bool:
	var game: Node = get_node_or_null("/root/Game")
	return game != null and game.get("session_active") == true and not Util.board_locked(self) and not get_parent().is_queued_for_deletion() and _mux.i_am_owner() and _mux.purpose == _purpose

func request_apply_name(text: String, request_id: int) -> void:
	if multiplayer.is_server():
		server_apply_name(text, request_id)
	else:
		server_apply_name.rpc_id(1, text, request_id)

@rpc("any_peer", "call_remote", "reliable")
func server_apply_name(text: String, request_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var game: Node = get_node_or_null("/root/Game")
	var message := ""
	if game == null or game.get("session_active") != true or get_parent().is_queued_for_deletion() or Util.board_locked(self):
		message = "当前无法修改名称"
	elif sender != 1 and not multiplayer.get_peers().has(sender):
		return
	elif _mux.get_owner_id() != sender or _mux.purpose != _purpose:
		message = "请先取得查看权限"
	elif text.length() > MAX_LENGTH:
		message = "名称最多 64 个字符"
	var cleaned := clean_name(text)
	if message.is_empty():
		if cleaned != display_name:
			sync_name.rpc(cleaned)
		else:
			message = "名称未变化"
	var accepted: bool = message.is_empty() or message == "名称未变化"
	if sender == 1:
		name_result(request_id, accepted, message, display_name)
	else:
		name_result.rpc_id(sender, request_id, accepted, message, display_name)

func request_sync_name() -> void:
	if is_inside_tree() and multiplayer.multiplayer_peer != null:
		server_sync_name.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_sync_name() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender > 1 and multiplayer.get_peers().has(sender):
		sync_name.rpc_id(sender, display_name)

@rpc("authority", "call_local", "reliable")
func sync_name(text: String) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	display_name = text
	name_changed.emit()

@rpc("authority", "call_remote", "reliable")
func name_result(request_id: int, accepted: bool, message: String, current_name: String) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	if display_name != current_name:
		display_name = current_name
		name_changed.emit()
	submission_finished.emit(request_id, accepted, message)
