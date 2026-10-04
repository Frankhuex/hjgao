class_name CardDatabase
extends Node

const DEFAULT_DECK_PATH = "res://deck_instances/poker.json"

var deck_instance: DeckInstance

func init_deck_instance() -> bool:
	if not FileAccess.file_exists(DEFAULT_DECK_PATH):
		printerr("牌库文件不存在：", DEFAULT_DECK_PATH)
		return false
	return init_deck_instance_from_json_str(FileAccess.get_file_as_string(DEFAULT_DECK_PATH))

func init_deck_instance_from_json_str(json_str: String) -> bool:
	var result := DeckJson.parse(json_str)
	if result.deck == null:
		printerr(result.error)
		return false
	deck_instance = result.deck
	return true

func export_deck_instance() -> String:
	return deck_instance.serialize_to_json()

func get_all_IDs() -> Array[int]:
	return deck_instance.card_ID_to_card_name.keys()

func get_ordered_card_IDs_by_type() -> Dictionary[String, Array]:
	return deck_instance.get_ordered_card_IDs_by_type()

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

func is_upright(id: int) -> bool:
	return deck_instance.card_ID_to_is_upright[id]

func get_priority(id: int) -> int:
	return deck_instance.deck_template.card_name_to_priority[get_card_name(id)]

# Flipping
signal on_flip

# Orientation
signal orientation_changed(updates: Dictionary)
func local_flip(id: int):
	var front := is_front(id)
	deck_instance.card_ID_to_is_front[id] = not front

func request_flip(id: int):
	if Util.board_locked(self): return
	if Util.is_server(self):
		server_flip(id)
	else:
		server_flip.rpc_id(1, id)

func request_flip_to(id: int, front: bool):
	if Util.board_locked(self): return
	if Util.is_server(self):
		server_flip_to(id, front)
	else:
		server_flip_to.rpc_id(1, id, front)

@rpc("any_peer", "call_remote", "reliable")
func server_flip(id: int):
	if Util.not_server(self): return
	if Util.board_locked(self) or not deck_instance.card_ID_to_card_name.has(id): return
	local_flip(id)
	sync_flip_status.rpc(deck_instance.card_ID_to_is_front)

@rpc("any_peer", "call_remote", "reliable")
func server_flip_to(id: int, front: bool):
	if Util.not_server(self): return
	if Util.board_locked(self) or not deck_instance.card_ID_to_card_name.has(id): return
	if is_front(id) == front: return
	local_flip(id)
	sync_flip_status.rpc(deck_instance.card_ID_to_is_front)

@rpc("authority", "call_local", "reliable")
func sync_flip_status(card_ID_to_is_front: Dictionary):
	deck_instance.card_ID_to_is_front = card_ID_to_is_front
	on_flip.emit()

func apply_orientation_operation(operation: Const.PileOrientationOperation, card_IDs: Array[int]) -> void:
	if deck_instance == null:
		return
	var updates: Dictionary = {}
	var face_updates: Dictionary = {}
	for card_id: int in card_IDs:
		if not deck_instance.card_ID_to_card_name.has(card_id):
			continue
		var current_upright := is_upright(card_id)
		var new_upright := current_upright
		var new_front := is_front(card_id)
		match operation:
			Const.PileOrientationOperation.SINGLE_TOGGLE:
				new_upright = not current_upright
			Const.PileOrientationOperation.ALL_UPRIGHT:
				new_upright = true
			Const.PileOrientationOperation.ALL_INVERTED:
				new_upright = false
			Const.PileOrientationOperation.ALL_TOGGLE:
				new_upright = not current_upright
			Const.PileOrientationOperation.RANDOM_FACE:
				new_front = randi() % 2 == 0
			Const.PileOrientationOperation.RANDOM_UPRIGHT:
				new_upright = randi() % 2 == 0
		if new_front != is_front(card_id):
			deck_instance.card_ID_to_is_front[card_id] = new_front
			face_updates[card_id] = new_front
		if new_upright == current_upright:
			continue
		deck_instance.card_ID_to_is_upright[card_id] = new_upright
		updates[card_id] = new_upright
	if not updates.is_empty() and not face_updates.is_empty():
		sync_random_status.rpc(face_updates, updates)
	elif not updates.is_empty():
		sync_orientation_status.rpc(updates)
	elif not face_updates.is_empty():
		sync_flip_status.rpc(deck_instance.card_ID_to_is_front)

func reset_face_and_orientation() -> void:
	if deck_instance == null:
		return
	for card_id: int in deck_instance.card_ID_to_card_name.keys():
		deck_instance.card_ID_to_is_front[card_id] = true
		deck_instance.card_ID_to_is_upright[card_id] = true
	sync_face_and_orientation_status.rpc(deck_instance.card_ID_to_is_front, deck_instance.card_ID_to_is_upright)

@rpc("authority", "call_local", "reliable")
func sync_face_and_orientation_status(new_card_ID_to_is_front: Dictionary, new_card_ID_to_is_upright: Dictionary) -> void:
	deck_instance.card_ID_to_is_front = new_card_ID_to_is_front
	deck_instance.card_ID_to_is_upright = new_card_ID_to_is_upright
	on_flip.emit()
	orientation_changed.emit(new_card_ID_to_is_upright)

@rpc("authority", "call_local", "reliable")
func sync_orientation_status(updates: Dictionary):
	for card_id: Variant in updates:
		if card_id is int and str(card_id).is_valid_int():
			var upright_id := str(card_id).to_int()
			if deck_instance.card_ID_to_card_name.has(upright_id):
				deck_instance.card_ID_to_is_upright[upright_id] = updates[card_id]
	orientation_changed.emit(updates)

@rpc("authority", "call_local", "reliable")
func sync_random_status(new_face_updates: Dictionary, new_upright_updates: Dictionary):
	for card_id: Variant in new_face_updates:
		if card_id is int and str(card_id).is_valid_int():
			var face_id := str(card_id).to_int()
			if deck_instance.card_ID_to_card_name.has(face_id):
				deck_instance.card_ID_to_is_front[face_id] = new_face_updates[card_id]
	for card_id: Variant in new_upright_updates:
		if card_id is int and str(card_id).is_valid_int():
			var upright_id := str(card_id).to_int()
			if deck_instance.card_ID_to_card_name.has(upright_id):
				deck_instance.card_ID_to_is_upright[upright_id] = new_upright_updates[card_id]
	on_flip.emit()
	orientation_changed.emit(new_upright_updates)
	
