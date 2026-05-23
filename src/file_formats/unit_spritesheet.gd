class_name UnitSpritesheetData
extends Resource

@export var unique_name: String = ""
@export var shp_name: String = ""
@export var seq_name: String = ""
@export var is_flying: bool = false
@export var graphic_height: int = 0
@export var color_palette: PackedColorArray = []

func _init(spr: Spr = null) -> void:
	if spr == null:
		return
	
	unique_name = spr.file_name.get_basename()
	shp_name = spr.shp_name
	seq_name = spr.seq_name
	is_flying = spr.flying_flag != 0
	graphic_height = spr.graphic_height
	color_palette = spr.color_palette
