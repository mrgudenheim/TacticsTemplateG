class_name VfxTestUtils
## Shared utilities for VFX test scenes.


## Load a map with Y-mirrored mesh (matching battle system default: mirror_xyz = [false, true, false]).
## Returns the MapChunkNodes added as child of `container`, or null if the map can't be loaded.
static func load_mirrored_map(map_index: int, container: Node3D) -> MapChunkNodes:
	if map_index >= RomReader.maps_array.size():
		push_warning("[VfxTestUtils] Map index %d out of range" % map_index)
		return null

	var map_data: MapData = RomReader.maps_array[map_index]
	if not map_data.is_initialized:
		map_data.init_map()

	var new_map_instance: MapChunkNodes = MapChunkNodes.instantiate()
	new_map_instance.map_data = map_data
	new_map_instance.name = map_data.unique_name

	# Apply Y-mirror
	var mirror_scale := Vector3(1, -1, 1)
	var mesh_aabb: AABB = map_data.mesh.get_aabb()
	var surface_arrays: Array = map_data.mesh.surface_get_arrays(0)
	var original_mesh_center: Vector3 = mesh_aabb.get_center()

	for vertex_idx: int in surface_arrays[Mesh.ARRAY_VERTEX].size():
		var vertex: Vector3 = surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx]
		vertex = (vertex - original_mesh_center) * mirror_scale + (mesh_aabb.size / 2.0)
		surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx] = vertex

	var custom0_flags: int = MapData.mirror_custom0(surface_arrays, original_mesh_center, mirror_scale, mesh_aabb.size / 2.0)

	# Flip winding order for odd-axis mirror
	for idx: int in surface_arrays[Mesh.ARRAY_VERTEX].size() / 3:
		var tri_idx: int = idx * 3
		var temp_vertex: Vector3 = surface_arrays[Mesh.ARRAY_VERTEX][tri_idx]
		surface_arrays[Mesh.ARRAY_VERTEX][tri_idx] = surface_arrays[Mesh.ARRAY_VERTEX][tri_idx + 2]
		surface_arrays[Mesh.ARRAY_VERTEX][tri_idx + 2] = temp_vertex
		var temp_uv: Vector2 = surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx]
		surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx] = surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx + 2]
		surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx + 2] = temp_uv

	var modified_mesh: ArrayMesh = ArrayMesh.new()
	modified_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays, [], {}, custom0_flags)
	new_map_instance.mesh_instance.mesh = modified_mesh

	new_map_instance.set_mesh_shader(map_data.albedo_texture_indexed, map_data.texture_palettes)
	new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	new_map_instance.play_animations(map_data)
	container.add_child(new_map_instance)

	return new_map_instance


static func vec3_str(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
