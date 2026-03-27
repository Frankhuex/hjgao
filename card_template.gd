class_name CardTemplate
extends Resource

@export var name: String
@export var count: int
@export var description: String

func _init(name: String, count: int, description: String):
	self.name = name
	self.count = count
	self.description = description

func to_dict() -> Dictionary:
	return {
		"name": name,
		"count": count,
		"description": description
	}
