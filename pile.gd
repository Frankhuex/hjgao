class_name Pile
extends StaticBody3D

@onready var _mesh: CSGBox3D   = $CSGBox3D
@onready var _label: Label3D   = $Label3D
@onready var _collision: CollisionShape3D = $CollisionShape3D 

@onready var _owner_mux: OwnerMux = $OwnerMux
@onready var _dragger: Dragger = $Dragger
@onready var _accessor: PileAccessor  = $Accessor
@onready var _spawner: PileCardSpawner = $CardSpawner

const DRAGGING_Y        = 0.0
const UP_DOWN_DURATION  = 0.0
const HEIGHT_ABOVE_PILE = 0.02
const CARD_THICKNESS    = 0.01
const SMALL_LENGTH      = 0.001
const BASE_THICKNESS    = 0.05

var card_ID_stack: Array[int] = []

func preready(_card_ID_stack: Array[int]):
	card_ID_stack = _card_ID_stack

func _ready():
	_dragger.config(_owner_mux, DRAGGING_Y, UP_DOWN_DURATION)
	_accessor.config(_owner_mux)
	_spawner.config(_owner_mux)

func _on_base_area_input_event(camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if Util.is_left_mouse_down(event):
		if _dragger.request_drag():
			get_viewport().set_input_as_handled() 

func _input(event: InputEvent):
	if Util.is_left_mouse_down(event):
		if _dragger.request_drop():
			get_viewport().set_input_as_handled() 

func _input_event(_camera, event: InputEvent, _position, _normal, _shape_idx):
	if Util.is_left_mouse_down(event):
		if _spawner.request_spawn_card(Const.CardSource.TOP):
			get_viewport().set_input_as_handled() 
	elif Util.is_right_mouse_down(event):
		if _accessor.request_open_viewer():
			get_viewport().set_input_as_handled() 

func _process(_delta):
	_dragger.process_drag()

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
		
