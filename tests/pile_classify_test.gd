extends "res://tests/pile_lifecycle_test.gd"

const SOURCE := "classification_source"
const MIXED_IDS: Array[int] = [701, 9, 601, 303, 501, 401, 402, 205, 101]
const SELECTED_IDS: Array[int] = [701, 9, 303, 401, 205]
const REMAINING_IDS: Array[int] = [601, 501, 402, 101]

func _make_source(pos: Vector3) -> Pile:
	game._clear_board_nodes()
	while game._board_objects_are_pending_deletion():
		await process_frame
	return game.add_pile(MIXED_IDS.duplicate(), SOURCE, pos, "混合源堆")

func _move_selected(viewer: DeckViewerUI, ids: Array[int]) -> void:
	for id: int in ids:
		for card: UICard in viewer.list_top.get_children():
			if card.card_ID() == id:
				card.reparent(viewer.list_bottom)
				break
	viewer._refresh_draw_button()

func _verify_partial(source: Pile, left: bool = false) -> void:
	var expected_stacks: Array[Array] = [[303, 9], [205], [401], [701]]
	var expected_names: Array[String] = ["X", "Y", "未分类", "W"]
	var direction := 1.0 if left else -1.0
	for i in range(4):
		var target := _pile("extra_pile_%d" % (i + 1))
		_check(target != null and target.card_ID_stack == expected_stacks[i], "selected subset grouped and sorted")
		_check(target.display_name == expected_names[i], "classification initial name")
		_check(target.position.distance_to(source.position + Vector3(direction * (1.12 + 1.5 * i), 0, 0)) < 0.001, "aligned sequential side positions")
		_check(absf(target.rotation.y - source.rotation.y) < 0.001, "orientation inherited")
	_check(source.card_ID_stack == REMAINING_IDS and source.display_name == "混合源堆", "source order and name retained")
	_check(not source.owner_mux.is_owned() and game.card_sorter.get_child_count() == 0, "last release and no loose cards")
	_check(_pile("extra_pile_5") == null, "unselected types do not create empty piles")
	_check(game.card_db.is_front(303) and not game.card_db.is_upright(303), "selected orientation preserved")

func _local_tests() -> void:
	await game.deck_change.server_change(FileAccess.get_file_as_string("res://tests/fixtures/card_types.json"))
	var source := await _make_source(Vector3(-3, 0, 1))
	source.rotation.y = 0.73
	game.card_db.deck_instance.card_ID_to_is_front[303] = true
	game.card_db.deck_instance.card_ID_to_is_upright[303] = false
	source.accessor.request_open_viewer()
	await process_frame
	var viewer := source.accessor._viewer
	_check(not viewer.btn_classify_to_piles.visible, "empty pending hides classify button")
	_move_selected(viewer, SELECTED_IDS)
	_check(viewer.btn_classify_to_piles.visible, "pending shows classify button")
	var wrong: Array[int] = [701, 9, 303, 401, 402]
	source.accessor.server_classify_to_new_piles(REMAINING_IDS, wrong, 1)
	_check(_pile("extra_pile_1") == null and source.card_ID_stack == MIXED_IDS, "duplicate and missing partition rejected")
	game.clear_table_in_progress = true
	source.accessor.server_classify_to_new_piles(REMAINING_IDS, SELECTED_IDS, 2)
	_check(_pile("extra_pile_1") == null, "global lock rejects classification")
	game.clear_table_in_progress = false
	source.card_ID_stack = REMAINING_IDS.duplicate()
	viewer.btn_classify_to_piles.pressed.emit()
	_check(not viewer._submission_pending and viewer.list_bottom.get_child_count() == 5 and viewer.submission_status.visible, "failure keeps draft and unblocks UI")
	source.card_ID_stack = MIXED_IDS.duplicate()
	viewer.btn_classify_to_piles.pressed.emit()
	await process_frame
	_verify_partial(source, true)
	_check(not is_instance_valid(viewer), "success closes viewer")
	source.accessor.server_classify_to_new_piles(REMAINING_IDS, SELECTED_IDS, 3)
	_check(_pile("extra_pile_5") == null, "duplicate request after release rejected")
	source = await _make_source(Vector3(3, 0, 1))
	source.rotation.y = 1.1
	source.accessor.request_open_viewer()
	await process_frame
	viewer = source.accessor._viewer
	_move_selected(viewer, MIXED_IDS)
	viewer.btn_classify_to_piles.pressed.emit()
	await process_frame
	_check(source.card_ID_stack.is_empty() and is_instance_valid(source), "full classification keeps empty source")
	var types: Array[String] = ["X", "Y", "", "Z", "untyped", "W"]
	var groups := game.card_db.get_ordered_card_IDs_by_type()
	for i in range(6):
		var target := _pile("extra_pile_%d" % (i + 5))
		_check(target.card_ID_stack == groups[types[i]], "full classification stacks")
		_check(target.position.distance_to(Vector3(1.88 - 1.5 * i, 0, 1)) < 0.001, "right side continues past table")
	_check(_pile("extra_pile_10").position.x < -5.0, "out-of-bounds placement allowed")
	print("PARSER_OK")

func _host() -> void:
	await game.deck_change.server_change(FileAccess.get_file_as_string("res://tests/fixtures/card_types.json"))
	var source := await _make_source(Vector3(3, 0, 1))
	source.rotation.y = 1.1
	game.card_db.deck_instance.card_ID_to_is_front[303] = true
	game.card_db.deck_instance.card_ID_to_is_upright[303] = false
	print("HOST_READY")
	while _pile("extra_pile_4") == null:
		await process_frame
	_verify_partial(source)
	while game.player_names.size() > 1:
		await process_frame
	print("HOST_PHASE_OK")
	while game.player_names.size() < 2:
		await process_frame
	while game.player_names.size() > 1:
		await process_frame
	print("HOST_OK")

func _await_partial() -> void:
	while true:
		var ready := _pile(SOURCE) != null and _pile(SOURCE).card_ID_stack == REMAINING_IDS
		for i in range(4):
			var target := _pile("extra_pile_%d" % (i + 1))
			if target == null or target.card_ID_stack.is_empty() or target.display_name.is_empty():
				ready = false
		if ready:
			return
		await process_frame

func _client() -> void:
	while _pile(SOURCE) == null or _pile(SOURCE).card_ID_stack.is_empty():
		await process_frame
	var source := _pile(SOURCE)
	source.accessor.request_classify_to_new_piles(REMAINING_IDS, SELECTED_IDS, 4)
	await create_timer(0.2).timeout
	_check(_pile("extra_pile_1") == null, "nonowner request rejected")
	source.accessor.request_open_viewer()
	while not source.accessor.i_am_viewing():
		await process_frame
	var viewer := source.accessor._viewer
	_move_selected(viewer, SELECTED_IDS)
	viewer.btn_classify_to_piles.pressed.emit()
	await _await_partial()
	while is_instance_valid(viewer) or source.owner_mux.is_owned():
		await process_frame
	_verify_partial(source)
	print("CLIENT_OK")

func _late_join() -> void:
	await _await_partial()
	_verify_partial(_pile(SOURCE))
	print("LATE_JOIN_OK")
