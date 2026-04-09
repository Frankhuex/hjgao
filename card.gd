class_name Card
extends StaticBody3D

@onready var card_db: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var card_sorter: CardSorter = get_node("/root/Game/CardSorter")
@onready var camera := get_viewport().get_camera_3d()
@onready var label  := $Pivot/Label3D
@onready var pivot  := $Pivot

# Setup
func preready(_name: String):
	name = _name

func _ready():
	on_dragger_change.connect(check_and_float_up)
	card_db.on_flip.emit(check_and_flip)

# Inputs
func _input_event(camera, event, position, normal, shape_idx):
	if Util.is_left_mouse_down(event):
		if dragger == 0:
			request_drag()
		elif dragger == multiplayer.get_unique_id():
			request_release()

# Util
func card_ID():
	return int(name)

# Dragging
var dragger := 0 #必须保留dragger变量，因为authority没有0
signal on_dragger_change

func request_drag():
	server_set_dragger.rpc_id(1)

func request_release():
	server_reset_dragger.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func server_set_dragger():
	if Util.not_server(self): return
	if dragger != 0:                return
	set_dragger.rpc(Util.sender_id(self))

@rpc("any_peer", "call_remote", "reliable")
func server_reset_dragger():
	if Util.not_server(self): return
	if dragger == 0:                return
	set_dragger.rpc(0)
	
@rpc("any_peer", "call_local", "reliable")
func set_dragger(new_dragger: int):
	dragger = new_dragger
	if new_dragger == 0:
		set_multiplayer_authority(1)
		check_and_drop_down()
	else:
		set_multiplayer_authority(new_dragger)
	on_dragger_change.emit()

func i_am_dragger():
	return dragger == Util.my_id(self)

const DRAGGING_Y       = 0.5
const UP_DOWN_DURATION = 0.1
func check_and_float_up(): #玩家接到拖牌权后调用
	if i_am_dragger():
		Util.tween_y(self, DRAGGING_Y, UP_DOWN_DURATION)
	
func check_and_drop_down(): #只有服务器能调用，无须rpc
	if dragger == 0 and multiplayer.is_server():
		Util.tween_y(self, 0, UP_DOWN_DURATION)

# Flipping
func request_flip():
	card_db.request_flip(card_ID())

const FLIP_DURATION = 0.3
func check_and_flip(id: int, is_front: bool):
	if id != card_ID(): return
	var target_rot_x := 0 if is_front else 180
	Util.tween_rot_x(self, target_rot_x, FLIP_DURATION)

			
