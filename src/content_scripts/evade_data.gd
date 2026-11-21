class_name EvadeData
extends Resource

@export var value: int = 0
@export var source: EvadeSource
@export var type: EvadeType = EvadeType.PHYSICAL
@export var directions: Array[Directions] = [Directions.FRONT]
var animation_id: int = -1:
	get: return animation_ids[source]

static var animation_ids: Dictionary[EvadeSource, int] = {
	EvadeSource.JOB : 0x30,
	EvadeSource.SHIELD : 0xb2, # TODO shield block depends on relative height
	EvadeSource.ACCESSORY : 0x30,
	EvadeSource.WEAPON : 0xb2, # TODO is this the right animation for weapon guard? how to pass in right item id?
}

enum EvadeType {
	NONE,
	PHYSICAL,
	MAGICAL,
}

enum EvadeSource {
	JOB,
	SHIELD,
	ACCESSORY,
	WEAPON,
}

enum Directions {
	FRONT,
	SIDE,
	BACK,
}


func _init(new_value: int = 5, new_source: EvadeSource = EvadeSource.SHIELD, new_type: EvadeType = EvadeType.PHYSICAL, new_directions: Array[Directions] = []) -> void:
	value = new_value
	source = new_source
	type = new_type
	
	if not new_directions.is_empty():
		directions = new_directions
	else:
		set_default_directions()


func set_default_directions() -> void:
	if type == EvadeType.MAGICAL:
		directions = [Directions.FRONT, Directions.SIDE, Directions.BACK]
	else:
		match source:
			EvadeSource.JOB:
				directions = [Directions.FRONT]
			EvadeSource.SHIELD, EvadeSource.WEAPON:
				directions = [Directions.FRONT, Directions.SIDE]
			EvadeSource.ACCESSORY:
				directions = [Directions.FRONT, Directions.SIDE, Directions.BACK]