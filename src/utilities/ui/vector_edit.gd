@tool
class_name VectorEdit
extends HBoxContainer

signal vector_changed(vector)

@export var vector_type: VectorType = VectorType.VECTOR3:
	get: return vector_type
	set(value):
		vector_type = value
		set_spinboxes(value)

var vector:
	get: return get_vector()

enum VectorType {
	VECTOR3,
	VECTOR3I,
	VECTOR2,
	VECTOR2I,
}

@export var x_spinbox: SpinBox
@export var y_spinbox: SpinBox
@export var z_spinbox: SpinBox


func _ready() -> void:
	x_spinbox.value_changed.connect(changed)
	y_spinbox.value_changed.connect(changed)
	z_spinbox.value_changed.connect(changed)


func set_spinboxes(new_vector_type: VectorType) -> void:
	match new_vector_type:
		VectorType.VECTOR3:
			z_spinbox.visible = true
			
			x_spinbox.rounded = false
			y_spinbox.rounded = false
			z_spinbox.rounded = false
		VectorType.VECTOR3I:
			z_spinbox.visible = true
			
			x_spinbox.rounded = true
			y_spinbox.rounded = true
			z_spinbox.rounded = true
		VectorType.VECTOR2:
			z_spinbox.visible = false
			
			x_spinbox.rounded = false
			y_spinbox.rounded = false
			z_spinbox.rounded = false
		VectorType.VECTOR2I:
			z_spinbox.visible = false
			
			x_spinbox.rounded = true
			y_spinbox.rounded = true
			z_spinbox.rounded = true
	
	changed()


func get_vector():
	match vector_type:
		VectorType.VECTOR3:
			return Vector3(x_spinbox.value, y_spinbox.value, z_spinbox.value)
		VectorType.VECTOR3I:
			return Vector3i(roundi(x_spinbox.value), roundi(y_spinbox.value), roundi(z_spinbox.value))
		VectorType.VECTOR2:
			return Vector2(x_spinbox.value, y_spinbox.value)
		VectorType.VECTOR2I:
			return Vector2i(roundi(x_spinbox.value), roundi(y_spinbox.value))


func changed(_value: float = 0.0) -> void:
	vector_changed.emit(get_vector())
