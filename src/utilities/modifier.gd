class_name Modifier
extends Resource

enum ModifierType {
	ADD,
	MULT,
	SET,
}

@export var type: ModifierType = ModifierType.ADD
@export var formula_text: String = "value + 0.0"
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


func _init(new_formula_text: String = "value + 0.0", new_type: ModifierType = ModifierType.ADD, new_order: int = 1) -> void:
	type = new_type
	order = new_order
	formula_text = new_formula_text


func get_expression_result(value: float, user: Unit, target: Unit) -> float:
	var expression: Expression = Expression.new()
	var error: Error = expression.parse(formula_text, ["user", "target", "value"])
	if error != OK:
		push_error(expression.get_error_text())
		return 0.0
	var result: float = expression.execute([user, target, value])
	if not expression.has_execute_failed():
		return result
	
	push_error(formula_text + " execute failed")
	return 0.0


func apply(to_value: int, user: Unit = null, target: Unit = null) -> int:
	# var formula_result: float = value_formula.get_base_value(user, target)
	var formula_result: float = get_expression_result(to_value, user, target)
	return roundi(formula_result)


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
