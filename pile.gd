class_name Pile
extends StaticBody3D

@onready var mesh      := $CSGBox3D
@onready var collision := $CollisionShape3D 
@onready var label     := $Label3D
@onready var card_sorter: CardSorter = get_node("/root/Game/CardSorter")
@onready var card_database: CardDatabase = get_node("/root/Game/CardDatabase")
@onready var dragger: Dragger = $Dragger

const DECK_VIEWER = preload("res://DeckViewerUI.tscn")
const DRAGGING_Y       = 0.0
const UP_DOWN_DURATION = 0.0

func _ready():
	dragger.config(DRAGGING_Y, UP_DOWN_DURATION)

func _on_base_area_input_event(camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if Util.is_left_mouse_down(event):
		dragger.request_drag_or_release()
		get_viewport().set_input_as_handled() 

func _process(_delta):
	dragger.process_drag()
	
