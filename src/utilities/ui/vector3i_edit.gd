@tool
class_name Vector3iEdit
extends HBoxContainer

signal vector_changed(vector: Vector3i)

const scene: PackedScene = preload("res://src/utilities/ui/vector3i_edit.tscn")

@export var vector: Vector3i:
	get: return Vector3i(roundi(x_spinbox.value), roundi(y_spinbox.value), roundi(z_spinbox.value))
	set(value):
		vector = value
		set_vector_ui(value)

@onready var x_spinbox: SpinBox = $xSpinBox
@onready var y_spinbox: SpinBox = $ySpinBox
@onready var z_spinbox: SpinBox = $zSpinBox


static func instantiate() -> Vector3iEdit:
	return scene.instantiate()


func _ready() -> void:
	x_spinbox.value_changed.connect(changed)
	y_spinbox.value_changed.connect(changed)
	z_spinbox.value_changed.connect(changed)


func set_vector_ui(new_vector: Vector3i) -> void:
	x_spinbox.value = new_vector.x
	y_spinbox.value = new_vector.y
	z_spinbox.value = new_vector.z


func changed(_value: Vector3i) -> void:
	vector_changed.emit(vector)
