class_name SecondaryAction
extends Resource

var action_idx: int
var action_unique_name: String
var chance: int
var requires_primary_hit: bool = true
var play_caster_animation: bool = true
var roll_hit_chance: bool = true

static func create_from_dictionary(property_dict: Dictionary) -> SecondaryAction:
	return SecondaryAction.new(
		str(property_dict.get("action_unique_name", "")),
		int(property_dict.get("chance", 100)),
		bool(property_dict.get("requires_primary_hit", true)),
		bool(property_dict.get("play_caster_animation", true)),
		bool(property_dict.get("roll_hit_chance", true))
	)

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

func to_dictionary() -> Dictionary:
	return {
		"action_unique_name": action_unique_name,
		"chance": chance,
		"requires_primary_hit": requires_primary_hit,
		"play_caster_animation": play_caster_animation,
		"roll_hit_chance": roll_hit_chance,
	}
