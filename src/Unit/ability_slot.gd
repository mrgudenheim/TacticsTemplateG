class_name AbilitySlot
extends Resource

@export var ability_slot_name: String = "[Ability Slot]"
@export var slot_types: Array[Ability.SlotType] = []
@export var ability_unique_name: String


func _init(new_name: String = "", new_slot_types: Array[Ability.SlotType] = [], new_ability_unique_name: String = "") -> void:
	ability_slot_name = new_name
	slot_types = new_slot_types
	ability_unique_name = new_ability_unique_name


func get_ability() -> Ability:
	if GameData.ability_paths.has(ability_unique_name):
		return GameData.get_ability(ability_unique_name)
	
	push_warning("can't find ability in GameData: " + ability_unique_name)
	return Ability.new()


func _to_string() -> String:
	return ability_slot_name + ": " + get_ability().display_name
