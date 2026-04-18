class_name MapChunkSettingsUi
extends Control

signal map_chunk_settings_changed(new_map_chunk_settings: MapChunkSettingsUi)
signal map_chunk_nodes_changed(new_map_chunk_settings: MapChunkSettingsUi)
signal deleted(new_map_chunk_settings: MapChunkSettingsUi)

const settings_ui_scene: PackedScene = preload("res://src/battle/editor/map_chunk_settings.tscn")

@export var chunk_name_dropdown: OptionButton
@export var position_edit_container: Container
@export var mirror_bools_container: Container
@export var delete_button: Button

@export var position_edit: Vector3iEdit
@export var mirror_checkboxes: Array[CheckBox]

# @export var map_chunk: Scenario.MapChunk = Scenario.MapChunk.new()
@export var map_chunk: Scenario.MapChunk
@export var map_chunk_nodes: MapChunkNodes


static func instantiate(new_map_chunk: Scenario.MapChunk = null) -> MapChunkSettingsUi:
	var new_map_chunk_settings: MapChunkSettingsUi = settings_ui_scene.instantiate()
	new_map_chunk_settings.map_chunk = new_map_chunk
	return new_map_chunk_settings


func _ready() -> void:
	delete_button.pressed.connect(queue_free)
	chunk_name_dropdown.item_selected.connect(on_chunk_selected)
	position_edit.vector_changed.connect(set_map_chunk_position)
	
	for map_data: MapData in RomReader.maps.values():
		chunk_name_dropdown.add_item(map_data.unique_name)

	var map_index: int = range(1, chunk_name_dropdown.item_count).pick_random() # don't include map 0 that causes error
	if map_chunk.unique_name == "map_unique_name":
		# vanilla maps need to be mirrored along y
		# mirror along x to get the un-mirrored look after mirroring along y	
		map_chunk.set_mirror_xyz([true, true, false])
	else:
		map_index = RomReader.maps.keys().find(map_chunk.unique_name)
	
	for idx: int in mirror_checkboxes.size():
		mirror_checkboxes[idx].button_pressed = map_chunk.mirror_xyz[idx]
		mirror_checkboxes[idx].toggled.connect(on_mirror_changed)
	
	# var default_map_unique_name: String = "map_056_orbonne_monastery"
	# default_map_unique_name = "map_091_thieves_fort"
	# var default_index: int = RomReader.maps.keys().find(default_map_unique_name)
	# if default_index == -1:
	# 	default_index = 0
	
	chunk_name_dropdown.select(map_index)
	chunk_name_dropdown.item_selected.emit(map_index)

	position_edit.vector = map_chunk.corner_position


func _exit_tree() -> void:
	if is_queued_for_deletion():
		if map_chunk_nodes != null:
			map_chunk_nodes.queue_free()
			map_chunk_settings_changed.emit(self)
		
		chunk_name_dropdown.queue_free()
		position_edit_container.queue_free()
		mirror_bools_container.queue_free()
		delete_button.queue_free()

		deleted.emit(self)


func add_row_to_table(settings_table: Container) -> void:
	chunk_name_dropdown.reparent(settings_table)
	position_edit_container.reparent(settings_table)
	mirror_bools_container.reparent(settings_table)
	delete_button.reparent(settings_table)


func on_chunk_selected(dropdown_item_index: int) -> void:
	map_chunk.unique_name = chunk_name_dropdown.get_item_text(dropdown_item_index)
	if map_chunk_nodes != null:
		map_chunk_nodes.queue_free()

	map_chunk_nodes = get_map_chunk_nodes(map_chunk.unique_name)
	map_chunk_nodes_changed.emit(self)


func on_mirror_changed(_toggled_on: bool) -> void:
	var new_mirror_xyz: Array[bool] = [false, false, false]
	for idx: int in mirror_checkboxes.size():
		new_mirror_xyz[idx] = mirror_checkboxes[idx].button_pressed
	map_chunk.set_mirror_xyz(new_mirror_xyz)

	on_chunk_selected(chunk_name_dropdown.selected)
	# map_chunk_nodes_changed.emit(self)


func get_map_chunk_nodes(map_chunk_unique_name: String) -> MapChunkNodes:
	var map_chunk_data: MapData = RomReader.maps[map_chunk_unique_name]
	if not map_chunk_data.is_initialized:
		map_chunk_data.init_map()

	var new_map_instance: MapChunkNodes = MapChunkNodes.instantiate()
	new_map_instance.map_data = map_chunk_data
	new_map_instance.name = map_chunk_data.unique_name
	
	# if gltf_map_mesh != null:
	# 	new_map_instance.mesh.queue_free()
	# 	var new_gltf_mesh: MeshInstance3D = gltf_map_mesh.duplicate()
	# 	new_map_instance.add_child(new_gltf_mesh)
	# 	new_map_instance.mesh = new_gltf_mesh
	# 	new_map_instance.mesh.rotation_degrees = Vector3.ZERO
	# else:

	var mesh_aabb: AABB = map_chunk_data.mesh.get_aabb()
	if map_chunk.mirror_scale != Vector3i.ONE or mesh_aabb.position != Vector3.ZERO:
		var surface_arrays: Array = map_chunk_data.mesh.surface_get_arrays(0)
		var original_mesh_center: Vector3 = mesh_aabb.get_center()
		var mirror_vec := Vector3(map_chunk.mirror_scale)
		for vertex_idx: int in surface_arrays[Mesh.ARRAY_VERTEX].size():
			var vertex: Vector3 = surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx]
			vertex = (vertex - original_mesh_center) * mirror_vec + (mesh_aabb.size / 2.0)
			surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx] = vertex

		var custom0_flags: int = MapData.mirror_custom0(surface_arrays, original_mesh_center, mirror_vec, mesh_aabb.size / 2.0)

		var sum_scale: int = map_chunk.mirror_scale.x + map_chunk.mirror_scale.y + map_chunk.mirror_scale.z
		if sum_scale == 1 or sum_scale == -3:
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
	else:
		new_map_instance.mesh_instance.mesh = map_chunk_data.mesh

	new_map_instance.set_mesh_shader(map_chunk_data.albedo_texture_indexed, map_chunk_data.texture_palettes)
	new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	
	return new_map_instance


func set_map_chunk_position(new_position: Vector3i) -> void:
	map_chunk.corner_position = new_position
	map_chunk_nodes.position = new_position
	map_chunk_nodes.position.y = map_chunk_nodes.position.y * MapData.HEIGHT_SCALE

	map_chunk_settings_changed.emit(self)
