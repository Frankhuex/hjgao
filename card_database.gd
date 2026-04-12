class_name CardDatabase
extends Node

@onready var deck_instance := load_deck_instance_from_json("res://poker.json")

func _ready():
	if Util.not_server(self):
		request_sync_front_status()

#新玩家请求同步is_front
func request_sync_front_status():
	print("user: ", Util.my_id(self), " request_sync_front_status")
	server_sync_card_ID_stack.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_sync_card_ID_stack():
	if Util.not_server(self): return
	sync_flip_status.rpc_id(Util.sender_id(self), deck_instance.card_ID_to_is_front)

func load_deck_instance_from_json(file_path: String) -> DeckInstance:
	return DeckInstance.load_from_json(load_json_file(file_path))
	
func load_json_file(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		print("文件不存在！")
		return null
	var file    := FileAccess.open(file_path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	var json  := JSON.new()
	var error := json.parse(content)
	if error == OK:
		return json.data #通常是 Dictionary 或 Array
	else:
		printerr("JSON 解析失败: ", json.get_error_message(), " 行数: ", json.get_error_line())
		return null

func export_deck_instance() -> String:
	return deck_instance.serialize_to_json()

func get_all_IDs() -> Array[int]:
	return deck_instance.card_ID_to_card_name.keys()

func get_card_name(id: int) -> String:
	return deck_instance.card_ID_to_card_name[id]

func get_card_template(id: int) -> CardTemplate:
	var card_name := get_card_name(id)
	return deck_instance.deck_template.card_name_to_card_template[card_name]

func is_front(id: int) -> bool:
	return deck_instance.card_ID_to_is_front[id]

func get_priority(id: int) -> int:
	return deck_instance.deck_template.card_name_to_priority[get_card_name(id)]

# Flipping
signal on_flip
func local_flip(id: int):
	var front := is_front(id)
	deck_instance.card_ID_to_is_front[id] = not front

func request_flip(id: int):
	if Util.is_server(self):
		server_flip(id)
	else:
		server_flip.rpc_id(1, id)

func request_flip_to(id: int, front: bool):
	if Util.is_server(self):
		server_flip_to(id, front)
	else:
		server_flip_to.rpc_id(1, id, front)

@rpc("any_peer", "call_remote", "reliable")
func server_flip(id: int):
	if Util.not_server(self): return
	local_flip(id)
	sync_flip_status.rpc(deck_instance.card_ID_to_is_front)

@rpc("any_peer", "call_remote", "reliable")
func server_flip_to(id: int, front: bool):
	if Util.not_server(self): return
	if is_front(id) == front: return
	local_flip(id)
	sync_flip_status.rpc(deck_instance.card_ID_to_is_front)

@rpc("any_peer", "call_local", "reliable")
func sync_flip_status(card_ID_to_is_front: Dictionary):
	deck_instance.card_ID_to_is_front = card_ID_to_is_front
	on_flip.emit()

	
