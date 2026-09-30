class_name GameSession
extends Node3D
@onready var main_menu: Control    = $CanvasLayer/MainMenu
@onready var players: Node3D       = $Players
@onready var piles: Node3D         = $Piles
@onready var counters: Node3D      = $Counters
@onready var main_camera: Camera3D = $MainCamera3D
@onready var card_db: CardDatabase = $CardDatabase
@onready var card_sorter: CardSorter = $CardSorter
@onready var input_host_port: LineEdit   = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HBoxContainer/InputHostPort
@onready var input_join_IP: LineEdit     = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HBoxContainer2/InputJoinIP
@onready var input_join_port: LineEdit   = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HBoxContainer2/InputJoinPort
@onready var input_player_name: LineEdit = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/PlayerNameRow/InputPlayerName
@onready var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer
@onready var pause_button: Button = $PauseCanvasLayer/PauseButton
@onready var pause_overlay: Control = $PauseCanvasLayer/PauseOverlay
@onready var player_list: ItemList = $PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/PlayerList
@onready var clear_table_button: Button = $PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer4/ClearTableButton
@onready var clear_table_confirmation: ConfirmationDialog = $PauseCanvasLayer/ClearTableConfirmation
@onready var add_counter_button: Button = $PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/AddCounterButton
@onready var clear_counters_button: Button = $PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ClearCountersButton
@onready var clear_counters_confirmation: ConfirmationDialog = $PauseCanvasLayer/ClearCountersConfirmation
@onready var tooltip_check_box: CheckBox = $PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer2/TooltipCheckBox
@onready var chat_panel_check_box: CheckBox = $PauseCanvasLayer/PauseOverlay/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer2/ChatPanelCheckBox
@onready var card_description_tooltip: CardDescriptionTooltip = $CardDescriptionTooltip
@onready var deck_change: DeckChange = $DeckChange
@onready var chat_ui: ChatPanel = $ChatUI

const PLAYER = preload("res://Player.tscn")
const PILE   = preload("res://Pile.tscn")
const COUNTER = preload("res://Counter.tscn")
const PORT   = 7788
const CONNECTION_TIMEOUT = 10.0
const PLAYER_NAME_MAX_LENGTH = 24
const CLIENT_AUTH_MAX_BYTES = 1024
const AUTH_PROTOCOL_VERSION = 1
const CHAT_HISTORY_LIMIT = 200
const CHAT_MESSAGE_MAX_LENGTH = 500
const CHAT_MESSAGE_MAX_LINES = 8
const CHAT_BURST_TOKENS = 5
const CHAT_TOKEN_REFILL_PER_SECOND = 1

var peer: ENetMultiplayerPeer
var local_player: Player
var session_active := false
var connection_attempt := 0
var main_camera_initial_transform: Transform3D
var clear_table_in_progress := false
var requested_player_name := ""
var pending_player_names: Dictionary = {}
var player_names: Dictionary = {}
var player_roster_cache: Array = []
var chat_history: Array = []
var chat_rate_tokens: Dictionary = {}
var chat_rate_second: Dictionary = {}
var chat_history_served: Dictionary = {}

func _ready():
	# 1. 基础信号绑定
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	scene_multiplayer.auth_callback = _on_auth_data_received
	scene_multiplayer.auth_timeout = CONNECTION_TIMEOUT
	scene_multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	scene_multiplayer.peer_authentication_failed.connect(_on_peer_authentication_failed)
	players.child_entered_tree.connect(_on_player_entered_tree)
	players.child_exiting_tree.connect(_on_player_exiting_tree)
	chat_ui.send_requested.connect(_on_chat_send_requested)
	chat_ui.input_focus_entered.connect(_on_chat_input_focus_entered)
	chat_ui.input_focus_exited.connect(_on_chat_input_focus_exited)
	main_camera_initial_transform = main_camera.transform
	pause_overlay.hide()
	pause_button.hide()
	_sync_tooltip_check_box()
	_sync_chat_panel_check_box()
	
	# 2. 解析命令行参数
	var args := OS.get_cmdline_args()
	var custom_port := _get_arg_value(args, "--port=")
	
	# 确定最终使用的端口（如果命令行没传，就用默认常量 PORT）
	var final_port := int(custom_port) if custom_port != "" else PORT
	
	# 3. 如果是无头模式，自动根据解析到的端口开房
	if DisplayServer.get_name() == "headless":
		print("--- 无头服务器模式 ---")
		print("目标端口: ", final_port)
		start_server(final_port, true)
		return
		
	#var sim = multiplayer
	#if sim:
		## 使用 set 方法绕过编译期检查
		#sim.set("test_config_network_latency", 200)
		#sim.set("test_config_network_jitter", 30)
		#sim.set("test_config_packet_loss", 0.05)
		#
		#print("网络模拟已开启：200ms 延迟 (通过 set 赋值)")

func _get_arg_value(args: PackedStringArray, prefix: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.replace(prefix, "")
	return ""

func start_server(port: int, headless: bool):
	if not card_db.init_deck_instance():
		printerr("创建房间失败：牌库初始化失败")
		return
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		printerr("创建房间失败，端口：", port)
		return
		
	print("成功创建房间于端口：", port)
	multiplayer.multiplayer_peer = peer
	session_active = true
	chat_history.clear()
	chat_rate_tokens.clear()
	chat_rate_second.clear()
	chat_history_served.clear()
	chat_ui.reset()
	add_pile(card_db.get_all_IDs(), "公共牌堆")
	
	if not headless:
		var host_name := Util.sanitize_player_name(input_player_name.text, Util.my_id(self), PLAYER_NAME_MAX_LENGTH)
		var self_player := add_player(Util.my_id(self), host_name)
		create_pile_for_player([], self_player)
		_broadcast_player_roster()

	if main_menu:
		main_menu.hide()
	_update_pause_button()
		
###################################################
# Host
func _on_host_button_pressed() -> void:
	var host_port_str := input_host_port.text
	if not host_port_str.is_valid_int():
		printerr("Port must be integer")
		return
	start_server(int(host_port_str), false)

func add_player(id: int, display_name: String = "") -> Player:
	var player := PLAYER.instantiate() as Player
	var final_name := Util.sanitize_player_name(display_name, id, PLAYER_NAME_MAX_LENGTH)
	player.name = str(id)
	player.display_name = final_name
	player_names[id] = final_name
	players.add_child(player)
	return player

func add_pile(card_IDs: Array[int], pile_name: String) -> Pile:
	var pile: Pile = PILE.instantiate()
	pile.preready(pile_name, card_IDs)
	piles.add_child(pile, true)
	return pile

###################################################
# Counter
func _on_add_counter_button_pressed() -> void:
	if not session_active or clear_table_in_progress:
		return
	chat_ui.release_input_focus()
	if multiplayer.is_server():
		add_counter(_find_free_counter_position())
	else:
		server_add_counter.rpc_id(1)   # 计数器由房主端 Spawner 生成，非房主请求房主代加

@rpc("any_peer", "call_remote", "reliable")
func server_add_counter() -> void:
	if Util.not_server(self) or not session_active or clear_table_in_progress:
		return
	add_counter(_find_free_counter_position())

func add_counter(pos: Vector3) -> Counter:
	var counter: Counter = COUNTER.instantiate()
	counters.add_child(counter, true)
	counter.global_position = pos
	return counter

func _find_free_counter_position() -> Vector3:
	# 在桌面两侧扫描空位，避开现有计数器与牌堆
	for row_z: float in [2.6, -2.6]:
		for i in range(4):
			var pos := Vector3(3.3 - i * 2.2, 0, row_z)
			if _counter_position_free(pos):
				return pos
	return Vector3(0, 0, 2.6) # 都满了就放默认位置

func _counter_position_free(pos: Vector3) -> bool:
	for child: Node in counters.get_children():
		if child is Counter and (child as Counter).global_position.distance_to(pos) < 2.0:
			return false
	for child: Node in piles.get_children():
		if child is Pile and (child as Pile).global_position.distance_to(pos) < 2.0:
			return false
	return true

func _on_peer_connected(id: int):
	if not multiplayer.is_server():
		return
	print("旅行伙伴加入~，玩家ID：", id)
	var display_name := str(pending_player_names.get(id, ""))
	pending_player_names.erase(id)
	var player := add_player(id, display_name)
	create_pile_for_player([], player)
	_broadcast_player_roster()

func _on_peer_disconnected(id: int):
	if not multiplayer.is_server():
		return
	print("伙伴离开了，玩家ID：", id)
	pending_player_names.erase(id)
	player_names.erase(id)
	chat_rate_tokens.erase(id)
	chat_rate_second.erase(id)
	chat_history_served.erase(id)
	# 1. 找到并删除玩家节点
	var player_node = players.get_node_or_null(str(id))
	if player_node:
		player_node.queue_free()
		print("已清理玩家节点：", id)
	_broadcast_player_roster.call_deferred()

func _on_player_entered_tree(node: Node):
	if node is Player:
		if not player_roster_cache.is_empty():
			_apply_player_roster(player_roster_cache)
		_register_local_player.call_deferred(node as Player)

func _register_local_player(player_node: Player):
	if not is_instance_valid(player_node) or not player_node.is_multiplayer_authority():
		return
	local_player = player_node
	if not local_player.status_changed.is_connected(_update_pause_button):
		local_player.status_changed.connect(_update_pause_button)
	local_player.set_input_enabled(true)
	local_player.apply_mouse_mode()
	_update_pause_button()

func _on_player_exiting_tree(node: Node):
	if node == local_player:
		_restore_main_camera()
		local_player = null
		_update_pause_button()

func _on_peer_authenticating(id: int):
	if not multiplayer.is_server():
		return
	if deck_change.active:
		scene_multiplayer.disconnect_peer(id)
		return
	if card_db.deck_instance == null:
		printerr("拒绝玩家认证：服务器牌库未初始化")
		scene_multiplayer.disconnect_peer(id)
		return
	var error: Error = scene_multiplayer.send_auth(id, card_db.export_deck_instance().to_utf8_buffer())
	if error != OK:
		printerr("发送 DeckInstance 快照失败，玩家ID：", id, " 错误码：", error)
		scene_multiplayer.disconnect_peer(id)

func _on_auth_data_received(id: int, data: PackedByteArray):
	if multiplayer.is_server():
		if deck_change.active:
			scene_multiplayer.disconnect_peer(id)
			return
		if data.size() > CLIENT_AUTH_MAX_BYTES:
			printerr("拒绝玩家认证：确认消息过大，玩家ID：", id)
			scene_multiplayer.disconnect_peer(id)
			return
		var parsed_payload: Variant = JSON.parse_string(data.get_string_from_utf8())
		if typeof(parsed_payload) != TYPE_DICTIONARY:
			printerr("拒绝玩家认证：JSON 解析失败，玩家ID：", id)
			scene_multiplayer.disconnect_peer(id)
			return
		var payload: Dictionary = parsed_payload
		var protocol_version := str(payload.get("version", "")).to_int()
		if protocol_version != AUTH_PROTOCOL_VERSION:
			printerr("拒绝玩家认证：协议版本不匹配，玩家ID：", id)
			scene_multiplayer.disconnect_peer(id)
			return
		if payload.get("deck_ready", false) != true:
			printerr("拒绝玩家认证：DeckInstance 确认消息无效，玩家ID：", id)
			scene_multiplayer.disconnect_peer(id)
			return
		var raw_name: Variant = payload.get("player_name", "")
		if typeof(raw_name) != TYPE_STRING:
			printerr("拒绝玩家认证：玩家名称格式无效，玩家ID：", id)
			scene_multiplayer.disconnect_peer(id)
			return
		var player_name := str(raw_name)
		pending_player_names[id] = Util.sanitize_player_name(player_name, id, PLAYER_NAME_MAX_LENGTH)
		var error: Error = scene_multiplayer.complete_auth(id)
		if error != OK:
			printerr("服务器完成认证失败，玩家ID：", id, " 错误码：", error)
			pending_player_names.erase(id)
		return

	if id != 1 or not card_db.init_deck_instance_from_json_str(data.get_string_from_utf8()):
		printerr("加入失败：服务器 DeckInstance 快照无效")
		scene_multiplayer.disconnect_peer(id)
		return
	var auth_reply := {
		"version": AUTH_PROTOCOL_VERSION,
		"deck_ready": true,
		"player_name": requested_player_name,
	}
	var send_error: Error = scene_multiplayer.send_auth(id, JSON.stringify(auth_reply).to_utf8_buffer())
	if send_error != OK:
		printerr("发送 DeckInstance 就绪确认失败，错误码：", send_error)
		scene_multiplayer.disconnect_peer(id)
		return
	var complete_error: Error = scene_multiplayer.complete_auth(id)
	if complete_error != OK:
		printerr("客户端完成认证失败，错误码：", complete_error)

func _on_peer_authentication_failed(id: int):
	if multiplayer.is_server():
		pending_player_names.erase(id)
		printerr("玩家 DeckInstance 同步认证失败，玩家ID：", id)
	else:
		_stop_and_fail("DeckInstance 同步认证失败")

func _input(event: InputEvent):
	if deck_change.has_dialog() or clear_table_confirmation.visible or clear_counters_confirmation.visible or _counter_viewer_editing():
		chat_ui.release_input_focus()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and chat_ui.is_input_focused() and not chat_ui.is_point_in_input(mouse_event.position):
			chat_ui.release_input_focus()
		return
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	if chat_ui.is_input_focused():
		if key_event.keycode == KEY_ESCAPE:
			chat_ui.release_input_focus()
			if not pause_overlay.visible:
				_open_pause_menu()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
			if not key_event.shift_pressed:
				chat_ui.submit_current_input()
				get_viewport().set_input_as_handled()
			return
		return
	if pause_overlay.visible:
		if key_event.keycode == KEY_ESCAPE:
			_close_pause_menu()
			get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_T:
		if session_active and is_instance_valid(local_player):
			chat_ui.toggle()
			_sync_chat_panel_check_box()
			get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_Q:
		if session_active:
			card_description_tooltip.toggle_tooltip_enabled()
			_sync_tooltip_check_box()
			get_viewport().set_input_as_handled()
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	if session_active and is_instance_valid(local_player):
		_open_pause_menu()
		get_viewport().set_input_as_handled()

func _open_pause_menu():
	if not session_active or not is_instance_valid(local_player) or pause_overlay.visible:
		return
	chat_ui.release_input_focus()
	_release_local_interactions()
	local_player.set_input_enabled(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	pause_button.hide()
	add_counter_button.visible = session_active # 所有玩家都可添加计数器
	_sync_tooltip_check_box()
	_sync_chat_panel_check_box()
	pause_overlay.show()
	_sync_player_roster()

func _close_pause_menu():
	if clear_table_in_progress:
		return
	if not pause_overlay.visible:
		return
	pause_overlay.hide()
	if session_active and is_instance_valid(local_player):
		local_player.set_input_enabled(true)
		local_player.apply_mouse_mode()
	_update_pause_button()

func _update_pause_button():
	pause_button.visible = session_active and not pause_overlay.visible and is_instance_valid(local_player)

func _on_tooltip_check_box_toggled(enabled: bool) -> void:
	card_description_tooltip.set_tooltip_enabled(enabled)

func _sync_tooltip_check_box() -> void:
	tooltip_check_box.set_pressed_no_signal(card_description_tooltip.is_tooltip_enabled())

func _on_chat_panel_check_box_toggled(open: bool) -> void:
	if open:
		chat_ui.open()
	else:
		chat_ui.close()

func _sync_chat_panel_check_box() -> void:
	chat_panel_check_box.set_pressed_no_signal(chat_ui.is_open())

func _request_player_roster() -> void:
	if not session_active or Util.is_server(self):
		return
	request_player_roster.rpc_id(1)

func _sync_player_roster() -> void:
	if not session_active:
		return
	if Util.is_server(self):
		_apply_player_roster(_build_player_roster())
		return
	if not player_roster_cache.is_empty():
		_refresh_player_list()
	_request_player_roster()

func _broadcast_player_roster() -> void:
	if Util.not_server(self) or not session_active:
		return
	var roster := _build_player_roster()
	_apply_player_roster(roster)
	receive_player_roster.rpc(roster)

@rpc("any_peer", "call_remote", "reliable")
func request_player_roster() -> void:
	if Util.not_server(self):
		return
	var sender_id := Util.sender_id(self)
	if sender_id <= 0:
		return
	receive_player_roster.rpc_id(sender_id, _build_player_roster())

@rpc("authority", "call_remote", "reliable")
func receive_player_roster(roster: Array) -> void:
	_apply_player_roster(roster)

func _build_player_roster() -> Array:
	var roster: Array = []
	for child: Node in players.get_children():
		if not child is Player or child.is_queued_for_deletion():
			continue
		var player := child as Player
		var peer_id := int(player.name)
		var display_name := str(player_names.get(peer_id, player.display_name))
		roster.append({
			"id": peer_id,
			"name": display_name,
			"is_host": peer_id == 1,
		})
	roster.sort_custom(_roster_entry_less)
	return roster

func _roster_entry_less(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("id", "0")).to_int() < str(right.get("id", "0")).to_int()

func _apply_player_roster(roster: Array) -> void:
	player_roster_cache = roster.duplicate(true)
	for item: Variant in player_roster_cache:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var peer_id := str(entry.get("id", "0")).to_int()
		var display_name := str(entry.get("name", ""))
		var player := players.get_node_or_null(str(peer_id)) as Player
		if player != null:
			player.display_name = display_name
	_refresh_player_list()

func _refresh_player_list() -> void:
	if not is_instance_valid(player_list):
		return
	player_list.clear()
	for item: Variant in player_roster_cache:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var peer_id := str(entry.get("id", "0")).to_int()
		var display_name := str(entry.get("name", ""))
		var text := "%s  [ID %d]" % [display_name, peer_id]
		if entry.get("is_host", false) == true:
			text += "  [房主]"
		if peer_id == Util.my_id(self):
			text += "  [我]"
		player_list.add_item(text)

func _on_chat_send_requested(content: String) -> void:
	if not session_active:
		return
	var message := Util.sanitize_chat_message(content, CHAT_MESSAGE_MAX_LENGTH, CHAT_MESSAGE_MAX_LINES)
	if message.is_empty():
		return
	if Util.is_server(self):
		_server_accept_chat_message(Util.my_id(self), message)
	else:
		_send_chat_message_to_server.call_deferred(message)

func _send_chat_message_to_server(content: String) -> void:
	if not session_active or Util.is_server(self):
		return
	var error := multiplayer.rpc(1, self, &"submit_chat_message", [content])
	if error != OK:
		printerr("发送聊天消息失败，错误码：", error)

func _on_chat_input_focus_entered() -> void:
	if not session_active or not is_instance_valid(local_player) or not local_player.is_card_mode():
		chat_ui.release_input_focus()
		return
	if pause_overlay.visible or _has_blocking_modal():
		chat_ui.release_input_focus()
		return
	local_player.set_input_enabled(false)

func _on_chat_input_focus_exited() -> void:
	if not session_active or not is_instance_valid(local_player):
		return
	if pause_overlay.visible or _has_blocking_modal():
		return
	local_player.set_input_enabled(true)

func _has_blocking_modal() -> bool:
	return deck_change.has_dialog() or clear_table_confirmation.visible

@rpc("any_peer", "call_remote", "reliable")
func submit_chat_message(content: String) -> void:
	if Util.not_server(self) or not session_active:
		return
	var sender_id := Util.sender_id(self)
	if sender_id <= 0 or not player_names.has(sender_id):
		return
	_server_accept_chat_message(sender_id, content)

func _server_accept_chat_message(sender_id: int, content: String) -> void:
	if Util.not_server(self) or not session_active:
		return
	if not _allow_chat_message(sender_id):
		return
	var message := Util.sanitize_chat_message(content, CHAT_MESSAGE_MAX_LENGTH, CHAT_MESSAGE_MAX_LINES)
	if message.is_empty():
		return
	var sender_name := str(player_names.get(sender_id, "玩家%d" % sender_id))
	chat_history.append({
		"sender_id": sender_id,
		"sender_name": sender_name,
		"content": message,
	})
	while chat_history.size() > CHAT_HISTORY_LIMIT:
		chat_history.pop_front()
	receive_chat_message.rpc(sender_id, sender_name, message)

func _allow_chat_message(peer_id: int) -> bool:
	var now_second := int(Time.get_ticks_msec() / 1000)
	var tokens := int(str(chat_rate_tokens.get(peer_id, CHAT_BURST_TOKENS)).to_int())
	var last_second := int(str(chat_rate_second.get(peer_id, now_second)).to_int())
	var elapsed := maxi(0, now_second - last_second)
	tokens = mini(CHAT_BURST_TOKENS, tokens + elapsed * CHAT_TOKEN_REFILL_PER_SECOND)
	if tokens <= 0:
		chat_rate_tokens[peer_id] = tokens
		chat_rate_second[peer_id] = now_second
		return false
	chat_rate_tokens[peer_id] = tokens - 1
	chat_rate_second[peer_id] = now_second
	return true

@rpc("authority", "call_local", "reliable")
func receive_chat_message(sender_id: int, sender_name: String, content: String) -> void:
	var message := Util.sanitize_chat_message(content, CHAT_MESSAGE_MAX_LENGTH, CHAT_MESSAGE_MAX_LINES)
	if message.is_empty():
		return
	chat_ui.append_message(sender_name, message)
	if sender_id != Util.my_id(self):
		chat_ui.show_notification(sender_name, message)

@rpc("any_peer", "call_remote", "reliable")
func request_chat_history() -> void:
	if Util.not_server(self) or not session_active:
		return
	var sender_id := Util.sender_id(self)
	if sender_id <= 0:
		return
	if chat_history_served.has(sender_id):
		return
	chat_history_served[sender_id] = true
	receive_chat_history.rpc_id(sender_id, chat_history)

@rpc("authority", "call_remote", "reliable")
func receive_chat_history(history: Array) -> void:
	chat_ui.replace_history(history)

func _request_chat_history() -> void:
	if not session_active or Util.is_server(self):
		return
	request_chat_history.rpc_id(1)

func _release_local_interactions():
	card_description_tooltip.hide_all()
	for child in card_sorter.get_children():
		if child is Card:
			var card: Card = child
			card.release_local_interaction()
	for child in piles.get_children():
		if child is Pile:
			var pile: Pile = child
			pile.release_local_interaction()
	for child in counters.get_children():
		if child is Counter:
			var counter: Counter = child
			counter.release_local_interaction()
	_close_local_deck_viewers()

func _close_local_deck_viewers():
	for node in get_tree().root.get_children():
		if node is DeckViewerUI or node is CounterViewerUI:
			node.queue_free()

func _counter_viewer_editing() -> bool:
	for node in get_tree().root.get_children():
		var viewer := node as CounterViewerUI
		if viewer != null and viewer.is_editing_text():
			return true
	return false

func _on_pause_button_pressed():
	_open_pause_menu()

func _on_return_game_button_pressed():
	_close_pause_menu()

func _on_clear_table_button_pressed() -> void:
	if not session_active or clear_table_in_progress:
		return
	chat_ui.release_input_focus()
	clear_table_confirmation.popup_centered(Vector2i(640, 260))

func _on_clear_table_confirmed() -> void:
	if not session_active:
		return
	if Util.is_server(self):
		server_clear_table()
	else:
		server_clear_table.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_clear_table() -> void:
	if Util.not_server(self) or not session_active or clear_table_in_progress:
		return
	if card_db.deck_instance == null:
		printerr("一键清场失败：牌库尚未初始化")
		return

	clear_table_in_progress = true
	set_clear_table_busy.rpc(true)
	prepare_for_table_clear.rpc()

	_clear_board_nodes()

	# queue_free() 会在帧末执行；确认旧节点真正离树后再创建同名牌堆。
	while _board_objects_are_pending_deletion():
		await get_tree().process_frame
	if not session_active or card_db.deck_instance == null:
		clear_table_in_progress = false
		set_clear_table_busy.rpc(false)
		return

	_rebuild_board()
	clear_table_in_progress = false
	set_clear_table_busy.rpc(false)
	print("一键清场完成")

func _rebuild_board() -> void:
	var all_card_ids: Array[int] = card_db.get_all_IDs()
	all_card_ids.sort_custom(_card_id_less)
	var public_pile := add_pile(all_card_ids, "公共牌堆")
	public_pile.global_position = Vector3.ZERO
	for child: Node in players.get_children():
		if child is Player and not child.is_queued_for_deletion():
			var empty_card_ids: Array[int] = []
			create_pile_for_player(empty_card_ids, child as Player)

@rpc("authority", "call_local", "reliable")
func prepare_for_table_clear() -> void:
	clear_table_confirmation.hide()
	card_description_tooltip.hide_all()
	_close_local_deck_viewers()

@rpc("authority", "call_local", "reliable")
func set_clear_table_busy(busy: bool) -> void:
	clear_table_in_progress = busy
	clear_table_button.disabled = busy
	deck_change.set_busy(busy)

func _card_id_less(card_id_a: int, card_id_b: int) -> bool:
	var priority_a := card_db.get_priority(card_id_a)
	var priority_b := card_db.get_priority(card_id_b)
	if priority_a == priority_b:
		return card_id_a < card_id_b
	return priority_a < priority_b

func _board_objects_are_pending_deletion() -> bool:
	for child: Node in card_sorter.get_children():
		if child is Card:
			return true
	for child: Node in piles.get_children():
		if child is Pile:
			return true
	return false

func _clear_board_nodes() -> void:
	card_sorter.card_ID_stack.clear()
	for child: Node in card_sorter.get_children():
		if child is Card:
			child.queue_free()
	for child: Node in piles.get_children():
		if child is Pile:
			child.queue_free()

###################################################
# 一键清计数器（与一键清场相互独立，见设计文档 Q2）
func _on_clear_counters_button_pressed() -> void:
	if not session_active or clear_table_in_progress:
		return
	chat_ui.release_input_focus()
	clear_counters_confirmation.popup_centered(Vector2i(640, 260))

func _on_clear_counters_confirmed() -> void:
	if not session_active:
		return
	if Util.is_server(self):
		server_clear_counters()
	else:
		server_clear_counters.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_clear_counters() -> void:
	if Util.not_server(self) or not session_active or clear_table_in_progress:
		return
	clear_table_in_progress = true # 复用全局清场锁：清计数器期间 Util.board_locked() 拒绝一切申请
	set_clear_table_busy.rpc(true)
	prepare_for_counters_clear.rpc()
	for child: Node in counters.get_children():
		if child is Counter:
			child.queue_free()
	while _counters_are_pending_deletion():
		await get_tree().process_frame
	clear_table_in_progress = false
	set_clear_table_busy.rpc(false)
	print("一键清计数器完成")

@rpc("authority", "call_local", "reliable")
func prepare_for_counters_clear() -> void:
	clear_counters_confirmation.hide()

func _counters_are_pending_deletion() -> bool:
	for child: Node in counters.get_children():
		if child is Counter:
			return true
	return false

func _on_disconnect_button_pressed():
	_release_local_interactions()
	_return_to_main_menu("已退出房间")

func create_pile_for_player(card_IDs: Array[int], player: Player) -> Pile:
	var pile := add_pile(card_IDs, "pile" + player.name)
	pile.global_position = Vector3(player.global_position.x, 0.0, player.global_position.z)
	return pile

#################################################
# Client
func _on_join_button_pressed() -> void:
	var join_IP := input_join_IP.text
	var join_port_str := input_join_port.text
	if not join_port_str.is_valid_int():
		printerr("Port must be integer")
		return
	requested_player_name = input_player_name.text
	var port := int(join_port_str)
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(join_IP, port)
	if err != OK:
		printerr("本地初始化失败（端口被占用或IP格式错误）")
		return
		
	# 【修改】这里只代表发起了请求，所以不要隐藏菜单
	print("正在尝试连接服务器：", join_IP + ":" + join_port_str, "...")
	connection_attempt += 1
	var current_attempt := connection_attempt
	multiplayer.multiplayer_peer = peer
	get_tree().create_timer(CONNECTION_TIMEOUT).timeout.connect(func(): _on_connection_timeout(current_attempt))

# 真正连接成功
func _on_connected_to_server():
	print("【成功】已进入房间！")
	connection_attempt += 1
	session_active = true
	main_menu.hide()
	_update_pause_button()
	_request_player_roster.call_deferred()
	_request_chat_history.call_deferred()

# 连接物理失败（比如握手包被防火墙拦截，由引擎触发）
func _on_connection_failed():
	_stop_and_fail("服务器拒绝连接或握手失败")

func _on_server_disconnected():
	if session_active:
		_return_to_main_menu("服务器已关闭")

# 【新增：手动超时处理】
func _on_connection_timeout(attempt: int):
	if attempt != connection_attempt:
		return
	# 如果计时器到了，但菜单还没隐藏，说明还没连上
	if main_menu.visible and not session_active:
		_stop_and_fail("连接超时：服务器没有响应")

# 统一的清理函数，避免逻辑重复
func _stop_and_fail(reason: String):
	print("【连接放弃】", reason)
	_return_to_main_menu(reason)

func _return_to_main_menu(reason: String):
	deck_change.reset()
	connection_attempt += 1
	session_active = false
	clear_table_in_progress = false
	clear_table_confirmation.hide()
	clear_table_button.disabled = false
	pause_overlay.hide()
	pause_button.hide()
	player_list.clear()
	chat_ui.reset()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	card_description_tooltip.hide_all()
	_close_local_deck_viewers()
	_restore_main_camera()
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = null
	_clear_session_nodes()
	card_db.deck_instance = null
	local_player = null
	requested_player_name = ""
	pending_player_names.clear()
	player_names.clear()
	player_roster_cache.clear()
	chat_history.clear()
	chat_rate_tokens.clear()
	chat_rate_second.clear()
	chat_history_served.clear()
	main_menu.show()
	print(reason)

func _restore_main_camera():
	if not is_instance_valid(main_camera):
		return
	if main_camera.get_parent() != self:
		main_camera.reparent(self)
	main_camera.transform = main_camera_initial_transform

func _clear_session_nodes():
	_clear_board_nodes()
	for child: Node in counters.get_children():
		child.queue_free()
	for child: Node in players.get_children():
		child.queue_free()
