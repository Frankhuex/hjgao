extends Node3D
@onready var main_menu: Control    = $CanvasLayer/MainMenu
@onready var players: Node3D       = $Players
@onready var piles: Node3D         = $Piles
@onready var main_camera: Camera3D = $MainCamera3D
@onready var card_db: CardDatabase = $CardDatabase
@onready var input_host_port: LineEdit   = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HBoxContainer/InputHostPort
@onready var input_join_IP: LineEdit     = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HBoxContainer2/InputJoinIP
@onready var input_join_port: LineEdit   = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HBoxContainer2/InputJoinPort
@onready var scene_multiplayer: SceneMultiplayer = multiplayer as SceneMultiplayer

const PLAYER = preload("res://Player.tscn")
const PILE   = preload("res://Pile.tscn")
const PORT   = 7788
const CONNECTION_TIMEOUT = 10.0
const AUTH_READY_ACK = "deck_instance_ready"

var peer: ENetMultiplayerPeer

func _ready():
	# 1. 基础信号绑定
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	scene_multiplayer.auth_callback = _on_auth_data_received
	scene_multiplayer.auth_timeout = CONNECTION_TIMEOUT
	scene_multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	scene_multiplayer.peer_authentication_failed.connect(_on_peer_authentication_failed)
	
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
	multiplayer.peer_connected.connect(_on_peer_connected)	
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	add_pile(card_db.get_all_IDs(), "公共牌堆")
	
	if not headless:
		var self_player := add_player(Util.my_id(self))
		create_pile_for_player([], self_player)

	if main_menu:
		main_menu.hide()
		
###################################################
# Host
func _on_host_button_pressed() -> void:
	var host_port_str := input_host_port.text
	if not host_port_str.is_valid_int():
		printerr("Port must be integer")
		return
	start_server(int(host_port_str), false)

func add_player(id: int) -> Player:
	var player := PLAYER.instantiate()
	player.name = str(id)
	players.add_child(player)
	return player

func add_pile(card_IDs: Array[int], pile_name: String) -> Pile:
	var pile: Pile = PILE.instantiate()
	pile.preready(pile_name, card_IDs)
	piles.add_child(pile)
	return pile

func _on_peer_connected(id: int):
	print("旅行伙伴加入~，玩家ID：", id)
	var player := add_player(id)
	create_pile_for_player([], player)

func _on_peer_disconnected(id: int):
	print("伙伴离开了，玩家ID：", id)
	# 1. 找到并删除玩家节点
	var player_node = players.get_node_or_null(str(id))
	if player_node:
		player_node.queue_free()
		print("已清理玩家节点：", id)

func _on_peer_authenticating(id: int):
	if not multiplayer.is_server():
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
		if data.get_string_from_utf8() != AUTH_READY_ACK:
			printerr("拒绝玩家认证：DeckInstance 确认消息无效，玩家ID：", id)
			scene_multiplayer.disconnect_peer(id)
			return
		var error: Error = scene_multiplayer.complete_auth(id)
		if error != OK:
			printerr("服务器完成认证失败，玩家ID：", id, " 错误码：", error)
		return

	if id != 1 or not card_db.init_deck_instance_from_json_str(data.get_string_from_utf8()):
		printerr("加入失败：服务器 DeckInstance 快照无效")
		scene_multiplayer.disconnect_peer(id)
		return
	var send_error: Error = scene_multiplayer.send_auth(id, AUTH_READY_ACK.to_utf8_buffer())
	if send_error != OK:
		printerr("发送 DeckInstance 就绪确认失败，错误码：", send_error)
		scene_multiplayer.disconnect_peer(id)
		return
	var complete_error: Error = scene_multiplayer.complete_auth(id)
	if complete_error != OK:
		printerr("客户端完成认证失败，错误码：", complete_error)

func _on_peer_authentication_failed(id: int):
	if multiplayer.is_server():
		printerr("玩家 DeckInstance 同步认证失败，玩家ID：", id)
	else:
		_stop_and_fail("DeckInstance 同步认证失败")

func create_pile_for_player(card_IDs: Array[int], player: Player):
	var pile := add_pile(card_IDs, "pile"+player.name)
	pile.global_position.x = player.global_position.x
	pile.global_position.z = player.global_position.z

#################################################
# Client
func _on_join_button_pressed() -> void:
	var join_IP := input_join_IP.text
	var join_port_str := input_join_port.text
	if not join_port_str.is_valid_int():
		printerr("Port must be integer")
		return
	var port := int(join_port_str)
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(join_IP, port)
	if err != OK:
		printerr("本地初始化失败（端口被占用或IP格式错误）")
		return
		
	# 【修改】这里只代表发起了请求，所以不要隐藏菜单
	print("正在尝试连接服务器：", join_IP + ":" + join_port_str, "...")
	multiplayer.multiplayer_peer = peer
	get_tree().create_timer(CONNECTION_TIMEOUT).timeout.connect(_on_connection_timeout)

# 真正连接成功
func _on_connected_to_server():
	print("【成功】已进入房间！")
	main_menu.hide()

# 连接物理失败（比如握手包被防火墙拦截，由引擎触发）
func _on_connection_failed():
	_stop_and_fail("服务器拒绝连接或握手失败")

# 【新增：手动超时处理】
func _on_connection_timeout():
	# 如果计时器到了，但菜单还没隐藏，说明还没连上
	if main_menu.visible:
		_stop_and_fail("连接超时：服务器没有响应")

# 统一的清理函数，避免逻辑重复
func _stop_and_fail(reason: String):
	if multiplayer.multiplayer_peer != null:
		print("【连接放弃】", reason)
		# 关键：这行会彻底杀掉当前的 ENet 尝试，释放端口
		multiplayer.multiplayer_peer = null
		# 可以在这里给用户弹个窗提示，或者恢复按钮点击
