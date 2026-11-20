class_name ActionEffect
extends Resource

@export var base_power_formula: FormulaData = FormulaData.new("0.0", [5, 0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, true, true)
@export var type: EffectType = EffectType.UNIT_STAT
@export var effect_stat_type: UnitData.StatType = UnitData.StatType.HP
@export var show_ui: bool = true
@export var transfer_to_user: bool = false # absorb, steal
@export var apply_to_user: bool = false
@export var set_value: bool = false # false = add value, true = set value
@export var label: String = ""

enum EffectType {
	UNIT_STAT,
	CURRENCY,
	INVENTORY,
	#BREAK_EQUIPMENT, # Break is Remove equipment + lower inventory?
	REMOVE_EQUIPMENT, # Steal if transfer = true
	#PHYSICAL_EVADE, 
	#MAGIC_EVADE,
	PUSH,
}


func _init(
	new_type: EffectType = EffectType.UNIT_STAT, 
	new_effect_stat: UnitData.StatType = UnitData.StatType.HP, 
	new_show_ui: bool = true, 
	new_transfer_to_user: bool = false, 
	new_set_value: bool = false,
) -> void:
	type = new_type
	effect_stat_type = new_effect_stat
	show_ui = new_show_ui
	transfer_to_user = new_transfer_to_user
	set_value = new_set_value


func get_value(user: UnitData, target: UnitData, element: Action.ElementTypes) -> int:
	return roundi(base_power_formula.get_result(user, target, element))


func get_modified_value(
	user: UnitData,
	target: UnitData,
	action: Action,
	units_override: Array[UnitData] = []
) -> int:
	var effect_value: int = get_value(user, target, action.element)
	if not action.passive_power_modifier_applies_to_hit_chance:
		var user_passive_effects: Array[PassiveEffect] = user.get_all_passive_effects(action.ignore_passives, units_override)
		var target_passive_effects: Array[PassiveEffect] = target.get_all_passive_effects(action.ignore_passives, units_override)
		for passive_effect: PassiveEffect in user_passive_effects:
			effect_value = passive_effect.power_modifier_user.apply(effect_value, user, target)
		for passive_effect: PassiveEffect in target_passive_effects:
			effect_value = passive_effect.power_modifier_targeted.apply(effect_value, user, target)
	return effect_value


func set_effect_label() -> void:
	label = EffectType.keys()[type]
	
	if type == EffectType.UNIT_STAT:
		label = UnitData.StatType.keys()[effect_stat_type]
	if type == EffectType.CURRENCY:
		label = "Gold"


func get_text(value: int) -> String:
	if label == "":
		set_effect_label()
	
	var text: String = str(value) + " " + label
	if set_value:
		text = label + " = " + str(value)
	elif value > 0:
		text = "+" + text
	
	return text


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


static func create_from_json(json_string: String) -> ActionEffect:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_action_effect: ActionEffect = create_from_dictionary(property_dict)
	
	return new_action_effect


static func create_from_dictionary(property_dict: Dictionary) -> ActionEffect:
	var new_action_effect: ActionEffect = ActionEffect.new()
	for property_name: String in property_dict.keys():
		if property_name == "base_power_formula":
			var new_formula_data: FormulaData = FormulaData.create_from_dictionary(property_dict[property_name])
			new_action_effect.set(property_name, new_formula_data)
		elif property_name == "type":
			new_action_effect.type = EffectType[property_dict[property_name]]
		elif property_name == "effect_stat_type":
			new_action_effect.effect_stat_type = UnitData.StatType[property_dict[property_name]]
		else:
			new_action_effect.set(property_name, property_dict[property_name])

	new_action_effect.emit_changed()
	return new_action_effect
