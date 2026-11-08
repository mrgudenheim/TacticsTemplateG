class_name MapChunk
extends Resource

@export var unique_name: String = "map_unique_name"
@export var mirror_xyz: Array[bool] = [false, false, false]:
	set(value):
		mirror_xyz = value
		set_mirror_xyz(mirror_xyz)
@export var corner_position: Vector3i = Vector3i.ZERO
@export var rotation_degrees: float = 0.0 # 90 degree rotation increments
var mirror_scale: Vector3i = Vector3i.ONE


static func create_from_dictionary(property_dict: Dictionary) -> MapChunk:
	var new_map_chunk: MapChunk = MapChunk.new()
	for property_name: String in property_dict.keys():
		if property_name == "corner_position":
			var vector_as_array: Array = property_dict[property_name]
			var new_corner_position: Vector3i = Vector3i(roundi(vector_as_array[0]), roundi(vector_as_array[1]), roundi(vector_as_array[2]))
			new_map_chunk.set(property_name, new_corner_position)
		elif property_name == "mirror_xyz":
			var array: Array = property_dict[property_name]
			var new_mirror_xyz: Array[bool] = []
			new_mirror_xyz.assign(array)
			new_map_chunk.set(property_name, new_mirror_xyz)
			new_map_chunk.set_mirror_xyz(new_mirror_xyz)
		else:
			new_map_chunk.set(property_name, property_dict[property_name])

	new_map_chunk.emit_changed()
	return new_map_chunk


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


func set_mirror_xyz(new_mirror_xyz: Array[bool]) -> void:
	mirror_xyz = new_mirror_xyz
	if mirror_xyz.size() >= 3:
		mirror_scale.x = -1 if mirror_xyz[0] else 1
		mirror_scale.y = -1 if mirror_xyz[1] else 1
		mirror_scale.z = -1 if mirror_xyz[2] else 1
