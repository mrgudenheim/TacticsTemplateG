class_name SubFrameData
extends Resource

const SUBFRAME_LENGTH:int = 4 # bytes
@export var shift_x: int = 0
@export var shift_y: int = 0
@export var load_location_x: int = 0 # 8px tiles
@export var load_location_y: int = 0 # 8px tiles
@export var rect_size: Vector2i = Vector2i.ONE # in 8px tiles
@export var flip_x: bool = false
@export var flip_y: bool = false

func _to_string() -> String:
	var values: PackedStringArray = [
		shift_x,
		shift_y,
		load_location_x,
		load_location_y,
		rect_size,
		flip_x,
		flip_y,
		]
	
	return ", ".join(values)
