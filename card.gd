class_name Card
extends StaticBody3D

@onready var _card_db: CardDatabase   = get_node("/root/Game/CardDatabase")
@onready var _card_sorter: CardSorter = get_node("/root/Game/CardSorter")
@onready var _label: Label3D      = $Pivot/Label3D
@onready var _pivot: Node3D       = $Pivot
@onready var _dragger: Dragger    = $Dragger
@onready var _owner_mux: OwnerMux = $OwnerMux
@onready var _description_tooltip: CardDescriptionTooltip = get_node("/root/Game/CardDescriptionTooltip")

const DRAGGING_Y       = 0.5
const UP_DOWN_DURATION = 0.1

# Preready Setup
var _preready_global_position: Vector3
var _is_mouse_hovering := false
# var _preready_global_rot_y: float

func preready(id: int, _global_position: Vector3):
	name = str(id)
	_preready_global_position = _global_position
	#_preready_global_rot_y    = _global_rot_y

func _ready():
	global_position   = _preready_global_position
	#global_rotation.y = _preready_global_rot_y
	
	_label.text = _card_db.get_card_name(card_ID())
	var is_front := _card_db.is_front(card_ID())
	_pivot.rotation_degrees.x = get_rot_x_by_is_front(is_front)
	
	_dragger.config(_owner_mux, UP_DOWN_DURATION, DRAGGING_Y, func(): return _card_sorter.get_drop_y(), "card")
	_owner_mux.on_owner_change.connect(_server_card_sorter_action)
	_card_db.on_flip.connect(check_and_flip)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	SfxManager.I.play(SfxManager.Snd.SPAWN)   # R8：Card.tscn 全项目仅 spawner 实例化，_ready 即"从牌堆取出"，全端播放

func _exit_tree() -> void:
	if is_instance_valid(_description_tooltip):
		_description_tooltip.hide_for(self)
	var game: GameSession = get_node_or_null("/root/Game")
	if _dragger.is_being_dragged() and game != null and game.session_active \
			and not Util.board_locked(self):
		SfxManager.I.play(SfxManager.Snd.PILE_IN)   # R7：带着 DRAG 占用被回收 = 塞回牌堆，全端播放

func _on_mouse_entered() -> void:
	_is_mouse_hovering = true
	_refresh_description_tooltip()

func _on_mouse_exited() -> void:
	_is_mouse_hovering = false
	_description_tooltip.hide_for(self)

func _refresh_description_tooltip() -> void:
	if not _is_mouse_hovering:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE or not _card_db.is_front(card_ID()):
		_description_tooltip.hide_for(self)
		return
	_description_tooltip.show_for(self, card_ID())
	
# Inputs
func _input_event(_camera, event: InputEvent, _position, _normal, _shape_idx):
	if Util.is_left_mouse_down(event):
		if _dragger.request_drag():
			get_viewport().set_input_as_handled() 
	elif Util.is_right_mouse_down(event):
		request_flip()
		get_viewport().set_input_as_handled() 

var requested_check_into_pile := false
func _input(event: InputEvent):
	if Util.is_left_mouse_down(event):
		if not requested_check_into_pile:
			requested_check_into_pile = check_into_pile()
			if requested_check_into_pile:
				get_viewport().set_input_as_handled() 
				return
		if _dragger.request_drop():
			get_viewport().set_input_as_handled() 
	elif Util.is_right_mouse_down(event) and _dragger.i_am_dragging():
		print("flip by any input")
		request_flip()
		get_viewport().set_input_as_handled() 

func _process(_delta: float):
	_dragger.process_drag()
	process_float_upon_pile()

# CardSorter
func _server_card_sorter_action():
	if Util.not_server(self): return
	if _owner_mux.is_owned():
		_card_sorter.server_unregister_card(card_ID())
	else:
		_card_sorter.server_register_card(card_ID())
	
# Flipping
func request_flip():
	_card_db.request_flip(card_ID())

func release_local_interaction():
	if _owner_mux.i_am_owner():
		_dragger.suspend_local_interaction()
		_owner_mux.request_release()

const FLIP_DURATION = 0.3
func check_and_flip():
	var is_front := _card_db.is_front(card_ID())
	var target_rot_x := get_rot_x_by_is_front(is_front)
	if absf(_pivot.rotation_degrees.x - target_rot_x) > 1.0:  # 本牌状态真的变了（阈值容纳浮点/动画中间态）
		SfxManager.I.play(SfxManager.Snd.FLIP)   # R5-3D：与翻牌动画一致，全端播放
	Util.tween_rot_x(_pivot, target_rot_x, FLIP_DURATION)
	_refresh_description_tooltip()

# Util
func card_ID() -> int:
	return int(name)

func get_rot_x_by_is_front(is_front: bool) -> float:
	print("card: ",name ," is_front: ",is_front)
	return 0 if is_front else 180

# Pile detection
class PileSource:
	var pile: Pile
	var source: Const.CardSource
	func _init(_pile: Pile, _source: Const.CardSource):
		pile = _pile
		source = _source
	
func detect_pile_or_hotspot() -> PileSource:
	var camera      := get_viewport().get_camera_3d()
	var space_state := get_world_3d().direct_space_state
	var mouse_pos   := get_viewport().get_mouse_position()
	var ray_origin  := camera.project_ray_origin(mouse_pos)
	var ray_end     := ray_origin + camera.project_ray_normal(mouse_pos) * 100
	
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [get_rid()] # 排除自己，避免射线撞到正在拖拽的牌
	query.collide_with_areas = true # 开启区域检测
	
	var result := space_state.intersect_ray(query)
	if result:
		var hit_obj = result.collider
		if hit_obj is Pile:
			var pile: Pile = hit_obj
			return PileSource.new(pile, Const.CardSource.TOP)
		elif hit_obj is Hotspot:
			var hotspot: Hotspot = hit_obj
			var pile: Pile = hotspot.parent_pile
			return PileSource.new(pile, hotspot.drop_mode)
	return null

func process_float_upon_pile():
	if not _dragger.i_am_dragging(): return
	var pile_source := detect_pile_or_hotspot()
	if pile_source:
		if pile_source.source == Const.CardSource.TOP:
			Util.tween_y(self, pile_source.pile.get_y_when_over_pile(), UP_DOWN_DURATION)
			return
	Util.tween_y(self, DRAGGING_Y, UP_DOWN_DURATION)

func check_into_pile() -> bool:
	if not _dragger.i_am_dragging(): return false
	var pile_source := detect_pile_or_hotspot()
	if pile_source:
		return pile_source.pile.receiver.request_receive_card(card_ID(), pile_source.source)
	return false
