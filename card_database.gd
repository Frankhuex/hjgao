class_name CardDatabase
extends Node

const DEFAULT_DECK_PATH = "res://poker.json"

var deck_instance: DeckInstance

func init_deck_instance() -> bool:
	if not FileAccess.file_exists(DEFAULT_DECK_PATH):
		printerr("牌库文件不存在：", DEFAULT_DECK_PATH)
		return false
	return init_deck_instance_from_json_str(FileAccess.get_file_as_string(DEFAULT_DECK_PATH))

func init_deck_instance_from_json_str(json_str: String) -> bool:
	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		printerr("DeckInstance JSON 解析失败: ", json.get_error_message(), " 行数: ", json.get_error_line())
		return false
	var loaded_deck_instance := DeckInstance.load_from_json(json.data)
	if loaded_deck_instance == null:
		printerr("DeckInstance JSON 格式校验失败")
		return false
	deck_instance = loaded_deck_instance
	return true

func export_deck_instance() -> String:
	return deck_instance.serialize_to_json()

func get_all_IDs() -> Array[int]:
	return deck_instance.card_ID_to_card_name.keys()

func get_card_name(id: int) -> String:
	return deck_instance.card_ID_to_card_name[id]

func get_card_template(id: int) -> CardTemplate:
	var card_name := get_card_name(id)
	return deck_instance.deck_template.card_name_to_card_template[card_name]

func get_card_tooltip_text(id: int) -> String:
	var card_name := get_card_name(id).strip_edges()
	var description := get_card_template(id).description.strip_edges()
	if card_name.is_empty():
		return description
	if description.is_empty():
		return card_name
	return card_name + ": " + description

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

	
