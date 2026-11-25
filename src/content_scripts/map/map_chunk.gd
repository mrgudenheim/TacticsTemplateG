class_name MapChunk
extends Resource

@export var unique_name: String = "map_unique_name"
@export var mirror_xyz: Array[bool] = [false, false, false]
@export var corner_position: Vector3i = Vector3i.ZERO
@export var rotation_degrees: float = 0.0 # 90 degree rotation increments
var mirror_scale: Vector3i = Vector3i.ONE


func set_mirror_xyz(new_mirror_xyz: Array[bool]) -> void:
	mirror_xyz = new_mirror_xyz
	if mirror_xyz.size() >= 3:
		mirror_scale.x = -1 if mirror_xyz[0] else 1
		mirror_scale.y = -1 if mirror_xyz[1] else 1
		mirror_scale.z = -1 if mirror_xyz[2] else 1
