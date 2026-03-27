class_name Hotspot
extends Area3D

@onready var mesh  := $MeshInstance3D
@onready var label := $Label3D

@export var label_name := "底"
@export var drop_mode  := Pile.CardSource.BOTTOM

var parent_pile : Pile
var material    : StandardMaterial3D

const normal_color   = Color(1, 1, 1, 1)
const hover_color    = Color(1, 1, 0, 1)
const tween_duration = 0.15

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	label.text = label_name
	if not parent_pile:
		var p := get_parent()
		if p is Pile:
			parent_pile = p
			
	if mesh.get_active_material(0):
		material = mesh.get_active_material(0).duplicate()
		mesh.set_surface_override_material(0, material)
	
	_update_visual_color(normal_color)
	
func _on_mouse_entered():
	animate(hover_color, Vector3(1.1, 1.1, 1.1))

func _on_mouse_exited():
	animate(normal_color, Vector3(1.0, 1.0, 1.0))
	
# 使用 Tween 实现平滑渐变
func animate(target_color: Color, target_scale: Vector3):
	var tween := create_tween()
	tween.set_parallel(true) # 让网格和文字同时变色
	tween.tween_property(material, "albedo_color", target_color, tween_duration)
	tween.tween_property(label, "modulate", target_color, tween_duration)
	tween.tween_property(mesh, "scale", target_scale, tween_duration)

# 初始状态直接设置
func _update_visual_color(color: Color):
	material.albedo_color = color
	label.modulate = color
