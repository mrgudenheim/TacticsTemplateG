class_name MapChunkSettingsUi
extends Control

signal map_chunk_settings_changed(new_map_chunk_settings: MapChunkSettingsUi)
signal map_chunk_nodes_changed(new_map_chunk_settings: MapChunkSettingsUi)
signal deleted(new_map_chunk_settings: MapChunkSettingsUi)

const SETTINGS_UI_SCENE: PackedScene = preload("res://src/battle/editor/map_chunk_settings.tscn")

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
	var new_map_chunk_settings: MapChunkSettingsUi = SETTINGS_UI_SCENE.instantiate()
	new_map_chunk_settings.map_chunk = new_map_chunk
	return new_map_chunk_settings


func _ready() -> void:
	delete_button.pressed.connect(queue_free)
	chunk_name_dropdown.item_selected.connect(on_chunk_selected)
	position_edit.vector_changed.connect(set_map_chunk_position)
	
	for map_data_name: String in GameData.map_data_paths.keys():
		chunk_name_dropdown.add_item(map_data_name)
	
	var map_index: int = Utilities.get_option_button_index_by_string(chunk_name_dropdown, map_chunk.unique_name)
	if map_index == -1: # map name not found
		map_index = range(1, chunk_name_dropdown.item_count).pick_random() # don't include map 0 that causes error
	
	for idx: int in mirror_checkboxes.size():
		mirror_checkboxes[idx].button_pressed = map_chunk.mirror_xyz[idx]
		mirror_checkboxes[idx].toggled.connect(on_mirror_changed)
	
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
	var map_chunk_data: MapData = GameData.get_map_data(map_chunk_unique_name)

	var new_map_instance: MapChunkNodes = MapChunkNodes.instantiate()
	new_map_instance.map_data = map_chunk_data
	new_map_instance.name = map_chunk_data.unique_name

	var transformed_mesh: ArrayMesh = FftMapData.get_transformed_mesh(map_chunk_data.mesh, map_chunk.mirror_scale)
	new_map_instance.mesh_instance.mesh = transformed_mesh

	new_map_instance.set_mesh_shader(GameData.get_texture(map_chunk_data.unique_name), map_chunk_data.palettes)
	new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	
	return new_map_instance


func set_map_chunk_position(new_position: Vector3i) -> void:
	map_chunk.corner_position = new_position
	map_chunk_nodes.position = new_position
	map_chunk_nodes.position.y = map_chunk_nodes.position.y * FftMapData.HEIGHT_SCALE

	map_chunk_settings_changed.emit(self)
