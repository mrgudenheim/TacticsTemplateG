class_name ActionPreview
extends Control

@export var label: Label
@export var unit: UnitActor
var camera: Camera3D

func _ready() -> void:
	camera = get_viewport().get_camera_3d()


func _process(_delta: float) -> void:
	if camera != null:
		var camera_right: Vector3 = camera.basis * Vector3.RIGHT
		position = camera.unproject_position(unit.char_body.position + (Vector3.UP * 1.0) + (camera_right * 0.0))
