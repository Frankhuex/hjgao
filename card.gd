class_name Card
extends StaticBody3D

const DRAGGING_Y       = 0.5
const TAKE_UP_DURATION = 0.1
const FLIP_DURATION    = 0.3

var flip_tween : Tween
var card_name  : String
var card_sorter: CardSorter

var is_dragged_from_pile := false
var is_dragging  := false
var drag_offset  := Vector3.ZERO
var fixed_y      := 0.0 
var target_rot_x := 0.0

@onready var camera = get_viewport().get_camera_3d()
@onready var label  = $Label3D

func _ready():
	set_card_text("你居垦")
	if not card_sorter:
		var p = get_parent()
		while p != null and not (p is CardSorter):
			p = p.get_parent()
		if p is CardSorter:
			card_sorter = p
			if not is_dragged_from_pile:
				card_sorter.register_card(self)

func update_target_y(new_y: float):
	#if fixed_y == new_y:
		#return 
	#fixed_y = new_y
	var t = create_tween()
	# 可选：加上 ease_out 会让动画在快到位时更平滑
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "global_position:y", new_y, TAKE_UP_DURATION)
	
func _input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			input_ray_pickable = false
			fixed_y = DRAGGING_Y
			update_target_y(DRAGGING_Y)
			is_dragging = true
			var intersection = get_mouse_position_on_plane()
			if intersection != null:
				drag_offset = global_position - intersection
			get_viewport().set_input_as_handled() 
				
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			flip_box()
			get_viewport().set_input_as_handled()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_dragging:
				var hovered_pile := get_hovered_pile()
				if hovered_pile: # 这个空指针判断要留下
					# 通知牌堆接管这张牌
					hovered_pile.insert_card_to_viewer(self)
				else:
					flip_box()
				get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_dragging:
				is_dragging = false
				input_ray_pickable = true 
				if is_dragged_from_pile:
					is_dragged_from_pile = false
					card_sorter.register_card(self)
				card_sorter.bring_to_front(self)
				check_for_pile_drop()

func _process(_delta):
	if is_dragging:
		check_for_pile_drop()
		var intersection = get_mouse_position_on_plane()
		if intersection != null:
			var target_pos = intersection + drag_offset
			global_position.x = target_pos.x
			global_position.z = target_pos.z

func get_hovered_pile() -> Pile:
	if not camera: return null
	var space_state := get_world_3d().direct_space_state
	var mouse_pos   := get_viewport().get_mouse_position()
	var ray_origin  := camera.project_ray_origin(mouse_pos)
	var ray_end     := ray_origin + camera.project_ray_normal(mouse_pos) * 100
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	
	var result := space_state.intersect_ray(query)
	if result and result.collider is Pile:
		return result.collider as Pile
	return null

# 【新增】：回收检测逻辑
func check_for_pile_drop():
	if not camera: return
	
	# 射线检测鼠标下方的物体
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
		# 如果撞到了牌堆（通过脚本类型或组判断）
		
		if hit_obj is Pile:
			var pile_obj: Pile = hit_obj
			if is_dragging:
				update_target_y(pile_obj.get_y_when_over_pile())
			else:
				pile_obj.receive_card(card_name, Pile.CardSource.TOP)
				queue_free() # 销毁卡牌
				card_sorter.unregister_card(self)
			return
		elif hit_obj is Hotspot:
			var hotspot_obj: Hotspot = hit_obj
			var target_pile := hotspot_obj.parent_pile
			if not is_dragging:
				target_pile.receive_card(card_name, hotspot_obj.drop_mode)
				queue_free() # 销毁卡牌
				card_sorter.unregister_card(self)
			# 不要return
			
	if is_dragging:
		update_target_y(DRAGGING_Y)
	return

func get_mouse_position_on_plane() -> Variant:
	if not camera: return null
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_normal := camera.project_ray_normal(mouse_pos)
	var plane := Plane(Vector3.UP, fixed_y)
	return plane.intersects_ray(ray_origin, ray_normal)

func flip_box():
	var is_animating := flip_tween and flip_tween.is_valid()
	if not is_animating:
		target_rot_x = rotation_degrees.x
	target_rot_x += 180.0
	if is_animating:
		flip_tween.kill()
	flip_tween = create_tween()
	flip_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(self, "rotation_degrees:x", target_rot_x, FLIP_DURATION)

func set_card_text(new_text: String):
	card_name = new_text
	label.text = new_text
