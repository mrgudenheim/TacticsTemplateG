extends Node

signal data_imported
signal message(message: String)
signal import_progress(current_value: int, max_value: int)

const DATA_PATH_CONFIG: String = "user://external_data_paths.cfg"
var external_data_paths: Dictionary [String, String] = {
	"IMPORT_PATH" : "",
	"ROM_PATH" : "",
	"EXPORT_PATH" : "",
}

var is_ready: bool = false
var lazy_load_data: bool = true

var shps: Dictionary[String, Shp] = {} # [unique_name (eg. filename without extension), Spr] TODO fill with data
var seqs: Dictionary[String, Seq] = {} # [unique_name (eg. filename without extension), Spr] TODO fill with data
var maps_gltf: Dictionary[String, Node] = {}
var maps_data: Dictionary[String, MapData] = {} # var map_tiles: Dictionary[Vector2i, Array] = {} # Array[TerrainTile], palettes, animations
var map_tile_meshes: Dictionary[TerrainTile.SlopeType, ArrayMesh] = {}
var vfx: Dictionary[String, VisualEffectData] = {}
var shared_vfx_data: TrapEffectData
var projectiles_gltf: Dictionary[String, Node] = {}
var items: Dictionary[String, ItemData] = {} # [unique_name, ItemData]
var status_effects: Dictionary[String, StatusEffect] = {} # [unique_name, StatusEffect]
var jobs_data: Dictionary[String, JobData] = {} # [unique_name, JobData]
var skillsets: Dictionary[String, Skillset] = {}
var actions: Dictionary[String, Action] = {} # [unique_name, Action]
var triggered_actions: Dictionary[String, TriggeredAction] = {} # [unique_name, TriggeredAction]
var passive_effects: Dictionary[String, PassiveEffect] = {} # [unique_name, TriggeredAction]
var abilities: Dictionary[String, Ability] = {} # [unique_name, Ability]
var scenarios: Dictionary[String, Scenario] = {} # [unique_name, Scenario]
var names: Dictionary[String, PackedStringArray] = {} # [name_category, possible names]
var palettes: Dictionary[String, PackedColorArray] = {}
var textures: Dictionary[String, Texture2D] = {}
var unit_spritesheets_data: Dictionary[String, UnitSpritesheetData] = {}
var animation_layer_priorities: PackedVector4Array = []
var initial_unit_data: InitialUnitData

# lazy loading
var shp_paths: Dictionary[String, String] = {}
var seq_paths: Dictionary[String, String] = {}
var map_gltf_paths: Dictionary[String, String] = {}
var map_data_paths: Dictionary[String, String] = {}
var vfx_data_paths: Dictionary[String, String] = {}
var item_paths: Dictionary[String, String] = {}
var status_effect_paths: Dictionary[String, String] = {}
var job_paths: Dictionary[String, String] = {}
var skillset_paths: Dictionary[String, String] = {}
var action_paths: Dictionary[String, String] = {}
var triggered_action_paths: Dictionary[String, String] = {}
var passive_effect_paths: Dictionary[String, String] = {}
var ability_paths: Dictionary[String, String] = {}
var scenario_paths: Dictionary[String, String] = {}
var texture_paths: Dictionary[String, String] = {}
var unit_spritesheet_data_paths: Dictionary[String, String] = {}


func _ready() -> void:
	external_data_paths = _get_saved_data_paths()
	await get_tree().process_frame
	await get_tree().process_frame
	# RomReader.export_tile_meshes("res://src/content_scripts/map/", Vector3(-1.0, 1.0, 1.0))
	if not external_data_paths["IMPORT_PATH"].is_empty() and DirAccess.dir_exists_absolute(external_data_paths["IMPORT_PATH"]):
		call_deferred("import_data", external_data_paths["IMPORT_PATH"])


func _get_saved_data_paths() -> Dictionary [String, String]:
	var file: FileAccess = FileAccess.open(DATA_PATH_CONFIG, FileAccess.READ)
	if file == null:
		var err: Error = FileAccess.get_open_error()
		push_error(err)
		return {
			"IMPORT_PATH" : "",
			"ROM_PATH" : "",
			"EXPORT_PATH" : "",
		}

	var file_text: String = file.get_as_text()
	var untyped_dict : Dictionary = JSON.parse_string(file_text)
	var typed_dict : Dictionary[String, String] = {}
	typed_dict.assign(untyped_dict)
	return typed_dict


func save_data_paths() -> void:
	var json_file: FileAccess = FileAccess.open(DATA_PATH_CONFIG, FileAccess.WRITE)
	json_file.store_line(JSON.stringify(external_data_paths, "\t"))
	json_file.close()


func clear_data() -> void:
	is_ready = false
	shps = {} 
	seqs = {} 
	maps_gltf = {}
	maps_data = {}
	map_tile_meshes = {}
	vfx = {}
	projectiles_gltf = {}
	items = {} 
	status_effects = {} 
	jobs_data = {} 
	actions = {} 
	triggered_actions = {}
	passive_effects = {} 
	abilities = {} 
	scenarios = {} 
	names = {}
	palettes = {}
	textures = {}
	unit_spritesheets_data = {}
	animation_layer_priorities = []
	initial_unit_data = null

	shp_paths.clear()
	seq_paths.clear()
	map_gltf_paths.clear()
	map_data_paths.clear()
	vfx_data_paths.clear()
	item_paths.clear()
	status_effect_paths.clear()
	job_paths.clear()
	skillset_paths.clear()
	action_paths.clear()
	triggered_action_paths.clear()
	passive_effect_paths.clear()
	ability_paths.clear()
	scenario_paths.clear()
	texture_paths.clear()
	unit_spritesheet_data_paths.clear()


func import_data(directory_path: String) -> void:
	clear_data()

	for slope_type: TerrainTile.SlopeType in TerrainTile.SlopeType.values():
		var mesh_name: String = TerrainTile.SlopeType.keys()[slope_type].to_lower()
		var mesh_file_path: String = "res://src/content_scripts/map/tile_mesh_" + mesh_name + ".tres"
		var mesh: ArrayMesh = ResourceLoader.load(mesh_file_path, "ArrayMesh")
		map_tile_meshes[slope_type] = mesh
	
	var start_time: int = Time.get_ticks_msec()

	var file_paths: PackedStringArray = Utilities.get_file_list_recursive(directory_path, false)

	push_warning("Time to find import files (ms): " + str(Time.get_ticks_msec() - start_time))
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
		if current_file == 1 or elapsed_time > (1/60.0):
			message.emit("Importing: " + file_path.get_file())
			await get_tree().process_frame
			last_frame_time = Time.get_ticks_msec()

		var data_type: String = file_path.split(".")[-2]
		
		if file_path.ends_with(".json"):
			#var file_text: String = FileAccess.get_file_as_string(file_path)

			match data_type:
				"action":
					action_paths[file_path.get_file().trim_suffix(".action.json")] = file_path
				"ability":
					ability_paths[file_path.get_file().trim_suffix(".ability.json")] = file_path
					#var new_content: Ability = Ability.create_from_json(file_text)
					#if not abilities.keys().has(new_content.unique_name):
						#abilities[new_content.unique_name] = new_content
				"triggered_action":
					triggered_action_paths[file_path.get_file().trim_suffix(".triggered_action.json")] = file_path
					#var new_content: TriggeredAction = TriggeredAction.create_from_json(file_text)
					#if not triggered_actions.keys().has(new_content.unique_name):
						#triggered_actions[new_content.unique_name] = new_content
				"passive_effect":
					passive_effect_paths[file_path.get_file().trim_suffix(".passive_effect.json")] = file_path
				"item":
					item_paths[file_path.get_file().trim_suffix(".item.json")] = file_path
					#var new_content: ItemData = ItemData.create_from_json(file_text)
					#if not items.keys().has(new_content.unique_name):
						#items[new_content.unique_name] = new_content
				"scenario":
					scenario_paths[file_path.get_file().trim_suffix(".scenario.json")] = file_path
				"job":
					job_paths[file_path.get_file().trim_suffix(".job.json")] = file_path
					#var new_content: JobData = JobData.create_from_json(file_text)
					#if not scenarios.keys().has(new_content.unique_name):
						#jobs_data[new_content.unique_name] = new_content
				"text":
					var file_text: String = FileAccess.get_file_as_string(file_path)
					names["all"] = JSON.parse_string(file_text) as PackedStringArray
					names["all_no_empty"] = names["all"].duplicate()
					for idx: int in range(names["all_no_empty"].size() -1, -1, -1):
						if names["all_no_empty"][idx] == "":
							names["all_no_empty"].remove_at(idx)
		
		elif file_path.ends_with(".status_effect.tres"):
			status_effect_paths[file_path.get_file().trim_suffix(".status_effect.tres")] = file_path
			#var new_status_effect: StatusEffect = ResourceLoader.load(file_path, "StatusEffect")
			#status_effects[new_status_effect.unique_name] = new_status_effect
		elif file_path.ends_with(".skillset.tres"):
			skillset_paths[file_path.get_file().trim_suffix(".skillset.tres")] = file_path
			#var new_skillset: Skillset = ResourceLoader.load(file_path, "Skillset")
			#skillsets[new_skillset.unique_name] = new_skillset
		elif file_path.ends_with(".palette.tres"):
			var new_palette: ColorPalette = ResourceLoader.load(file_path, "ColorPalette")
			palettes[file_path.get_file().trim_suffix(".palette.tres")] = new_palette.colors
		elif file_path.ends_with(".unit_spritesheet.tres"):
			unit_spritesheet_data_paths[file_path.get_file().trim_suffix(".unit_spritesheet.tres")] = file_path
			#var new_spritesheet_data: UnitSpritesheetData = ResourceLoader.load(file_path, "UnitSpritesheetData")
			#unit_spritesheets_data[file_path.get_file().trim_suffix(".unit_spritesheet.tres")] = new_spritesheet_data
		elif file_path.ends_with(".map.glb"):
			map_gltf_paths[file_path.get_file().trim_suffix(".map.glb")] = file_path
			# maps_gltf[file_path.get_file().trim_suffix(".map.glb")] = GltfManager.import_gltf(file_path)
		elif file_path.ends_with(".map_data.tres"):
			map_data_paths[file_path.get_file().trim_suffix(".map_data.tres")] = file_path
			# maps_data[file_path.get_file().trim_suffix(".map_data.tres")] = ResourceLoader.load(file_path, "MapData")
		elif file_path.ends_with(".texture.webp"):
			texture_paths[file_path.get_file().trim_suffix(".texture.webp")] = file_path
			# var new_image: Image = Image.load_from_file(file_path)
			# textures[file_path.get_file().trim_suffix(".texture.webp")] = ImageTexture.create_from_image(new_image)
		elif file_path.to_lower().ends_with(".shp.tres"):
			shp_paths[file_path.get_file().trim_suffix(".shp.tres")] = file_path
			# var new_shp: Shp = ResourceLoader.load(file_path, "Shp")
			# new_shp.is_initialized = true
			# shps[file_path.get_file().trim_suffix(".shp.tres")] = new_shp
		elif file_path.to_lower().ends_with(".seq.tres"):
			seq_paths[file_path.get_file().trim_suffix(".seq.tres")] = file_path
			# var new_seq: Seq = ResourceLoader.load(file_path, "Seq")
			# new_seq.is_initialized = true
			# seqs[file_path.get_file().trim_suffix(".seq.tres")] = new_seq
		elif file_path.ends_with("animation_data.tres"):
			var new_animation_data: AnimationData = ResourceLoader.load(file_path, "AnimationData")
			animation_layer_priorities = new_animation_data.animation_layer_priorities.duplicate()
		elif file_path.to_lower().ends_with(".vfx_data.tres"):
			vfx_data_paths[file_path.get_file().trim_suffix(".vfx_data.tres")] = file_path
			# var new_vfx: VisualEffectData = ResourceLoader.load(file_path, "VisualEffectData")
			# vfx[file_path.get_file().trim_suffix(".vfx_data.tres")] = new_vfx
		elif file_path.to_lower().ends_with("shared_vfx.data.tres"):
			shared_vfx_data = ResourceLoader.load(file_path, "TrapEffectData")
		elif file_path.ends_with(".projectile.glb"):
			projectiles_gltf[file_path.get_file().trim_suffix(".projectile.glb")] = GltfManager.import_gltf(file_path)
		elif file_path.ends_with("initial_unit_data.tres"):
			initial_unit_data = ResourceLoader.load(file_path, "InitialUnitData")

	if lazy_load_data == false:
		load_all_data()

	var import_time: int = Time.get_ticks_msec() - start_time
	print_debug("Time to import files (ms): " + str(import_time))
	push_warning("Time to import files (ms): " + str(import_time))
	is_ready = true
	data_imported.emit()


## Lazy loading functions
func get_shp(unique_name: String) -> Shp:
	if shps.has(unique_name):
		return shps[unique_name]
	
	var file_path: String = shp_paths[unique_name]
	var new_shp: Shp = ResourceLoader.load(file_path, "Shp")
	new_shp.is_initialized = true
	shps[unique_name] = new_shp
	return shps[unique_name]


func get_seq(unique_name: String) -> Seq:
	if seqs.has(unique_name):
		return seqs[unique_name]
	
	var file_path: String = seq_paths[unique_name]
	var new_seq: Seq = ResourceLoader.load(file_path, "Seq")
	new_seq.is_initialized = true
	seqs[unique_name] = new_seq
	return seqs[unique_name]


func get_map_gltf(unique_name: String) -> Node:
	if maps_gltf.has(unique_name):
		return maps_gltf[unique_name]
	
	var file_path: String = map_gltf_paths[unique_name]
	maps_gltf[unique_name] = GltfManager.import_gltf(file_path)
	return maps_gltf[unique_name]


func get_map_data(unique_name: String) -> MapData:
	if maps_data.has(unique_name):
		return maps_data[unique_name]
	
	var file_path: String = map_data_paths[unique_name]
	var new_map_data: MapData = ResourceLoader.load(file_path, "MapData")
	var mesh_instance: MeshInstance3D = get_map_gltf(new_map_data.unique_name).get_child(1)
	new_map_data.mesh = mesh_instance.mesh
	maps_data[unique_name] = new_map_data
	return maps_data[unique_name]


func get_vfx_data(unique_name: String) -> VisualEffectData:
	if vfx.has(unique_name):
		return vfx[unique_name]
	
	var file_path: String = vfx_data_paths[unique_name]
	var new_vfx: VisualEffectData = ResourceLoader.load(file_path, "VisualEffectData")
	new_vfx.texture = get_texture(new_vfx.unique_name)
	vfx[unique_name] = new_vfx
	return vfx[unique_name]


func get_item(unique_name: String) -> ItemData:
	if items.has(unique_name):
		return items[unique_name]
	
	var file_path: String = item_paths[unique_name]
	var file_text: String = FileAccess.get_file_as_string(file_path)
	items[unique_name] = ItemData.create_from_json(file_text)
	return items[unique_name]


func get_status_effect(unique_name: String) -> StatusEffect:
	if status_effects.has(unique_name):
		return status_effects[unique_name]
	
	var file_path: String = status_effect_paths[unique_name]
	status_effects[unique_name] = ResourceLoader.load(file_path, "StatusEffect")
	return status_effects[unique_name]


func get_job(unique_name: String) -> JobData:
	if jobs_data.has(unique_name):
		return jobs_data[unique_name]
	
	var file_path: String = job_paths[unique_name]
	var file_text: String = FileAccess.get_file_as_string(file_path)
	jobs_data[unique_name] = JobData.create_from_json(file_text)
	return jobs_data[unique_name]


func get_skillset(unique_name: String) -> Skillset:
	if skillsets.has(unique_name):
		return skillsets[unique_name]
	
	var file_path: String = skillset_paths[unique_name]
	skillsets[unique_name] = ResourceLoader.load(file_path, "Skillset")
	return skillsets[unique_name]


func get_action(unique_name: String) -> Action:
	if actions.has(unique_name):
		return actions[unique_name]
	
	var file_path: String = action_paths[unique_name]
	var file_text: String = FileAccess.get_file_as_string(file_path)
	var new_action: Action = Action.create_from_json(file_text)
	if new_action.vfx_name != "":
		new_action.vfx_data = get_vfx_data(new_action.vfx_name)
	actions[unique_name] = new_action
	return actions[unique_name]


func get_triggered_action(unique_name: String) -> TriggeredAction:
	if triggered_actions.has(unique_name):
		return triggered_actions[unique_name]
	
	var file_path: String = triggered_action_paths[unique_name]
	var file_text: String = FileAccess.get_file_as_string(file_path)
	triggered_actions[unique_name] = TriggeredAction.create_from_json(file_text)
	return triggered_actions[unique_name]


func get_passive_effect(unique_name: String) -> PassiveEffect:
	if passive_effects.has(unique_name):
		return passive_effects[unique_name]
	
	var file_path: String = passive_effect_paths[unique_name]
	var file_text: String = FileAccess.get_file_as_string(file_path)
	passive_effects[unique_name] = PassiveEffect.create_from_json(file_text)
	return passive_effects[unique_name]


func get_ability(unique_name: String) -> Ability:
	if abilities.has(unique_name):
		return abilities[unique_name]
	
	var file_path: String = ability_paths[unique_name]
	var file_text: String = FileAccess.get_file_as_string(file_path)
	abilities[unique_name] = Ability.create_from_json(file_text)
	return abilities[unique_name]


func get_scenario(unique_name: String) -> Scenario:
	if scenarios.has(unique_name):
		return scenarios[unique_name]
	
	var file_path: String = scenario_paths[unique_name]
	var file_text: String = FileAccess.get_file_as_string(file_path)
	scenarios[unique_name] = Scenario.create_from_json(file_text)
	return scenarios[unique_name]


func get_texture(unique_name: String) -> Texture2D:
	if textures.has(unique_name):
		return textures[unique_name]
	
	var file_path: String = texture_paths[unique_name]
	var new_image: Image = Image.load_from_file(file_path)
	textures[unique_name] = ImageTexture.create_from_image(new_image)
	return textures[unique_name]


func get_spritesheet_data(unique_name: String) -> UnitSpritesheetData:
	if unit_spritesheets_data.has(unique_name):
		return unit_spritesheets_data[unique_name]
	
	var file_path: String = unit_spritesheet_data_paths[unique_name]
	unit_spritesheets_data[unique_name] = ResourceLoader.load(file_path, "UnitSpritesheetData")
	return unit_spritesheets_data[unique_name]


func load_all_data() -> void:
	for file_name: String in shp_paths.keys():
		get_shp(file_name)
	for file_name: String in seq_paths.keys():
		get_seq(file_name)
	for file_name: String in map_gltf_paths.keys():
		get_map_gltf(file_name)
	for file_name: String in map_data_paths.keys():
		get_map_data(file_name)
	for file_name: String in vfx_data_paths.keys():
		get_vfx_data(file_name)
	for file_name: String in item_paths.keys():
		get_item(file_name)
	for file_name: String in status_effect_paths.keys():
		get_status_effect(file_name)
	for file_name: String in job_paths.keys():
		get_job(file_name)
	for file_name: String in skillset_paths.keys():
		get_skillset(file_name)
	for file_name: String in action_paths.keys():
		get_action(file_name)
	for file_name: String in triggered_action_paths.keys():
		get_triggered_action(file_name)
	for file_name: String in passive_effect_paths.keys():
		get_passive_effect(file_name)
	for file_name: String in ability_paths.keys():
		get_ability(file_name)
	for file_name: String in scenario_paths.keys():
		get_scenario(file_name)
	for file_name: String in texture_paths.keys():
		get_texture(file_name)
	for file_name: String in unit_spritesheet_data_paths.keys():
		get_spritesheet_data(file_name)


static func get_16_color_palette(palette_id: int, full_palette: PackedColorArray) -> PackedColorArray:
	return full_palette.slice(palette_id * 16, (palette_id + 1) * 16)
