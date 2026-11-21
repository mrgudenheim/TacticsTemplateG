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


func _init(new_formula_text: String = "value + 0.0", new_type: ModifierType = ModifierType.ADD, new_order: int = 1) -> void:
	type = new_type
	order = new_order
	formula_text = new_formula_text


func get_expression_result(value: float, user: UnitData, target: UnitData) -> float:
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


func apply(to_value: int, user: UnitData = null, target: UnitData = null) -> int:
	# var formula_result: float = value_formula.get_base_value(user, target)
	var formula_result: float = get_expression_result(to_value, user, target)
	return roundi(formula_result)
