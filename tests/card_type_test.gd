extends "res://tests/pile_lifecycle_test.gd"

const TYPE_FIXTURE := "res://tests/fixtures/card_types.json"
const SECOND_DECK := '{"deck_template":{"ordered_card_templates":[{"name":"I","count":2,"type":"Y"},{"name":"J","count":1,"type":"X"},{"name":"K","count":1,"type":null}]},"card_ID_to_card_name":{"903":"I","902":"J","901":"I","904":"K"},"card_ID_to_is_upright":{"901":false}}'

class TypedDatabase extends CardDatabase:
	func init_deck_instance() -> bool:
		return init_deck_instance_from_json_str(FileAccess.get_file_as_string(TYPE_FIXTURE))

func _parser_tests() -> void:
	var result := DeckJson.parse(FileAccess.get_file_as_string(TYPE_FIXTURE))
	_check(result.deck != null, "typed fixture parses")
	var template := result.deck.deck_template
	_check(template.ordered_card_names == ["A", "B", "C", "D", "E", "F", "G", "H"], "global JSON order preserved")
	_check(template.ordered_types == ["X", "Y", "", "Z", "untyped", "W"], "first-occurrence type order")
	_check(template.type_to_ordered_card_names["X"] == ["A", "C"] and template.type_to_ordered_card_names[""] == ["D", "E"], "subsequence names and empty key")
	_check(template.type_to_priority[""] == 2 and template.card_name_to_priority["B"] == 1, "two independent priorities")
	_check(result.deck.get_ordered_card_IDs_by_type()["X"] == [101, 303, 9], "template order dominates arbitrary ID order")
	var round_trip := DeckJson.parse(result.deck.serialize_to_json())
	_check(round_trip.deck != null and round_trip.deck.deck_template.ordered_types == template.ordered_types, "type order round trip")
	_check(round_trip.deck.deck_template.type_to_ordered_card_names == template.type_to_ordered_card_names, "type index round trip")
	_check(round_trip.deck.card_ID_to_is_front == result.deck.card_ID_to_is_front and round_trip.deck.card_ID_to_is_upright == result.deck.card_ID_to_is_upright, "orientation round trip")
	var auto_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TYPE_FIXTURE))
	auto_json.erase("card_ID_to_card_name")
	auto_json.erase("card_ID_to_is_front")
	auto_json.erase("card_ID_to_is_upright")
	var automatic := DeckJson.parse(JSON.stringify(auto_json))
	_check(automatic.deck.card_ID_to_card_name[1] == "A" and automatic.deck.card_ID_to_card_name[2] == "A" and automatic.deck.card_ID_to_card_name[3] == "B", "automatic IDs obey original order")
	_check(automatic.deck.get_ordered_card_IDs_by_type()["X"] == [1, 2, 4], "automatic typed subsequence")
	for empty_value: Variant in [null, "", "  ", "\n\t"]:
		var input: Dictionary = {"deck_template": {"ordered_card_templates": [{"name": "empty", "type": empty_value}, {"name": "typed", "type": "untyped"}]}}
		var empty := DeckJson.parse(JSON.stringify(input))
		_check(empty.deck != null and empty.deck.deck_template.ordered_types == ["", "untyped"], "empty type first and literal untyped separate")
	for invalid: Variant in [1, true, [], {}, "x".repeat(65), "a\nb", "a\tb", "a" + String.chr(127) + "b"]:
		var input: Dictionary = {"deck_template": {"ordered_card_templates": [{"name": "invalid", "type": invalid}]}}
		_check(DeckJson.parse(JSON.stringify(input)).deck == null, "invalid type rejected")
	var boundary := CardTemplate.new("boundary", 1, "", "x".repeat(64))
	_check(CardTemplate.validate_type(boundary.type).is_empty(), "64 character type accepted")
	var many_templates: Array[Dictionary] = []
	for i in range(1000):
		many_templates.append({"name": str(i), "type": "T%d" % i})
	var many := DeckJson.parse(JSON.stringify({"deck_template": {"ordered_card_templates": many_templates}}))
	_check(many.deck != null and many.deck.deck_template.ordered_types.size() == 1000, "no new type-count restriction")

func _verify_board(second: bool, faces_reset: bool = false) -> void:
	var expected_types: Array[String] = []
	expected_types.assign(["Y", "X", ""] if second else ["X", "Y", "", "Z", "untyped", "W"])
	var expected_ids: Array[Array] = []
	expected_ids.assign([[901, 903], [902], [904]] if second else [[101, 303, 9], [205], [401, 402], [501], [601], [701]])
	_check(game.card_db.deck_instance.deck_template.ordered_types == expected_types, "local type index")
	var total := 0
	for i in range(expected_types.size()):
		var pile := _pile("type_pile_%d" % (i + 1))
		_check(pile != null, "classification node present")
		_check(pile.card_ID_stack == expected_ids[i], "classification stack exact order")
		var expected_name := "未分类" if expected_types[i].is_empty() else expected_types[i]
		_check(pile.display_name == expected_name, "initial classification display name")
		_check(pile.position.distance_to(game._initial_type_pile_position(i, expected_types.size())) < 0.001, "classification spawn position")
		total += pile.card_ID_stack.size()
	_check(total == game.card_db.get_all_IDs().size(), "cards conserved")
	_check(game.card_sorter.get_child_count() == 0, "no loose cards")
	if second:
		_check(_pile("type_pile_4") == null and _pile("type_pile_6") == null, "old extra classifications removed")
		_check(game.card_db.is_front(901) == faces_reset and game.card_db.is_upright(901) == faces_reset, "import versus clear face behavior")

func _await_board(second: bool, faces_reset: bool = false) -> void:
	var types: Array[String] = []
	types.assign(["Y", "X", ""] if second else ["X", "Y", "", "Z", "untyped", "W"])
	while true:
		var ready := not game.clear_table_in_progress and game.card_db.deck_instance.deck_template.ordered_types == types
		for i in range(types.size()):
			var pile := _pile("type_pile_%d" % (i + 1))
			if pile == null or pile.card_ID_stack.is_empty() or pile.display_name.is_empty():
				ready = false
		if ready and (not faces_reset or game.card_db.is_front(901)):
			return
		await process_frame

func _local_tests() -> void:
	_parser_tests()
	_check(_pile("公共牌堆").display_name == "未分类", "old deck default group name")
	game._return_to_main_menu("restart with typed database")
	await process_frame
	await process_frame
	game.card_db.set_script(TypedDatabase)
	game.start_server(TEST_PORT, false)
	await process_frame
	_verify_board(false)
	_check(game._initial_type_pile_position(0, 1) == Vector3.ZERO, "single type centered")
	_check(game._initial_type_pile_position(4, 6) == Vector3(-0.75, 0, 1) and game._initial_type_pile_position(5, 6) == Vector3(0.75, 0, 1), "last incomplete row centered")
	_check(game._initial_type_pile_position(999, 1000).z > 5.0, "layout extends beyond table")
	_check(game.card_db.get_priority(205) < game.card_db.get_priority(9), "mixed deck priority follows global sequence")
	var counter := game.add_counter(Vector3.ZERO)
	var source := _pile("type_pile_1")
	source.accessor.request_open_viewer()
	await process_frame
	var viewer := source.accessor._viewer
	await game.server_clear_table()
	await process_frame
	_check(not is_instance_valid(viewer), "clear removes old viewer")
	_verify_board(false)
	_check(game.card_db.is_front(101) and game.card_db.is_upright(101), "clear resets imported orientation")
	_check(is_instance_valid(counter) and counter.position == Vector3.ZERO, "central counter preserved without avoidance")
	await game.deck_change.server_change(SECOND_DECK)
	await process_frame
	_verify_board(true)
	_check(is_instance_valid(counter), "change keeps counter")
	print("PARSER_OK")

func _host() -> void:
	await game.deck_change.server_change(FileAccess.get_file_as_string(TYPE_FIXTURE))
	await process_frame
	_verify_board(false)
	game.add_counter(Vector3.ZERO)
	game.server_add_pile()
	print("HOST_READY")
	while not game.card_db.deck_instance.card_ID_to_card_name.has(901) or game.clear_table_in_progress:
		await process_frame
	_verify_board(true)
	_check(game.counters.get_child_count() == 1 and _pile("extra_pile_1") == null, "change removes hand-made pile and preserves counter")
	while not game.card_db.is_front(901) or game.clear_table_in_progress:
		await process_frame
	_verify_board(true, true)
	while game.player_names.size() > 1:
		await process_frame
	print("HOST_PHASE_OK")
	while game.player_names.size() < 2:
		await process_frame
	while game.player_names.size() > 1:
		await process_frame
	print("HOST_OK")

func _client() -> void:
	await _await_board(false)
	_verify_board(false)
	var source := _pile("type_pile_1")
	source.accessor.request_open_viewer()
	while not source.accessor.i_am_viewing():
		await process_frame
	var viewer := source.accessor._viewer
	game.deck_change.server_change.rpc_id(1, SECOND_DECK)
	await _await_board(true)
	_verify_board(true)
	_check(not is_instance_valid(viewer), "change releases client viewer")
	_check(game.counters.get_child_count() == 1, "client counter preserved")
	await create_timer(0.4).timeout
	game.server_clear_table.rpc_id(1)
	await _await_board(true, true)
	_verify_board(true, true)
	print("CLIENT_OK")

func _late_join() -> void:
	await _await_board(true, true)
	_verify_board(true, true)
	_check(game.counters.get_child_count() == 1, "late join counter preserved")
	print("LATE_JOIN_OK")
