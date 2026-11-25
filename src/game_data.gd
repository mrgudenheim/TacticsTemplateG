extends Node

signal data_indexed
signal message(message: String)
signal import_progress(current_value: int, max_value: int)

enum Directions {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

const DATA_PATH_CONFIG: String = "user://external_data_paths.cfg"
var external_data_paths: Dictionary[String, String] = {
	"IMPORT_PATH": "user://",
	"ROM_PATH": "user://",
	"EXPORT_PATH": "user://",
}

var is_ready: bool = false
var lazy_load_data: bool = true

# Lazy-loaded resource/asset registries
var shps: DataRegistry
var seqs: DataRegistry
var map_meshes: DataRegistry
var maps_data: DataRegistry
var vfx: DataRegistry
var items: DataRegistry
var status_effects: DataRegistry
var jobs: DataRegistry
var skillsets: DataRegistry
var actions: DataRegistry
var triggered_actions: DataRegistry
var passive_effects: DataRegistry
var abilities: DataRegistry
var scenarios: DataRegistry
var textures: DataRegistry
var unit_spritesheets: DataRegistry

var _registries: Array[DataRegistry] = []

# Eager-loaded / secondary / singleton data
var map_tile_meshes: Dictionary[TerrainTile.SlopeType, ArrayMesh] = {}
var shared_vfx_data: TrapEffectData
var projectiles_gltf: Dictionary[String, Node] = {}
var items_by_idx: Dictionary[int, ItemData] = {}
var names: Dictionary[String, PackedStringArray] = {} # [name_category, possible names]
var palettes: Dictionary[String, PackedColorArray] = {}
var animation_layer_priorities: PackedVector4Array = []
var initial_unit_data: InitialUnitData


func _init() -> void:
	shps = _create_registry("Shp", ".shp.tres", _load_shp)
	seqs = _create_registry("Seq", ".seq.tres", _load_seq)
	map_meshes = _create_registry("MapMesh", ".map.glb", _load_map_mesh)
	maps_data = _create_registry("MapData", ".map_data.tres", _load_map_data)
	vfx = _create_registry("VisualEffectData", ".vfx_data.tres", _load_vfx_data)
	items = _create_registry("ItemData", ItemData.FILE_SUFFIX, _load_item)
	status_effects = _create_registry("StatusEffect", StatusEffect.FILE_SUFFIX, ResourceLoader.load)
	jobs = _create_registry("JobData", JobData.FILE_SUFFIX, ResourceLoader.load)
	skillsets = _create_registry("Skillset", Skillset.FILE_SUFFIX, ResourceLoader.load)
	actions = _create_registry("Action", Action.FILE_SUFFIX, _load_action)
	triggered_actions = _create_registry("TriggeredAction", TriggeredAction.FILE_SUFFIX, ResourceLoader.load)
	passive_effects = _create_registry("PassiveEffect", PassiveEffect.FILE_SUFFIX, ResourceLoader.load)
	abilities = _create_registry("Ability", Ability.FILE_SUFFIX, ResourceLoader.load)
	scenarios = _create_registry("Scenario", Scenario.FILE_SUFFIX, ResourceLoader.load)
	textures = _create_registry("Texture2D", ".texture.webp", _load_texture)
	unit_spritesheets = _create_registry("UnitSpritesheetData", ".unit_spritesheet.tres", ResourceLoader.load)


func _create_registry(
	resource_type_name: String,
	file_suffix: String,
	loader: Callable,
) -> DataRegistry:
	var registry: DataRegistry = DataRegistry.new(
		resource_type_name,
		file_suffix,
		loader,
	)
	_registries.append(registry)
	return registry


func _ready() -> void:
	external_data_paths = _get_saved_data_paths()
	await get_tree().process_frame
	await get_tree().process_frame
	# RomReader.export_tile_meshes("res://src/content_scripts/map/", Vector3(-1.0, 1.0, 1.0))
	#if not external_data_paths["IMPORT_PATH"].is_empty() and DirAccess.dir_exists_absolute(external_data_paths["IMPORT_PATH"]):
		#call_deferred("index_data", external_data_paths["IMPORT_PATH"])


func _get_saved_data_paths() -> Dictionary[String, String]:
	var file: FileAccess = FileAccess.open(DATA_PATH_CONFIG, FileAccess.READ)
	if file == null:
		var err: Error = FileAccess.get_open_error()
		push_error(err)
		return external_data_paths

	var file_text: String = file.get_as_text()
	var untyped_dict: Dictionary = JSON.parse_string(file_text)
	var typed_dict: Dictionary[String, String] = {}
	typed_dict.assign(untyped_dict)
	return typed_dict


func save_data_paths() -> void:
	var json_file: FileAccess = FileAccess.open(DATA_PATH_CONFIG, FileAccess.WRITE)
	json_file.store_line(JSON.stringify(external_data_paths, "\t"))
	json_file.close()


func clear_data() -> void:
	is_ready = false
	for registry: DataRegistry in _registries:
		registry.clear()

	map_tile_meshes = {}
	shared_vfx_data = null
	projectiles_gltf = {}
	items_by_idx = {}
	names = {}
	palettes = {}
	animation_layer_priorities = []
	initial_unit_data = null


func index_data(directory_path: String) -> void:
	clear_data()

	for slope_type: TerrainTile.SlopeType in TerrainTile.SlopeType.values():
		var mesh_name: String = TerrainTile.SlopeType.keys()[slope_type].to_lower()
		var mesh_file_path: String = "res://src/content_scripts/map/tile_mesh_" + mesh_name + ".tres"
		var mesh: ArrayMesh = ResourceLoader.load(mesh_file_path, "ArrayMesh")
		map_tile_meshes[slope_type] = mesh

	var start_time: int = Time.get_ticks_msec()

	var file_paths: PackedStringArray = Utilities.get_file_list_recursive(directory_path, false)

	print_debug("Time to find import files (ms): " + str(Time.get_ticks_msec() - start_time))
	start_time = Time.get_ticks_msec()
	var last_frame_time: int = Time.get_ticks_msec()

	var num_files: int = file_paths.size()
	var current_file: int = 0

	if num_files == 0:
		import_progress.emit(0, 0)
		push_warning("no files to import at: " + directory_path)
		return

	for file_path: String in file_paths:
		current_file += 1
		import_progress.emit(current_file, num_files)

		var elapsed_time: float = (Time.get_ticks_msec() - last_frame_time) / 1000.0
		if current_file == 1 or elapsed_time > (1.0 / 60.0):
			message.emit("Importing: " + file_path.get_file())
			await get_tree().process_frame
			last_frame_time = Time.get_ticks_msec()

		if file_path.ends_with(".text.json"):
			var file_text: String = FileAccess.get_file_as_string(file_path)
			names["all"] = JSON.parse_string(file_text) as PackedStringArray
			names["all_no_empty"] = names["all"].duplicate()
			for idx: int in range(names["all_no_empty"].size() - 1, -1, -1):
				if names["all_no_empty"][idx] == "":
					names["all_no_empty"].remove_at(idx)
		elif file_path.ends_with(".palette.tres"):
			var new_palette: ColorPalette = ResourceLoader.load(file_path, "ColorPalette")
			palettes[file_path.get_file().trim_suffix(".palette.tres")] = new_palette.colors
		elif file_path.ends_with("animation_data.tres"):
			var new_animation_data: AnimationData = ResourceLoader.load(file_path, "AnimationData")
			animation_layer_priorities = new_animation_data.animation_layer_priorities.duplicate()
		elif file_path.to_lower().ends_with("shared_vfx.data.tres"):
			shared_vfx_data = ResourceLoader.load(file_path, "TrapEffectData")
		elif file_path.ends_with(".projectile.glb"):
			projectiles_gltf[file_path.get_file().trim_suffix(".projectile.glb")] = GltfManager.import_gltf(file_path)
		elif file_path.ends_with("initial_unit_data.tres"):
			initial_unit_data = ResourceLoader.load(file_path, "InitialUnitData")
		else:
			for registry: DataRegistry in _registries:
				if registry.index_file(file_path):
					break

	if lazy_load_data == false:
		load_all_data()

	var import_time: int = Time.get_ticks_msec() - start_time
	print_debug("Time to index files (ms): " + str(import_time))
	is_ready = true
	data_indexed.emit()


## Custom registry loaders
func _load_shp(file_path: String) -> Shp:
	var new_shp: Shp = ResourceLoader.load(file_path, "Shp")
	if new_shp != null:
		new_shp.is_initialized = true
	return new_shp


func _load_seq(file_path: String) -> Seq:
	var new_seq: Seq = ResourceLoader.load(file_path, "Seq")
	if new_seq != null:
		new_seq.is_initialized = true
	return new_seq


func _load_map_mesh(file_path: String) -> ArrayMesh:
	return GltfManager.import_gltf_array_mesh(file_path)


func _load_map_data(file_path: String) -> MapData:
	var new_map_data: MapData = ResourceLoader.load(file_path, "MapData")
	if new_map_data == null:
		return null
	new_map_data.mesh = get_map_mesh(new_map_data.unique_name)
	return new_map_data


func _load_vfx_data(file_path: String) -> VisualEffectData:
	var new_vfx: VisualEffectData = ResourceLoader.load(file_path, "VisualEffectData")
	if new_vfx != null:
		new_vfx.texture = get_texture(new_vfx.unique_name)
	return new_vfx


func _load_item(file_path: String) -> ItemData:
	var loaded_item: ItemData = ResourceLoader.load(file_path, "ItemData")
	if loaded_item != null:
		items_by_idx[loaded_item.item_idx] = loaded_item
	return loaded_item


func _load_action(file_path: String) -> Action:
	var new_action: Action = ResourceLoader.load(file_path, "Action")
	if new_action != null and new_action.vfx_name != "":
		new_action.vfx_data = get_vfx_data(new_action.vfx_name)
	return new_action


func _load_texture(file_path: String) -> Texture2D:
	var new_image: Image = Image.load_from_file(file_path)
	if new_image == null:
		return null
	return ImageTexture.create_from_image(new_image)


## Typed lazy-loading getters
func get_shp(unique_name: String) -> Shp:
	return shps.get_or_null(unique_name) as Shp


func get_seq(unique_name: String) -> Seq:
	return seqs.get_or_null(unique_name) as Seq


func get_map_mesh(unique_name: String) -> ArrayMesh:
	return map_meshes.get_or_null(unique_name) as ArrayMesh


func get_map_data(unique_name: String) -> MapData:
	return maps_data.get_or_null(unique_name) as MapData


func get_vfx_data(unique_name: String) -> VisualEffectData:
	return vfx.get_or_null(unique_name) as VisualEffectData


func get_item(unique_name: String) -> ItemData:
	return items.get_or_null(unique_name) as ItemData


func get_item_by_idx(target_item_idx: int) -> ItemData:
	if items_by_idx.has(target_item_idx):
		return items_by_idx[target_item_idx]

	for item_unique_name: String in items.get_all_ids():
		var candidate_item: ItemData = get_item(item_unique_name)
		if candidate_item != null and candidate_item.item_idx == target_item_idx:
			return candidate_item

	return null


func get_status_effect(unique_name: String) -> StatusEffect:
	return status_effects.get_or_null(unique_name) as StatusEffect


func get_job(unique_name: String) -> JobData:
	return jobs.get_or_null(unique_name) as JobData


func get_skillset(unique_name: String) -> Skillset:
	return skillsets.get_or_null(unique_name) as Skillset


func get_action(unique_name: String) -> Action:
	return actions.get_or_null(unique_name) as Action


func get_triggered_action(unique_name: String) -> TriggeredAction:
	return triggered_actions.get_or_null(unique_name) as TriggeredAction


func get_passive_effect(unique_name: String) -> PassiveEffect:
	return passive_effects.get_or_null(unique_name) as PassiveEffect


func get_ability(unique_name: String) -> Ability:
	return abilities.get_or_null(unique_name) as Ability


func get_scenario(unique_name: String) -> Scenario:
	return scenarios.get_or_null(unique_name) as Scenario


func get_texture(unique_name: String) -> Texture2D:
	return textures.get_or_null(unique_name) as Texture2D


func get_spritesheet_data(unique_name: String) -> UnitSpritesheetData:
	return unit_spritesheets.get_or_null(unique_name) as UnitSpritesheetData


func load_all_data() -> void:
	for registry: DataRegistry in _registries:
		registry.load_all()


func export_resource(resource: Resource, save_path: String = "") -> Error:
	if resource.unique_name.is_empty():
		push_warning("Skipping export of resource with empty unique_name: " + str(resource.FILE_SUFFIX))
		return ERR_INVALID_DATA
	if save_path == "":
		save_path = external_data_paths["EXPORT_PATH"]
	var resource_dir: String = save_path.path_join(resource.SAVE_FOLDER)
	DirAccess.make_dir_recursive_absolute(resource_dir)
	var resource_file_path: String = resource_dir.path_join(resource.unique_name + resource.FILE_SUFFIX)
	var error: Error = ResourceSaver.save(resource, resource_file_path)
	if error != OK:
		push_error("Error saving resource: " + error_string(error) + " - " + resource.unique_name + resource.FILE_SUFFIX)
	return error


static func get_16_color_palette(palette_id: int, full_palette: PackedColorArray) -> PackedColorArray:
	return full_palette.slice(palette_id * 16, (palette_id + 1) * 16)
