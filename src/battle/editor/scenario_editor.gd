class_name ScenarioEditor
extends Control

@export var scenario: Scenario = Scenario.new()

@export var battle_manager: BattleManager
@export var start_button: Button
@export var load_scenario_button: OptionButton
@export var export_scenario_button: Button
@export var import_scenario_button: Button
@export var import_file_dialog: FileDialog
@export var new_scenario_button: Button

@export var background_gradient_color_pickers: Array[ColorPickerButton]
@export var background_gradient_colors: PackedColorArray = []

@export var battle_subviewport: SubViewport
@export var battle_setup_container: TabContainer
@export var team_setups: Array[TeamSetup]
@export var team_setup_scene: PackedScene

@export var job_select_control: JobSelectControl
@export var item_select_control: ItemSelectControl
@export var ability_select_control: AbilitySelectControl

@export var unit_dragged: Unit
@export var tile_highlight: Node3D
@export var unit_editor: UnitEditor

@export var add_map_chunk_button: Button
@export var map_chunk_settings_container: GridContainer
@export var map_chunk_settings_list: Array[MapChunkSettingsUi]
@export var show_map_tiles_check: CheckBox
@export var map_tile_highlights: Array[Node3D] = []

func _process(_delta: float) -> void:
	if unit_dragged != null:
		unit_dragged.char_body.position = battle_manager.current_cursor_map_position + Vector3(0, 0.25, 0)
		
		var cursor_tile: TerrainTile = battle_manager.current_tile_hover
		if tile_highlight != null:
			if cursor_tile == null:
				return
			
			var tile_highlight_pos: Vector3 = tile_highlight.global_position - Vector3(0, 0.025, 0)
			if tile_highlight_pos == cursor_tile.get_world_position(true): # do nothing if tile has not changed
				return
			tile_highlight.queue_free()
		
		var highlight_color: Color = Color.WHITE
		var can_end_on_tile: bool = (cursor_tile.no_walk == 0 
				and cursor_tile.no_stand_select == 0 
				and cursor_tile.no_cursor == 0
				and not unit_dragged.prohibited_terrain.has(cursor_tile.surface_type_id)) # lava, etc.
		if can_end_on_tile:
			highlight_color = Color.BLUE
			
		var new_tile_highlight: MeshInstance3D = cursor_tile.get_tile_mesh()
		new_tile_highlight.material_override = battle_manager.tile_highlights[highlight_color] # use pre-existing materials
		add_child(new_tile_highlight)
		tile_highlight = new_tile_highlight
		new_tile_highlight.position = cursor_tile.get_world_position(true) + Vector3(0, 0.025, 0)


func _ready() -> void:
	add_map_chunk_button.pressed.connect(add_map_chunk_settings)
	for color_picker: ColorPickerButton in background_gradient_color_pickers:
		background_gradient_colors.append(color_picker.color)
		color_picker.color_changed.connect(update_background_gradient)
	
	start_button.pressed.connect(battle_manager.start_battle)
	show_map_tiles_check.toggled.connect(show_all_tiles)
	export_scenario_button.pressed.connect(export_scenario)
	import_scenario_button.pressed.connect(open_import_dialong)
	import_file_dialog.file_selected.connect(import_scenario)
	new_scenario_button.pressed.connect(queue_new_scenario)
	load_scenario_button.item_selected.connect(load_scenario) 


func load_scenario(dropdown_idx: int) -> void:
	var scenario_to_load: Scenario = RomReader.scenarios[load_scenario_button.get_item_text(dropdown_idx)].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	scenario_to_load.unique_name = scenario_to_load.unique_name + "_new"
	# update mirror_scale for duplicated map chunks
	for map_chunk: Scenario.MapChunk in scenario_to_load.map_chunks:
		map_chunk.set_mirror_xyz(map_chunk.mirror_xyz)
	
	queue_new_scenario(scenario_to_load)


func queue_new_scenario(new_scenario: Scenario = null) -> void:
	if battle_manager.battle_is_running:
		while not battle_manager.safe_to_load_map:
			await get_tree().process_frame # TODO loop over safe_to_load_new_map, set false while awaiting processing
	
	init_scenario(new_scenario)


func init_scenario(new_scenario: Scenario = null) -> void:
	battle_manager.battle_is_running = false

	remove_all_teams()
	if tile_highlight != null:
		tile_highlight.queue_free()

	# remove current map chunks
	for map_chunk_settings_instance: MapChunkSettingsUi in map_chunk_settings_list:
		map_chunk_settings_instance.queue_free()
	
	load_scenario_button.clear()
	load_scenario_button.add_separator("Load Scenario")
	for scenario_unique_name: String in RomReader.scenarios.keys():
		load_scenario_button.add_item(scenario_unique_name)
	load_scenario_button.select(0)
	
	if new_scenario != null:
		scenario = new_scenario
		
		background_gradient_color_pickers[0].color = scenario.background_gradient_bottom
		background_gradient_color_pickers[1].color = scenario.background_gradient_top
		update_background_gradient()

		for map_chunk: Scenario.MapChunk in scenario.map_chunks:
			add_map_chunk_settings(map_chunk)
		battle_manager.update_total_map_tiles(scenario.map_chunks)

		if scenario.is_fft_scenario:
			battle_manager.update_units_data_tile_location(scenario.units_data, scenario.map_chunks[0])
			scenario.is_fft_scenario = false

		for unit_data: UnitData in scenario.units_data:
			battle_manager.spawn_unit_from_unit_data(unit_data)
		
		for team_idx: int in battle_manager.teams.size():
			if battle_manager.teams[team_idx] == null:
				var new_team: Team = Team.new()
				new_team.team_name = "Team" + str(team_idx + 1)
				battle_manager.teams[team_idx] = new_team

			add_team(battle_manager.teams[team_idx])
	else:
		var number: int = 1
		var new_scenario_num: String = scenario.unique_name.get_slice("new_scenario_", 1)
		if new_scenario_num.is_valid_int():
			number = int(new_scenario_num) + 1
			
		scenario.unique_name = "new_scenario_%02d" % number
		while RomReader.scenarios.keys().has(scenario.unique_name):
			number += 1
			scenario.unique_name = "new_scenario_%02d" % number
		init_random_scenario()

	await get_tree().process_frame
	var first_unit: Unit = battle_manager.units[0]
	for unit_idx: int in battle_manager.units.size():
		if not battle_manager.units[unit_idx].is_queued_for_deletion():
			first_unit = battle_manager.units[unit_idx]
			break

	unit_editor.setup(first_unit) # default to first unit
	var unit_tile: TerrainTile = first_unit.tile_position
	tile_highlight = get_new_tile_highlight(unit_tile, Color.BLUE)


func init_random_scenario() -> void:
	remove_all_teams()
	
	add_map_chunk_settings()
	var map_chunk_data: MapData = RomReader.maps[scenario.map_chunks[0].unique_name]
	background_gradient_color_pickers[0].color = map_chunk_data.background_gradient_bottom
	background_gradient_color_pickers[1].color = map_chunk_data.background_gradient_top
	update_background_gradient()

	for team_num: int in 2:
		var new_team: Team = Team.new()
		battle_manager.teams.append(new_team)
		new_team.team_name = "Team" + str(team_num + 1)
		
		add_team(new_team, true)


func populate_option_lists() -> void:
	job_select_control.populate_list()
	item_select_control.populate_list()
	ability_select_control.populate_list()


func setup_job_select(unit: Unit) -> void:
	job_select_control.visible = true
	for job_select_button: JobSelectButton in job_select_control.job_select_buttons:
		job_select_button.selected.connect(func(new_job: JobData) -> void: update_unit_job(unit, new_job))


func desetup_job_select() -> void:
	job_select_control.visible = false
	for job_select_button: JobSelectButton in job_select_control.job_select_buttons:
		Utilities.disconnect_all_connections(job_select_button.selected)


func setup_item_select(unit: Unit, slot: EquipmentSlot) -> void:
	item_select_control.visible = true
	for item_select_button: ItemSelectButton in item_select_control.item_select_buttons:
		if item_select_button.sprite_rect.texture.atlas == null:
			item_select_button.sprite_rect.texture.atlas = RomReader.item_bin_texture
			var item_graphic_id: int = item_select_button.item_data.item_graphic_id
			@warning_ignore("integer_division")
			var row: int = item_graphic_id / 15 # 15 columns of icons
			var col: int = item_graphic_id % 15
			item_select_button.sprite_rect.texture.region = Rect2(col * 16, 32 + (row * 16), 16, 16)
			# TODO get correct texture for item icons

		if slot.slot_types.has(item_select_button.item_data.slot_type) and unit.equipable_item_types.has(item_select_button.item_data.item_type):
			item_select_button.visible = true
			item_select_button.selected.connect(func(new_item: ItemData) -> void: update_unit_equipment(unit, slot, new_item))
		else:
			item_select_button.visible = false


func desetup_item_select() -> void:
	item_select_control.visible = false
	for item_select_button: ItemSelectButton in item_select_control.item_select_buttons:
		Utilities.disconnect_all_connections(item_select_button.selected)


func setup_ability_select(unit: Unit, slot: AbilitySlot) -> void:
	ability_select_control.visible = true
	for ability_select_button: AbilitySelectButton in ability_select_control.ability_select_buttons:
		if slot.slot_types.has(ability_select_button.ability_data.slot_type):
			ability_select_button.visible = true
			ability_select_button.selected.connect(func(new_ability: Ability) -> void: update_unit_ability(unit, slot, new_ability))
		else:
			ability_select_button.visible = false


func desetup_ability_select() -> void:
	ability_select_control.visible = false
	for ability_select_button: AbilitySelectButton in ability_select_control.ability_select_buttons:
		Utilities.disconnect_all_connections(ability_select_button.selected)


func update_unit_job(unit: Unit, new_job: JobData) -> void:
	unit.set_job_id(new_job.job_id)
	# TODO update stats (apply multipliers, redo growths, etc.)
	
	desetup_job_select()


func update_unit_equipment(unit: Unit, slot: EquipmentSlot, new_item: ItemData) -> void:
	unit.set_equipment_slot(slot, new_item)
	
	desetup_item_select()


func update_unit_ability(unit: Unit, slot: AbilitySlot, new_ability: Ability) -> void:
	unit.equip_ability(slot, new_ability)
	
	desetup_ability_select()


func add_map_chunk_settings(new_map_chunk: Scenario.MapChunk = null) -> void:
	if new_map_chunk == null:
		new_map_chunk = Scenario.MapChunk.new()
		scenario.map_chunks.append(new_map_chunk)
	
	var new_map_chunk_settings: MapChunkSettingsUi = MapChunkSettingsUi.instantiate(new_map_chunk)
	new_map_chunk_settings.map_chunk_nodes_changed.connect(update_map_chunk_nodes)
	new_map_chunk_settings.map_chunk_settings_changed.connect(update_map)
	new_map_chunk_settings.add_row_to_table(map_chunk_settings_container)
	map_chunk_settings_list.append(new_map_chunk_settings)
	new_map_chunk_settings.deleted.connect(
		func(deleted_map_chunk_settings: MapChunkSettingsUi) -> void: 
			var idx: int = map_chunk_settings_list.find(deleted_map_chunk_settings)
			if idx >= 0:
				map_chunk_settings_list.remove_at(idx)
	)
	
	add_child(new_map_chunk_settings)


func update_map_chunk_nodes(new_map_chunk_settings: MapChunkSettingsUi) -> void:
	battle_manager.maps.add_child(new_map_chunk_settings.map_chunk_nodes)

	new_map_chunk_settings.map_chunk_nodes.play_animations(new_map_chunk_settings.map_chunk_nodes.map_data)
	new_map_chunk_settings.map_chunk_nodes.input_event.connect(battle_manager.on_map_input_event)
	new_map_chunk_settings.set_map_chunk_position(new_map_chunk_settings.map_chunk.corner_position)

	update_map(new_map_chunk_settings)


func update_map(new_map_chunk_settings: MapChunkSettingsUi) -> void:
	if new_map_chunk_settings.is_queued_for_deletion():
		scenario.map_chunks.erase(new_map_chunk_settings.map_chunk)
	
	show_all_tiles(false)
	battle_manager.update_total_map_tiles(scenario.map_chunks)
	update_unit_positions(battle_manager.units)
	if tile_highlight != null:
		tile_highlight.queue_free()
	if unit_editor.unit != null:
		tile_highlight = get_new_tile_highlight(unit_editor.unit.tile_position, Color.BLUE)
	show_all_tiles(show_map_tiles_check.button_pressed)


func update_unit_positions(units: Array[Unit]) -> void:
	for unit: Unit in units:
		if battle_manager.total_map_tiles.keys().has(unit.tile_position.location):
			unit.tile_position = battle_manager.total_map_tiles[unit.tile_position.location][0]
		else: # find nearest tile
			var shortest_distance2: int = 9999
			var closest_tile: TerrainTile = battle_manager.total_map_tiles.values()[0][0]
			for xy: Vector2i in battle_manager.total_map_tiles.keys():
				var this_distance2: int = xy.distance_squared_to(unit.tile_position.location)
				if this_distance2 < shortest_distance2:
					shortest_distance2 = this_distance2
					closest_tile = battle_manager.total_map_tiles[xy][0]
			unit.tile_position = closest_tile

		unit.set_position_to_tile()


func update_background_gradient(_new_color: Color = Color.BLACK) -> void:
	background_gradient_colors.clear()
	for color_picker: ColorPickerButton in background_gradient_color_pickers:
		background_gradient_colors.append(color_picker.color)
	
	battle_manager.background_gradient.texture.gradient.colors = background_gradient_colors
	scenario.background_gradient_bottom = background_gradient_colors[0]
	scenario.background_gradient_top = background_gradient_colors[1]


func add_team(new_team: Team, is_random: bool = false) -> Team:	
	var new_team_setup: TeamSetup = team_setup_scene.instantiate()
	battle_setup_container.add_child(new_team_setup)
	team_setups.append(new_team_setup)
	
	new_team_setup.unit_job_select_pressed.connect(setup_job_select)
	new_team_setup.unit_item_select_pressed.connect(setup_item_select)
	new_team_setup.unit_ability_select_pressed.connect(setup_ability_select)
	new_team_setup.need_new_unit.connect(battle_manager.spawn_random_unit)
	battle_manager.unit_created.connect(new_team_setup.add_unit_editor)
	
	new_team_setup.setup(new_team, is_random)
	
	return new_team


func remove_all_teams() -> void:
	for team_setup: TeamSetup in team_setups:
		team_setup.name += "remove"
		team_setup.num_units_spinbox.value = 0 # remoe all units
		team_setup.num_units_spinbox.value_changed.emit(0)
		team_setup.queue_free()
	battle_manager.teams.clear()
	team_setups.clear()


func show_all_tiles(show_tiles: bool = true, highlight_color: Color = Color.WHITE) -> void:
	for tile_highlight_node: Node3D in map_tile_highlights:
		tile_highlight_node.queue_free()
	
	map_tile_highlights.clear()
	if not show_tiles:
		return
	
	for tile_stack: Array in battle_manager.total_map_tiles.values():
		for tile: TerrainTile in tile_stack:
			var can_end_on_tile: bool = (tile.no_walk == 0 
					and tile.no_stand_select == 0 
					and tile.no_cursor == 0)
			if can_end_on_tile:
				highlight_color = Color.BLUE
			
			var new_tile_highlight: MeshInstance3D = get_new_tile_highlight(tile, highlight_color)
			map_tile_highlights.append(new_tile_highlight)


func get_new_tile_highlight(new_tile: TerrainTile, highlight_color: Color) -> MeshInstance3D:
	var new_tile_highlight: MeshInstance3D = new_tile.get_tile_mesh()
	new_tile_highlight.material_override = battle_manager.tile_highlights[highlight_color] # use pre-existing materials
	add_child(new_tile_highlight) # defer the call for when this function is called from _on_exit_tree
	new_tile_highlight.position = new_tile.get_world_position(true) + Vector3(0, 0.025, 0)

	return new_tile_highlight


func adjust_height(tab_idx: int) -> void:
	push_warning(str(tab_idx))
	if tab_idx == 0:
		battle_setup_container.size.y = 0
		await get_tree().process_frame
		battle_setup_container.position.y = 0
	else:
		battle_setup_container.offset_bottom = 0


func update_unit_dragging(unit: Unit, event: InputEvent) -> void:
	if event.is_action_pressed("primary_action") and unit_dragged == null:
		unit_dragged = unit # TODO only drag one unit at a time
		unit_editor.setup(unit)
		unit_editor.visible = true
		# unit.char_body is moved in _process
	elif event.is_action_released("primary_action") and unit_dragged != null: # snap unit to tile when released
		# check if unit can end movement on tile
		var tile: TerrainTile = battle_manager.current_tile_hover
		var can_end_on_tile: bool = tile.no_walk == 0 and tile.no_stand_select == 0 and tile.no_cursor == 0
		if can_end_on_tile and not unit.prohibited_terrain.has(tile.surface_type_id): # lava, etc.
			unit.tile_position = battle_manager.get_tile(battle_manager.current_cursor_map_position)
		
		unit.char_body.global_position = unit.tile_position.get_world_position()
		unit_dragged = null
		# tile_highlight.queue_free()


func export_scenario() -> void:
	scenario.units_data.clear()
	for unit: Unit in battle_manager.units:
		var new_unit_data: UnitData = UnitData.new()
		new_unit_data.init_from_unit(unit)
		scenario.units_data.append(new_unit_data)
	Utilities.save_json(scenario)
	RomReader.scenarios[scenario.unique_name] = scenario


func open_import_dialong() -> void:
	# https://docs.godotengine.org/en/stable/classes/class_filedialog.html#class-filedialog-property-current-dir
	import_file_dialog.current_dir = "user://overrides/scenarios" # current_dir is not helpful for Windows native file dialaog
	# import_file_dialog.current_dir = OS.get_system_dir(OS.SystemDir.SYSTEM_DIR_DOCUMENTS)
	
	import_file_dialog.visible = true
	# import_file_dialog.popup_file_dialog() # Godot 4.6


func import_scenario(file_path: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	var file_text: String = file.get_as_text()
	var new_scenario: Scenario = Scenario.create_from_json(file_text)
	RomReader.scenarios[new_scenario.unique_name] = new_scenario # do not use "add_to_global_list" as it may set a new unique name
	
	queue_new_scenario(new_scenario)
