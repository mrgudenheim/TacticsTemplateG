@tool
class_name Vector3iEdit
extends HBoxContainer

signal vector_changed(vector: Vector3i)

const SCENE: PackedScene = preload("uid://dxvm0fphohpx4")

var _vector: Vector3i = Vector3i.ZERO

@export var vector: Vector3i:
	get:
		if not is_node_ready():
			return _vector
		return Vector3i(roundi(x_spinbox.value), roundi(y_spinbox.value), roundi(z_spinbox.value))
	set(value):
		_vector = value
		set_vector_ui(value)

@onready var x_spinbox: SpinBox = $xSpinBox
@onready var y_spinbox: SpinBox = $ySpinBox
@onready var z_spinbox: SpinBox = $zSpinBox


static func instantiate() -> Vector3iEdit:
	return SCENE.instantiate()


func _ready() -> void:
	set_vector_ui(_vector)
	x_spinbox.value_changed.connect(changed)
	y_spinbox.value_changed.connect(changed)
	z_spinbox.value_changed.connect(changed)


func set_vector_ui(new_vector: Vector3i) -> void:
	if x_spinbox == null or y_spinbox == null or z_spinbox == null:
		return
	x_spinbox.value = new_vector.x
	y_spinbox.value = new_vector.y
	z_spinbox.value = new_vector.z


func changed(_value: float) -> void:
	vector_changed.emit(vector)
