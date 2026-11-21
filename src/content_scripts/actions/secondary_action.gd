class_name SecondaryAction
extends Resource

var action_idx: int
@export var action_unique_name: String = ""
@export var chance: int = 100
@export var requires_primary_hit: bool = true
@export var play_caster_animation: bool = true
@export var roll_hit_chance: bool = true


func _init(
	new_unique_name: String = "",
	new_chance: int = 100,
	new_requires_primary_hit: bool = true,
	new_play_caster_animation: bool = true,
	new_roll_hit_chance: bool = true
) -> void:
	action_unique_name = new_unique_name
	chance = new_chance
	requires_primary_hit = new_requires_primary_hit
	play_caster_animation = new_play_caster_animation
	roll_hit_chance = new_roll_hit_chance
