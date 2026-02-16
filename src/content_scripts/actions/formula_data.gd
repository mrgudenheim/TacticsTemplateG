# https://ffhacktics.com/wiki/Formulas
# TOFU https://ffhacktics.com/smf/index.php?topic=12969.0
class_name FormulaData
extends Resource

#@export var is_modified_by_faith: bool = false
#@export var is_modified_by_element: bool = false
#@export var is_modified_by_undead: bool = false

# @export var formula: Formulas = Formulas.V1
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

enum FaithModifier {
	NONE,
	FAITH,
	UNFAITH,
}

static func create_from_json(json_string: String) -> FormulaData:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_formula: FormulaData = create_from_dictionary(property_dict)

	return new_formula


static func create_from_dictionary(property_dict: Dictionary) -> FormulaData:
	var new_formula: FormulaData = FormulaData.new()
	for property_name: String in property_dict.keys():
		# if property_name == "formula":
		# 	new_formula.formula = Formulas[property_dict[property_name]]
		if property_name == "user_faith_modifier":
			new_formula.user_faith_modifier = FaithModifier[property_dict[property_name]]
		elif property_name == "target_faith_modifier":
			new_formula.target_faith_modifier = FaithModifier[property_dict[property_name]]
		else:
			new_formula.set(property_name, property_dict[property_name])

	new_formula.emit_changed()
	return new_formula


func _init(new_formula_text: String = "0.0", new_values: PackedFloat64Array = [100.0, 1.0], 
		new_user_faith_modifier: FaithModifier = FaithModifier.NONE, new_target_faith_modifier: FaithModifier = FaithModifier.NONE, 
		new_modified_by_element: bool = true, new_modified_by_zodiac: bool = true, 
		new_reverse_sign: bool = true) -> void:
	formula_text = new_formula_text
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
	var error: Error = expression.parse(formula_text, ["user", "target", "values"])
	if error != OK:
		push_error(expression.get_error_text())
		return 0.0
	var result: float = expression.execute([user, target, values])
	if not expression.has_execute_failed():
		return result
	
	push_error(formula_text + " execute failed")
	return 0.0


func get_base_value(user: Unit, target: Unit) -> float:
	var base_value: float = values[0]
	base_value = get_expression_result(user, target)
			
	if reverse_sign:
		base_value = -base_value
	
	return base_value


func faith_modify(value: float, unit: Unit) -> float:
	return value * unit.faith / 100.0


func unfaith_modify(value: float, unit: Unit) -> float:
	return value * (100 - unit.faith) / 100.0


func zodiac_modify(value: float, user: Unit, target: Unit) -> float:
	# TODO user vs target zodiac compatability
	if user.zodiac != target.zodiac:
		value = value * 1.25
	
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
