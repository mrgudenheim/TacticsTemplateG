# https://ffhacktics.com/wiki/Formulas
# TOFU https://ffhacktics.com/smf/index.php?topic=12969.0
class_name FormulaData
extends Resource

#@export var is_modified_by_faith: bool = false
#@export var is_modified_by_element: bool = false
#@export var is_modified_by_undead: bool = false

@export var formula: Formulas = Formulas.V1
@export var formula_text: String = ""
@export var values: PackedFloat64Array = [100.0, 1.0]
@export var reverse_sign: bool = true
@export var user_faith_modifier: FaithModifier = FaithModifier.NONE
@export var target_faith_modifier: FaithModifier = FaithModifier.NONE
#@export var is_modified_by_user_faith: bool = false
#@export var is_modified_by_target_faith: bool = false
@export var is_modified_by_element: bool = true
@export var is_modified_by_zodiac: bool = true
#@export var healing_damages_undead: bool = false # needs to be on Action since formula does not know if value will be used for healing

# applicable evasion is defined on Action
#@export var physical_evasion_applies: bool = false
#@export var magical_evasion_applies: bool = false
#@export var no_evasion_applies: bool = false

# TODO default description of "Formula description could not be found"
static var formula_descriptions: Dictionary[Formulas, String] = {
	Formulas.PA_X_V1: "PAxWP",
	Formulas.MA_X_V1: "MAxWP",
	Formulas.AVG_PA_MA_X_V1: "AVG_PA_MAxWP",
	Formulas.AVG_PA_SP_X_V1: "AVG_PA_SPxWP",
	Formulas.PA_BRAVE_X_V1: "PA_BRAVExWP",
	Formulas.RANDOM_PA_X_V1: "RANDOM_PAxWP",
	Formulas.V1_X_V1: "WPxWP",
	Formulas.PA_BRAVE_X_PA: "PA_BRAVExPA",
}

enum FaithModifier {
	NONE,
	FAITH,
	UNFAITH,
}

# TODO remove specific formulas and allow any string using Expression
# https://docs.godotengine.org/en/stable/classes/class_expression.html
enum Formulas {
	V1,
	PA_X_V1,
	MA_X_V1,
	WP_X_V1,
	AVG_PA_MA_X_V1,
	AVG_PA_SP_X_V1,
	PA_BRAVE_X_V1,
	RANDOM_PA_X_V1,
	V1_X_V1,
	PA_BRAVE_X_PA,
	MA_PLUS_V1,
	MA_PLUS_V1_X_MA_DIV_2,
	PA_PLUS_V1_X_MA_DIV_2,
	PA_PLUS_WP_PLUS_V1,
	SP_PLUS_V1,
	LVL_X_SP_X_V1,
	MIN_TARGET_EXP_OR_SP_PLUS_V1,
	PA_PLUS_V1,
	PA_X_WP_PLUS_V1,
	PA_X_WP_X_V1,
	PA_X_PA_PLUS_V1_DIV_2,
	RANDOM_V1_X_PA_X_3_PLUS_V2_DIV_2,
	RANDOM_V1_X_PA,
	USER_MAX_HP_X_V1,
	USER_MAX_MP_X_V1,
	TARGET_MAX_HP_X_V1,
	TARGET_MAX_MP_X_V1,
	USER_CURRENT_HP_MINUS_V1,
	TARGET_CURRENT_MP_MINUS_V1,
	TARGET_CURRENT_HP_MINUS_V1,
	USER_MISSING_HP_X_V1,
	TARGET_MISSING_HP_X_V1,
	TARGET_CURRENT_HP_X_V1,
	RANDOM_V1_V2,
	BRAVE_X_V1,
}


static func create_from_json(json_string: String) -> FormulaData:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_formula: FormulaData = create_from_dictionary(property_dict)

	return new_formula


static func create_from_dictionary(property_dict: Dictionary) -> FormulaData:
	var new_formula: FormulaData = FormulaData.new()
	for property_name: String in property_dict.keys():
		if property_name == "formula":
			new_formula.formula = Formulas[property_dict[property_name]]
		elif property_name == "user_faith_modifier":
			new_formula.user_faith_modifier = FaithModifier[property_dict[property_name]]
		elif property_name == "target_faith_modifier":
			new_formula.target_faith_modifier = FaithModifier[property_dict[property_name]]
		else:
			new_formula.set(property_name, property_dict[property_name])

	new_formula.emit_changed()
	return new_formula


func _init(new_formula: Formulas = Formulas.V1, new_values: PackedFloat64Array = [100.0, 1.0], 
		new_user_faith_modifier: FaithModifier = FaithModifier.NONE, new_target_faith_modifier: FaithModifier = FaithModifier.NONE, 
		new_modified_by_element: bool = true, new_modified_by_zodiac: bool = true, 
		new_reverse_sign: bool = true) -> void:
	formula = new_formula
	values = new_values
	user_faith_modifier = new_user_faith_modifier
	target_faith_modifier = new_target_faith_modifier
	is_modified_by_element = new_modified_by_element
	is_modified_by_zodiac = new_modified_by_zodiac
	reverse_sign = new_reverse_sign


func get_result(user: Unit, target: Unit, element: Action.ElementTypes) -> float:
	var result: float = get_base_value(user, target)
	
	match user_faith_modifier:
		FaithModifier.FAITH:
			result = faith_modify(result, user)
		FaithModifier.UNFAITH:
			result = unfaith_modify(result, user)
	
	match target_faith_modifier:
		FaithModifier.FAITH:
			result = faith_modify(result, target)
		FaithModifier.UNFAITH:
			result = unfaith_modify(result, target)
	
	if is_modified_by_element:
		result = element_modify(result, user, target, element)
	
	if is_modified_by_zodiac:
		result = zodiac_modify(result, user, target)
	
	return result


func get_expression_result(user: Unit, target: Unit) -> float:
	var expression: Expression = Expression.new()

	var error: Error = expression.parse(formula_text, ["user", 'target'])
	if error != OK:
		push_error(expression.get_error_text())
		return 0.0
	var result: float = expression.execute([user, target])
	if not expression.has_execute_failed():
		return result
	
	push_error(formula_text + " execute failed")
	return 0.0


func get_base_value(user: Unit, target: Unit) -> float:
	# if user != null and target != null:
	# 	var new_value: float = get_expression_result("user.stats[user.StatType.HP].modified_value * 5", user, target)
	# 	return new_value
	var base_value: float = values[0]
	var wp: int 
	if not user == null:
		wp = user.primary_weapon.weapon_power
	
	match formula:
		Formulas.V1:
			base_value = values[0]
		Formulas.PA_X_V1:
			base_value = user.physical_attack_current * values[0]
		Formulas.MA_X_V1:
			base_value = user.magical_attack_current * values[0]
		Formulas.WP_X_V1:
			base_value = wp * values[0]
		Formulas.AVG_PA_MA_X_V1:
			base_value = ((user.physical_attack_current + user.magical_attack_current) / 2.0) * values[0]
		Formulas.AVG_PA_SP_X_V1:
			base_value = ((user.physical_attack_current + user.speed_current) / 2.0) * values[0]
		Formulas.PA_BRAVE_X_V1:
			base_value = (user.physical_attack_current * user.brave_current / 100.0) * values[0]
		Formulas.RANDOM_PA_X_V1:
			base_value = randi_range(1, user.physical_attack_current) * values[0]
		Formulas.V1_X_V1:
			base_value = values[0] * values[0]
		Formulas.PA_BRAVE_X_PA:
			base_value = (user.physical_attack_current * user.brave_current / 100.0) * user.physical_attack_current
		Formulas.MA_PLUS_V1:
			base_value = user.magical_attack_current + values[0] # MAplusV1
		Formulas.MA_PLUS_V1_X_MA_DIV_2:
			base_value = (user.magical_attack_current + values[0]) * user.magical_attack_current / 2.0 # 0x1e, 0x1f, 0x5e, 0x5f, 0x60 rafa/malak
		Formulas.PA_PLUS_V1_X_MA_DIV_2:
			base_value = (user.physical_attack_current + values[0]) * user.magical_attack_current / 2.0 # 0x24 geomancy
		Formulas.PA_PLUS_WP_PLUS_V1:
			base_value = user.physical_attack_current + wp + values[0] # 0x25 break equipment
		Formulas.SP_PLUS_V1:
			base_value = user.speed_current + values[0] # 0x26 steal equipment SPplusX
		Formulas.LVL_X_SP_X_V1:
			base_value = user.level * user.speed_current * values[0] # 0x27 steal gil LVLxSP
		Formulas.MIN_TARGET_EXP_OR_SP_PLUS_V1:
			base_value = minf(target.unit_exp, user.speed_current + values[0]) # 0x28 steal exp
		Formulas.PA_PLUS_V1:
			base_value = user.physical_attack_current + values[0] # 0x2b, 0x2c PAplusY
		Formulas.PA_X_WP_PLUS_V1:
			base_value = user.physical_attack_current * (wp + values[0]) # 0x2d agrais sword skills
		Formulas.PA_X_WP_X_V1:
			base_value = user.physical_attack_current * wp * values[0] # 0x2e, 0x2f, 0x30
		Formulas.PA_X_PA_PLUS_V1_DIV_2:
			base_value = (user.physical_attack_current + values[0]) * user.physical_attack_current / 2.0 # 0x31 monk skills
		Formulas.RANDOM_V1_X_PA_X_3_PLUS_V2_DIV_2:
			base_value = randi_range(1, roundi(values[0])) * ((user.physical_attack_current * 3) + values[1]) / 2.0 # 0x32 repeating fist # TODO 2 variables rndm to X, PA + Y
			#base_value = user.physical_attack_current * values[0] / 2.0 # 0x34 chakra
		Formulas.RANDOM_V1_X_PA:
			base_value = user.physical_attack_current * randi_range(1, roundi(values[0])) # 0x37
		Formulas.USER_MAX_HP_X_V1:
			base_value = user.hp_max * values[0] # 0x3c wish, energy USER_MAX_HP
		Formulas.USER_MAX_MP_X_V1:
			base_value = user.mp_max * values[0] # USER_MAX_MP
		Formulas.TARGET_MAX_HP_X_V1:
			base_value = target.hp_max * values[0] # 0x09 wish, energy TARGET_MAX_HP
		Formulas.TARGET_MAX_MP_X_V1:
			base_value = target.mp_max * values[0] # 0x09 wish, energy TARGET_MAX_HP
		
		Formulas.USER_CURRENT_HP_MINUS_V1:
			base_value = user.hp_current - values[0] # 0x17, 0x3e TARGET_CURRENT_HP
		Formulas.TARGET_CURRENT_MP_MINUS_V1:
			base_value = target.mp_current - values[0] # 0x16 mute TARGET_CURRENT_MP
		Formulas.TARGET_CURRENT_HP_MINUS_V1:
			base_value = target.hp_current - values[0] # 0x17, 0x3e TARGET_CURRENT_HP
		Formulas.USER_MISSING_HP_X_V1:
			base_value = (user.hp_max - user.hp_current) * values[0] # 0x43 USER_MISSING_HP
		Formulas.TARGET_MISSING_HP_X_V1:
			base_value = (target.hp_max - target.hp_current) * values[0] # 0x45 TARGET_MISSING_HP
		Formulas.TARGET_CURRENT_HP_X_V1:
			base_value = target.hp_current * values[0] # TARGET_CURRENT_HP, ai status score
		Formulas.RANDOM_V1_V2:
			base_value = randi_range(roundi(values[0]), roundi(values[1])) # 0x4b RANDOM_RANGE
		Formulas.BRAVE_X_V1:
			base_value = user.brave_current * values[0] # reactions
			
			
			#base_value = action_modifier / 100.0 # % treat value as a percent when actually applying effect
			# TODO target ct?
			
	if reverse_sign:
		base_value = -base_value
	
	return base_value


func faith_modify(value: float, unit: Unit) -> float:
	return value * unit.faith_current / 100.0


func unfaith_modify(value: float, unit: Unit) -> float:
	return value * (100 - unit.faith_current) / 100.0


func zodiac_modify(value: float, user: Unit, target: Unit) -> float:
	# TODO user vs target zodiac compatability
	
	return value


func element_modify(value: float, user: Unit, target: Unit, element: Action.ElementTypes) -> float:
	if target.elemental_cancel.has(element):
		return 0.0
	
	var new_value: float = value
	if user.elemental_strengthen.has(element):
		new_value = new_value * 1.25
	
	if target.elemental_weakness.has(element):
		new_value = new_value * 2
	
	if target.elemental_half.has(element):
		new_value = new_value / 2
	
	if target.elemental_absorb.has(element):
		if new_value < 0:
			new_value = abs(new_value) # positive is healing
	
	return new_value


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
