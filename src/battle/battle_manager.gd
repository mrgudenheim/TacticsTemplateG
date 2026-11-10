class_name BattleManager
extends Node3D

signal map_input_event(action_instance: ActionInstance, camera: Camera3D, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int) # TODO should action_instance be removed from signal?
signal unit_created(new_unit: UnitData)
signal delayed_action_completed

const SCALE: float = 1.0 / FftMapData.TILE_SIDE_LENGTH
const SCALED_UNITS_PER_HEIGHT: float = SCALE * FftMapData.UNITS_PER_HEIGHT

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
@export var units: Array[UnitData] = []
@export var teams: Array[Team] = []
@export var controller: UnitControllerRT
@export var battle_is_running: bool = false
@export var safe_to_load_map: bool = true
@export var battle_end_panel: Control
@export var post_battle_messages: Control
@export var start_new_battle_button: Button
@export var active_unit: UnitData
@export var game_state_container: Container
@export var game_state_label: Label
@export var scenario_editor: ScenarioEditor

var trap_instance: TrapEffectInstance
var projectile_instance: ProjectileEffectInstance

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

@export var show_statbar_check: CheckBox


func _ready() -> void:
	main_camera = camera_controller.camera

	load_rom_button.file_selected.connect(RomReader.on_load_rom_dialog_file_selected)
	GameData.data_indexed.connect(on_data_ready)
	orthographic_check.toggled.connect(camera_controller.on_orthographic_toggled)
	show_statbar_check.toggled.connect(set_unit_statbars_visible)
	#camera_controller.zoom_changed.connect(update_phantom_camera_spring)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_debug_ui()


func toggle_debug_ui() -> void:
	scenario_editor.visible = not scenario_editor.visible
	if scenario_editor.visible:
		game_state_container.visible = false
		battle_view.reparent(scenario_editor.battle_subviewport)
		
		for unit: UnitData in units:
			if unit.unit_actor != null and not unit.unit_actor.unit_input_event.is_connected(scenario_editor.update_unit_dragging):
				unit.unit_actor.unit_input_event.connect(scenario_editor.update_unit_dragging)
		
		camera_controller.follow_node = null
		controller.unit = null
	else:
		game_state_container.visible = true
		if scenario_editor.tile_highlight != null:
			scenario_editor.tile_highlight.queue_free()
		
		for unit: UnitData in units:
			if unit.unit_actor != null and unit.unit_actor.unit_input_event.is_connected(scenario_editor.update_unit_dragging):
				unit.unit_actor.unit_input_event.disconnect(scenario_editor.update_unit_dragging)

		battle_view.reparent(self)

		if active_unit != null and active_unit.unit_actor != null:
			camera_controller.follow_node = active_unit.unit_actor.char_body
			controller.unit = active_unit.unit_actor
		else:
			camera_controller.follow_node = null


func on_data_ready() -> void:
	#push_warning("on data ready")
	load_rom_button.visible = false

	if trap_instance != null:
		trap_instance.stop()
		trap_instance.queue_free()
	trap_instance = TrapEffectInstance.new()
	trap_instance.name = "TrapEffectInstance"
	battle_view.add_child(trap_instance)
	trap_instance.initialize()

	if projectile_instance != null:
		projectile_instance.stop()
		projectile_instance.queue_free()
	projectile_instance = ProjectileEffectInstance.new()
	projectile_instance.name = "ProjectileEffectInstance"
	battle_view.add_child(projectile_instance)
	projectile_instance.initialize()

	scenario_editor.populate_option_lists()
	scenario_editor.visible = true
	# var default_scenario: Scenario = GameData.get_scenario("map_032_slums_in_dorter_01")
	#var default_scenario: Scenario = GameData.get_scenario("map_083_zirekile_falls_14")
	# scenario_editor.init_scenario(default_scenario)
	scenario_editor.init_scenario()
	set_unit_statbars_visible(show_statbar_check.button_pressed)


func update_total_map_tiles(map_chunks: Array[MapChunk]) -> void:
	total_map_tiles.clear()

	for map_chunk: MapChunk in map_chunks:
		var map_chunk_data: MapData = GameData.get_map_data(map_chunk.unique_name)
		#if not map_chunk_data.is_initialized:
			#continue

		var map_tile_scale: Vector2 = Vector2(map_chunk.mirror_scale.x, map_chunk.mirror_scale.z)
		var map_tile_offset: Vector2 = Vector2(map_chunk.corner_position.x, map_chunk.corner_position.z)
		var transformed_tiles: Array[TerrainTile] = map_chunk_data.get_transformed_tiles(map_tile_offset, map_tile_scale, 0)

		for tile: TerrainTile in transformed_tiles:
			tile.height_bottom += map_chunk.corner_position.y
			tile.height_mid = tile.height_bottom + (tile.slope_height / 2.0)
			
			if not total_map_tiles.has(tile.xz_location):
				total_map_tiles[tile.xz_location] = []
			# sort tiles by ascending height
			var tile_level: int = total_map_tiles[tile.xz_location].bsearch_custom(tile, 
				func(tile_a: TerrainTile, tile_b: TerrainTile) -> bool: return tile_a.height_mid > tile_b.height_mid
			)
			total_map_tiles[tile.xz_location].insert(tile_level, tile)


func start_battle() -> void:
	scenario_editor.visible = false
	if scenario_editor.tile_highlight != null:
		scenario_editor.tile_highlight.queue_free()
	
	for unit: UnitData in units:
		if unit.unit_actor != null and unit.unit_actor.unit_input_event.is_connected(scenario_editor.update_unit_dragging):
			unit.unit_actor.unit_input_event.disconnect(scenario_editor.update_unit_dragging)
	
	battle_view.reparent(self)
	# get list of units again; reparenting temporarily removes the unit from the tree and Units auto remove themselves from the Array when they leave the tree
	units.clear()
	for child: Node in units_container.get_children():
		var actor: UnitActor = child as UnitActor
		if actor != null and actor.unit_data != null:
			units.append(actor.unit_data)
	set_unit_statbars_visible(show_statbar_check.button_pressed)
	game_state_container.visible = true
	
	if not units.is_empty() and units[0].unit_actor != null:
		camera_controller.follow_node = units[0].unit_actor.char_body
		controller.unit = units[0].unit_actor
	#controller.rotate_camera(1) # HACK workaround for bug where controls are off until camera is rotated
	
	if not battle_is_running:
		battle_is_running = true
		process_battle()


func spawn_random_unit(team: Team) -> UnitData:
	var rand_job_name: String = GameData.job_paths.keys().pick_random()
	var rand_job: JobData = GameData.get_job(rand_job_name)
	while [0x2c, 0x31].has(rand_job.job_id): # prevent jobs without idle frames - 0x2c (Alma2) and 0x31 (Ajora) do not have walking frames
		rand_job_name = GameData.job_paths.keys().pick_random()
		rand_job = GameData.get_job(rand_job_name)
	var tile_location: TerrainTile = get_random_stand_terrain_tile()
	var new_unit: UnitData = spawn_unit(tile_location, rand_job.unique_name, team)
	new_unit.controller = UnitData.Controller.PLAYER
	
	unit_created.emit(new_unit)
	return new_unit


func spawn_unit(tile_position: TerrainTile, job_name: String, team: Team, level: int = 40) -> UnitData:
	var new_unit_data: UnitData = UnitData.new()
	new_unit_data.battle_manager = self
	new_unit_data.terrain_tile_position = tile_position
	var new_job_data: JobData = GameData.get_job(job_name)
	var job_id: int = new_job_data.job_id
	if job_id < 0x5e: # non-monster
		new_unit_data.stat_basis = [UnitData.StatBasis.MALE, UnitData.StatBasis.FEMALE].pick_random()
	else:
		new_unit_data.stat_basis = UnitData.StatBasis.MONSTER
	new_unit_data.set_job(job_name)
	new_unit_data.update_unit_facing([Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT].pick_random())
	new_unit_data.stats[UnitData.StatType.LEVEL].set_value(level)
	UnitData.generate_leveled_raw_stats(new_unit_data.stat_basis, level, new_unit_data.job_data, new_unit_data.stats_raw)
	
	var use_higher_stat_values: bool = false
	if ["RUKA.SEQ", "KANZEN.SEQ", "ARUTE.SEQ"].has(new_unit_data.spritesheet_file_name): # lucavi
		use_higher_stat_values = true
	UnitData.calc_battle_stats(new_unit_data.job_data, new_unit_data.stats_raw, new_unit_data.stats, true, use_higher_stat_values)
	
	new_unit_data.equip_random_abilities()
	new_unit_data.equip_items_leveled()
	new_unit_data.team_idx = teams.find(team)
	new_unit_data.team = team
	new_unit_data.team_name = team.team_name
	new_unit_data.controller = UnitData.Controller.AI

	return spawn_unit_from_unit_data(new_unit_data)


func spawn_unit_from_unit_data(new_unit_data: UnitData) -> UnitData:
	if new_unit_data.job_data.unique_name == "unique_name" and new_unit_data.job_unique_name != "job_unique_name":
		new_unit_data.job_data = GameData.get_job(new_unit_data.job_unique_name)
	var new_unit_actor: UnitActor = UnitActor.instantiate()
	new_unit_data.battle_manager = self
	new_unit_actor.battle_manager = self
	new_unit_actor.bind_unit_data(new_unit_data)
	if not units.has(new_unit_data):
		units.append(new_unit_data)

	if new_unit_data.terrain_tile_position == null:
		var unit_xz_position: Vector2i = Vector2i(new_unit_data.tile_position.x, new_unit_data.tile_position.z)
		var xz_index: int = total_map_tiles.keys().find(unit_xz_position)
		if xz_index >= 0:
			new_unit_data.terrain_tile_position = total_map_tiles.values()[xz_index][new_unit_data.tile_position.y]
		elif not total_map_tiles.is_empty():
			new_unit_data.terrain_tile_position = total_map_tiles.values()[0][0]

	camera_controller.rotated.connect(new_unit_actor.char_body.set_rotation_degrees) # have sprite update as camera rotates
	new_unit_actor.char_body.set_rotation_degrees(Vector3(0, camera_controller.rotation_degrees.y, 0))
	new_unit_actor.update_animation_facing(camera_controller.camera_facing_vector)
	
	new_unit_actor.update_stat_bars_scale(camera_controller.zoom)
	camera_controller.zoom_changed.connect(new_unit_actor.update_stat_bars_scale)
	
	new_unit_actor.name = new_unit_data.job_unique_name + "-" + new_unit_data.unit_unique_name
	
	if new_unit_data.team == null:
		if new_unit_data.team_idx < 0:
			new_unit_data.team_idx = 0
		if teams.size() < new_unit_data.team_idx + 1:
			teams.resize(new_unit_data.team_idx + 1)
		
		if teams[new_unit_data.team_idx] == null:
			var new_team: Team = Team.new()
			new_team.team_name = "Team" + str(new_unit_data.team_idx + 1)
			teams[new_unit_data.team_idx] = new_team

		new_unit_data.team = teams[new_unit_data.team_idx]
	else:
		if new_unit_data.team_idx < 0:
			new_unit_data.team_idx = teams.find(new_unit_data.team)
			if new_unit_data.team_idx < 0:
				teams.append(new_unit_data.team)
				new_unit_data.team_idx = teams.size() - 1

	new_unit_data.team_name = new_unit_data.team.team_name
	if not new_unit_data.team.units.has(new_unit_data):
		new_unit_data.team.units.append(new_unit_data)

	new_unit_data.ai_controller.strategy = UnitAi.Strategy.BEST

	new_unit_data.update_passive_effects()
	new_unit_actor.unit_input_event.connect(scenario_editor.update_unit_dragging)

	units_container.add_child(new_unit_actor)
	
	return new_unit_data


func update_units_pathfinding() -> void:
	#for unit: UnitActor in units:
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
	for unit: UnitData in units:
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
						status_action_instance.submitted_targets.append(unit.terrain_tile_position) # TODO get targets for status action
						# RomReader.actions[status.action_on_complete].use(status_action_instance)
						if unit.unit_actor != null:
							camera_controller.follow_node = unit.unit_actor.char_body
						game_state_label.text = unit.job_data.display_name + "-" + unit.display_name + " processing " + status.status_effect_name + " ending"
						await status_action_instance.use()
						if not battle_is_running: return
						# await status_action_instance.action_completed
						if check_end_conditions():
							safe_to_load_map = true
							return
					if status.delayed_action != null: # execute stored delayed actions, TODO checks to null (no mp, silenced, etc.)
						#status.delayed_action.show_targets_highlights(status.delayed_action.preview_targets_highlights) # show submitted targets TODO retain preview highlight nodes?
						#await unit.get_tree().create_timer(0.5).timeout
						if unit.unit_actor != null:
							camera_controller.follow_node = unit.unit_actor.char_body
						game_state_label.text = unit.job_data.display_name + "-" + unit.display_name + " processing delayed " + status.delayed_action.action.display_name
						await status.delayed_action.use()
						if not battle_is_running: return
						#await status.delayed_action.action_completed
						delayed_action_completed.emit()
						if not battle_is_running: return
						if check_end_conditions():
							safe_to_load_map = true
							return
			safe_to_load_map = true
			await get_tree().process_frame
			if not battle_is_running: return
		for status: StatusEffect in statuses_to_remove:
			unit.remove_status(status)

	for unit: UnitData in units: # increment each units ct by speed
		if not unit.is_ct_frozen(): # check status that prevent ct gain (stop, sleep, etc.)
			var ct_gain: int = unit.stats[UnitData.StatType.SPEED].current_value
			for passive_effect: PassiveEffect in unit.get_all_passive_effects():
				ct_gain = passive_effect.ct_gain_modifier.apply(ct_gain)
			unit.stats[UnitData.StatType.CT].add_value(ct_gain)

	# execute unit turns in PriorityQueue order until all units have CT < 100
	while true:
		var ready_queue: PriorityQueue = get_ready_turn_queue()
		if ready_queue.is_empty():
			break
		
		var unit: UnitData = ready_queue.pop()
		
		safe_to_load_map = false
		await start_units_turn(unit) # process statuses on turn start and update actions
		
		if not battle_is_running:
			return
		
		if not unit.is_defeated():
			if not unit.controller == UnitData.Controller.AI:
				safe_to_load_map = true

			# wait for player controlled turn
			while not unit.is_ending_turn:
				await get_tree().process_frame
				if not battle_is_running:
					return
				if unit == null: 
					return
			
			clear_action_buttons()
			unit.actions_updated.disconnect(update_action_buttons)
			active_unit = null
			
			if check_end_conditions():
				safe_to_load_map = true
				return
		
		safe_to_load_map = true
		await get_tree().process_frame
		
		if not battle_is_running: 
			return
	
	# TODO increment status ticks, delayed action ticks, and unit ticks in the same step, then order resolution?


## Builds a PriorityQueue of all units currently ready to take a turn (CT >= 100).
## Uses negative CT so highest CT acts first; unit index breaks ties.
func get_ready_turn_queue() -> PriorityQueue:
	var queue: PriorityQueue = PriorityQueue.new()
	for idx: int in units.size():
		var unit: UnitData = units[idx]
		if not is_instance_valid(unit):
			continue
		
		if unit.stats[UnitData.StatType.CT].current_value >= 100 and not unit.is_ct_frozen():
			# negative CT pops highest CT first; index breaks ties
			var priority: float = -float(unit.stats[UnitData.StatType.CT].current_value) + (float(idx) * 0.0001)
			queue.push(unit, priority)
	
	return queue


func check_end_conditions() -> bool:
	for team: Team in teams:
		team.check_end_conditions(self)
	
	if teams.any(func(team: Team) -> bool: return team.state == Team.State.WON):
		battle_is_running = false
		return true
	
	return false


func start_units_turn(unit: UnitData) -> void:
	if unit.unit_actor != null:
		controller.unit = unit.unit_actor
	active_unit = unit
	
	if not unit.is_defeated():
		if unit.unit_actor != null:
			camera_controller.follow_node = unit.unit_actor.char_body
		unit.actions_updated.connect(update_action_buttons)
	
	await unit.start_turn()


func clear_action_buttons() -> void:
	for child: Node in action_button_list.get_children():
		child.queue_free()


func update_action_buttons(unit: UnitData) -> void:
	clear_action_buttons()
	
	# show list UI for selecting an action TODO should action list be toggle/button group?
	for action_instance: ActionInstance in unit.actions_data.values():
		var new_action_button: ActionButton = ActionButton.new(action_instance)
		action_button_list.add_child(new_action_button)
		
		# disable buttons for actions that are not usable - TODO provide hints why action is not usable - not enough mp, already moved, etc.
		if not action_instance.is_usable():
			new_action_button.disabled = true


func get_scaled_collision_shape(mesh: Mesh, collision_scale: Vector3) -> ConcavePolygonShape3D:
	var new_collision_shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	var faces: PackedVector3Array = new_collision_shape.get_faces()
	for i: int in faces.size():
		faces[i] = faces[i] * collision_scale
	
	#push_warning(faces)
	new_collision_shape.set_faces(faces)
	new_collision_shape.backface_collision = true
	return new_collision_shape


func get_random_terrain_tile() -> TerrainTile:
	if total_map_tiles.size() == 0:
		push_warning("No map tiles")
	
	var random_key: Vector2i = total_map_tiles.keys().pick_random()
	var tiles: Array = total_map_tiles[random_key]
	var tile: TerrainTile = tiles.pick_random()
	
	return tile


func get_random_stand_terrain_tile() -> TerrainTile:
	var potential_tiles: Array[TerrainTile] = get_stand_tiles()
	var random_valid_tile: TerrainTile = potential_tiles.pick_random()
	
	while units.any(func(unit: UnitData) -> bool: return unit.terrain_tile_position == random_valid_tile):
		potential_tiles.erase(random_valid_tile)
		random_valid_tile = potential_tiles.pick_random()
	
	return random_valid_tile


func get_stand_tiles() -> Array[TerrainTile]:
	var valid_tiles: Array[TerrainTile] = []
	for tile_xy: Vector2i in total_map_tiles.keys():
		var potential_tile: TerrainTile = total_map_tiles[tile_xy][0]
		if potential_tile.no_stand_select != 0 or potential_tile.no_walk != 0:
			continue
		
		valid_tiles.append(potential_tile)
	return valid_tiles


func set_unit_statbars_visible(statbar_is_visible: bool) -> void:
	for unit: UnitData in units:
		if unit.unit_actor != null:
			unit.unit_actor.set_stat_bar_visiblity(statbar_is_visible)


func clear_maps() -> void:
	total_map_tiles.clear()
	for child: Node in maps.get_children():
		child.queue_free()
		maps.remove_child(child)


func clear_units() -> void:
	for unit: UnitData in units:
		if unit.unit_actor != null:
			unit.unit_actor.queue_free()
	
	units.clear()
	#for child: Node in units_container.get_children():
		#child.queue_free()


func increment_counter(unit: UnitData) -> void:
	var knocked_out_icon: Image = unit.unit_actor.animation_manager.global_shp.get_assembled_frame(0x17, unit.unit_actor.animation_manager.global_spr.spritesheet, 0, 0, 0, 0)
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
				current_vert_error = abs(((new_tile.height_mid + new_tile.depth) * FftMapData.HEIGHT_SCALE) - input_position.y)
			else:
				var new_vert_error: float = abs(((new_tile.height_mid + new_tile.depth) * FftMapData.HEIGHT_SCALE) - input_position.y)
				if new_vert_error < current_vert_error:
					current_vert_error = new_vert_error
					tile = new_tile
	
	return tile
