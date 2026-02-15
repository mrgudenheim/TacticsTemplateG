class_name BattleManager
extends Node3D

signal map_input_event(action_instance: ActionInstance, camera: Camera3D, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) # TODO should action_instance be removed from signal?
signal unit_created(new_unit: Unit)

const SCALE: float = 1.0 / MapData.TILE_SIDE_LENGTH
const SCALED_UNITS_PER_HEIGHT: float = SCALE * MapData.UNITS_PER_HEIGHT

# debug vars
@export var use_test_teams: bool = false
@export var texture_viewer: Sprite3D # for debugging
@export var reference_quad: MeshInstance3D # for debugging
@export var highlights_container: Node3D

#static var main_camera: Camera3D
#@export var phantom_camera: PhantomCamera3D
@export var load_rom_button: LoadRomButton

@export var orthographic_check: CheckBox
@export var camera_controller: CameraController
var main_camera: Camera3D
@export var background_gradient: TextureRect

@export var maps: Node3D
var total_map_tiles: Dictionary[Vector2i, Array] = {} # Array[TerrainTile]
var current_tile_hover: TerrainTile # TODO remove? not used, get_tile() used instead?
var current_cursor_map_position: Vector3
@export var tile_highlights: Dictionary[Color, Material] = {}
@export var global_passive_effects: Array[PassiveEffect] = []

@export var battle_view: Node3D
@export var action_menu: Control
@export var action_button_list: BoxContainer
@export var units_container: Node3D
@export var units: Array[Unit] = []
@export var teams: Array[Team] = []
@export var controller: UnitControllerRT
@export var battle_is_running: bool = false
@export var safe_to_load_map: bool = true
@export var battle_end_panel: Control
@export var post_battle_messages: Control
@export var start_new_battle_button: Button
@export var active_unit: Unit
@export var game_state_container: Container
@export var game_state_label: Label

var event_num: int = 0 # TODO handle event timeline

@export var icon_counter: GridContainer

var walled_maps: PackedInt32Array = [
	3,
	4,
	7,
	8,
	10,
	11,
	13,
	14,
	16,
	17,
	18,
	20,
	21,
	24,
	26,
	33,
	39,
	41,
	51,
	52,
	53,
	62,
	65,
	68,
	73,
	92,
	93,
	94,
	95,
	96,
	104,
]

@export var scenario_editor: ScenarioEditor


func _ready() -> void:
	main_camera = camera_controller.camera
	
	load_rom_button.file_selected.connect(RomReader.on_load_rom_dialog_file_selected)
	RomReader.rom_loaded.connect(on_rom_loaded)
	orthographic_check.toggled.connect(camera_controller.on_orthographic_toggled)
	#camera_controller.zoom_changed.connect(update_phantom_camera_spring)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_debug_ui()


func toggle_debug_ui() -> void:
	scenario_editor.visible = not scenario_editor.visible
	if scenario_editor.visible:
		game_state_container.visible = false
		battle_view.reparent(scenario_editor.battle_subviewport)
		
		for unit: Unit in units:
			if not unit.unit_input_event.is_connected(scenario_editor.update_unit_dragging):
				unit.unit_input_event.connect(scenario_editor.update_unit_dragging)
		
		camera_controller.follow_node = null
		controller.unit = null
	else:
		game_state_container.visible = true
		if scenario_editor.tile_highlight != null:
			scenario_editor.tile_highlight.queue_free()
		
		for unit: Unit in units:
			unit.unit_input_event.disconnect(scenario_editor.update_unit_dragging)

		battle_view.reparent(self)

		if active_unit != null:
			camera_controller.follow_node = active_unit.char_body
			controller.unit = active_unit
		else:
			camera_controller.follow_node = null


func on_rom_loaded() -> void:
	push_warning("on rom loaded")
	load_rom_button.visible = false

	scenario_editor.populate_option_lists()
	scenario_editor.visible = true
	if use_test_teams:
		scenario_editor.init_scenario(RomReader.scenarios["test0"])
	else:
		scenario_editor.init_scenario()


func load_scenario(new_scenario: Scenario) -> void:
	background_gradient.texture.gradient.colors[0] = new_scenario.background_gradient_bottom
	background_gradient.texture.gradient.colors[1] = new_scenario.background_gradient_top

	# setup map chunks
	for map_chunk: Scenario.MapChunk in new_scenario.map_chunks:
		load_map_chunk(map_chunk)
	
	update_total_map_tiles(new_scenario.map_chunks)

	for unit_data: UnitData in new_scenario.units_data:
		spawn_unit_from_unit_data(unit_data)


func load_map_chunk(map_chunk: Scenario.MapChunk) -> void:
	var map_chunk_data: MapData = RomReader.maps[map_chunk.unique_name]
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
	# modify mesh based on mirroring and so bottom left corner is at (0, 0, 0)
	# TODO handle rotation
	if map_chunk.mirror_scale != Vector3i.ONE or mesh_aabb.position != Vector3.ZERO:
		var surface_arrays: Array = map_chunk_data.mesh.surface_get_arrays(0)
		var original_mesh_center: Vector3 = mesh_aabb.get_center()
		for vertex_idx: int in surface_arrays[Mesh.ARRAY_VERTEX].size():
			var vertex: Vector3 = surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx]
			vertex = vertex - original_mesh_center # shift center to be at (0, 0, 0) to make moving after mirroring easy
			vertex = vertex * Vector3(map_chunk.mirror_scale) # apply mirroring
			vertex = vertex + (mesh_aabb.size / 2.0) # shift so mesh_aabb start will be at (0, 0, 0)
			
			surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx] = vertex
		
		# var new_array_index: Array = []
		# new_array_index.resize(surface_arrays[Mesh.ARRAY_VERTEX].size())
		# if mirrored along an odd number of axis polygons will render with the wrong facing
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

				# TODO fix ordering of normals for mirrored mesh?
		
		var modified_mesh: ArrayMesh = ArrayMesh.new()
		modified_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		new_map_instance.mesh_instance.mesh = modified_mesh
	else:
		new_map_instance.mesh_instance.mesh = map_chunk_data.mesh

	new_map_instance.set_mesh_shader(map_chunk_data.albedo_texture_indexed, map_chunk_data.texture_palettes)
	new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	
	new_map_instance.play_animations(map_chunk_data)
	new_map_instance.input_event.connect(on_map_input_event)
	new_map_instance.position = map_chunk.corner_position

	maps.add_child(new_map_instance)


func update_total_map_tiles(map_chunks: Array[Scenario.MapChunk]) -> void:
	total_map_tiles.clear()

	for map_chunk: Scenario.MapChunk in map_chunks:
		var map_chunk_data: MapData = RomReader.maps[map_chunk.unique_name]
		if not map_chunk_data.is_initialized:
			continue
		
		var mesh_aabb: AABB = map_chunk_data.mesh.get_aabb()
		
		var map_tile_offset: Vector2i = Vector2i(map_chunk.corner_position.x, map_chunk.corner_position.z)
		for tile: TerrainTile in map_chunk_data.terrain_tiles:
			if tile.no_cursor == 1:
				continue
			
			var total_location: Vector2i = tile.location
			var map_scale: Vector2i = Vector2i(map_chunk.mirror_scale.x, map_chunk.mirror_scale.z)
			total_location = total_location * map_scale
			
			var mirror_shift: Vector2i = Vector2i.ZERO # ex. (0,0) should be (-1, -1) when mirrored across x and y
			if map_scale.x == -1:
				mirror_shift.x = -1
				mirror_shift.x += roundi(mesh_aabb.size.x)
			if map_scale.y == -1:
				mirror_shift.y = -1
				mirror_shift.y += roundi(mesh_aabb.size.z)
			
			var quadrant_shift: Vector2i = Vector2i(roundi(mesh_aabb.position.x) * map_scale.x, roundi(mesh_aabb.position.z) * map_scale.y)
			total_location = total_location + mirror_shift + map_tile_offset - quadrant_shift

			# total_location = total_location + Vector2i(map_chunk.position.x, map_chunk.position.z)
			if not total_map_tiles.has(total_location):
				total_map_tiles[total_location] = []
			var total_tile: TerrainTile = tile.duplicate()
			total_tile.location = total_location
			total_tile.tile_scale.x = map_chunk.mirror_scale.x
			total_tile.tile_scale.z = map_chunk.mirror_scale.z
			total_tile.height_bottom += map_chunk.corner_position.y + roundi(mesh_aabb.end.y / MapData.HEIGHT_SCALE)
			total_tile.height_mid = total_tile.height_bottom + (total_tile.slope_height / 2.0)
			
			# sort tiles by ascending height
			var tile_level: int = total_map_tiles[total_location].bsearch_custom(total_tile, 
				func(tile_a: TerrainTile, tile_b: TerrainTile) -> bool: return tile_a.height_mid > tile_b.height_mid
				)
			total_map_tiles[total_location].insert(tile_level, total_tile)


func update_units_data_tile_location(units_data: Array[UnitData], map_chunk: Scenario.MapChunk) -> Array[UnitData]:
	var map_chunk_data: MapData = RomReader.maps[map_chunk.unique_name]
	var map_tile_offset: Vector2i = Vector2i(map_chunk.corner_position.x, map_chunk.corner_position.z)
	var mesh_aabb: AABB = map_chunk_data.mesh.get_aabb()
	for unit_data: UnitData in units_data:
		var total_location: Vector2i = Vector2i(unit_data.tile_position.x, unit_data.tile_position.z)
		var map_scale: Vector2i = Vector2i(map_chunk.mirror_scale.x, map_chunk.mirror_scale.z)
		total_location = total_location * map_scale
		
		var mirror_shift: Vector2i = Vector2i.ZERO # ex. (0,0) should be (-1, -1) when mirrored across x and y
		if map_scale.x == -1:
			mirror_shift.x = -1
			mirror_shift.x += roundi(mesh_aabb.size.x)
		if map_scale.y == -1:
			mirror_shift.y = -1
			mirror_shift.y += roundi(mesh_aabb.size.z)
		
		var quadrant_shift: Vector2i = Vector2i(roundi(mesh_aabb.position.x) * map_scale.x, roundi(mesh_aabb.position.z) * map_scale.y)
		total_location = total_location + mirror_shift + map_tile_offset - quadrant_shift

		unit_data.tile_position = Vector3i(total_location.x, unit_data.tile_position.y, total_location.y)
	
	return units_data


func start_battle() -> void:
	scenario_editor.visible = false
	if scenario_editor.tile_highlight != null:
		scenario_editor.tile_highlight.queue_free()
	
	for unit: Unit in units:
		unit.unit_input_event.disconnect(scenario_editor.update_unit_dragging)
	
	battle_view.reparent(self)
	# get list of units again; reparenting temporarily removes the unit from the tree and Units auto remove themselves from the Array when they leave the tree
	units.assign(units_container.get_children())
	game_state_container.visible = true
	
	camera_controller.follow_node = units[0].char_body
	controller.unit = units[0]
	#controller.rotate_camera(1) # HACK workaround for bug where controls are off until camera is rotated
	
	if not battle_is_running:
		battle_is_running = true
		process_battle()


#func add_units_to_map() -> void:
	#var team1: Team = Team.new()
	#teams.append(team1)
	#team1.team_name = "Team 1 (Player)"
	#
	#var team2: Team = Team.new()
	#teams.append(team2)
	#team2.team_name = "Team 2 (Computer)"
	#
	##if use_test_teams:
		##add_test_teams_to_map()
	##else: # use random teams
		##var generic_job_ids: Array[int] = []
		##generic_job_ids.assign(range(0x4a, 0x5a)) # generics
		##var special_characters: Array[int] = [
			##0x01, # ramza 1
			##0x04, # ramza 4
			##0x05, # delita 1
			##0x34, # agrias
			##0x11, # gafgorian
			##]
		##
		##var monster_jobs: Array[int] = []
		##monster_jobs.assign(range(0x5e, 0x8e)) # generic monsters
		##var special_monsters: Array[int] = [
			##0x41, # holy angel
			##0x49, # arch angel
			##0x3c, # gigas/warlock (Belias)
			##0x3e, # angel of death
			##0x40, # regulator (Hashmal)
			##0x43, # impure king (quakelin)
			##0x45, # ghost of fury (adremelk)
			##0x97, # serpentarious
			##0x91, # steel giant
			##]
		##
		##var team_1_job_ids: Array[int] = generic_job_ids
		##team_1_job_ids.append_array(special_characters)
		##
		##var team_2_job_ids: Array[int] = monster_jobs
		##team_2_job_ids.append_array(special_monsters)
		##
		##for random_unit: int in units_per_team:
			##var rand_job: int = team_1_job_ids.pick_random()
			##while [0x2c, 0x31].has(rand_job): # prevent jobs without idle frames - 0x2c (Alma2) and 0x31 (Ajora) do not have walking frames
				##rand_job = randi_range(0x01, 0x8d)
			##var new_unit: Unit = spawn_unit(get_random_stand_terrain_tile(), rand_job, team1)
			##new_unit.is_ai_controlled = false
		##
		##for random_unit: int in units_per_team:
			##var rand_job: int = team_2_job_ids.pick_random()
			###var rand_job: int = randi_range(0x5e, 0x8d) # monsters
			##while [0x2c, 0x31].has(rand_job): # prevent jobs without idle frames - 0x2c (Alma2) and 0x31 (Ajora) do not have walking frames
				##rand_job = randi_range(0x01, 0x8d)
			##var new_unit: Unit = spawn_unit(get_random_stand_terrain_tile(), rand_job, team2)
			###new_unit.is_ai_controlled = false
	#
	#await update_units_pathfinding()
	#
	##new_unit.start_turn(self)
	#
	#units.shuffle()
	#
	#hide_debug_ui()


func add_test_teams_to_map() -> void:
	pass
	################## unit 1
	#var spawn_tile: TerrainTile = total_map_tiles[Vector2i(1, 1)][0] # [Vector2i(x, y)][layer]
	#var job_id: int = 0x05 # 0x05 is Delita holy knight
	#var new_unit: Unit = spawn_unit(spawn_tile, job_id, teams[0]) 
	#new_unit.is_ai_controlled = false
	#new_unit.set_primary_weapon(0x1d) # item_id - 0x1d is ice brand
	#
	## add abilities: slot ids 0 - Skillset 1, 1 - skillset 2, 2 - reaction, 3 - support, 4 - movement
	#var ability_unique_name: String = "counter_attack" # usually the psx ability name in snake_case, but some are changed (see RomReader.Abilities after loading ROM for full list, RSM start on page 22)
	## TODO implement skillsets
	#new_unit.equip_ability(new_unit.ability_slots[2], RomReader.abilities[ability_unique_name]) # reaction
	#new_unit.equip_ability(new_unit.ability_slots[3], RomReader.abilities["abandon"]) # support
	#new_unit.equip_ability(new_unit.ability_slots[4], RomReader.abilities["move_get_hp"]) # movement
	#
	#new_unit.generate_raw_stats(Unit.StatBasis.MALE) # StatBasis Options: MALE, FEMALE, OTHER, MONSTER
	#var level: int = 40
	#new_unit.stats[Unit.StatType.LEVEL].set_value(level)
	#new_unit.generate_leveled_stats(level, new_unit.job_data)
	#new_unit.generate_battle_stats(new_unit.job_data)
	#
	#var item_unique_name: String = "ice_brand" # usually the psx item name in snake_case (see RomReader.Items after loading ROM for full list)
	## RH is already set by set_primary_weapon() above
	##new_unit.set_equipment_slot(new_unit.equip_slots[0], RomReader.items[item_unique_name]) # RH
	#new_unit.set_equipment_slot(new_unit.equip_slots[1], RomReader.items["buckler"]) # LH
	#new_unit.set_equipment_slot(new_unit.equip_slots[2], RomReader.items["crystal_helmet"]) # headgear
	#new_unit.set_equipment_slot(new_unit.equip_slots[3], RomReader.items["power_sleeve"]) # body
	#new_unit.set_equipment_slot(new_unit.equip_slots[4], RomReader.items["small_mantle"]) # accessory
	#
	################## unit 2
	#spawn_tile = total_map_tiles[Vector2i(1, 2)][0] # [Vector2i(x, y)][layer]
	#job_id = 0x11 # 0x11 is Gafgorian
	#new_unit = spawn_unit(spawn_tile, job_id, teams[1]) 
	#new_unit.is_ai_controlled = false
	#new_unit.set_primary_weapon(RomReader.items["blood_sword"].item_idx) # item_id
	#
	## TODO implement skillsets
	#new_unit.equip_ability(new_unit.ability_slots[2], RomReader.abilities["pa_save"]) # reaction
	#new_unit.equip_ability(new_unit.ability_slots[3], RomReader.abilities["attack_up"]) # support
	#new_unit.equip_ability(new_unit.ability_slots[4], RomReader.abilities["move+1"]) # movement
	#
	#new_unit.generate_raw_stats(Unit.StatBasis.MALE) # StatBasis Options: MALE, FEMALE, OTHER, MONSTER
	#level = 40
	#new_unit.stats[Unit.StatType.LEVEL].set_value(level)
	#new_unit.generate_leveled_stats(level, new_unit.job_data)
	#new_unit.generate_battle_stats(new_unit.job_data)
	#
	## RH is already set by set_primary_weapon() above
	##new_unit.set_equipment_slot(new_unit.equip_slots[0], RomReader.items["blood_sword"]) # RH
	#new_unit.set_equipment_slot(new_unit.equip_slots[1], RomReader.items["buckler"]) # LH
	#new_unit.set_equipment_slot(new_unit.equip_slots[2], RomReader.items["crystal_helmet"]) # headgear
	#new_unit.set_equipment_slot(new_unit.equip_slots[3], RomReader.items["power_sleeve"]) # body
	#new_unit.set_equipment_slot(new_unit.equip_slots[4], RomReader.items["small_mantle"]) # accessory
	
	# add player unit
	#var random_tile: TerrainTile = get_random_stand_terrain_tile()
	#var new_unit: Unit = spawn_unit(random_tile, 0x05, teams[0]) # 0x05 is Delita holy knight
	#new_unit.is_ai_controlled = false
	#new_unit.set_primary_weapon(0x1d) # ice brand
	
	# var new_ramza: Unit = spawn_unit(get_random_stand_terrain_tile(), 0x01, teams[0])
	
	# add non-player unit
	# var new_unit2: Unit = spawn_unit(get_random_stand_terrain_tile(), 0x07, teams[1]) # 0x07 is Algus
	# new_unit2.set_primary_weapon(0x4e) # crossbow
	
	## set up what to do when target unit is knocked out
	#new_unit2.knocked_out.connect(load_random_map_delay)
	#new_unit2.knocked_out.connect(increment_counter)
	
	#var new_unit3: Unit = spawn_unit(get_random_stand_terrain_tile(), 0x11, teams[1]) # 0x11 is Gafgorian dark knight
	#new_unit3.set_primary_weapon(0x17) # blood sword
	
	#var specific_jobs: PackedInt32Array = [
		##0x65, # grenade
		##0x67, # panther
		##0x76, # juravis
		##0x4a, # squire
		##0x50, # black mage
		##0x53, # thief
		##0x4f, # white mage
		#0x52, # summoner
		##0x51, # time mage
		##0x55, # oracle
		##0x49, # arch angel
		##0x5f, # black chocobo
		##0x64, # bomb
		##0x7b, # wildbow
		##0x87, # dark behemoth
		##0x8D, # tiamat
		#0x99, # archaic demon
		#]
	
	#var generic_jobs: PackedInt32Array = range(0x4a, 0x5d) # all generics
	#var special_jobs: PackedInt32Array = []
	#var standard_monsters: PackedInt32Array = range(0x5e, 0x8e) # all standard monsters
	#var specific_jobs: PackedInt32Array = []
	#specific_jobs.append_array(generic_jobs)
	#specific_jobs.append_array(special_jobs)
	#specific_jobs.append_array(standard_monsters)
	
	#for specific_job: int in specific_jobs:
		#spawn_unit(get_random_stand_terrain_tile(), specific_job, teams[0])
	
	#units[3].set_primary_weapon(0x4a) # blaze gun
	
	#var test_ability: Ability = Ability.new()
	#var test_triggered_action: TriggeredAction = TriggeredAction.new()
	#test_ability.triggered_actions.append(test_triggered_action)
	
	# Move Hp Up
	#test_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.MOVED
	#test_triggered_action.action_unique_name = "regen_heal" # Regen
	#test_triggered_action.trigger_chance_formula.values = [100.0]
	#test_triggered_action.trigger_chance_formula.formula = FormulaData.Formulas.V1
	#test_triggered_action.targeting = TriggeredAction.TargetingTypes.SELF
	#test_triggered_action.display_name = "Move Get HP"
	#test_triggered_action.unique_name = test_triggered_action.display_name.to_snake_case()
	#
	#Utilities.save_json(test_triggered_action)
	# var json_file = FileAccess.open("user://overrides/triggered_actions/move-hp-up.json", FileAccess.WRITE)
	# json_file.store_line(test_triggered_action.to_json())
	# json_file.close()
	
	# Counter Attack
	#test_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.TARGETTED_POST_ACTION
	#test_triggered_action.action_unique_name = "ATTACK" # primary attack special case
	#test_triggered_action.trigger_chance_formula.values = [1.0]
	#test_triggered_action.trigger_chance_formula.formula = FormulaData.Formulas.BRAVExV1
	#test_triggered_action.targeting = TriggeredAction.TargetingTypes.INITIATOR
	#test_triggered_action.display_name = "attack"
	#test_triggered_action.unique_name = test_triggered_action.display_name.to_snake_case()
	#
	#Utilities.save_json(test_triggered_action)
	# json_file = FileAccess.open("user://overrides/triggered_actions/counter.json", FileAccess.WRITE)
	# json_file.store_line(test_triggered_action.to_json())
	# json_file.close()
	
	# Test Trigger
	#test_triggered_action.trigger = TriggeredAction.TriggerTiming.TARGETTED_POST_ACTION
	#test_triggered_action.action_idx = -1 # primary attack special case
	#test_triggered_action.trigger_chance_formula.values = [1.0]
	#test_triggered_action.trigger_chance_formula.formula = FormulaData.Formulas.BRAVExV1
	#test_triggered_action.user_stat_thresholds = { Unit.StatType.HP : 5 }
	#test_triggered_action.targeting = TriggeredAction.TargetingTypes.INITIATOR
	#test_triggered_action.name = "Test Trigger"
	#
	#json_file = FileAccess.open("user://overrides/test_trigger.json", FileAccess.WRITE)
	#json_file.store_line(test_triggered_action.to_json())
	#json_file.close()
	
	# var json_file = FileAccess.open("user://overrides/triggered_actions/test_trigger.json", FileAccess.READ)
	# var json_text: String = json_file.get_as_text()
	# test_triggered_action = TriggeredAction.create_from_json(json_text)
	# test_ability.triggered_actions = [test_triggered_action]
	
	#test_ability.triggered_actions_names.append("attack")
	# test_ability.triggered_actions_names.append("regen_heal")
	#test_ability.display_name = "Counter Attack"
	#test_ability.unique_name = "counter"
	#Utilities.save_json(test_ability)


	#var csv_row = test_triggered_action.to_csv_row()
	#
	#json_file = FileAccess.open("user://overrides/triggered_actions/triggered_actions_db.txt", FileAccess.WRITE)
	#json_file.store_line(test_triggered_action.get_csv_headers())
	#json_file.store_line(csv_row)
	#json_file.close()
	
	#for unit in units:
		## unit.equip_ability(unit.ability_slots[4], test_ability)
		#unit.is_ai_controlled = false


func spawn_random_unit(team: Team) -> Unit:
	var rand_job: int = range(1, RomReader.jobs_data.size()).pick_random()
	while [0x2c, 0x31].has(rand_job): # prevent jobs without idle frames - 0x2c (Alma2) and 0x31 (Ajora) do not have walking frames
		rand_job = randi_range(0x01, 0x8d)
	var tile_location: TerrainTile = get_random_stand_terrain_tile()
	var new_unit: Unit = spawn_unit(tile_location, rand_job, team)
	new_unit.is_ai_controlled = false
	
	unit_created.emit(new_unit)
	return new_unit


func spawn_unit(tile_position: TerrainTile, job_id: int, team: Team, level: int = 40) -> Unit:
	var new_unit: Unit = Unit.instantiate()
	units_container.add_child(new_unit)
	new_unit.global_battle_manager = self
	units.append(new_unit)
	new_unit.initialize_unit()
	new_unit.tile_position = tile_position
	#new_unit.char_body.global_position = Vector3(tile_position.location.x + 0.5, randi_range(15, 20), tile_position.location.y + 0.5)
	new_unit.char_body.global_position = Vector3(tile_position.location.x + 0.5, tile_position.get_world_position().y + 0.25, tile_position.location.y + 0.5)
	if job_id < 0x5e: # non-monster
		new_unit.stat_basis = [Unit.StatBasis.MALE, Unit.StatBasis.FEMALE].pick_random()
	else:
		new_unit.stat_basis = Unit.StatBasis.MONSTER
	new_unit.set_job_id(job_id)
	if range(0x4a, 0x5e).has(job_id):
		new_unit.set_sprite_palette(range(0,5).pick_random())
	new_unit.update_unit_facing([Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT].pick_random())
	new_unit.stats[Unit.StatType.LEVEL].set_value(level)
	Unit.generate_leveled_raw_stats(new_unit.stat_basis, level, new_unit.job_data, new_unit.stats_raw)
	
	var use_higher_stat_values: bool = false
	if ["RUKA.SEQ", "KANZEN.SEQ", "ARUTE.SEQ"].has(new_unit.animation_manager.global_seq.file_name): # lucavi
		use_higher_stat_values = true
	Unit.calc_battle_stats(new_unit.job_data, new_unit.stats_raw, new_unit.stats, true, use_higher_stat_values)
	
	camera_controller.rotated.connect(new_unit.char_body.set_rotation_degrees) # have sprite update as camera rotates
	new_unit.char_body.set_rotation_degrees(Vector3(0, camera_controller.rotation_degrees.y, 0))
	new_unit.update_animation_facing(camera_controller.camera_facing_vector)
	
	new_unit.update_stat_bars_scale(camera_controller.zoom)
	camera_controller.zoom_changed.connect(new_unit.update_stat_bars_scale)
	
	new_unit.icon.texture = RomReader.frame_bin_texture # TODO clean up status icon stuff
	new_unit.icon2.texture = RomReader.frame_bin_texture
	
	new_unit.generate_random_abilities()
	new_unit.primary_weapon_assigned.connect(func(_weapon_unique_name: String) -> void: new_unit.update_actions(self))
	new_unit.generate_equipment()
	#var unit_actions: Array[Action] = new_unit.get_skillset_actions()
	#if unit_actions.any(func(action: Action): return not action.required_equipment_type.is_empty()):
		#while not unit_actions.any(func(action: Action): return action.required_equipment_type.has(new_unit.primary_weapon.item_type)):
			#new_unit.set_primary_weapon(randi_range(0, 0x79)) # random weapon
	
	new_unit.name = new_unit.job_nickname + "-" + new_unit.unit_nickname
	
	new_unit.team_id = teams.find(team)
	new_unit.team = team
	team.units.append(new_unit)
	
	new_unit.is_ai_controlled = true
	new_unit.ai_controller.strategy = UnitAi.Strategy.BEST

	new_unit.unit_battle_details_ui.setup(new_unit)
	new_unit.unit_input_event.connect(scenario_editor.update_unit_dragging)
	
	return new_unit


func spawn_unit_from_unit_data(unit_data: UnitData) -> Unit:
	var new_unit: Unit = Unit.instantiate()
	units_container.add_child(new_unit)
	new_unit.global_battle_manager = self
	units.append(new_unit)
	new_unit.initialize_unit()

	var xz_index: int = total_map_tiles.keys().find(Vector2i(unit_data.tile_position.x, unit_data.tile_position.z))
	if xz_index >= 0:
		new_unit.tile_position = total_map_tiles.values()[xz_index][unit_data.tile_position.y]
	else:
		new_unit.tile_position = total_map_tiles.values()[0][0]
	# for tile_array: Array in total_map_tiles.values():
	# 	var xz_tiles: Array[TerrainTile] = []
	# 	xz_tiles.assign(tile_array)
	# 	for tile: TerrainTile in xz_tiles:
	# 		if tile.get_world_position() == unit_data.tile_position:
	# 			new_unit.tile_position = tile
	# 			break
	# 	if new_unit.tile_position != null:
	# 		break
	# if new_unit.tile_position == null: # default to first tile
	# 	new_unit.tile_position = total_map_tiles.values()[0][0]

	new_unit.set_position_to_tile()
	# new_unit.update_unit_facing(Unit.FacingVectors[Unit.Facings[unit_data.facing_direction]])
	new_unit.set_job_id(RomReader.jobs_data[unit_data.job_unique_name].job_id)
	new_unit.set_sprite_by_file_name(unit_data.spritesheeet_file_name)
	new_unit.set_sprite_palette(unit_data.palette_id)
	new_unit.update_unit_facing(Unit.FacingVectors[unit_data.facing_direction])
	# new_unit.gender = Unit.Gender[unit_data.gender]
	new_unit.gender = unit_data.gender
	new_unit.level = unit_data.level
	new_unit.stats_raw = unit_data.stats_raw
	new_unit.stats = unit_data.stats

	new_unit.stats[Unit.StatType.HP].value_changed.connect(new_unit.hp_changed)
	var stat_bars: Array[StatBar] = []
	stat_bars.assign(new_unit.stat_bars_container.get_children())
	stat_bars[0].set_stat(str(Unit.StatType.keys()[Unit.StatType.HP]), new_unit.stats[Unit.StatType.HP])
	stat_bars[1].set_stat(str(Unit.StatType.keys()[Unit.StatType.MP]), new_unit.stats[Unit.StatType.MP])
	stat_bars[2].set_stat(str(Unit.StatType.keys()[Unit.StatType.CT]), new_unit.stats[Unit.StatType.CT])
	
	camera_controller.rotated.connect(new_unit.char_body.set_rotation_degrees) # have sprite update as camera rotates
	new_unit.char_body.set_rotation_degrees(Vector3(0, camera_controller.rotation_degrees.y, 0))
	new_unit.update_animation_facing(camera_controller.camera_facing_vector)
	
	new_unit.update_stat_bars_scale(camera_controller.zoom)
	camera_controller.zoom_changed.connect(new_unit.update_stat_bars_scale)
	
	new_unit.icon.texture = RomReader.frame_bin_texture # TODO clean up status icon stuff
	new_unit.icon2.texture = RomReader.frame_bin_texture
	
	new_unit.ability_slots = unit_data.ability_slots
	new_unit.primary_weapon_assigned.connect(func(_weapon_unique_name: String) -> void: new_unit.update_actions(self))
	new_unit.equip_slots = unit_data.equip_slots
	new_unit.set_primary_weapon(unit_data.equip_slots[0].item_unique_name)
	#var unit_actions: Array[Action] = new_unit.get_skillset_actions()
	#if unit_actions.any(func(action: Action): return not action.required_equipment_type.is_empty()):
		#while not unit_actions.any(func(action: Action): return action.required_equipment_type.has(new_unit.primary_weapon.item_type)):
			#new_unit.set_primary_weapon(randi_range(0, 0x79)) # random weapon
	
	new_unit.unit_nickname = unit_data.display_name
	new_unit.name = new_unit.job_nickname + "-" + new_unit.unit_nickname
	
	if teams.size() < unit_data.team_idx + 1:
		teams.resize(unit_data.team_idx + 1)
	
	if teams[unit_data.team_idx] == null:
		var new_team: Team = Team.new()
		new_team.team_name = "Team" + str(unit_data.team_idx + 1)
		teams[unit_data.team_idx] = new_team

	new_unit.team = teams[unit_data.team_idx]
	new_unit.team_id = unit_data.team_idx
	new_unit.team.units.append(new_unit)
	
	new_unit.is_ai_controlled = true if unit_data.controller == 0 else false
	new_unit.ai_controller.strategy = UnitAi.Strategy.BEST

	new_unit.update_passive_effects()
	new_unit.unit_battle_details_ui.setup(new_unit)
	new_unit.unit_input_event.connect(scenario_editor.update_unit_dragging)
	
	return new_unit


func update_units_pathfinding() -> void:
	#for unit: Unit in units:
		#var max_move_cost: int = 9999
		#if unit != active_unit:
			#max_move_cost = unit.move_current # stop pathfinding early for non-active units, only need potential move targets, not path to every possible tile
		#
		#await unit.update_map_paths(total_map_tiles, units, max_move_cost)
	pass


func process_battle() -> void:
	while battle_is_running:
		await process_clock_tick()
		
		# TODO check end conditions, switching map, etc.
	
	for team: Team in teams:
		if team.state == Team.State.WON:
			battle_end_panel.visible = true
			var end_condition_title: Label = Label.new()
			end_condition_title.text = team.team_name + " Won!"
			end_condition_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			post_battle_messages.add_child(end_condition_title)
			for end_condition: EndCondition in team.end_conditions.keys():
				if team.end_conditions[end_condition] == true and end_condition.end_type == EndCondition.EndType.WIN:
					var end_condition_message: Label = Label.new()
					end_condition_message.text = end_condition.post_battle_message
					post_battle_messages.add_child(end_condition_message)


# TODO implement action timeline
func process_clock_tick() -> void:
	game_state_label.text = "processing new clock tick"
	
	# increment status ticks
	for unit: Unit in units:
		var statuses_to_remove: Array[StatusEffect] = []
		for status: StatusEffect in unit.current_statuses:
			safe_to_load_map = false
			if status.duration_type == StatusEffect.DurationType.TICKS:
				status.duration -= 1
				if status.duration <= 0:
					#unit.current_statuses.erase(status)
					statuses_to_remove.append(status)
					if status.action_on_complete != "": # process potential removal if ticks_left == 0
						var status_action_instance: ActionInstance = ActionInstance.new(RomReader.actions[status.action_on_complete], unit, self)
						status_action_instance.submitted_targets.append(unit.tile_position) # TODO get targets for status action
						# RomReader.actions[status.action_on_complete].use(status_action_instance)
						camera_controller.follow_node = unit.char_body
						game_state_label.text = unit.job_nickname + "-" + unit.unit_nickname + " processing " + status.status_effect_name + " ending"
						await status_action_instance.use()
						# await status_action_instance.action_completed
						if check_end_conditions():
							safe_to_load_map = true
							return
					if status.delayed_action != null: # execute stored delayed actions, TODO checks to null (no mp, silenced, etc.)
						#status.delayed_action.show_targets_highlights(status.delayed_action.preview_targets_highlights) # show submitted targets TODO retain preview highlight nodes?
						#await unit.get_tree().create_timer(0.5).timeout
						camera_controller.follow_node = unit.char_body
						game_state_label.text = unit.job_nickname + "-" + unit.unit_nickname + " processing delayed " + status.delayed_action.action.display_name
						await status.delayed_action.use()
						#await status.delayed_action.action_completed
						if check_end_conditions():
							safe_to_load_map = true
							return
			safe_to_load_map = true
			await get_tree().process_frame
		for status: StatusEffect in statuses_to_remove:
			unit.remove_status(status)
	
	for unit: Unit in units: # increment each units ct by speed
		if not unit.current_statuses.any(func(status: StatusEffect) -> bool: return status.freezes_ct): # check status that prevent ct gain (stop, sleep, etc.)
			var ct_gain: int = unit.speed
			for status: StatusEffect in unit.current_statuses:
				ct_gain = status.passive_effect.ct_gain_modifier.apply(ct_gain)
			unit.stats[Unit.StatType.CT].add_value(ct_gain) 
	
	# execute unit turns, ties decided by unit index in units[]
	# TODO keep looping until all units ct_current < 100
	for unit: Unit in units:
		if unit.ct_current >= 100:
			safe_to_load_map = false
			await start_units_turn(unit)
			#if unit.is_defeated: # check status that counts as KO, aka prevents turn (dead, petrify, etc.)
				#unit.end_turn()
			if not unit.is_defeated:
				if not unit.is_ai_controlled:
					safe_to_load_map = true
				while not unit.is_ending_turn:
					await get_tree().process_frame
					if unit == null: # prevent error when loading map
						return
				if check_end_conditions():
					safe_to_load_map = true
					return
			safe_to_load_map = true
			await get_tree().process_frame
	
	# TODO increment status ticks, delayed action ticks, and unit ticks in the same step, then order resolution?


func check_end_conditions() -> bool:
	for team: Team in teams:
		team.check_end_conditions(self)
	
	if teams.any(func(team: Team) -> bool: return team.state == Team.State.WON):
		battle_is_running = false
		return true
	
	return false


func start_units_turn(unit: Unit) -> void:
	controller.unit = unit
	active_unit = unit
	
	if not unit.is_defeated:
		camera_controller.follow_node = unit.char_body
	
	await unit.start_turn(self)


# TODO handle event timeline
#func process_next_event() -> void:
	#event_num = (event_num + 1) % units.size()
	#var new_unit: Unit = units[event_num]
	#controller.unit = new_unit
	#phantom_camera.follow_target = new_unit.char_body
	#
	#new_unit.start_turn(self)


func get_map(new_map_data: MapData, map_position: Vector3, map_scale: Vector3, gltf_map_mesh: MeshInstance3D = null) -> MapChunkNodes:
	map_scale.y = -1 # vanilla used -y as up
	var new_map_instance: MapChunkNodes = MapChunkNodes.instantiate()
	new_map_instance.map_data = new_map_data
	
	if gltf_map_mesh != null:
		new_map_instance.mesh_instance.queue_free()
		var new_gltf_mesh: MeshInstance3D = gltf_map_mesh.duplicate()
		new_map_instance.add_child(new_gltf_mesh)
		new_map_instance.mesh_instance = new_gltf_mesh
		new_map_instance.mesh_instance.rotation_degrees = Vector3.ZERO
	else:
		new_map_instance.mesh_instance.mesh = new_map_data.mesh
	new_map_instance.mesh_instance.scale = map_scale
	new_map_instance.position = map_position
	#new_map_instance.global_rotation_degrees = Vector3(0, 0, 0)
	
	new_map_instance.set_mesh_shader(new_map_data.albedo_texture_indexed, new_map_data.texture_palettes)
	
	#var shape_mesh: ConcavePolygonShape3D = new_map_data.mesh.create_trimesh_shape()
	if map_scale == Vector3.ONE:
		new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	else:
		new_map_instance.collision_shape.shape = get_scaled_collision_shape(new_map_instance.mesh_instance.mesh, map_scale)
	
	new_map_instance.play_animations(new_map_data)
	new_map_instance.input_event.connect(on_map_input_event)
	
	return new_map_instance


func get_scaled_collision_shape(mesh: Mesh, collision_scale: Vector3) -> ConcavePolygonShape3D:
	var new_collision_shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	var faces: PackedVector3Array = new_collision_shape.get_faces()
	for i: int in faces.size():
		faces[i] = faces[i] * collision_scale
	
	#push_warning(faces)
	new_collision_shape.set_faces(faces)
	new_collision_shape.backface_collision = true
	return new_collision_shape


func initialize_map_tiles() -> void:
	total_map_tiles.clear()
	var map_chunks: Array[MapChunkNodes] = []
	
	for map_holder: Node3D in maps.get_children():
		for map_chunk: MapChunkNodes in map_holder.get_children() as Array[MapChunkNodes]:
			map_chunks.append(map_chunk)
	
	for map_chunk: MapChunkNodes in map_chunks:
		for tile: TerrainTile in map_chunk.map_data.terrain_tiles:
			if tile.no_cursor == 1:
				continue
			
			var total_location: Vector2i = tile.location
			var map_scale: Vector2i = Vector2i(roundi(map_chunk.mesh_instance.scale.x), roundi(map_chunk.mesh_instance.scale.z))
			total_location = total_location * map_scale
			var mirror_shift: Vector2i = map_scale # ex. (0,0) should be (-1, -1) when mirrored across x and y
			if map_scale.x == 1:
				mirror_shift.x = 0
			if map_scale.y == 1:
				mirror_shift.y = 0
			total_location = total_location + mirror_shift
			total_location = total_location + Vector2i(roundi(map_chunk.position.x), roundi(map_chunk.position.z))
			if not total_map_tiles.has(total_location):
				total_map_tiles[total_location] = []
			var total_tile: TerrainTile = tile.duplicate()
			total_tile.location = total_location
			total_tile.tile_scale.x = map_chunk.mesh_instance.scale.x
			total_tile.tile_scale.z = map_chunk.mesh_instance.scale.z
			total_tile.height_bottom += roundi(map_chunk.position.y / MapData.HEIGHT_SCALE)
			total_tile.height_mid = total_tile.height_bottom + (total_tile.slope_height / 2.0)
			total_map_tiles[total_location].append(total_tile)


func get_random_terrain_tile() -> TerrainTile:
	if total_map_tiles.size() == 0:
		push_warning("No map tiles")
	
	var random_key: Vector2i = total_map_tiles.keys().pick_random()
	var tiles: Array = total_map_tiles[random_key]
	var tile: TerrainTile = tiles.pick_random()
	
	return tile


func get_random_stand_terrain_tile() -> TerrainTile:
	var tile: TerrainTile
	for tile_idx: int in total_map_tiles.size():
		tile = get_random_terrain_tile()
		if tile.no_stand_select != 0 or tile.no_walk != 0:
			continue
		
		if units.any(func(unit: Unit) -> bool: return unit.tile_position == tile):
			continue
		
		break
	
	return tile


func clear_maps() -> void:
	total_map_tiles.clear()
	for child: Node in maps.get_children():
		child.queue_free()
		maps.remove_child(child)


func clear_units() -> void:
	for unit: Unit in units:
		unit.queue_free()
	
	units.clear()
	#for child: Node in units_container.get_children():
		#child.queue_free()


func increment_counter(unit: Unit) -> void:
	var knocked_out_icon: Image = unit.animation_manager.global_shp.get_assembled_frame(0x17, unit.animation_manager.global_spr.spritesheet, 0, 0, 0, 0)
	knocked_out_icon = knocked_out_icon.get_region(Rect2i(40, 50, 40, 40))
	
	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.texture = ImageTexture.create_from_image(knocked_out_icon)
	icon_counter.add_child(icon_rect)


func on_map_input_event(camera: Camera3D, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) -> void:
	current_cursor_map_position = event_position
	current_tile_hover = get_tile(event_position)
	
	map_input_event.emit(camera, event, event_position, normal, shape_idx)


func get_tile(input_position: Vector3) -> TerrainTile:
	var tile_location: Vector2i = Vector2i(floor(input_position.x), floor(input_position.z))
	var tile: TerrainTile = null
	if total_map_tiles.has(tile_location):
		var current_vert_error: float = 999.9
		for new_tile: TerrainTile in total_map_tiles[tile_location]:
			if tile == null:
				tile = new_tile
				current_vert_error = abs(((new_tile.height_mid + new_tile.depth) * MapData.HEIGHT_SCALE) - input_position.y)
			else:
				var new_vert_error: float = abs(((new_tile.height_mid + new_tile.depth) * MapData.HEIGHT_SCALE) - input_position.y)
				if new_vert_error < current_vert_error:
					current_vert_error = new_vert_error
					tile = new_tile
	
	return tile
