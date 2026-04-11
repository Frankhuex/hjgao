class_name Card
extends StaticBody3D

@onready var _card_db: CardDatabase   = get_node("/root/Game/CardDatabase")
@onready var _card_sorter: CardSorter = get_node("/root/Game/CardSorter")
@onready var _label: Label3D      = $Pivot/Label3D
@onready var _pivot: Node3D       = $Pivot
@onready var _dragger: Dragger    = $Dragger
@onready var _owner_mux: OwnerMux = $OwnerMux

const DRAGGING_Y       = 0.5
const UP_DOWN_DURATION = 0.1

# Preready Setup
var _preready_global_position: Vector3
var _preready_global_rot_y: float

func preready(id: int, _global_position: Vector3, _global_rot_y: float):
	name = str(id)
	_preready_global_position = _global_position
	_preready_global_rot_y    = _global_rot_y

func _ready():
	global_position   = _preready_global_position
	global_rotation.y = _preready_global_rot_y
	_label.text = name
	var is_front := _card_db.is_front(card_ID())
	_pivot.rotation_degrees.x = 0 if is_front else 180
	
	_dragger.config(_owner_mux, DRAGGING_Y, UP_DOWN_DURATION)
	_owner_mux.on_owner_change.connect(_server_card_sorter_action)
	_card_db.on_flip.connect(check_and_flip)
	
# Inputs
func _input_event(_camera, event: InputEvent, _position, _normal, _shape_idx):
	if Util.is_left_mouse_down(event):
		if _dragger.request_drag():
			get_viewport().set_input_as_handled() 

func _input(event: InputEvent):
	if Util.is_left_mouse_down(event):
		if _dragger.request_drop():
			get_viewport().set_input_as_handled() 
	elif Util.is_right_mouse_down(event):
		request_flip()
		get_viewport().set_input_as_handled() 

func _process(_delta):
	_dragger.process_drag()
	
# CardSorter
func _server_card_sorter_action(purpose: Const.Purpose):
	if Util.not_server(self): return
	if _owner_mux.is_owned():
		_card_sorter.server_unregister_card(card_ID())
	else:
		_card_sorter.server_register_card(card_ID())
	
# Flipping
func request_flip():
	_card_db.request_flip(card_ID())

const FLIP_DURATION = 0.3
func check_and_flip(id: int, is_front: bool):
	if id != card_ID(): return
	var target_rot_x := 0 if is_front else 180
	Util.tween_rot_x(self, target_rot_x, FLIP_DURATION)

# Util
func card_ID() -> int:
	return int(name)
