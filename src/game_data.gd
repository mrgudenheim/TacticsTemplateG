extends Node

var is_ready: bool = false

var shps: Dictionary[String, Shp] = {} # [unique_name (eg. filename without extension), Spr] TODO fill with data
var seqs: Dictionary[String, Seq] = {} # [unique_name (eg. filename without extension), Spr] TODO fill with data
var maps_gltf: Dictionary[String, Node] = {}
var maps_data: Dictionary[String, FftMapData] = {} # var map_tiles: Dictionary[Vector2i, Array] = {} # Array[TerrainTile], palettes, gradient, animations, traps?, move find item?
var vfx: Array[VisualEffectData] = []
var items: Dictionary[String, ItemData] = {} # [unique_name, ItemData]
var status_effects: Dictionary[String, StatusEffect] = {} # [unique_name, StatusEffect]
var jobs_data: Dictionary[String, JobData] = {} # [unique_name, JobData]
var actions: Dictionary[String, Action] = {} # [unique_name, Action]
var triggered_actions: Dictionary[String, TriggeredAction] = {} # [unique_name, TriggeredAction]
var passive_effects: Dictionary[String, PassiveEffect] = {} # [unique_name, TriggeredAction]
var abilities: Dictionary[String, Ability] = {} # [unique_name, Ability]
var _scenarios: Dictionary[String, Scenario] = {} # [unique_name, Scenario]
var names: Dictionary[String, PackedStringArray] = {} # [name_category, possible names]

# Textures
var unit_spritesheets: Dictionary[String, Texture2D] = {} # [unique_name (eg. filename without extension), Spr] TODO fill with data
var frame_bin_texture: Texture2D
var items_texture: Texture2D


func import_data(directory_path: String) -> void:
	var file_paths: PackedStringArray = Utilities.get_file_list_recursive(directory_path)

	for file_path: String in file_paths:
		var data_type: String = file_path.split(".")[-2]
		
		if file_path.ends_with(".json"):
			var file_text: String = FileAccess.get_file_as_string(file_path)

			match data_type:
				"action":
					var new_content: Action = Action.create_from_json(file_text)
					if not actions.keys().has(new_content.unique_name):
						new_content.add_to_global_list()
				"ability":
					var new_content: Ability = Ability.create_from_json(file_text)
					if not abilities.keys().has(new_content.unique_name):
						new_content.add_to_global_list()
				"triggered_action":
					var new_content: TriggeredAction = TriggeredAction.create_from_json(file_text)
					if not triggered_actions.keys().has(new_content.unique_name):
						new_content.add_to_global_list()
				"passive_effect":
					var new_content: PassiveEffect = PassiveEffect.create_from_json(file_text)
					if not passive_effects.keys().has(new_content.unique_name):
						new_content.add_to_global_list()
				"status_effect":
					var new_content: StatusEffect = StatusEffect.create_from_json(file_text)
					if not status_effects.keys().has(new_content.unique_name):
						new_content.add_to_global_list()
				"item":
					var new_content: ItemData = ItemData.create_from_json(file_text)
					if not items.keys().has(new_content.unique_name): # TODO allow overwriting content
						new_content.add_to_global_list()
				"scenario":
					var file_name: String = ".".join(file_path.get_file().split(".").slice(0, -2))
					var new_content: Scenario = Scenario.lazy_init(file_name)
					if not _scenarios.keys().has(new_content.unique_name): # TODO allow overwriting content
						new_content.add_to_global_list()
				# TODO map_data?
		elif file_path.ends_with(".tres"):
			# TODO import map_tiles?, shp, seq, vfx
			pass
		elif file_path.ends_with(".glb"):
			# TODO import map gltf?
			pass


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


func get_scenario(unique_name: String) -> Scenario:
	if _scenarios[unique_name].is_loaded:
		return _scenarios[unique_name]
	
	var data_filepath: String = "user://"
	var filepath: String = data_filepath + "scenarios/" + unique_name + ".scenario.json"
	var file_text: String = FileAccess.get_file_as_string(filepath)
	var new_scenario: Scenario = Scenario.create_from_json(file_text)
	_scenarios[new_scenario.unique_name] = new_scenario
	return new_scenario