class_name Player
extends CharacterBody3D

#@onready var camera = $CameraPivot/Camera3D
@onready var pivot: Node3D = $CameraPivot
@onready var mesh: MeshInstance3D = $MeshInstance3D

enum PlayerStatus { MOVE = 0, CARD = 1 }
var player_status := PlayerStatus.CARD
const DEFAULT_CAMERA_POSITION = Vector3(0.0, 5.312, 1.979)
const DEFAULT_CAMERA_ROTATION_DEGREES = Vector3(-77.6, 0.0, 0.0)

func _enter_tree():
	set_multiplayer_authority(name.to_int())
	
func _ready():
	set_random_pos()
	if is_multiplayer_authority(): 
		var main_camera := get_viewport().get_camera_3d()
		main_camera.reparent(pivot)
		main_camera.position = Vector3.ZERO #相对于pivot

func set_random_pos():
	var center := Vector3(0, 5.669, 0)
	var radius := 2.5
	
	# 1. 在 0 到 360 度（2π 弧度）之间随机选一个角度
	# TAU 是 Godot 内置常量，等价于 2 * PI
	var angle := randf_range(0.0, TAU)
	
	# 2. 利用三角函数计算出 XZ 平面上的圆周偏移量
	var offset_x := cos(angle) * radius
	var offset_z := sin(angle) * radius
	
	global_position = center + Vector3(offset_x, 0, offset_z)
	

#func set_random_color():
	#mesh.get_active_material(0).albedo_color = Color(randf(), randf(), randf())

func toggle_status():
	if player_status == PlayerStatus.CARD:
		player_status = PlayerStatus.MOVE
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		player_status = PlayerStatus.CARD
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event):
	if not is_multiplayer_authority(): return
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE:
			toggle_status()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent):
	if not is_multiplayer_authority(): 
		return
	
	if player_status == PlayerStatus.MOVE and event is InputEventMouseMotion:
		var event_mouse_motion: InputEventMouseMotion = event
		rotate_y(-event_mouse_motion.relative.x * 0.002)
		pivot.rotate_x(-event_mouse_motion.relative.y * 0.002)
		pivot.rotation.x = clamp(pivot.rotation.x, -1.5, 1.5) #弧度制

func _physics_process(_delta):
	if not is_multiplayer_authority(): 
		return
	
	if player_status == PlayerStatus.CARD:
		velocity = Vector3.ZERO
		return
	
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * 5.0
		velocity.z = direction.z * 5.0
	else:
		velocity.x = move_toward(velocity.x, 0, 5.0)
		velocity.z = move_toward(velocity.z, 0, 5.0)

	move_and_slide()
