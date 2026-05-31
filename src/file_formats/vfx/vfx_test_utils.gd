class_name VfxTestUtils
## Shared utilities for VFX test scenes.


## Load a map with Y-mirrored mesh (matching battle system default: mirror_xyz = [false, true, false]).
## Returns the MapChunkNodes added as child of `container`, or null if the map can't be loaded.
static func load_mirrored_map(map_index: int, container: Node3D) -> MapChunkNodes:
	if map_index >= RomReader.maps_array.size():
		push_warning("[VfxTestUtils] Map index %d out of range" % map_index)
		return null

	var map_data: MapData = GameData.maps_data.values()[map_index]
	if not map_data.is_initialized:
		map_data.init_map()

	var new_map_instance: MapChunkNodes = MapChunkNodes.instantiate()
	# MapChunkNodes.map_data is the runtime MapData resource (built from the raw
	# FftMapData parser). The mesh/texture/mirror logic below still reads from the
	# FftMapData (`map_data`), which carries the raw mesh + indexed texture.
	new_map_instance.map_data = MapData.init_from_fft_map_data(map_data)
	new_map_instance.name = map_data.unique_name
	
	var transformed_mesh: ArrayMesh = FftMapData.get_transformed_mesh(map_data.mesh, Vector3(1, -1, 1))
	new_map_instance.mesh_instance.mesh = transformed_mesh

	new_map_instance.set_mesh_shader(map_data.albedo_texture_indexed, map_data.texture_palettes)
	new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	new_map_instance.play_animations(new_map_instance.map_data)
	container.add_child(new_map_instance)

	return new_map_instance


static func vec3_str(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
