class_name ActionEffect
extends Resource

@export var base_power_formula: FormulaData = FormulaData.new("0.0", [5, 0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, true, true)
@export var type: EffectType = EffectType.UNIT_STAT
@export var effect_stat_type: Unit.StatType = Unit.StatType.HP
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
}


func _init(new_type: EffectType = EffectType.UNIT_STAT, new_effect_stat: Unit.StatType = Unit.StatType.HP, new_show_ui: bool = true, new_transfer_to_user: bool = false, new_set_value: bool = false) -> void:
	type = new_type
	effect_stat_type = new_effect_stat
	show_ui = new_show_ui
	transfer_to_user = new_transfer_to_user
	set_value = new_set_value


func get_value(user: Unit, target: Unit, element: Action.ElementTypes) -> int:
	return roundi(base_power_formula.get_result(user, target, element))


func get_ai_value(user: Unit, target: Unit, element: Action.ElementTypes) -> int:
	var nominal_value: int = roundi(base_power_formula.get_result(user, target, element))
	var is_friendly: bool = target.team == user.team
	var ai_value: int = nominal_value
	
	if type == EffectType.UNIT_STAT:
		if set_value:
			ai_value = target.stats[effect_stat_type].get_set_delta(nominal_value)
		else:
			ai_value = target.stats[effect_stat_type].get_add_delta(nominal_value)
		
		if target.is_defeated:
			ai_value = 0 # prevent ai from focusing defeated units with non-status changes
	else:
		ai_value = 0 # TODO remove equipment should not be 0, check changes/modifiers for stats, statuses, element interactions
	
	if not is_friendly:
		ai_value = -ai_value
	
	return ai_value


func set_effect_label() -> void:
	label = EffectType.keys()[type]
	
	if type == EffectType.UNIT_STAT:
		label = Unit.StatType.keys()[effect_stat_type]
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


func apply_value(apply_unit: Unit, value: int) -> int:
	match type:
		EffectType.UNIT_STAT:
			if set_value:
				apply_unit.stats[effect_stat_type].set_value(value)
			else:
				apply_unit.stats[effect_stat_type].add_value(value)
		EffectType.CURRENCY:
			if set_value:
				apply_unit.team.currency = value
			else:
				apply_unit.team.currency += value
		EffectType.INVENTORY:
			if set_value:
				apply_unit.team.inventory[0] = value # TODO get inventory item id to change
			else:
				apply_unit.team.inventory[0] += value # TODO get inventory item id to change
		EffectType.REMOVE_EQUIPMENT:
			pass
			# TODO implement action_effect removing equipment from unit.equip_slot
	
	var effect_text: String = get_text(value)
	apply_unit.show_popup_text(effect_text)
	
	return value

func apply(user: Unit, target: Unit, value: int) -> int:
	var apply_unit: Unit = target
	if apply_to_user:
		apply_unit = user
	
	value = apply_value(apply_unit, value)
	
	if transfer_to_user:
		apply_value(user, -value)
	
	return value


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
			new_action_effect.effect_stat_type = Unit.StatType[property_dict[property_name]]
		else:
			new_action_effect.set(property_name, property_dict[property_name])

	new_action_effect.emit_changed()
	return new_action_effect
