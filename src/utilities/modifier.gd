class_name Modifier
extends Resource

enum ModifierType {
	ADD,
	MULT,
	SET,
}

@export var type: ModifierType = ModifierType.ADD
@export var value_formula: FormulaData = FormulaData.new(FormulaData.Formulas.V1)
@export var order: int = 1 # order to be appliede
# TODO track modifier source?


static func create_from_json(json_string: String) -> Modifier:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_modifier: Modifier = create_from_dictionary(property_dict)
	
	return new_modifier


static func create_from_dictionary(property_dict: Dictionary) -> Modifier:
	var new_modifier: Modifier = Modifier.new()
	for property_name: String in property_dict.keys():
		if property_name == "value_formula":
			var new_formula: FormulaData = FormulaData.create_from_dictionary(property_dict[property_name])
			new_modifier.set(property_name, new_formula)
		elif property_name == "type":
			new_modifier.type = ModifierType[property_dict[property_name]]
		else:
			new_modifier.set(property_name, property_dict[property_name])

	new_modifier.emit_changed()
	return new_modifier


func _init(new_value: float = 1.0, new_type: ModifierType = ModifierType.ADD, new_order: int = 1) -> void:
	type = new_type
	order = new_order

	value_formula = FormulaData.new(FormulaData.Formulas.V1, [new_value])
	value_formula.reverse_sign = false
	value_formula.is_modified_by_element = false
	value_formula.is_modified_by_zodiac = false


# func apply(to_value: int) -> int:
# 	match type:
# 		ModifierType.ADD:
# 			return roundi(to_value + value)
# 		ModifierType.MULT:
# 			return roundi(to_value * value)
# 		ModifierType.SET:
# 			return roundi(value)
# 		_:
# 			push_warning("Modifier type unknown: " + str(type))
# 			return -1


func apply(to_value: int, user: Unit = null, target: Unit = null) -> int:
	var formula_result: float = value_formula.get_base_value(user, target)

	match type:
		ModifierType.ADD:
			return roundi(to_value + formula_result)
		ModifierType.MULT:
			return roundi(to_value * formula_result)
		ModifierType.SET:
			return roundi(formula_result)
		_:
			push_warning("Modifier type unknown: " + str(type))
			return -1


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