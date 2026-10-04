class_name Pile
extends StaticBody3D

@onready var _mesh: CSGBox3D   = $CSGBox3D
@onready var _label: Label3D   = $Label3D
@onready var _collision: CollisionShape3D = $CollisionShape3D 

@onready var owner_mux: OwnerMux = $OwnerMux
@onready var dragger: Dragger = $Dragger
@onready var accessor: PileAccessor  = $Accessor
@onready var spawner: PileCardSpawner = $CardSpawner
@onready var receiver: PileCardReceiver = $CardReceiver

const DRAGGING_Y        = 0.0
const UP_DOWN_DURATION  = 0.0
const HEIGHT_ABOVE_PILE = 0.02
const CARD_THICKNESS    = 0.01
const SMALL_LENGTH      = 0.001
const BASE_THICKNESS    = 0.05

var card_ID_stack: Array[int] = []
signal stack_changed

@onready var name_editor: NameEditor = $NameEditor
@onready var detail_viewer: DetailViewer = $DetailViewer
@onready var _name_label: Label3D = $NameLabel
var display_name: String:
	get:
		return name_editor.display_name if is_instance_valid(name_editor) else ""

func _refresh_name() -> void:
	_name_label.text = display_name
	_name_label.visible = not display_name.is_empty()
	detail_viewer.refresh()

func _detail_text() -> String:
	return "" if dragger.is_being_dragged() else display_name

func request_delete_pile() -> void:
	if Util.is_server(self):
		server_delete_pile()
	else:
		server_delete_pile.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_delete_pile() -> void:
	if Util.not_server(self) or Util.board_locked(self) or is_queued_for_deletion():
		return
	var game := get_node("/root/Game") as GameSession
	if not game.session_active or not card_ID_stack.is_empty():
		return
	var sender := Util.sender_id(self)
	if sender == 0:
		sender = 1
	if sender != 1 and not (owner_mux.get_owner_id() == sender and owner_mux.purpose == Const.Purpose.PILE_VIEW):
		return
	queue_free()

func preready(_name:String, _card_ID_stack: Array[int], initial_display_name: String = ""):
	name = _name
	card_ID_stack = _card_ID_stack
	(get_node("NameEditor") as NameEditor).initialize_name(initial_display_name)

func _ready():
	name_editor.configure(owner_mux, Const.Purpose.PILE_VIEW)
	name_editor.name_changed.connect(_refresh_name)
	detail_viewer.configure(self, _detail_text, [self, $BaseArea, $Hotspot_Bottom, $Hotspot_Random])
	_refresh_name()
	dragger.config(owner_mux, UP_DOWN_DURATION, DRAGGING_Y)
	accessor.config()
	spawner.config()
	_update_visuals()
	if Util.not_server(self):
		request_sync_card_ID_stack()

#新玩家请求同步牌堆
func request_sync_card_ID_stack():
	print("user: ", Util.my_id(self), " request_sync_card_ID_stack")
	server_sync_card_ID_stack.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_sync_card_ID_stack():
	if Util.not_server(self): return
	sync_card_ID_stack.rpc(card_ID_stack)

@rpc("any_peer", "call_local", "reliable")
func sync_card_ID_stack(_card_ID_stack: Array[int]):
	card_ID_stack = _card_ID_stack
	_update_visuals()
	stack_changed.emit()

# Inputs
func _on_base_area_input_event(camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if Util.is_left_mouse_down(event):
		if dragger.request_drag():
			get_viewport().set_input_as_handled() 

func _input(event: InputEvent):
	if Util.is_left_mouse_down(event):
		if dragger.request_drop():
			get_viewport().set_input_as_handled() 

func _input_event(_camera, event: InputEvent, _position, _normal, _shape_idx):
	if Util.is_left_mouse_down(event):
		if spawner.request_spawn_card(Const.CardSource.TOP):
			get_viewport().set_input_as_handled() 
	elif Util.is_right_mouse_down(event):
		if accessor.request_open_viewer():
			get_viewport().set_input_as_handled() 

func _on_hotspot_bottom_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if Util.is_left_mouse_down(event):
		if spawner.request_spawn_card(Const.CardSource.BOTTOM):
			get_viewport().set_input_as_handled() 

func _on_hotspot_random_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	if Util.is_left_mouse_down(event):
		if spawner.request_spawn_card(Const.CardSource.RANDOM):
			get_viewport().set_input_as_handled() 

func _process(_delta):
	if multiplayer.multiplayer_peer == null or is_queued_for_deletion():
		return
	dragger.process_drag()

func release_local_interaction():
	if owner_mux.i_am_owner():
		dragger.suspend_local_interaction()
		owner_mux.request_release()

# Util
func get_y_when_over_pile() -> float:
	return BASE_THICKNESS + card_ID_stack.size() * CARD_THICKNESS + HEIGHT_ABOVE_PILE
	
func calc_spawn_pos(card_IDs: Array[int]) -> Dictionary[int, Vector3]:
	var is_on_left_side := global_position.x < 0
	var spawn_direction := 1.0 if is_on_left_side else -1.0
	var main_offset     := 1.0
	var spacing         := 0.12
	
	var card_ID_to_pos: Dictionary[int, Vector3] = {}
	for i in range(card_IDs.size()):
		var card_ID   := card_IDs[i]
		var offset_x  := spawn_direction * ((i + 1) * spacing + main_offset)
		card_ID_to_pos[card_ID] = self.global_position + Vector3(offset_x, Card.DRAGGING_Y, 0)
	return card_ID_to_pos

func _update_visuals():
	if not is_node_ready(): return
	var h := card_ID_stack.size() * CARD_THICKNESS
	_label.text = str(len(card_ID_stack))
	_label.position.y = h + SMALL_LENGTH + BASE_THICKNESS
	_name_label.position.y = h + BASE_THICKNESS + 0.015
	_mesh.size.y = max(h, SMALL_LENGTH)
	_mesh.position.y = h / 2.0 + BASE_THICKNESS
	_collision.shape = _collision.shape.duplicate() # 独立化资源
	(_collision.shape as BoxShape3D).size.y = max(h, SMALL_LENGTH)
	_collision.position.y = h / 2.0 + BASE_THICKNESS
