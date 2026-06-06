class_name Ability
extends Resource

enum SlotType {
	# SKILLSET,
	REACTION,
	SUPPORT,
	MOVEMENT,
	ACTION,
}

const SAVE_FOLDER: String = "abilities/"
const FILE_SUFFIX: String = "ability"

@export var unique_name: String = "unique_name"
@export var display_name: String = "[Ability Name]"
@export var slot_type: SlotType = SlotType.ACTION
@export var description: String = "[ability description]"

@export var jp_cost: int = 0
@export var chance_to_learn: float = 100 # percent
@export var learn_with_jp: bool = true
@export var display_ability_name: bool = true
@export var learn_on_hit: bool = false

@export var passive_effect_name: String = ""
var passive_effect: PassiveEffect = PassiveEffect.new()

@export var triggered_actions_names: PackedStringArray = []
var triggered_actions: Array[TriggeredAction] = []

func add_to_global_list(will_overwrite: bool = false) -> void:
	if ["", "unique_name"].has(unique_name):
		unique_name = display_name.to_snake_case()
	
	if RomReader.abilities.keys().has(unique_name) and will_overwrite:
		push_warning("Overwriting existing action: " + unique_name)
	elif RomReader.abilities.keys().has(unique_name) and not will_overwrite:
		var num: int = 2
		var formatted_num: String = "%02d" % num
		var new_unique_name: String = unique_name + "_" + formatted_num
		while RomReader.abilities.keys().has(new_unique_name):
			num += 1
			formatted_num = "%02d" % num
			new_unique_name = unique_name + "_" + formatted_num
		
		push_warning("Ability list already contains: " + unique_name + ". Incrementing unique_name to: " + new_unique_name)
		unique_name = new_unique_name
	
	RomReader.abilities[unique_name] = self


func to_json() -> String:
	var properties_to_exclude: PackedStringArray = [
		"RefCounted",
		"Resource",
		"resource_local_to_scene",
		"resource_path",
		"resource_name",
		"resource_scene_unique_id",
		"script",
	]
	return Utilities.object_properties_to_json(self, properties_to_exclude)


func get_passive_effect() -> PassiveEffect:
	return GameData.passive_effects[passive_effect_name]


static func create_from_json(json_string: String) -> Ability:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_ability: Ability = create_from_dictonary(property_dict)
	
	return new_ability


static func create_from_dictonary(property_dict: Dictionary) -> Ability:
	var new_ability: Ability = Ability.new()
	for property_name in property_dict.keys():
		if property_name == "slot_type":
			var type: String = property_dict[property_name]
			var new_slot_type: SlotType = SlotType[type]
			new_ability.set(property_name, new_slot_type)
		else:
			new_ability.set(property_name, property_dict[property_name])

	new_ability.emit_changed()
	return new_ability
