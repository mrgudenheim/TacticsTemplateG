class_name VfxTestUtils
## Shared utilities for VFX test scenes.


## Load a map with Y-mirrored mesh (matching battle system default: mirror_xyz = [false, true, false]).
## Returns the MapChunkNodes added as child of `container`, or null if the map can't be loaded.
static func load_mirrored_map(map_name: String, container: Node3D) -> MapChunkNodes:
	if not GameData.maps_data.keys().has(map_name):
		push_warning("[VfxTestUtils] Map not in GameData: " + map_name)
		return null

	var map_data: MapData = GameData.maps_data[map_name]
	#if not map_data.is_initialized:
		#map_data.init_map()

	var new_map_instance: MapChunkNodes = MapChunkNodes.instantiate()
	new_map_instance.map_data = map_data
	new_map_instance.name = map_data.unique_name
	
	var transformed_mesh: ArrayMesh = FftMapData.get_transformed_mesh(map_data.mesh, Vector3(1, 1, 1))
	new_map_instance.mesh_instance.mesh = transformed_mesh

	new_map_instance.set_mesh_shader(GameData.textures[map_data.unique_name], map_data.palettes)
	new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	new_map_instance.play_animations(map_data)
	container.add_child(new_map_instance)

	return new_map_instance


static func vec3_str(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
