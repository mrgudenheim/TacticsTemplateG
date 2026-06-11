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
			await get_tree().process_frame
			last_frame_time = Time.get_ticks_msec()

		var data_type: String = file_path.split(".")[-2]
		
		if file_path.ends_with(".json"):
			var file_text: String = FileAccess.get_file_as_string(file_path)

			match data_type:
				"action":
					var new_content: Action = Action.create_from_json(file_text)
					if not actions.keys().has(new_content.unique_name):
						actions[new_content.unique_name] = new_content
				"ability":
					var new_content: Ability = Ability.create_from_json(file_text)
					if not abilities.keys().has(new_content.unique_name):
						abilities[new_content.unique_name] = new_content
				"triggered_action":
					var new_content: TriggeredAction = TriggeredAction.create_from_json(file_text)
					if not triggered_actions.keys().has(new_content.unique_name):
						triggered_actions[new_content.unique_name] = new_content
				"passive_effect":
					var new_content: PassiveEffect = PassiveEffect.create_from_json(file_text)
					if not passive_effects.keys().has(new_content.unique_name):
						passive_effects[new_content.unique_name] = new_content
				# "status_effect":
				# 	var new_content: StatusEffect = StatusEffect.create_from_json(file_text)
				# 	if not status_effects.keys().has(new_content.unique_name):
				# 		status_effects[new_content.unique_name] = new_content
				"item":
					var new_content: ItemData = ItemData.create_from_json(file_text)
					if not items.keys().has(new_content.unique_name):
						items[new_content.unique_name] = new_content
				"scenario":
					var new_content: Scenario = Scenario.create_from_json(file_text)
					if not scenarios.keys().has(new_content.unique_name):
						scenarios[new_content.unique_name] = new_content
				"job":
					var new_content: JobData = JobData.create_from_json(file_text)
					if not scenarios.keys().has(new_content.unique_name):
						jobs_data[new_content.unique_name] = new_content
				"text":
					names["all"] = JSON.parse_string(file_text) as PackedStringArray
					names["all_no_empty"] = names["all"].duplicate()
					for idx: int in range(names["all_no_empty"].size() -1, -1, -1):
						if names["all_no_empty"][idx] == "":
							names["all_no_empty"].remove_at(idx)
		
		elif file_path.ends_with(".status_effect.tres"):
			var new_status_effect: StatusEffect = ResourceLoader.load(file_path, "StatusEffect")
			status_effects[new_status_effect.unique_name] = new_status_effect
		elif file_path.ends_with("skillset.tres"):
			var new_skillset: Skillset = ResourceLoader.load(file_path, "Skillset")
			skillsets[new_skillset.unique_name] = new_skillset
		elif file_path.ends_with(".palette.tres"):
			var new_palette: ColorPalette = ResourceLoader.load(file_path, "ColorPalette")
			palettes[file_path.get_file().trim_suffix(".palette.tres")] = new_palette.colors
		elif file_path.ends_with(".unit_spritesheet.tres"):
			var new_spritesheet_data: UnitSpritesheetData = ResourceLoader.load(file_path, "UnitSpritesheetData")
			unit_spritesheets_data[file_path.get_file().trim_suffix(".unit_spritesheet.tres")] = new_spritesheet_data
		elif file_path.ends_with(".map.glb"):
			maps_gltf[file_path.get_file().trim_suffix(".map.glb")] = GltfManager.import_gltf(file_path)
		elif file_path.ends_with(".map_data.tres"):
			maps_data[file_path.get_file().trim_suffix(".map_data.tres")] = ResourceLoader.load(file_path, "MapData")
		elif file_path.ends_with(".texture.webp"):
			var new_image: Image = Image.load_from_file(file_path)
			textures[file_path.get_file().trim_suffix(".texture.webp")] = ImageTexture.create_from_image(new_image)
		elif file_path.to_lower().ends_with(".shp.tres"):
			var new_shp: Shp = ResourceLoader.load(file_path, "Shp")
			new_shp.is_initialized = true
			shps[file_path.get_file().trim_suffix(".shp.tres")] = new_shp
		elif file_path.to_lower().ends_with(".seq.tres"):
			var new_seq: Seq = ResourceLoader.load(file_path, "Seq")
			new_seq.is_initialized = true
			seqs[file_path.get_file().trim_suffix(".seq.tres")] = new_seq
		elif file_path.ends_with("animation_data.tres"):
			var new_animation_data: AnimationData = ResourceLoader.load(file_path, "AnimationData")
			animation_layer_priorities = new_animation_data.animation_layer_priorities.duplicate()
		elif file_path.to_lower().ends_with(".vfx_data.tres"):
			var new_vfx: VisualEffectData = ResourceLoader.load(file_path, "VisualEffectData")
			vfx[file_path.get_file().trim_suffix(".vfx_data.tres")] = new_vfx
		elif file_path.to_lower().ends_with("shared_vfx.data.tres"):
			shared_vfx_data = ResourceLoader.load(file_path, "TrapEffectData")
		elif file_path.ends_with(".projectile.glb"):
			projectiles_gltf[file_path.get_file().trim_suffix(".projectile.glb")] = GltfManager.import_gltf(file_path)
		elif file_path.ends_with("initial_unit_data.tres"):
			initial_unit_data = ResourceLoader.load(file_path, "InitialUnitData")
	
	for map_data: MapData in maps_data.values():
		var mesh_instance: MeshInstance3D = maps_gltf[map_data.unique_name].get_child(1)
		map_data.mesh = mesh_instance.mesh
	
	for new_vfx: VisualEffectData in vfx.values():
		new_vfx.texture = textures[new_vfx.unique_name]
	
	for new_action: Action in actions.values():
		if new_action.vfx_name != "":
			new_action.vfx_data = vfx[new_action.vfx_name]

	push_warning("Time to import files (ms): " + str(Time.get_ticks_msec() - start_time))
	is_ready = true
	data_imported.emit()


func connect_data_references() -> void:
	# actions have no direct references, stores StatusEffect names in several places
	# for action: Action in actions:
		
	for triggered_action: TriggeredAction in triggered_actions.values():
		if actions.has(triggered_action.action_unique_name):
			triggered_action.action = actions[triggered_action.action_unique_name]

	for status_effect: StatusEffect in status_effects.values():
		if passive_effects.has(status_effect.passive_effect_name):
			status_effect.passive_effect = passive_effects[status_effect.passive_effect_name]
	
	for job_data: JobData in jobs_data.values():
		for passive_effect_name_idx: int in job_data.passive_effect_names.size():
			var passive_effect_name: String = job_data.passive_effect_names[passive_effect_name_idx]
			if passive_effect_name == "" and passive_effects.has(job_data.unique_name):
				passive_effect_name = job_data.unique_name
				job_data.passive_effect_names[passive_effect_name_idx] = passive_effect_name
				job_data.passive_effects.append(passive_effects[passive_effect_name])
			elif passive_effects.has(passive_effect_name):
				job_data.passive_effects.append(passive_effects[passive_effect_name])
			
		
		for innate_ability_id: int in job_data.innate_abilities_ids:
			# var ability_uname: String = fft_abilities[innate_ability_id].display_name.to_snake_case()
			var ability_uname: String = abilities.values()[innate_ability_id].unique_name
			if not job_data.innate_ability_names.has(ability_uname):
				job_data.innate_ability_names.append(ability_uname)

		for ability_name: String in job_data.innate_ability_names:
			if abilities.has(ability_name):
				job_data.innate_abilities.append(abilities[ability_name])

	for ability: Ability in abilities.values():
		if ability.passive_effect_name == "" and passive_effects.has(ability.unique_name):
			ability.passive_effect_name = ability.unique_name
			ability.passive_effect = passive_effects[ability.passive_effect_name]
		elif passive_effects.has(ability.passive_effect_name):
			ability.passive_effect = passive_effects[ability.passive_effect_name]

		for triggered_action_name: String in ability.triggered_actions_names:
			if triggered_actions.has(triggered_action_name):
				ability.triggered_actions.append(triggered_actions[triggered_action_name])
		
		if ability.triggered_actions_names.is_empty():
			if triggered_actions.has(ability.unique_name):
				ability.triggered_actions_names = [ability.unique_name]
				ability.triggered_actions.append(triggered_actions[ability.unique_name])

	for passive_effect: PassiveEffect in passive_effects.values():
		for action_name: String in passive_effect.added_actions_names:
			if actions.has(action_name):
				passive_effect.added_actions.append(actions[action_name])
		for triggered_action_name: String in passive_effect.added_triggered_actions_names:
			if triggered_actions.has(triggered_action_name):
				passive_effect.added_triggered_actions.append(triggered_actions[triggered_action_name])

	for item: ItemData in items.values():
		if passive_effects.has(item.passive_effect_name):
			item.passive_effect = passive_effects[item.passive_effect_name]
		if actions.has(item.weapon_attack_action_name):
			item.weapon_attack_action = actions[item.weapon_attack_action_name]


static func get_16_color_palette(palette_id: int, full_palette: PackedColorArray) -> PackedColorArray:
	return full_palette.slice(palette_id * 16, (palette_id + 1) * 16)


#func get_scenario(unique_name: String) -> Scenario:
	#if _scenarios[unique_name].is_loaded:
		#return _scenarios[unique_name]
	#
	#var data_filepath: String = "user://"
	#var filepath: String = data_filepath + "scenarios/" + unique_name + ".scenario.json"
	#var file_text: String = FileAccess.get_file_as_string(filepath)
	#var new_scenario: Scenario = Scenario.create_from_json(file_text)
	#_scenarios[new_scenario.unique_name] = new_scenario
	#return new_scenario
