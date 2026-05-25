class_name InitialUnitData
extends Resource

@export var initial_unit_raw_stats: Array[Dictionary] = [] # idx is stat_basis Dictionary[String, Vector2i] [stat_type_name, (min_stat, max_stat)]
@export var initial_unit_equipment: Array[Dictionary] = [] # idx is stat_basis Dictionary[String, String] [slot_name, item_name]
