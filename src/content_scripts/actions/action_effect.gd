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
		var power_modifiers: Array[Modifier] = []
		for passive_effect: PassiveEffect in user_passive_effects:
			power_modifiers.append(passive_effect.power_modifier_user)
		for passive_effect: PassiveEffect in target_passive_effects:
			power_modifiers.append(passive_effect.power_modifier_targeted)
		effect_value = Modifier.apply_all(power_modifiers, effect_value, user, target)
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
