class_name Player
extends CharacterBody3D

signal status_changed

#@onready var camera = $CameraPivot/Camera3D
@onready var pivot: Node3D = $CameraPivot
@onready var mesh: MeshInstance3D = $MeshInstance3D

enum PlayerStatus { MOVE = 0, CARD = 1 }
var player_status := PlayerStatus.CARD
var input_enabled := true
var display_name := ""
const DEFAULT_CAMERA_POSITION = Vector3(0.0, 5.312, 1.979)
const DEFAULT_CAMERA_ROTATION_DEGREES = Vector3(-77.6, 0.0, 0.0)

func _enter_tree():
	set_multiplayer_authority(name.to_int())
	
func preready(camera_transform: Transform3D, side: int) -> void:
	# 以主菜单视角为基准，绕桌面中心转到四边之一；服务器在入树前选定。
	var yaw: float = side * PI / 2.0
	position = camera_transform.origin.rotated(Vector3.UP, yaw)
	# 水平正对桌面中心，固定俯角由主菜单高度和水平距离确定。
	rotation = Vector3(0.0, atan2(position.x, position.z), 0.0)
	var camera_pivot: Node3D = get_node("CameraPivot") as Node3D
	var horizontal_distance: float = Vector2(position.x, position.z).length()
	camera_pivot.rotation = Vector3(-atan2(position.y, horizontal_distance), 0.0, 0.0)

func _ready():
	if is_multiplayer_authority():
		var main_camera: Camera3D = get_viewport().get_camera_3d()
		var camera_scale: Vector3 = main_camera.scale
		main_camera.reparent(pivot)
		# 朝向由玩家和 pivot 承担，保留原摄像机缩放，避免重复叠加旋转。
		main_camera.transform = Transform3D(Basis.from_scale(camera_scale), Vector3.ZERO)

#func set_random_color():
	#mesh.get_active_material(0).albedo_color = Color(randf(), randf(), randf())

func toggle_status():
	if not input_enabled:
		return
	if player_status == PlayerStatus.CARD:
		player_status = PlayerStatus.MOVE
	else:
		player_status = PlayerStatus.CARD
	apply_mouse_mode()
	status_changed.emit()

func set_input_enabled(enabled: bool):
	input_enabled = enabled
	if not input_enabled:
		velocity = Vector3.ZERO

func apply_mouse_mode():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if player_status == PlayerStatus.MOVE else Input.MOUSE_MODE_VISIBLE)

func is_card_mode() -> bool:
	return player_status == PlayerStatus.CARD

func _is_chat_panel_open() -> bool:
	var game := get_node_or_null("/root/Game") as GameSession
	return game != null and game.chat_ui.is_open()

func _input(event):
	if not is_multiplayer_authority(): return
	if not input_enabled: return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			toggle_status()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent):
	if not is_multiplayer_authority(): 
		return
	if not input_enabled:
		return
	
	if player_status == PlayerStatus.MOVE and event is InputEventMouseMotion:
		var event_mouse_motion: InputEventMouseMotion = event
		rotate_y(-event_mouse_motion.relative.x * 0.002)
		# 先限制俯仰角再赋值，避免越过竖直方向后欧拉角转换产生翻转。
		pivot.rotation.x = clampf(pivot.rotation.x - event_mouse_motion.relative.y * 0.002, -PI / 2.0, PI / 2.0)

func _physics_process(_delta):
	if not is_multiplayer_authority(): 
		return
	if not input_enabled:
		velocity = Vector3.ZERO
		return
	
	if player_status == PlayerStatus.CARD or _is_chat_panel_open():
		velocity = Vector3.ZERO
		return
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * 5.0
		velocity.z = direction.z * 5.0
	else:
		velocity.x = move_toward(velocity.x, 0, 5.0)
		velocity.z = move_toward(velocity.z, 0, 5.0)

	move_and_slide()
