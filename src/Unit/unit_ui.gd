class_name UnitUi
extends Control

@export var unit: UnitActor
@export var unit_char_body: CharacterBody3D
@export var offset: Vector2 = Vector2.DOWN
var camera: Camera3D

func _ready() -> void:
	camera = get_viewport().get_camera_3d()


func _process(_delta: float) -> void:
	if camera != null:
		var camera_right: Vector3 = camera.basis * Vector3.RIGHT
		position = camera.unproject_position(unit_char_body.position + (Vector3.UP * offset.y) + (camera_right * offset.x))
