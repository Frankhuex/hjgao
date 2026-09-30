class_name DeckChange
extends Node

const SYNC_TIMEOUT_MS: int = 15000
@onready var game: GameSession = get_parent() as GameSession
@onready var database: CardDatabase = game.get_node("CardDatabase")
@onready var button: Button = $"../PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer4/ChangeDeckButton"
@onready var file_dialog: FileDialog = $"../PauseCanvasLayer/DeckFileDialog"
@onready var confirmation: ConfirmationDialog = $"../PauseCanvasLayer/DeckChangeConfirmation"
@onready var message: AcceptDialog = $"../PauseCanvasLayer/DeckChangeMessage"
@onready var status: Label = $"../PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/DeckChangeStatus"
@onready var confirmation_template: String = confirmation.dialog_text
var candidate_json: String = ""
var transaction: int = 0
var phase: String = ""
var waiting: Dictionary[int, bool] = {}
var active: bool = false
var request_pending: bool = false

func _choose_file() -> void:
	if not game.session_active or Util.board_locked(self) or request_pending:
		return
	file_dialog.popup_centered(Vector2i(800, 600))

func _file_selected(path: String) -> void:
	if not game.session_active or Util.board_locked(self):
		return
	candidate_json = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		show_result("无法读取所选文件。")
		return
	if file.get_length() > DeckJson.MAX_BYTES:
		show_result("卡组文件不能超过 1 MiB。")
		return
	var text: String = file.get_as_text()
	var result := DeckJson.parse(text)
	if result.deck == null:
		show_result(result.error)
		return
	candidate_json = text
	confirmation.dialog_text = confirmation_template.format({
		"file_name": path.get_file(),
		"card_types": result.deck.deck_template.ordered_card_names.size(),
		"card_count": result.deck.card_ID_to_card_name.size(),
	})
	confirmation.popup_centered(Vector2i(680, 300))

func _submit() -> void:
	if not game.session_active or Util.board_locked(self) or candidate_json.is_empty():
		return
	request_pending = true
	set_busy(false)
	_set_status("等待服务器校验卡组…")
	var text: String = candidate_json
	candidate_json = ""
	if multiplayer.is_server():
		request_change(text)
	else:
		request_change.rpc_id(1, text)

@rpc("any_peer", "call_remote", "reliable")
func request_change(text: String) -> void:
	if not multiplayer.is_server() or not game.session_active:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if Util.board_locked(self):
		_reply(sender, "正在清场或更换卡组，请稍后再试。")
		return
	var result := DeckJson.parse(text)
	if result.deck == null:
		_reply(sender, result.error)
		return
	var canonical: String = result.deck.serialize_to_json()
	if canonical.to_utf8_buffer().size() > DeckJson.MAX_BYTES:
		_reply(sender, "展开后的完整卡组超过 1 MiB，请缩小卡组。")
		return
	transaction += 1
	var current: int = transaction
	var connection: MultiplayerPeer = multiplayer.multiplayer_peer
	active = true
	game.clear_table_in_progress = true
	var network: SceneMultiplayer = multiplayer as SceneMultiplayer
	network.refuse_new_connections = true
	for id: int in network.get_authenticating_peers():
		network.disconnect_peer(id)
	game.set_clear_table_busy.rpc(true)
	_start_wait("released")
	begin_change.rpc(current)
	if not await _wait_for_peers(current, connection):
		return
	# 所有端先释放占用，避免释放 RPC 到达时旧节点已被删除。
	game._clear_board_nodes()
	while game._board_objects_are_pending_deletion():
		await get_tree().process_frame
		if not _is_current(current, connection):
			return
	_start_wait("installed")
	install_change.rpc(current, canonical)
	if not await _wait_for_peers(current, connection):
		return
	game._rebuild_board()
	finish_change.rpc(current)
	network.refuse_new_connections = false
	phase = ""
	waiting.clear()
	game.set_clear_table_busy.rpc(false)

@rpc("authority", "call_local", "reliable")
func begin_change(id: int) -> void:
	transaction = id
	active = true
	request_pending = false
	file_dialog.hide()
	confirmation.hide()
	message.hide()
	game.prepare_for_table_clear()
	if is_instance_valid(game.local_player) and not game.pause_overlay.visible:
		game._open_pause_menu()
	else:
		game._release_local_interactions()
	_set_status("正在更换卡组，请稍候…")
	var connection: MultiplayerPeer = multiplayer.multiplayer_peer
	# 等待 OwnerMux 的释放广播返回，确保客户端已停止发送旧对象的位置同步。
	while _owns_board_object():
		await get_tree().process_frame
		if not _is_current(id, connection):
			return
	await get_tree().process_frame
	if not _is_current(id, connection):
		return
	_ack(id, "released")

func _owns_board_object() -> bool:
	for container: Node in [game.piles, game.card_sorter]:
		for node: Node in container.get_children():
			var mux: OwnerMux = node.get_node_or_null("OwnerMux") as OwnerMux
			if mux != null and mux.i_am_owner():
				return true
	return false

@rpc("authority", "call_local", "reliable")
func install_change(id: int, text: String) -> void:
	if not active or transaction != id:
		return
	var connection: MultiplayerPeer = multiplayer.multiplayer_peer
	# 只由服务器删除网络节点；客户端等待 Spawner 完成删除。
	while game._board_objects_are_pending_deletion():
		await get_tree().process_frame
		if not _is_current(id, connection):
			return
	# 牌堆 UI 的 queue_free 也需要在换库前完成。
	await get_tree().process_frame
	if not _is_current(id, connection):
		return
	if not database.init_deck_instance_from_json_str(text):
		game._return_to_main_menu("新卡组加载失败，请重新加入房间。")
		show_result("新卡组加载失败，已断开连接，请重新加入房间。")
		return
	_ack(id, "installed")

func _ack(id: int, stage: String) -> void:
	if multiplayer.is_server():
		waiting.erase(1)
	else:
		acknowledge.rpc_id(1, id, stage)

@rpc("any_peer", "call_remote", "reliable")
func acknowledge(id: int, stage: String) -> void:
	if multiplayer.is_server() and active and id == transaction and stage == phase:
		waiting.erase(multiplayer.get_remote_sender_id())

func _start_wait(stage: String) -> void:
	phase = stage
	waiting.clear()
	waiting[1] = true
	for id: int in multiplayer.get_peers():
		waiting[id] = true

func _wait_for_peers(id: int, connection: MultiplayerPeer) -> bool:
	var deadline: int = Time.get_ticks_msec() + SYNC_TIMEOUT_MS
	while not waiting.is_empty():
		if not _is_current(id, connection):
			return false
		for peer_id: int in waiting.keys():
			if peer_id != 1 and not multiplayer.get_peers().has(peer_id):
				waiting.erase(peer_id)
		if Time.get_ticks_msec() >= deadline:
			if waiting.has(1):
				game._return_to_main_menu("服务器加载卡组超时。")
				return false
			for peer_id: int in waiting.keys():
				(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)
				# disconnect_peer 不保证触发 peer_disconnected；复用玩家清理。
				game._on_peer_disconnected(peer_id)
			waiting.clear()
		await get_tree().process_frame
	return _is_current(id, connection)

func _is_current(id: int, connection: MultiplayerPeer) -> bool:
	return active and id == transaction and game.session_active and multiplayer.multiplayer_peer == connection

@rpc("authority", "call_local", "reliable")
func finish_change(id: int) -> void:
	if id != transaction:
		return
	active = false
	request_pending = false
	_set_status("卡组已更换。")

func _reply(peer_id: int, text: String) -> void:
	if peer_id == 1:
		show_result(text)
	else:
		show_result.rpc_id(peer_id, text)

@rpc("authority", "call_remote", "reliable")
func show_result(text: String) -> void:
	request_pending = false
	set_busy(Util.board_locked(self))
	_set_status(text)
	message.dialog_text = text
	message.popup_centered(Vector2i(600, 240))

func _set_status(text: String) -> void:
	status.text = text
	status.show()

func set_busy(busy: bool) -> void:
	button.disabled = busy or request_pending

func has_dialog() -> bool:
	return file_dialog.visible or confirmation.visible or message.visible

func reset() -> void:
	active = false
	transaction += 1
	phase = ""
	waiting.clear()
	candidate_json = ""
	request_pending = false
	file_dialog.hide()
	confirmation.hide()
	message.hide()
	status.hide()
	set_busy(false)
	(multiplayer as SceneMultiplayer).refuse_new_connections = false
