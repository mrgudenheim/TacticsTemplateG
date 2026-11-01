class_name Unit
extends Node3D

# https://ffhacktics.com/wiki/Miscellaneous_Unit_Data
# https://ffhacktics.com/wiki/Battle_Stats

signal initialized()
signal data_updated(unit: Unit)

signal ability_assigned(name: String)
signal ability_completed()
signal primary_weapon_assigned(item_unique_name: String)
signal image_changed(new_image: ImageTexture)
signal knocked_out(unit: Unit)
signal spritesheet_changed(new_spritesheet: ImageTexture)
@warning_ignore("unused_signal")
signal targeted_pre_action(this_unit: Unit, action_instance: ActionInstance) # emited in action_instance
@warning_ignore("unused_signal")
signal targeted_post_action(this_unit: Unit, action_instance: ActionInstance) # emited in action_instance
@warning_ignore("unused_signal")
signal reached_tile() # emited in use_move
@warning_ignore("unused_signal")
signal completed_move(this_unit: Unit, tile_moved: int) # emited in use_move
signal turn_started(this_unit: Unit)
signal turn_ended(this_unit: Unit)
signal unit_input_event(unit_actor: Unit, event: InputEvent)
signal paths_updated()

const StatBasis = UnitData.StatBasis
const Gender = UnitData.Gender
const StatType = UnitData.StatType
const Facings = UnitData.Facings
const FACING_VECTORS: Dictionary[UnitData.Facings, Vector3] = UnitData.FACING_VECTORS

static var unit_scene: PackedScene = null

var data: UnitData = UnitData.new()
var _has_bound_external_data: bool = false
var _scene_resources_initialized: bool = false
var _rendered_sprite_name: String = ""
var _rendered_palette_id: int = -1

var global_battle_manager: BattleManager
var team: Team
var is_controlled_by_me: bool = false # for multiplayer games
var is_ai_controlled: bool:
	get:
		return data.is_ai_controlled
	set(value):
		data.is_ai_controlled = value
var ai_controller: UnitAi = UnitAi.new()

@export var char_body: CharacterBody3D
@export var animation_manager: UnitAnimationManager
@export var popup_texts: PopupTextContainer
@export var stat_bars_position: Control
@export var stat_bars_container: Container
@export var unit_battle_details_ui: UnitDetailsBattleUi
@export var icon2: Sprite3D
@export var icon_cycle_time: float = 1.25
@export var icon_id: int = 0:
	get:
		return icon_id
	set(value):
		icon_id = value
		set_icon(icon_id)
@export var debug_menu: UnitDebugMenu

var is_defeated: bool:
	get:
		return data.is_defeated

var is_ct_frozen: bool:
	get:
		return data.is_ct_frozen

var unit_nickname: String:
	get:
		return data.display_name
	set(value):
		data.display_name = value
var job_nickname: String:
	get:
		if data.job_data != null:
			return data.job_data.display_name
		return "Job Nickname"
	set(_value):
		pass
var job_name: String:
	get:
		return data.job_unique_name
	set(value):
		data.job_unique_name = value

var character_id: int = 0
var unit_index_formation: int = 0
var stat_basis: UnitData.StatBasis:
	get:
		return data.stat_basis
	set(value):
		data.stat_basis = value
var gender: UnitData.Gender:
	get:
		return data.gender
	set(value):
		data.gender = value
var job_id: int = 0
var job_data: JobData:
	get:
		return data.job_data
	set(value):
		data.job_data = value
var sprite_palette_id: int:
	get:
		return data.palette_id
	set(value):
		data.palette_id = value
var sprite_palette_id_override: int = -1
var team_id: int:
	get:
		return data.team_idx
	set(value):
		data.team_idx = value
var player_control: bool = true

var immortal: bool:
	get:
		return data.immortal
	set(value):
		data.immortal = value
var immune_knockback: bool:
	get:
		return data.immune_knockback
	set(value):
		data.immune_knockback = value
var game_over_trigger: bool = false
var type_id: int = 0 # male, female, monster
var death_counter: int = 3
var zodiac: String:
	get:
		return data.zodiac
	set(value):
		data.zodiac = value

var innate_ability_ids: PackedInt32Array = []
var skillsets_names: PackedStringArray:
	get:
		return data.skillsets_names
	set(value):
		data.skillsets_names = value
# var skillsets: Array[Skillset] = []

var equipable_item_types: Array[ItemData.ItemType]:
	get:
		return data.equipable_item_types
	set(value):
		data.equipable_item_types = value
var primary_weapon: ItemData:
	get:
		return data.primary_weapon
	set(value):
		data.primary_weapon = value
var equip_slots: Array[EquipmentSlot]:
	get:
		return data.equip_slots
	set(value):
		data.equip_slots = value

var ability_slots: Array[AbilitySlot]:
	get:
		return data.ability_slots
	set(value):
		data.ability_slots = value

var stats: Dictionary[UnitData.StatType, StatValue]:
	get:
		return data.stats
	set(value):
		data.stats = value

var stats_raw: Dictionary[UnitData.StatType, float]:
	get:
		return data.stats_raw
	set(value):
		data.stats_raw = value


var unit_exp: int = 0:
	get: return data.unit_exp
var level: int = 0:
	get: return data.stats[StatType.LEVEL].current_value

var brave: int = 70:
	get: return data.brave
var faith: int = 70:
	get: return data.faith

var ct_current: int = 0:
	get: return data.ct_current
var ct_max: int = 100:
	get: return data.ct_max

var hp_max: int = 100:
	get: return data.hp_max
var hp: int = 70:
	get: return data.hp
var mp_max: int = 100:
	get: return data.mp_max
var mp: int = 70:
	get: return data.mp

var physical_attack: int = 5:
	get: return data.physical_attack
var magical_attack: int = 5:
	get: return data.magical_attack
var speed: int = 5:
	get: return data.speed
var move: int = 5:
	get: return data.move
var jump: int = 3:
	get: return data.jump

var always_statuses: PackedStringArray:
	get: return data.always_statuses
	set(value): data.always_statuses = value
var immune_statuses: PackedStringArray:
	get: return data.immune_statuses
	set(value): data.immune_statuses = value
var start_statuses: PackedStringArray:
	get: return data.start_statuses
	set(value): data.start_statuses = value

# TODO clean up unit status stuff
var current_statuses: Array[StatusEffect]:
	get: return data.current_statuses
	set(value): data.current_statuses = value
var current_status_ids: PackedStringArray:
	get: return data.current_status_ids
#var current_statuses2: Dictionary[StatusEffect, int] = {}

var learned_abilities: Array:
	get: return data.learned_abilities
	set(value): data.learned_abilities = value
var job_levels: Dictionary[JobData, int]:
	get: return data.job_levels
	set(value): data.job_levels = value
var job_jp: Dictionary[JobData, int]:
	get: return data.job_jp
	set(value): data.job_jp = value

var charging_abilities_ids: PackedInt32Array:
	get: return data.charging_abilities_ids
	set(value): data.charging_abilities_ids = value
var charging_abilities_remaining_ct: PackedInt32Array:
	get: return data.charging_abilities_remaining_ct
	set(value): data.charging_abilities_remaining_ct = value
var sprite_id: int = 0
var sprite_file_idx: int = 0
var sprite_file_name: String:
	get: return data.spritesheeet_file_name
	set(value): data.spritesheeet_file_name = value
var portrait_palette_id: int = 0
var unit_id: int = 0
var special_job_skillset_id: int = 0

var elemental_absorb: Array[Action.ElementTypes]:
	get: return data.elemental_absorb
	set(value): data.elemental_absorb = value
var elemental_cancel: Array[Action.ElementTypes]:
	get: return data.elemental_cancel
	set(value): data.elemental_cancel = value
var elemental_half: Array[Action.ElementTypes]:
	get: return data.elemental_half
	set(value): data.elemental_half = value
var elemental_weakness: Array[Action.ElementTypes]:
	get: return data.elemental_weakness
	set(value): data.elemental_weakness = value
var elemental_strengthen: Array[Action.ElementTypes]:
	get: return data.elemental_strengthen
	set(value): data.elemental_strengthen = value

var can_move: bool = true

#var map_position: Vector2i
var tile_position: TerrainTile:
	get:
		return data.current_tile
	set(value):
		data.current_tile = value
		if global_battle_manager != null and value != null:
			data.sync_tile_coords_from_map(global_battle_manager.total_map_tiles)
var prohibited_terrain: Array[int]:
	get: return data.prohibited_terrain
	set(value): data.prohibited_terrain = value
var terrain_costs: Dictionary[int, int]:
	get: return data.terrain_costs
	set(value): data.terrain_costs = value
var ignore_height: bool:
	get: return data.ignore_height
	set(value): data.ignore_height = value

var map_paths: Dictionary[TerrainTile, TerrainTile]
var path_costs: Dictionary[TerrainTile, float]
var paths_set: bool = false
@export var tile_highlights: Node3D
var facing: UnitData.Facings:
	get: return data.facing_direction
	set(value): data.facing_direction = value
var is_back_facing: bool = false
var facing_vector: Vector3 = Vector3.FORWARD:
	get:
		return data.facing_vector

var is_in_air: bool = false
var is_traveling_path: bool = false

var active_ability_name: String = ""
var action_data: Action

var active_action: ActionInstance
#@export var action_instance: ActionInstance
@export var move_action: Action
# @export var attack_action: Action
@export var wait_action: Action
@export var actions: Array[Action] = []
var actions_data: Dictionary[String, ActionInstance] = {}
var move_points_start: int:
	get: return data.move_points_start
	set(value): data.move_points_start = value
var move_points_remaining: int:
	get: return data.move_points_remaining
	set(value): data.move_points_remaining = value
var action_points_start: int:
	get: return data.action_points_start
	set(value): data.action_points_start = value
var action_points_remaining: int:
	get: return data.action_points_remaining
	set(value): data.action_points_remaining = value
@export var is_ending_turn: bool = false

@export var current_animation_id_fwd: int = 6 # set based on current action
@export var current_idle_animation_id: int = 6 # set based on status (critical, knocked out, etc.)
# constants?
@export var idle_walk_animation_id: int = 6 # 0x0c for flying sprites
@export var walk_to_animation_id: int = 0x18 # 0x1e (30) for flying sprites
@export var evade_animation_id: int = 0x30 # TODO fix for kanzen, arute?
@export var taking_damage_animation_id: int = 0x32
@export var knocked_out_animation_id: int = 0x34
@export var heal_animation_id: int = 0x36
@export var mid_jump_animation: int = 0x3e

var submerged_depth: int = 0


static func instantiate() -> Unit:
	if unit_scene == null:
		unit_scene = load("uid://dkudrb304m7t1")
	return unit_scene.instantiate()


func _init() -> void:
	data.initialize_defaults()


func _ready() -> void:
	var hp_bar: StatBar = add_stat_bar(StatType.HP)
	hp_bar.show_value = true
	
	var mp_bar: StatBar = add_stat_bar(StatType.MP)
	mp_bar.fill_color = Color.INDIAN_RED
	mp_bar.show_value = true

	var ct_bar: StatBar = add_stat_bar(StatType.CT)
	ct_bar.visual_max = 100.0
	ct_bar.update_stat(stats[StatType.CT])
	ct_bar.fill_color = Color.WEB_GREEN
	ct_bar.show_value = true
	
	icon2.texture = GameData.get_texture("misc")
	icon2.material_override = icon2.material_override.duplicate()
	icon2.material_override.set_shader_parameter("sprite_texture", GameData.get_texture("misc"))
	icon2.material_override.set_shader_parameter("palette_colors", GameData.palettes["misc"].slice(5 * 16, 6 * 16))
	icon2.material_override.set_shader_parameter("billboard_enabled", true)
	cycle_status_icons()
	
	add_to_group("Units")

	if not GameData.is_ready:
		GameData.data_indexed.connect(_on_game_data_indexed)
	else:
		_on_game_data_indexed()


func _on_game_data_indexed() -> void:
	_init_scene_resources()
	if not _has_bound_external_data:
		initialize_unit()
	else:
		_refresh_all_visuals_from_data()
		_on_data_changed(data)


func _exit_tree() -> void:
	if global_battle_manager != null and is_queued_for_deletion():
		var unit_index: int = global_battle_manager.units.find(self)
		for action_instance: ActionInstance in actions_data.values():
			action_instance.stop_targeting()
		if unit_index != -1: # if the unit is in the battle_manager array
			global_battle_manager.units.remove_at(unit_index)


func add_stat_bar(stat_type: UnitData.StatType) -> StatBar:
	var new_stat_bar: StatBar = StatBar.instantiate()
	new_stat_bar.set_stat(str(StatType.keys()[stat_type]), stats[stat_type])
	stat_bars_container.add_child(new_stat_bar)

	return new_stat_bar


func set_stat_bar_visiblity(new_is_visible: bool, stat_bar_idx: int = -1) -> void:
	if stat_bar_idx == -1:
		stat_bars_position.visible = new_is_visible
		return
	
	stat_bars_container.get_child(stat_bar_idx).visible = new_is_visible


func update_stat_bars_scale(camera_zoom: float) -> void:
	stat_bars_position.scale = Vector2.ONE * 3.775 / camera_zoom


func _init_scene_resources() -> void:
	if _scene_resources_initialized:
		return
	_scene_resources_initialized = true
	debug_menu.populate_options()

	move_action = GameData.get_action("move")
	wait_action = GameData.get_action("wait")
	
	animation_manager.wep_texture = GameData.get_texture("wep")
	animation_manager.wep_spritesheet_data = GameData.get_spritesheet_data("wep")
	animation_manager.wep_shp = GameData.get_shp("wep1")
	animation_manager.wep_seq = GameData.get_seq("wep1")
	
	animation_manager.eff_texture = GameData.get_texture("eff")
	animation_manager.eff_spritesheet_data = GameData.get_spritesheet_data("eff")
	animation_manager.eff_shp = GameData.get_shp("eff1")
	animation_manager.eff_seq = GameData.get_seq("eff1")
	
	var eff_frame_grid: ImageTexture = GameData.get_spritesheet_data("eff").create_frame_grid_texture(0, 0, 0, 0)
	animation_manager.unit_sprites_manager.sprite_effect.texture = eff_frame_grid
	var eff_material: ShaderMaterial = animation_manager.unit_sprites_manager.sprite_effect.material_override.duplicate()
	eff_material.set_shader_parameter("sprite_texture", eff_frame_grid)
	eff_material.set_shader_parameter("palette_colors", GameData.get_spritesheet_data("eff").color_palette.slice(0 * 16, 1 * 16))
	eff_material.set_shader_parameter("depth_mode", VfxConstants.DepthMode.UNIT)
	animation_manager.unit_sprites_manager.sprite_effect.material_override = eff_material

	animation_manager.unit_sprites_manager.sprite_item.texture = GameData.get_texture("items")
	
	animation_manager.other_texture = GameData.get_texture("other")
	animation_manager.other_shp = GameData.get_shp("other")


func initialize_unit() -> void:
	_init_scene_resources()
	if _has_bound_external_data:
		return

	skillsets_names.resize(2)
	skillsets_names.fill("")
	
	# 1 cure
	# 0xc8 blood suck
	# 0x9b stasis sword
	set_ability("stasis_sword")
	set_primary_weapon("mythril_spear") # 1 - dagger, 72 - mythril gun, 101 - mythril spear
	# TODO use equipment_slots
	#set_sprite_by_file_idx(98) # RAMUZA.SPR # TODO use sprite_id?
	set_sprite_by_file_name("ramuza")
	#set_sprite_by_file_name("RAMUZA.SPR")
	
	update_unit_facing(FACING_VECTORS[Facings.SOUTH])
	
	var random_name_idx: int = randi_range(0, GameData.names["all_no_empty"].size() - 1)
	unit_nickname = GameData.names["all_no_empty"][random_name_idx]

	initialized.emit()


func bind_unit_data(new_data: UnitData) -> void:
	_has_bound_external_data = true
	if data != null and data != new_data:
		if data.data_changed.is_connected(_on_data_changed):
			data.data_changed.disconnect(_on_data_changed)
		if data.statuses_changed.is_connected(_on_statuses_changed):
			data.statuses_changed.disconnect(_on_statuses_changed)
		if data.appearance_changed.is_connected(_on_appearance_changed):
			data.appearance_changed.disconnect(_on_appearance_changed)
		if data.primary_weapon_changed.is_connected(_on_primary_weapon_changed):
			data.primary_weapon_changed.disconnect(_on_primary_weapon_changed)
		if data.stats.has(StatType.HP) and data.stats[StatType.HP].value_changed.is_connected(hp_changed):
			data.stats[StatType.HP].value_changed.disconnect(hp_changed)

	data = new_data
	data.passive_context_getter = _get_passive_context
	data.auto_apply_hp_threshold_statuses = false
	data.ensure_initialized()

	if not data.data_changed.is_connected(_on_data_changed):
		data.data_changed.connect(_on_data_changed)
	if not data.statuses_changed.is_connected(_on_statuses_changed):
		data.statuses_changed.connect(_on_statuses_changed)
	if not data.appearance_changed.is_connected(_on_appearance_changed):
		data.appearance_changed.connect(_on_appearance_changed)
	if not data.primary_weapon_changed.is_connected(_on_primary_weapon_changed):
		data.primary_weapon_changed.connect(_on_primary_weapon_changed)
	if not data.stats[StatType.HP].value_changed.is_connected(hp_changed):
		data.stats[StatType.HP].value_changed.connect(hp_changed)

	if stat_bars_container != null and stat_bars_container.get_child_count() >= 3:
		var stat_bars: Array[Node] = stat_bars_container.get_children()
		(stat_bars[0] as StatBar).set_stat(str(StatType.keys()[StatType.HP]), data.stats[StatType.HP])
		(stat_bars[1] as StatBar).set_stat(str(StatType.keys()[StatType.MP]), data.stats[StatType.MP])
		(stat_bars[2] as StatBar).set_stat(str(StatType.keys()[StatType.CT]), data.stats[StatType.CT])

	if GameData.is_ready:
		_init_scene_resources()
		_refresh_all_visuals_from_data()
		_on_data_changed(data)
		initialized.emit()


func _get_passive_context() -> Dictionary:
	if global_battle_manager == null:
		return {}
	var units_data_list: Array[UnitData] = []
	for battle_unit: Unit in global_battle_manager.units:
		if is_instance_valid(battle_unit) and battle_unit.data != null:
			units_data_list.append(battle_unit.data)
	return {
		"units_data": units_data_list,
		"global_passives": global_battle_manager.global_passive_effects,
	}


func _refresh_all_visuals_from_data() -> void:
	var clean_sprite: String = data.spritesheeet_file_name.to_lower().trim_suffix(".spr")
	if clean_sprite != "" and (GameData.unit_spritesheet_data_paths.has(clean_sprite) or GameData.unit_spritesheets_data.has(clean_sprite)):
		set_sprite_by_file_name(clean_sprite)
	_rendered_palette_id = data.palette_id
	if _rendered_sprite_name != "":
		update_spritesheet_grid_texture()
	_apply_weapon_visuals()
	if data.primary_weapon != null and data.primary_weapon.unique_name != "":
		primary_weapon_assigned.emit(data.primary_weapon.unique_name)
	update_unit_facing(FACING_VECTORS[data.facing_direction])
	if global_battle_manager != null and global_battle_manager.camera_controller != null:
		update_animation_facing(global_battle_manager.camera_controller.camera_facing_vector)
	update_status_visuals()


func _on_data_changed(_unit_data: UnitData) -> void:
	if not _scene_resources_initialized:
		return
	var all_passive_effects: Array[PassiveEffect] = data.get_all_passive_effects()
	update_triggered_actions(all_passive_effects)
	set_available_actions(all_passive_effects)
	data_updated.emit(self)


func _on_statuses_changed(_unit_data: UnitData) -> void:
	if not _scene_resources_initialized:
		return
	update_status_visuals()


func _on_appearance_changed(_unit_data: UnitData) -> void:
	if not _scene_resources_initialized:
		return
	var clean_sprite: String = data.spritesheeet_file_name.to_lower().trim_suffix(".spr")
	if clean_sprite != _rendered_sprite_name and (GameData.unit_spritesheet_data_paths.has(clean_sprite) or GameData.unit_spritesheets_data.has(clean_sprite)):
		set_sprite_by_file_name(clean_sprite)
	elif data.palette_id != _rendered_palette_id:
		_rendered_palette_id = data.palette_id
		if sprite_palette_id_override == -1 and _rendered_sprite_name != "":
			update_spritesheet_grid_texture()


func _on_primary_weapon_changed(weapon_unique_name: String) -> void:
	if not _scene_resources_initialized:
		return
	_apply_weapon_visuals()
	primary_weapon_assigned.emit(weapon_unique_name)


func _physics_process(delta: float) -> void:
	# FFTae (and all non-battles) don't use physics, so this can be turned off
	if global_battle_manager == null:
		set_physics_process(false)
		return
	
	# Add the gravity.
	if not char_body.is_on_floor():
		char_body.velocity += char_body.get_gravity() * delta
	
	var velocity_horizontal: Vector3 = char_body.velocity
	velocity_horizontal.y = 0
	if velocity_horizontal.length_squared() > 0.01:
		update_unit_facing(velocity_horizontal.normalized())
	char_body.move_and_slide()


func _process(_delta: float) -> void:
	if not GameData.is_ready:
		return
	
	if char_body.velocity.y != 0 and is_in_air == false:
		is_in_air = true
		
		#var mid_jump_animation: int = 62 # front facing mid jump animation
		#if animation_manager.is_back_facing:
			#mid_jump_animation += 1
		current_animation_id_fwd = mid_jump_animation
		#debug_menu.anim_id_spin.value = mid_jump_animation
	elif char_body.velocity.y == 0 and is_in_air == true:
		is_in_air = false
		
		#var idle_animation: int = 6 # front facing idle walk animation
		#if animation_manager.is_back_facing:
			#idle_animation += 1
		current_animation_id_fwd = current_idle_animation_id
		#debug_menu.anim_id_spin.value = idle_animation
	
	set_base_animation_ptr_id(current_animation_id_fwd)


static func generate_leveled_raw_stats(stat_basis_to_use: UnitData.StatBasis, final_level: int, job: JobData, new_stats_raw: Dictionary[UnitData.StatType, float], use_rom: bool = false) -> void:
	UnitData.generate_leveled_raw_stats(stat_basis_to_use, final_level, job, new_stats_raw, use_rom)


static func generate_level_zero_raw_stats(stat_basis_to_use: UnitData.StatBasis, new_stats_raw: Dictionary[UnitData.StatType, float], use_rom: bool = false) -> void:
	UnitData.generate_level_zero_raw_stats(stat_basis_to_use, new_stats_raw, use_rom)


static func generate_level_zero_raw_stat(stat_name: String, stat_basis_to_use: UnitData.StatBasis, use_rom: bool = false) -> int:
	return UnitData.generate_level_zero_raw_stat(stat_name, stat_basis_to_use, use_rom)


static func grow_raw_stats(current_level: int, current_job: JobData, new_stats_raw: Dictionary[UnitData.StatType, float]) -> void:
	UnitData.grow_raw_stats(current_level, current_job, new_stats_raw)


static func calc_battle_stats(
		current_job: JobData,
		new_stats_raw: Dictionary[UnitData.StatType, float],
		new_stats: Dictionary[UnitData.StatType, StatValue],
		set_to_max: bool = true,
		use_larger_values: bool = false) -> void:
	UnitData.calc_battle_stats(current_job, new_stats_raw, new_stats, set_to_max, use_larger_values)


func generate_random_abilities() -> void:
	data.generate_random_abilities()


func update_equipable_item_types(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_equipable_item_types(all_passive_effects)


func generate_equipment() -> void:
	data.generate_equipment()


func set_equipment_slot(slot: EquipmentSlot, item: ItemData) -> void:
	data.set_equipment_slot(slot, item)


func update_stat_modifiers(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_stat_modifiers(all_passive_effects)


func get_item_unique_name_for_slot(slot_type: ItemData.SlotType, item_level: int, random: bool = false) -> String:
	return data.get_item_unique_name_for_slot(slot_type, item_level, random)


func equip_ability(slot: AbilitySlot, ability: Ability) -> void:
	data.equip_ability(slot, ability)


func equip_skillset(skillset_idx: int, new_skillset: Skillset) -> void:
	data.equip_skillset(skillset_idx, new_skillset)


func update_triggered_actions(all_passive_effects: Array[PassiveEffect]) -> void:
	if job_data != null:
		for ability: Ability in job_data.innate_abilities:
			for triggered_action: TriggeredAction in ability.triggered_actions:
				triggered_action.connect_trigger(self)
	
	for ability_slot: AbilitySlot in ability_slots:
		for triggered_action: TriggeredAction in ability_slot.get_ability().triggered_actions:
				triggered_action.connect_trigger(self)

	for passive_effect: PassiveEffect in all_passive_effects:
		for triggered_action: TriggeredAction in passive_effect.added_triggered_actions:
			triggered_action.connect_trigger(self)


func update_elemental_affinity(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_elemental_affinity(all_passive_effects)


func append_element_array_unique(current_array: Array[Action.ElementTypes], array_to_append: Array[Action.ElementTypes]) -> Array[Action.ElementTypes]:
	return data.append_element_array_unique(current_array, array_to_append)


func start_turn(battle_manager: BattleManager) -> void:
	battle_manager.game_state_label.text = job_nickname + "-" + unit_nickname + " starting turn"
	is_ending_turn = false

	for status_effect: StatusEffect in current_statuses:
		if status_effect.action_on_turn_start != "":
			var action_instance: ActionInstance = ActionInstance.new(GameData.get_action(status_effect.action_on_turn_start), self, battle_manager)
			action_instance.submitted_targets = [tile_position] # TODO allow other targeting for status actions on turn start
			await action_instance.use()

	# set CT
	stats[StatType.CT].add_value(-100)
	
	turn_started.emit(self)

	await update_actions(battle_manager)


func update_actions(battle_manager: BattleManager) -> void:
	if is_ending_turn:
		await end_turn()
		return
	
	if battle_manager.active_unit != self:
		return
	
	battle_manager.game_state_label.text = job_nickname + "-" + unit_nickname + " updating available actions"
	
	clear_action_buttons(battle_manager)
	
	# get possible actions
	for action_instance: ActionInstance in actions_data.values():
		action_instance.clear()
	
	actions_data.clear()
	
	# show list UI for selecting an action TODO should action list be toggle/button group?
	# set_available_actions(get_all_passive_effects())
	for action: Action in actions:
		var modified_action: Action = Action.get_modified_action(action, self)
		var new_action_instance: ActionInstance = ActionInstance.new(modified_action, self, battle_manager)
		actions_data[modified_action.unique_name] = new_action_instance
		
		if new_action_instance.is_usable():
			await new_action_instance.update_potential_targets()
		new_action_instance.action_completed.connect(update_actions)
	
	update_action_buttons(battle_manager)
	
	await select_first_action()


func set_available_actions(all_passive_effects: Array[PassiveEffect]) -> void:
	actions = data.get_available_actions(move_action, wait_action, all_passive_effects)


func get_skillsets() -> Array[Skillset]:
	return data.get_skillsets()


func get_skillset_actions() -> Array[Action]:
	return data.get_skillset_actions()


func clear_action_buttons(battle_manager: BattleManager) -> void:
	for child: Node in battle_manager.action_button_list.get_children():
		child.queue_free()


func update_action_buttons(battle_manager: BattleManager) -> void:
	# show list UI for selecting an action TODO should action list be toggle/button group?
	for action_instance: ActionInstance in actions_data.values():
		var new_action_button: ActionButton = ActionButton.new(action_instance)
		battle_manager.action_button_list.add_child(new_action_button)
		
		# disable buttons for actions that are not usable - TODO provide hints why action is not usable - not enough mp, already moved, etc.
		if not action_instance.is_usable():
			new_action_button.disabled = true


func select_first_action() -> void:
	# select first usable action by default (usually Move)
	active_action = null
	if global_battle_manager.active_unit != self: # TODO improve game flow to prevent this state from ever occuring
		return
	
	for action_instance: ActionInstance in actions_data.values():
		if action_instance.is_usable() and action_instance != actions_data[wait_action.unique_name]:
			active_action = action_instance
			#await active_action.update_potential_targets() # already initialized in update_actions
			if not is_ai_controlled:
				active_action.start_targeting()
			break
	
	# end turn when no actions left
	if active_action == null or is_defeated:
		await end_turn()
	else:
		if is_ai_controlled:
			#await get_tree().process_frame
			await ai_controller.choose_action(self)


func end_turn() -> void:
	#if UnitControllerRT.unit != self: # prevent accidentally ending a different units turn TODO what if the next turn is also this unit?
		#return
	
	global_battle_manager.game_state_label.text = job_nickname + "-" + unit_nickname + " ending turn"
	
	if active_action != null:
		active_action.clear()
		active_action.stop_targeting()
	
	for status_effect: StatusEffect in current_statuses:
		if status_effect.action_on_turn_end != "":
			var action_instance: ActionInstance = ActionInstance.new(GameData.get_action(status_effect.action_on_turn_end), self, global_battle_manager)
			action_instance.submitted_targets = [tile_position] # TODO allow other targeting for status actions on turn end
			await action_instance.use()
		
		if status_effect.duration_type == StatusEffect.DurationType.TURNS:
			status_effect.duration -= 1
			if status_effect.duration < 0 and status_effect.action_on_complete != "":
				var status_action_instance: ActionInstance = ActionInstance.new(GameData.get_action(status_effect.action_on_complete), self, global_battle_manager)
				status_action_instance.submitted_targets.append(tile_position) # TODO get targets for status action
				global_battle_manager.game_state_label.text = job_nickname + "-" + unit_nickname + " processing " + status_effect.status_effect_name + " completing"
				await status_action_instance.use()

				remove_status(status_effect)

	# set some stats for next turn - move_points_remaining, action_points_remaining, etc.
	move_points_remaining = move_points_start
	action_points_remaining = action_points_start
	
	is_ending_turn = true
	if is_instance_valid(global_battle_manager.active_unit) and global_battle_manager.active_unit != self: # prevent accidentally ending a different units turn TODO what if the next turn is also this unit?
		push_error(job_nickname + "-" + unit_nickname + " trying to end turn, but active unit is: " + global_battle_manager.active_unit.name)
	else:
		clear_action_buttons(global_battle_manager)
		global_battle_manager.active_unit = null
		turn_ended.emit()


# TODO should these be triggered actions on the statuses?
func hp_changed(clamped_value: StatValue) -> void:
	if global_battle_manager == null: # TODO should statuses be applied outside battle?
		return
	
	@warning_ignore("integer_division")
	var critical_hp_threshold: int = clamped_value.max_value / 5

	if clamped_value.current_value == 0:
		await add_status(GameData.get_status_effect("dead").duplicate(), true) # add dead
	elif clamped_value.current_value < critical_hp_threshold: # critical
		if not current_status_ids.has("critical"):
			await add_status(GameData.get_status_effect("critical").duplicate()) # add critical
	elif clamped_value.current_value >= critical_hp_threshold: # not critical
		remove_status_id("critical") # remove critical


func add_status(new_status: StatusEffect, ignore_immunity: bool = false) -> void:
	var applied: bool = data.apply_status(new_status, ignore_immunity)
	if not applied:
		return
	
	# use action_on_apply
	if new_status.action_on_apply != "" and global_battle_manager != null:
		var action_instance: ActionInstance = ActionInstance.new(GameData.get_action(new_status.action_on_apply), self, global_battle_manager)
		action_instance.submitted_targets = [tile_position] # TODO allow other targeting for status actions on turn end
		await action_instance.use()


func remove_status_id(status_removed_unique_name: String) -> void:
	data.remove_status_id(status_removed_unique_name)


func remove_status(status_removed: StatusEffect, remove_permanent: bool = false) -> void:
	data.remove_status(status_removed, remove_permanent)


func get_nullify_statuses() -> Array[StatusEffect]:
	return data.get_nullify_statuses()


func update_permanent_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_permanent_statuses(all_passive_effects)


func update_immune_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_immune_statuses(all_passive_effects)


func update_start_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_start_statuses(all_passive_effects)


func update_status_visuals() -> void:
	var anim_priority: int = 0
	var shading_priority: int = 0
	var other_type_priority: int = 0
	var spritesheet_priority: int = 0

	var anim_status: StatusEffect
	var current_anim: int = current_animation_id_fwd
	var other_type_status: StatusEffect
	var spritesheet_status: StatusEffect
	if current_statuses.is_empty():
		if current_animation_id_fwd == current_idle_animation_id:
			current_idle_animation_id = idle_walk_animation_id
			set_base_animation_ptr_id(current_idle_animation_id)
		else:
			current_idle_animation_id = idle_walk_animation_id
		
		icon2.region_rect = Rect2i(Vector2i.ZERO, Vector2i.ONE)
		animation_manager.unit_sprites_manager.sprite_primary.modulate = Color.WHITE
		animation_manager.other_type_index = 0
		set_sprite_by_job(job_name)
	else:
		for status: StatusEffect in current_statuses:
			if status.order >= anim_priority and status.idle_animation_id != -1:
				anim_priority = status.order
				anim_status = status
				
				# if current_animation_id_fwd == current_idle_animation_id:
				# 	current_idle_animation_id = status.idle_animation_id
				# 	set_base_animation_ptr_id(status.idle_animation_id)
				# else:
				# 	current_idle_animation_id = status.idle_animation_id
			
			if status.order >= shading_priority and status.modulation_color != Color.BLACK:
				shading_priority = status.order
				animation_manager.unit_sprites_manager.sprite_primary.modulate = status.modulation_color
			
			if status.order >= other_type_priority and status.spritesheet_file_name == "other":
				other_type_priority = status.order
				other_type_status = status
			
			if status.order >= spritesheet_priority and status.spritesheet_file_name != "":
				spritesheet_priority = status.order
				spritesheet_status = status
		
		if shading_priority == 0:
			animation_manager.unit_sprites_manager.sprite_primary.modulate = Color.WHITE
		
		if other_type_priority == 0:
			animation_manager.other_type_index = 0
		else:
			animation_manager.other_type_index = other_type_status.other_type_index
		
		# if spritesheet is changing
		if spritesheet_priority == 0 and sprite_file_name != job_data.sprite_name:
			set_base_animation_ptr_id(0) # prevent out of bounds error in case SEQ is also changing
			set_sprite_by_job(job_name)
		elif spritesheet_priority != 0:
			set_base_animation_ptr_id(0) # prevent out of bounds error in case SEQ is also changing
			set_sprite_by_file_name(spritesheet_status.spritesheet_file_name)
		
		if anim_priority == 0: # if no statuses set the idle animation (may happen when status is removed)
			if current_anim == current_idle_animation_id:
				current_idle_animation_id = idle_walk_animation_id
				set_base_animation_ptr_id(current_idle_animation_id)
			else:
				current_idle_animation_id = idle_walk_animation_id
		else:
			if current_anim == current_idle_animation_id:
				current_idle_animation_id = anim_status.idle_animation_id
				set_base_animation_ptr_id(anim_status.idle_animation_id)
			else:
				current_idle_animation_id = anim_status.idle_animation_id

		# palette update must come after spritesheet change to make sure palettes are taken from correct spritesheet
		if other_type_priority != 0:
			set_sprite_palette_override(sprite_palette_id + other_type_status.palette_idx_offset)


func use_attack() -> void:
	can_move = false
	push_warning("using attack: " + primary_weapon.display_name)
	#push_warning("Animations: " + str(PackedInt32Array([action_data.animation_start_id, action_data.animation_charging_id, action_data.animation_executing_id])))
	#if action_data.animation_start_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_start_id + int(is_back_facing)
		#await animation_manager.animation_completed
	#
	#if action_data.animation_charging_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_charging_id + int(is_back_facing)
		#await get_tree().create_timer(0.1 + (action_data.ticks_charge_time * 0.1)).timeout
	
		#animation_executing_id = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#animation_manager.unit_debug_menu.anim_id_spin.value = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
	
	# execute atttack
	#debug_menu.anim_id_spin.value = (RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) + int(is_back_facing) # TODO lookup based on target relative height
	current_animation_id_fwd = roundi(RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) # TODO lookup based on target relative height
	set_base_animation_ptr_id(current_animation_id_fwd)
	
	# TODO implement proper timeout for abilities that execute using an infinite loop animation
	# this implementation can overwrite can_move when in the middle of another ability
	get_tree().create_timer(2).timeout.connect(func() -> void: can_move = true) 
	
	await animation_manager.animation_completed

	#ability_completed.emit()
	animation_manager.reset_sprites()
	#debug_menu.anim_id_spin.value = current_idle_animation_id  + int(is_back_facing)
	current_animation_id_fwd = current_idle_animation_id
	set_base_animation_ptr_id(current_animation_id_fwd)
	can_move = true


func use_ability(pos: Vector3) -> void:
	can_move = false
	print_debug("animating: " + action_data.display_name)
	#push_warning("Animations: " + str(PackedInt32Array([action_data.animation_start_id, action_data.animation_charging_id, action_data.animation_executing_id])))
	if action_data.animation_start_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_start_id + int(is_back_facing)
		current_animation_id_fwd = action_data.animation_start_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		await animation_manager.animation_completed
	
	if action_data.animation_charging_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_charging_id + int(is_back_facing)
		current_animation_id_fwd = action_data.animation_charging_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		await get_tree().create_timer(0.1 + (action_data.ticks_charge_time * 0.1)).timeout
	
	#if action_data.animation_executing_id != 0:
	if action_data.animation_executing_id < 0:
		pass
	elif action_data.animation_executing_id == 0:
		#animation_executing_id = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#animation_manager.unit_debug_menu.anim_id_spin.value = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#debug_menu.anim_id_spin.value = (RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) + int(is_back_facing) # TODO lookup based on target relative height
		current_animation_id_fwd = get_attack_action().animation_executing_id # TODO lookup based on target relative height
		set_base_animation_ptr_id(current_animation_id_fwd)
	else:
		var ability_animation_executing_id: int = action_data.animation_executing_id
		if ["ruka", "arute", "kanzen"].has(GameData.get_spritesheet_data(sprite_file_name).seq_name):
			ability_animation_executing_id = 0x2c * 2 # https://ffhacktics.com/wiki/Set_attack_animation_flags_and_facing_3
		#debug_menu.anim_id_spin.value = ability_animation_executing_id + int(is_back_facing)
		current_animation_id_fwd = ability_animation_executing_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		
	#var new_vfx_location: Node3D = Node3D.new()
	#new_vfx_location.position = pos
	##new_vfx_location.position.y += 2 # TODO set position dependent on ability vfx data
	#new_vfx_location.name = "VfxLocation"
	#get_parent().add_child(new_vfx_location)
	var action_instance: ActionInstance = ActionInstance.new(action_data, self, global_battle_manager)
	if is_instance_valid(action_instance.action.vfx_data):
		action_instance.show_vfx(pos)
	
	# TODO implement proper timeout for abilities that execute using an infinite loop animation
	# this implementation can overwrite can_move when in the middle of another ability
	get_tree().create_timer(2).timeout.connect(func() -> void: can_move = true) 
		
	await animation_manager.animation_completed

	ability_completed.emit()
	animation_manager.reset_sprites()
	#debug_menu.anim_id_spin.value = current_idle_animation_id  + int(is_back_facing)
	current_animation_id_fwd = current_idle_animation_id
	set_base_animation_ptr_id(current_animation_id_fwd)
	can_move = true


func animate_start_action(animation_start_id: int, animation_charging_id: int) -> void:
	if animation_start_id != 0:
		set_base_animation_ptr_id(animation_start_id)
		await animation_manager.animation_completed
	
	if animation_charging_id != 0:
		set_base_animation_ptr_id(animation_charging_id)
		await get_tree().create_timer(0.1 + (action_data.ticks_charge_time * 0.1)).timeout # TODO allow looping until changed, ie. charging a spell


func animate_execute_action(animation_executing_id: int) -> void:
	if animation_executing_id < 0: # no animatione
		return
	
	var ability_animation_executing_id: int = animation_executing_id
	if ["ruka", "arute", "kanzen"].has(GameData.get_spritesheet_data(sprite_file_name).seq_name):
		ability_animation_executing_id = 0x2c * 2 # https://ffhacktics.com/wiki/Set_attack_animation_flags_and_facing_3
	#debug_menu.anim_id_spin.value = ability_animation_executing_id + int(is_back_facing)
	set_base_animation_ptr_id(ability_animation_executing_id)
	
	await animation_manager.animation_completed # TODO change based on vfx timing data?
	
	if current_animation_id_fwd == animation_executing_id:
		animate_return_to_idle()


func animate_take_hit() -> void:
	set_base_animation_ptr_id(taking_damage_animation_id)
	
	#if vfx != null:
		#await vfx.vfx_completed
	#else:
		#await get_tree().create_timer(0.5).timeout # TODO show based on vfx timing data?
	#
	#if current_animation_id_fwd == taking_damage_animation_id:
		#animate_return_to_idle()


func animate_recieve_heal() -> void:
	set_base_animation_ptr_id(heal_animation_id)
	
	#if vfx != null:
		#await vfx.vfx_completed
	#else:
		#await get_tree().create_timer(1).timeout # TODO show based on vfx timing data?
	#
	#if current_animation_id_fwd == heal_animation_id:
		#animate_return_to_idle()


func return_to_idle_from_hit() -> void:
	if [taking_damage_animation_id, heal_animation_id].has(current_animation_id_fwd):
		animate_return_to_idle()


func animate_evade(evade_animation_fwd_id: int) -> void:
	set_base_animation_ptr_id(evade_animation_fwd_id)
	
	await animation_manager.animation_completed
	
	if current_animation_id_fwd == evade_animation_fwd_id:
		animate_return_to_idle()


func animate_knock_out() -> void:
	current_idle_animation_id = knocked_out_animation_id
	set_base_animation_ptr_id(knocked_out_animation_id)
	
	knocked_out.emit(self)


func animate_return_to_idle() -> void:
	# add random delay to prevent unit animations from syncing
	# Talcall: if changing animation to one of the walking animations (anything less than 0xC) it checks the unit ID && 0x3 against the event timer. if they are equal, start animating the unit. else... don't animate the unit.
	var desync_delay: float = randf_range(0.0, 0.25)
	await get_tree().create_timer(desync_delay).timeout 
	
	set_base_animation_ptr_id(current_idle_animation_id)


func set_base_animation_ptr_id(ptr_id: int) -> void:
	current_animation_id_fwd = ptr_id
	var new_ptr: int = ptr_id
	if is_back_facing and new_ptr > 5:
		new_ptr = ptr_id + 1
	elif is_back_facing and new_ptr > 0: # handle facing frames 
		new_ptr = ptr_id + 2
	else:
		new_ptr = ptr_id # null animation
	
	#if is_back_facing:
		#debug_menu.anim_id_spin.value = ptr_id + 1
		##animation_manager.global_animation_ptr_id = ptr_id + 1
	#else:
		#debug_menu.anim_id_spin.value = ptr_id
		##animation_manager.global_animation_ptr_id = ptr_id
	
	if animation_manager.global_animation_ptr_id != new_ptr:
		debug_menu.anim_id_spin.value = new_ptr # TODO the debug ui should not be the primary path to changing he animation
		#animation_manager.global_animation_ptr_id = new_ptr


func update_unit_facing(dir: Vector3) -> void:
	var angle_deg: float = rad_to_deg(atan2(dir.z, dir.x))
	angle_deg = fposmod(angle_deg, 359.99) + 45 # add 45 so EAST is just < 90 instead of < 45 and > 315
	angle_deg = fposmod(angle_deg, 359.99) # correction for values over 360 due to adding 45
	var new_facing: Facings = facing
	if angle_deg < 90:
		new_facing = Facings.EAST
	elif angle_deg < 180:
		new_facing = Facings.NORTH
	elif angle_deg < 270:
		new_facing = Facings.WEST
	elif angle_deg < 360:
		new_facing = Facings.SOUTH
	
	if new_facing != facing:
		facing = new_facing
		if global_battle_manager != null:
			update_animation_facing(global_battle_manager.camera_controller.camera_facing_vector)


func update_animation_facing(camera_facing_vector: Vector3) -> void:
	var unit_facing_vector: Vector3 = FACING_VECTORS[facing]
	#var camera_facing_vector: Vector3 = UnitControllerRT.CameraFacingVectors[controller.camera_facing]
	#var facing_difference: Vector3 = camera_facing_vector - unt_facing_vectorwad
	
	var unit_facing_angle: float = fposmod(rad_to_deg(atan2(unit_facing_vector.z, unit_facing_vector.x)), 359.99)
	var camera_facing_angle: float = fposmod(rad_to_deg(atan2(-camera_facing_vector.z, -camera_facing_vector.x)), 359.99)
	var facing_difference_angle: float = fposmod(camera_facing_angle - unit_facing_angle, 359.99)
		
	#push_warning("Difference: " + str(facing_difference) + ", UnitFacing: " + str(unit_facing_vector) + ", CameraFacing: " + str(camera_facing_vector))
	#push_warning("Difference: " + str(facing_difference_angle) + ", UnitFacing: " + str(unit_facing_angle) + ", CameraFacing: " + str(camera_facing_angle))
	#push_warning(rad_to_deg(atan2(facing_difference.z, facing_difference.x)))
	
	var new_is_right_facing: bool = false
	#is_back_facing: bool = false
	if facing_difference_angle < 90:
		new_is_right_facing = true
		is_back_facing = false
	elif facing_difference_angle < 180:
		new_is_right_facing = true
		is_back_facing = true
	elif facing_difference_angle < 270:
		new_is_right_facing = false
		is_back_facing = true
	elif facing_difference_angle < 360:
		new_is_right_facing = false
		is_back_facing = false
	
	if (animation_manager.is_right_facing != new_is_right_facing
			or animation_manager.is_back_facing != is_back_facing):
		animation_manager.set_face_right(new_is_right_facing)
		
		# TODO when changing fwd/back animations, retain the current step of the animation
		# Talcall: the direction the unit is facing gets updated on every parse of the routine, but unless the animation is changing, 
		# the instruction pointer byte doesn't get refreshed every vanilla animation is coded such that this swapping between front and back works flawlessly.
		if animation_manager.is_back_facing != is_back_facing:
			animation_manager.is_back_facing = is_back_facing
			var back_facing_offset: int = 1
			if debug_menu.anim_id_spin.value < 5:
				back_facing_offset = 2 # there are 5 directions of facing animations, so diagonal front facing id=2 and diagonal back facing id=4
				# TODO utilize the extra facing frames

			if is_back_facing == true:
				debug_menu.anim_id_spin.value += back_facing_offset
			else:
				debug_menu.anim_id_spin.value -= back_facing_offset


func toggle_debug_menu() -> void:
	debug_menu.visible = not debug_menu.visible


func hide_debug_menu() -> void:
	debug_menu.visible = false


# func set_job_id(new_job_id: int) -> void:
# 	job_id = new_job_id
# 	job_data = RomReader.scus_data.jobs_data[job_id]
# 	set_sprite_by_job_id(new_job_id)
	
# 	skillsets.clear()
# 	skillsets.append(RomReader.scus_data.skillsets_data[job_data.skillset_id])
	
# 	job_nickname = job_data.display_name
	
# 	if animation_manager.global_spr.flying_flag:
# 		idle_walk_animation_id = 0x0c
# 		walk_to_animation_id = 0x1e
# 		current_idle_animation_id = idle_walk_animation_id
# 		set_base_animation_ptr_id(idle_walk_animation_id)
# 	else:
# 		idle_walk_animation_id = 0x06
# 		walk_to_animation_id = 0x18
# 		current_idle_animation_id = idle_walk_animation_id
# 		set_base_animation_ptr_id(idle_walk_animation_id)
	
# 	update_passive_effects()


func set_job(new_job_name: String) -> void:
	data.set_job(new_job_name)
	if animation_manager != null and animation_manager.global_spritesheet_data != null:
		if animation_manager.global_spritesheet_data.is_flying:
			idle_walk_animation_id = 0x0c
			walk_to_animation_id = 0x1e
			current_idle_animation_id = idle_walk_animation_id
			set_base_animation_ptr_id(idle_walk_animation_id)
		else:
			idle_walk_animation_id = 0x06
			walk_to_animation_id = 0x18
			current_idle_animation_id = idle_walk_animation_id
			set_base_animation_ptr_id(idle_walk_animation_id)


func set_ability(new_action_name: String) -> void:
	active_ability_name = new_action_name
	action_data = GameData.get_action(new_action_name)
	
	# if not action_data.vfx_data.is_initialized:
	# 	action_data.vfx_data.init_from_file()
	
	image_changed.emit(GameData.get_texture(action_data.vfx_name))
	#debug_menu.sprite_viewer.texture = ImageTexture.create_from_image(action_data.vfx_data.vfx_spr.spritesheet)
	ability_assigned.emit(new_action_name)


func set_primary_weapon(new_weapon_unique_name: String) -> void:
	data.set_primary_weapon(new_weapon_unique_name)


func _apply_weapon_visuals() -> void:
	if animation_manager == null or primary_weapon == null:
		return
	var weapon_palette_id: int = primary_weapon.wep_frame_palette
	var weapon_eff_id: int = primary_weapon.wep_eff_palette
	var weapon_grid_texture: ImageTexture = animation_manager.wep_spritesheet_data.create_frame_grid_texture(
		0, 0, primary_weapon.wep_frame_v_offset, 0, animation_manager.wep_shp.file_name)
	animation_manager.unit_sprites_manager.set_weapon_texture(weapon_grid_texture)
	animation_manager.unit_sprites_manager.sprite_weapon.material_override.set_shader_parameter("palette_colors", GameData.get_spritesheet_data("wep").color_palette.slice(weapon_palette_id * 16, (weapon_palette_id + 1) * 16))
	animation_manager.unit_sprites_manager.sprite_effect.material_override.set_shader_parameter("palette_colors", GameData.get_spritesheet_data("eff").color_palette.slice(weapon_eff_id * 16, (weapon_eff_id + 1) * 16))


func get_attack_action() -> Action:
	return data.get_attack_action()


# https://ffhacktics.com/wiki/Determine_Status_Bubble_Parameters
# https://ffhacktics.com/wiki/Display_Status_Bubble
func set_icon(new_icon_id: int) -> void:
	icon2.region_rect = RomReader.battle_bin_data.status_icon_rects[new_icon_id]


func set_status_icon_rect(rect: Rect2i) -> void:
	icon2.region_rect = rect


func cycle_status_icons() -> void:
	var status_idx: int = 0
	while true:
		var status: StatusEffect = null
		if not current_statuses.is_empty():
			status_idx = (status_idx + 1) % current_statuses.size()
			status = current_statuses[status_idx]
			var rect: Rect2i = status.get_icon_rect()
			set_status_icon_rect(rect)
		else:
			status_idx = 0
		
		await get_tree().create_timer(icon_cycle_time).timeout
			
		#if current_statuses2.keys().all(func(status: StatusEffect): return status.status_icon_rects.is_empty()):
			#set_status_icon_rect(Rect2i(Vector2i.ZERO, Vector2i.ONE))
			#await get_tree().create_timer(icon_cycle_time).timeout
		#elif current_statuses2.keys()[status_idx].status_icon_rects.size() > 0:
			#var rect: Rect2i = current_statuses2.keys()[status_idx].status_icon_rects[0]
			##var rect: Rect2i = status.get_icon_rect()
			#set_status_icon_rect(rect)
			#await get_tree().create_timer(icon_cycle_time).timeout
			#
			#if current_statuses2.keys().size() > 0:
				#status_idx = (status_idx + 1) % current_statuses2.keys().size()
			#else:
				#status_idx = 0
		#else:
			#if current_statuses2.keys().size() > 0:
				#status_idx = (status_idx + 1) % current_statuses2.keys().size()
			#else:
				#status_idx = 0


func get_evade(evade_source: EvadeData.EvadeSource, evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> int:
	return data.get_evade(evade_source, evade_type, evade_direction)


func get_evade_values(evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> Dictionary[EvadeData.EvadeSource, int]:
	return data.get_evade_values(evade_type, evade_direction)


func update_passive_effects(exclude_passives: PackedStringArray = []) -> void:
	var refill_hp_mp: bool = (global_battle_manager != null and not global_battle_manager.battle_is_running)
	data.update_passive_effects(exclude_passives, refill_hp_mp)


func get_all_passive_effects(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	return data.get_all_passive_effects(exclude_passives)


func get_native_passive_effects(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	return data.get_native_passive_effects(exclude_passives)


func get_passive_effects_from_others(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	return data.get_passive_effects_from_others(exclude_passives)


func show_popup_text(text: String) -> void:
	popup_texts.show_popup_text(text)


func set_sprite_by_file_idx(new_sprite_file_idx: int) -> void:
	if sprite_file_idx == new_sprite_file_idx:
		return # do nothing if no change
	
	sprite_file_idx = new_sprite_file_idx
	var spr: Spr = RomReader.sprs[new_sprite_file_idx]
	sprite_file_name = spr.file_name
	if RomReader.spr_file_name_to_id.has(spr.file_name):
		sprite_id = RomReader.spr_file_name_to_id[spr.file_name]
	debug_menu.sprite_options.select(new_sprite_file_idx)
	#on_sprite_selected(new_sprite_file_idx)
	if spr.file_name == "WEP.SPR":
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 32
	else:
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 16 + (16 * spr.sp2s.size())
	update_spritesheet_grid_texture()
	
	debug_menu.anim_id_spin.value = current_idle_animation_id


func set_sprite_by_file_name(new_sprite_file_name: String) -> void:
	if new_sprite_file_name.is_empty():
		return
	sprite_file_name = new_sprite_file_name
	_rendered_sprite_name = new_sprite_file_name
	if animation_manager == null:
		return
	on_sprite_selected(new_sprite_file_name)
	var num_sp2s: int = min(0, (GameData.get_texture(new_sprite_file_name).get_height() - 488)) / 256
	if new_sprite_file_name == "wep":
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 32
	else:
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 16 + (16 * num_sp2s)
	update_spritesheet_grid_texture()
	
	if debug_menu != null:
		debug_menu.anim_id_spin.value = current_idle_animation_id


func set_sprite_by_id(new_sprite_id: int) -> void:
	var new_sprite_file_idx: int = RomReader.spr_id_file_idxs[new_sprite_id]
	set_sprite_by_file_idx(new_sprite_file_idx)


# func set_sprite_by_job_id(new_job_id: int) -> void:
# 	var job_id_data: JobData = RomReader.scus_data.jobs_data[job_id]
# 	var new_sprite_id: int = job_id_data.sprite_id
# 	if new_job_id >= 0x4a and new_job_id <= 0x5d and stat_basis == StatBasis.FEMALE:
# 		new_sprite_id += 1
# 	set_sprite_by_id(new_sprite_id)
# 	if new_job_id >= 0x5e: # monster
# 		set_sprite_palette(job_data.monster_palette_id)


func set_sprite_by_job(new_job_name: String) -> void:
	var new_job_data: JobData = GameData.get_job(new_job_name)
	
	# TODO get different sprite_name for female generic jobs
	var sprite_name: String = new_job_data.sprite_name
	if (new_job_data.job_id >= 0x4a and new_job_data.job_id <= 0x5a or new_job_data.job_id == 0x5d) and stat_basis == StatBasis.FEMALE:
		sprite_name = sprite_name.replace("_m", "_w")
	set_sprite_by_file_name(sprite_name)
	if data.palette_id >= 0:
		set_sprite_palette(data.palette_id)
	elif new_job_data.default_palette_idx != -1:
		set_sprite_palette(new_job_data.default_palette_idx)
	else:
		set_sprite_palette(randi_range(0, 4))


func set_sprite_palette(new_palette_id: int) -> void:
	sprite_palette_id = new_palette_id
	_rendered_palette_id = new_palette_id
	if sprite_palette_id_override == -1 and animation_manager != null: # don't update grid texture if palette is still being overridden
		update_spritesheet_grid_texture()


func set_sprite_palette_override(new_palette_id: int) -> void:
	if new_palette_id == sprite_palette_id_override:
		return
	
	sprite_palette_id_override = new_palette_id
	update_spritesheet_grid_texture()


func modulate_sprite_color(new_modulate_color: Color) -> void:
	animation_manager.unit_sprites_manager.sprite_primary.modulate = new_modulate_color


func set_sprite_tint(tint: Vector3) -> void:
	animation_manager.unit_sprites_manager.set_tint(tint)


func set_submerged_depth(new_depth: int) -> void:
	if new_depth == submerged_depth:
		return
	
	submerged_depth = new_depth
	update_spritesheet_grid_texture()


func update_spritesheet_grid_texture() -> void:
	if animation_manager == null or sprite_file_name.is_empty():
		return
	var new_spritesheet_data: UnitSpritesheetData = GameData.get_spritesheet_data(sprite_file_name)
	var palette_idx_final: int = sprite_palette_id_override
	if sprite_palette_id_override < 0:
		palette_idx_final = max(0, sprite_palette_id)
	var new_grid_texture: Texture2D = new_spritesheet_data.create_frame_grid_texture(
		0, animation_manager.other_type_index, 0, submerged_depth
	)
	animation_manager.unit_sprites_manager.set_primary_texture(new_grid_texture)
	animation_manager.unit_sprites_manager.sprite_primary.material_override.set_shader_parameter("palette_colors", new_spritesheet_data.color_palette.slice(palette_idx_final * 16, (palette_idx_final + 1) * 16))

	spritesheet_changed.emit(new_grid_texture)


func on_sprite_selected(new_spritesheet_name: String) -> void:
	# var spr: Spr = RomReader.sprs[index]
	# if not spr.is_initialized:
	# 	spr.set_data()
	# 	if RomReader.spr_file_name_to_id.keys().has(spr.file_name):
	# 		spr.set_spritesheet_data(RomReader.spr_file_name_to_id[spr.file_name])
	# 	else:
	# 		spr.set_spritesheet_data(-1) # get data for OTHER.SPR
	
	# animation_manager.global_spr = spr
	
	# var shp: Shp = RomReader.shps_array[RomReader.file_records[spr.shp_name].type_index]
	# if not shp.is_initialized:
	# 	shp.set_data_from_shp_bytes(RomReader.get_file_data(shp.file_name))
	
	# var seq: Seq = RomReader.seqs_array[RomReader.file_records[spr.seq_name].type_index]
	# if not seq.is_initialized:
	# 	seq.set_data_from_seq_bytes(RomReader.get_file_data(seq.file_name))
	
	var shp: Shp = GameData.get_spritesheet_data(new_spritesheet_name).get_shp()
	var animation_changed: bool = false
	if shp.file_name == "type2":
		if animation_manager.wep_shp.file_name != "wep2":
			animation_manager.wep_shp = GameData.get_shp("wep2")
			_apply_weapon_visuals() # get new texture based on wep2.shp
			animation_changed = true
		animation_manager.wep_seq = GameData.get_seq("wep2")
	else:
		if animation_manager.wep_shp.file_name != "wep1":
			animation_manager.wep_shp = GameData.get_shp("wep1")
			_apply_weapon_visuals() # get new texture based on wep1.shp
			animation_changed = true
		animation_manager.wep_seq = GameData.get_seq("wep1")
	
	var seq: Seq = GameData.get_spritesheet_data(new_spritesheet_name).get_seq()
	if shp != animation_manager.global_shp or seq != animation_manager.global_seq:
		animation_changed = true
	
	# animation_manager.global_spr = spr
	animation_manager.global_spritesheet_data = GameData.get_spritesheet_data(new_spritesheet_name)
	animation_manager.global_shp = shp
	animation_manager.global_seq = seq
	
	
	#spritesheet_changed.emit(animation_manager.unit_sprites_manager.sprite_item.texture) # TODO hook up to sprite for debug purposes
	#spritesheet_changed.emit(ImageTexture.create_from_image(spr.spritesheet)) # TODO hook up to sprite for debug purposes
	#spritesheet_changed.emit(animation_manager.unit_sprites_manager.sprite_weapon.texture) # TODO hook up to sprite for debug purposes
	if animation_changed:
		# if animation_manager.global_animation_id >= animation_manager.global_seq.sequences.size():
		# 	set_base_animation_ptr_id(6) # triggers on_animation_changed
		# else:
		animation_manager.on_animation_changed()


func update_prohibited_terrain(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_prohibited_terrain(all_passive_effects)


func update_terrain_costs(all_passive_effects: Array[PassiveEffect]) -> void:
	data.update_terrain_costs(all_passive_effects)


func set_position_to_tile() -> void:
	char_body.global_position = Vector3(tile_position.location.x + 0.5, tile_position.get_world_position().y + 0.25, tile_position.location.y + 0.5)


func update_map_paths(map_tiles: Dictionary[Vector2i, Array], units: Array[Unit], max_cost: int = 9999) -> void:
	paths_set = false
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects()
	update_prohibited_terrain(all_passive_effects)
	update_terrain_costs(all_passive_effects)
	ignore_height = all_passive_effects.any(func(passive_effect: PassiveEffect) -> bool: return passive_effect.ignore_height)
	
	if move_action.targeting_strategy.has_method("get_map_paths"):
		map_paths = await move_action.targeting_strategy.get_map_paths(self, map_tiles, units, max_cost)
		paths_set = true
		paths_updated.emit()


func _on_character_body_3d_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	unit_input_event.emit(self, event)

	# show Unit preview ui - hp, mp, evade, equipment, statuses, status immunities, element affinity, etc. portrait/mini sprite?
	if Input.is_action_just_pressed("secondary_action"):
		unit_battle_details_ui.visible = !unit_battle_details_ui.visible
