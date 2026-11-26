class_name Modifier
extends Resource

const EXPRESSION_INPUT_NAMES: PackedStringArray = ["user", "target", "value"]

enum ModifierOrder {
	ADD,
	MULT,
	SET,
}

@export var order_type: ModifierOrder = ModifierOrder.ADD
@export var formula_text: String = "value + 0.0":
	set(value):
		if value != formula_text:
			formula_text = value
			_cached_expression = null
			_cached_formula_text = ""
# TODO track modifier source?

var _cached_expression: Expression = null
var _cached_formula_text: String = ""


func _init(new_formula_text: String = "value + 0.0", new_type: ModifierOrder = ModifierOrder.ADD) -> void:
	order_type = new_type
	formula_text = new_formula_text


func _get_parsed_expression() -> Expression:
	if _cached_expression != null and _cached_formula_text == formula_text:
		return _cached_expression

	var expression: Expression = Expression.new()
	var error: Error = expression.parse(formula_text, EXPRESSION_INPUT_NAMES)
	if error != OK:
		push_error("Modifier parse error (%s): %s" % [formula_text, expression.get_error_text()])
		_cached_expression = null
		_cached_formula_text = ""
		return null

	_cached_expression = expression
	_cached_formula_text = formula_text
	return _cached_expression


func get_expression_result(value: float, user: UnitData, target: UnitData) -> float:
	var expression: Expression = _get_parsed_expression()
	if expression == null:
		return 0.0
	var raw_result: Variant = expression.execute([user, target, value])
	if not expression.has_execute_failed() and raw_result != null:
		return float(raw_result)

	push_error(formula_text + " execute failed")
	return 0.0


func apply(to_value: int, user: UnitData = null, target: UnitData = null) -> int:
	# var formula_result: float = value_formula.get_base_value(user, target)
	var formula_result: float = get_expression_result(to_value, user, target)
	return roundi(formula_result)
