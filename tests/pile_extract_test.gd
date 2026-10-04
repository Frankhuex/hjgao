extends "res://tests/pile_lifecycle_test.gd"

func _local_tests() -> void:
	var source := _pile("公共牌堆")
	var original: Array[int] = source.card_ID_stack.duplicate()
	source.position = Vector3(-3, 0, 1)
	source.rotation.y = 0.73
	source.accessor.request_open_viewer()
	await process_frame
	var viewer := source.accessor._viewer
	_check(not viewer.btn_draw_to_pile.visible, "empty pending hides new-pile button")
	var first := viewer.list_top.get_child(0) as UICard
	first.reparent(viewer.list_bottom)
	viewer._refresh_draw_button()
	_check(viewer.btn_draw_to_pile.visible, "pending shows new-pile button")
	var remaining: Array[int] = original.duplicate()
	remaining.pop_front()
	var extracted: Array[int] = [original[0]]
	var duplicate: Array[int] = [original[1]]
	var count := game.piles.get_child_count()
	source.accessor.server_extract_to_new_pile(remaining, duplicate, 1)
	_check(game.piles.get_child_count() == count and source.card_ID_stack == original, "duplicate partition rejected")
	game.clear_table_in_progress = true
	source.accessor.server_extract_to_new_pile(remaining, extracted, 2)
	_check(source.card_ID_stack == original, "global lock rejects transfer")
	game.clear_table_in_progress = false
	source.receiver.server_receive_card(original[0], Const.CardSource.TOP)
	_check(source.card_ID_stack == original and source.owner_mux.purpose == Const.Purpose.PILE_VIEW, "receiver respects viewer lock")
	source.card_ID_stack = remaining.duplicate()
	viewer.btn_draw_to_pile.pressed.emit()
	_check(not viewer._submission_pending and not viewer.submission_blocker.visible and viewer.submission_status.visible, "rejected submission restores UI and reports reason")
	_check(viewer.list_bottom.get_child_count() == 1 and game.piles.get_child_count() == count, "rejection preserves draft and creates nothing")
	source.card_ID_stack = original.duplicate()
	game.card_db.deck_instance.card_ID_to_is_front[original[0]] = false
	game.card_db.deck_instance.card_ID_to_is_upright[original[0]] = false
	source.name_editor.request_apply_name("源牌堆", 1)
	viewer.btn_draw_to_pile.pressed.emit()
	await process_frame
	var target := _pile("extra_pile_1")
	_check(target != null and target.card_ID_stack == extracted, "partial transfer target")
	_check(source.card_ID_stack == remaining and not source.owner_mux.is_owned(), "source commit and release")
	_check(not is_instance_valid(viewer), "success closes viewer")
	_check(target.position.distance_to(Vector3(-1.88, 0, 1)) < 0.001 and absf(target.rotation.y - 0.73) < 0.001, "left position and inherited rotation")
	_check(target.display_name.is_empty() and source.display_name == "源牌堆" and game.card_sorter.get_child_count() == 0, "source name retained, target empty name and no loose cards")
	_check(not game.card_db.is_front(original[0]) and not game.card_db.is_upright(original[0]), "face and orientation preserved")
	source.accessor.server_extract_to_new_pile(remaining, extracted, 3)
	_check(_pile("extra_pile_2") == null, "repeated request after release rejected")
	source.position.x = 3
	source.accessor.request_open_viewer()
	await process_frame
	viewer = source.accessor._viewer
	for card: Node in viewer.list_top.get_children():
		card.reparent(viewer.list_bottom)
	viewer._on_draw_to_pile_pressed()
	await process_frame
	_check(source.card_ID_stack.is_empty() and is_instance_valid(source), "full transfer keeps empty source")
	_check(_pile("extra_pile_2").card_ID_stack == remaining and absf(_pile("extra_pile_2").position.x - 1.88) < 0.001, "right position and full order")
	print("PARSER_OK")

func _host() -> void:
	var source := _pile("公共牌堆")
	source.position = Vector3(3, 0, 1)
	source.rotation.y = 1.1
	var original: Array[int] = source.card_ID_stack.duplicate()
	print("HOST_READY")
	while _pile("extra_pile_1") == null:
		await process_frame
	var target := _pile("extra_pile_1")
	_check(target.card_ID_stack == [original[0], original[1]], "server receives ordered client extraction")
	_check(source.card_ID_stack.size() == original.size() - 2 and game.card_sorter.get_child_count() == 0, "server cards conserved")
	_check(not source.owner_mux.is_owned(), "server released source")
	while game.player_names.size() > 1:
		await process_frame
	print("HOST_PHASE_OK")
	while game.player_names.size() < 2:
		await process_frame
	while game.player_names.size() > 1:
		await process_frame
	print("HOST_OK")

func _client() -> void:
	var source := _pile("公共牌堆")
	while source == null or source.card_ID_stack.is_empty():
		await process_frame
		source = _pile("公共牌堆")
	var original: Array[int] = source.card_ID_stack.duplicate()
	var remaining: Array[int] = original.duplicate()
	remaining.pop_front()
	remaining.pop_front()
	var extracted: Array[int] = [original[0], original[1]]
	source.accessor.request_extract_to_new_pile(remaining, extracted, 10)
	await create_timer(0.2).timeout
	_check(_pile("extra_pile_1") == null, "client nonowner rejected")
	source.accessor.request_open_viewer()
	while not source.accessor.i_am_viewing():
		await process_frame
	var viewer := source.accessor._viewer
	for i in range(2):
		viewer.list_top.get_child(0).reparent(viewer.list_bottom)
	viewer._on_draw_to_pile_pressed()
	while is_instance_valid(viewer) or _pile("extra_pile_1") == null or _pile("extra_pile_1").card_ID_stack.is_empty():
		await process_frame
	await create_timer(0.2).timeout
	_check(_pile("extra_pile_1").card_ID_stack == extracted and source.card_ID_stack == remaining, "client arrays match")
	_check(_pile("extra_pile_1").position.distance_to(Vector3(1.88, 0, 1)) < 0.001 and absf(_pile("extra_pile_1").rotation.y - 1.1) < 0.001, "client spawn position and rotation")
	print("CLIENT_OK")

func _late_join() -> void:
	while _pile("extra_pile_1") == null or _pile("extra_pile_1").card_ID_stack.is_empty():
		await process_frame
	await create_timer(0.2).timeout
	var target := _pile("extra_pile_1")
	_check(target.card_ID_stack.size() == 2 and target.display_name.is_empty(), "late join nonempty stack and empty name")
	_check(target.position.distance_to(Vector3(1.88, 0, 1)) < 0.001 and absf(target.rotation.y - 1.1) < 0.001, "late join inherited rotation")
	_check(_pile("公共牌堆").card_ID_stack.size() + target.card_ID_stack.size() == game.card_db.get_all_IDs().size(), "late join conservation")
	print("LATE_JOIN_OK")
