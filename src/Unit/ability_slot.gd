class_name AbilitySlot
extends Resource

@export var ability_slot_name: String = "[Ability Slot]"
@export var slot_types: Array[Ability.SlotType] = []
@export var ability_unique_name: String
var ability: Ability:
	get: return GameData.abilities.get(ability_unique_name, Ability.new())


static func create_from_dictionary(property_dict: Dictionary) -> AbilitySlot:
	var new_ability_slot: AbilitySlot = AbilitySlot.new()
	for property_name in property_dict.keys():
		if property_name == "slot_types":
			var array = property_dict[property_name]
			var new_slot_types: Array[Ability.SlotType] = []
			for type in array:
				new_slot_types.append(Ability.SlotType[type])
			new_ability_slot.set(property_name, new_slot_types)
		else:
			new_ability_slot.set(property_name, property_dict[property_name])

	new_ability_slot.emit_changed()
	return new_ability_slot


func _init(new_name: String = "", new_slot_types: Array[Ability.SlotType] = [], new_ability_unique_name: String = "") -> void:
	ability_slot_name = new_name
	slot_types = new_slot_types
	ability_unique_name = new_ability_unique_name


func _to_string() -> String:
	return ability_slot_name + ": " + ability.display_name


func to_dictionary() -> Dictionary:
	var properties_to_exclude: PackedStringArray = [
		"RefCounted",
		"Resource",
		"resource_local_to_scene",
		"resource_path",
		"resource_name",
		"resource_scene_unique_id",
		"script",
	]
	
	return Utilities.object_properties_to_dictionary(self, properties_to_exclude)
