class_name Unit
extends Node3D

# https://ffhacktics.com/wiki/Miscellaneous_Unit_Data
# https://ffhacktics.com/wiki/Battle_Stats

signal initialized()
signal data_updated(unit: Unit)

signal ability_assigned(id: int)
signal ability_completed()
signal primary_weapon_assigned(item_unique_name: String)
signal image_changed(new_image: ImageTexture)
signal knocked_out(unit: Unit)
signal spritesheet_changed(new_spritesheet: ImageTexture)
signal targeted_pre_action(this_unit: Unit, action_instance: ActionInstance)
signal targeted_post_action(this_unit: Unit, action_instance: ActionInstance)
signal reached_tile()
signal completed_move(this_unit: Unit, tile_moved: int)
signal turn_started(this_unit: Unit)
signal turn_ended(this_unit: Unit)
signal unit_input_event(unit_data: Unit, event: InputEvent)
signal paths_updated()

enum StatBasis {
	MALE,
	FEMALE,
	OTHER,
	MONSTER,
}

enum Gender {
	MALE,
	FEMALE,
	OTHER,
	MONSTER,
}

enum StatType {
	HP,
	HP_MAX,
	MP,
	MP_MAX,
	CT,
	MOVE,
	JUMP,
	SPEED,
	PHYSICAL_ATTACK,
	MAGIC_ATTACK,
	BRAVE,
	FAITH,
	EXP,
	LEVEL,
}

enum Facings {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

static var unit_scene: PackedScene = load("res://src/Unit/unit.tscn")

const FacingVectors: Dictionary[Facings, Vector3] = {
	Facings.NORTH: Vector3.BACK,
	Facings.EAST: Vector3.RIGHT,
	Facings.SOUTH: Vector3.FORWARD,
	Facings.WEST: Vector3.LEFT,
}

var global_battle_manager: BattleManager
var team: Team
var is_controlled_by_me: bool = false # for multiplayer games
var is_ai_controlled: bool = false
var ai_controller: UnitAi = UnitAi.new()

@export var char_body: CharacterBody3D
@export var animation_manager: UnitAnimationManager
@export var popup_texts: PopupTextContainer
@export var stat_bars_position: Control
@export var stat_bars_container: Container
@export var unit_battle_details_ui: UnitDetailsBattleUi
@export var icon: UnitIcon
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
		return current_statuses.any(func(status: StatusEffect) -> bool: return status.counts_as_ko) # returns false when no statuses

@export var unit_nickname: String = "Unit Nickname"
@export var job_nickname: String = "Job Nickname"

var character_id: int = 0
var unit_index_formation: int = 0
var stat_basis: StatBasis = StatBasis.MALE
var gender: Gender = Gender.MALE
var job_id: int = 0
var job_data: JobData
var sprite_palette_id: int = 0
var sprite_palette_id_override: int = -1
var team_id: int = 0
var player_control: bool = true

var immortal: bool = false
var immune_knockback: bool = false
var game_over_trigger: bool = false
var type_id: int = 0 # male, female, monster
var death_counter: int = 3
var zodiac: String = "Ares"

var innate_ability_ids: PackedInt32Array = []
var skillsets: Array[ScusData.SkillsetData] = []

var equipable_item_types: Array[ItemData.ItemType] = []
var primary_weapon: ItemData
var equip_slots: Array[EquipmentSlot] = [
	EquipmentSlot.new("RH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
	EquipmentSlot.new("LH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
	EquipmentSlot.new("Head", [ItemData.SlotType.HEADGEAR]),
	EquipmentSlot.new("Body", [ItemData.SlotType.ARMOR]),
	EquipmentSlot.new("Accesory", [ItemData.SlotType.ACCESSORY]),
]

var ability_slots: Array[AbilitySlot] = [
	AbilitySlot.new("Skillset 1", [Ability.SlotType.SKILLSET]),
	AbilitySlot.new("Skillset 2", [Ability.SlotType.SKILLSET]),
	AbilitySlot.new("Reaction", [Ability.SlotType.REACTION]),
	AbilitySlot.new("Support", [Ability.SlotType.SUPPORT]),
	AbilitySlot.new("Movement", [Ability.SlotType.MOVEMENT]),
]

var stats: Dictionary[StatType, StatValue] = {
	StatType.HP_MAX : StatValue.new(0, 999, 150),
	StatType.HP : StatValue.new(0, 150, 100),
	StatType.MP_MAX : StatValue.new(0, 999, 100),
	StatType.MP : StatValue.new(0, 100, 70),
	StatType.CT : StatValue.new(0, 999, 25),
	StatType.MOVE : StatValue.new(0, 100, 3),
	StatType.JUMP : StatValue.new(0, 100, 3),
	StatType.SPEED : StatValue.new(0, 100, 10),
	StatType.PHYSICAL_ATTACK : StatValue.new(0, 100, 11),
	StatType.MAGIC_ATTACK : StatValue.new(0, 100, 12),
	StatType.BRAVE : StatValue.new(0, 100, 70),
	StatType.FAITH : StatValue.new(0, 100, 65),
	StatType.EXP : StatValue.new(0, 999, 99),
	StatType.LEVEL : StatValue.new(0, 99, 20),
}

var stats_raw: Dictionary[StatType, float] = {
	StatType.HP_MAX : 0.0, 
	StatType.MP_MAX : 0.0, 
	StatType.SPEED : 0.0, 
	StatType.PHYSICAL_ATTACK : 0.0, 
	StatType.MAGIC_ATTACK : 0.0, 
}


var unit_exp: int = 0:
	get: return stats[StatType.EXP].current_value
var level: int = 0:
	get: return stats[StatType.LEVEL].current_value

var brave_base: int = 70
var brave_current: int = 70:
	get: return stats[StatType.BRAVE].modified_value
var faith_base: int = 70
var faith_current: int = 70:
	get: return stats[StatType.FAITH].modified_value

var ct_current: int = 0:
	get: return stats[StatType.CT].current_value
var ct_max: int = 100:
	get: return stats[StatType.CT].max_value

var hp_max_base: int = 100:
	get: return stats[StatType.HP_MAX].base_value
var hp_max: int = 100:
	get: return stats[StatType.HP_MAX].modified_value
var hp_current: int = 70:
	get: return stats[StatType.HP].current_value
var mp_max_base: int = 100:
	get: return stats[StatType.MP_MAX].base_value
var mp_max: int = 100:
	get: return stats[StatType.MP_MAX].modified_value
var mp_current: int = 70:
	get: return stats[StatType.MP].current_value

var physical_attack_base: int = 5:
	get: return stats[StatType.PHYSICAL_ATTACK].base_value
var physical_attack_current: int = 5:
	get: return stats[StatType.PHYSICAL_ATTACK].modified_value
var magical_attack_base: int = 5:
	get: return stats[StatType.MAGIC_ATTACK].base_value
var magical_attack_current: int = 5:
	get: return stats[StatType.MAGIC_ATTACK].modified_value
var speed_base: int = 5:
	get: return stats[StatType.SPEED].base_value
var speed_current: int = 5:
	get: return stats[StatType.SPEED].modified_value
var move_base: int = 5:
	get: return stats[StatType.MOVE].base_value
var move_current: int = 5:
	get: return stats[StatType.MOVE].modified_value
var jump_base: int = 5:
	get: return stats[StatType.JUMP].base_value
var jump_current: int = 3:
	get: return stats[StatType.JUMP].modified_value

var always_statuses: PackedStringArray = []
var immune_statuses: PackedStringArray = []
var start_statuses: PackedStringArray = []

# TODO clean up unit status stuff
var current_statuses: Array[StatusEffect] = [] # entry will be duplicate of status definition with modified values (duration_left, delayed action, etc)
var current_status_ids: PackedStringArray = []:
	get:
		var status_unique_names: PackedStringArray = []
		for status: StatusEffect in current_statuses:
			if not status_unique_names.has(status.unique_name):
				status_unique_names.append(status.unique_name)
		return status_unique_names
#var current_statuses2: Dictionary[StatusEffect, int] = {}

var learned_abilities: Array = []
var job_levels: Dictionary[JobData, int] = {}
var job_jp: Dictionary[JobData, int] = {}

var charging_abilities_ids: PackedInt32Array = []
var charging_abilities_remaining_ct: PackedInt32Array = [] # TODO this should be tracked per ability?
var sprite_id: int = 0
var sprite_file_idx: int = 0
var sprite_file_name: String = "sprite_file_name.spr"
var portrait_palette_id: int = 0
var unit_id: int = 0
var special_job_skillset_id: int = 0

@export var elemental_absorb: Array[Action.ElementTypes] = []
@export var elemental_cancel: Array[Action.ElementTypes] = []
@export var elemental_half: Array[Action.ElementTypes] = []
@export var elemental_weakness: Array[Action.ElementTypes] = []
@export var elemental_strengthen: Array[Action.ElementTypes] = []

var can_move: bool = true

#var map_position: Vector2i
var tile_position: TerrainTile
var prohibited_terrain: Array[int] = [] # TileTerrain.surface_type_id
var terrain_costs: Dictionary[int, int] = {} # [TileTerrain.surface_type_id, cost]
var ignore_height: bool = false

var map_paths: Dictionary[TerrainTile, TerrainTile]
var path_costs: Dictionary[TerrainTile, float]
var paths_set: bool = false
@export var tile_highlights: Node3D
var facing: Facings = Facings.NORTH
var is_back_facing: bool = false
var facing_vector: Vector3 = Vector3.FORWARD:
	get:
		return FacingVectors[facing]

var is_in_air: bool = false
var is_traveling_path: bool = false

var active_ability_id: int = 0
var ability_data: FftAbilityData

var active_action: ActionInstance
#@export var action_instance: ActionInstance
@export var move_action: Action
@export var attack_action: Action
@export var wait_action: Action
@export var actions: Array[Action] = []
var actions_data: Dictionary[String, ActionInstance] = {}
@export var move_points_start: int = 1
@export var move_points_remaining: int = 1
@export var action_points_start: int = 1
@export var action_points_remaining: int = 1
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
	return unit_scene.instantiate()


func _ready() -> void:
	stats[StatType.HP_MAX].value_changed.connect(stats[StatType.HP].update_max_from_clamped_value)
	stats[StatType.MP_MAX].value_changed.connect(stats[StatType.MP].update_max_from_clamped_value)
	stats[StatType.HP].value_changed.connect(hp_changed)

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
	
	cycle_status_icons()
	
	add_to_group("Units")

	if not RomReader.is_ready:
		RomReader.rom_loaded.connect(initialize_unit)
	else:
		initialize_unit()


func _exit_tree() -> void:
	if global_battle_manager != null and is_queued_for_deletion():
		var unit_index: int = global_battle_manager.units.find(self)
		for action_instance: ActionInstance in actions_data.values():
			action_instance.stop_targeting()
		if unit_index != -1: # if the unit is in the battle_manager array
			global_battle_manager.units.remove_at(unit_index)


func add_stat_bar(stat_type: StatType) -> StatBar:
	var new_stat_bar: StatBar = StatBar.instantiate()
	new_stat_bar.set_stat(str(StatType.keys()[stat_type]), stats[stat_type])
	stat_bars_container.add_child(new_stat_bar)

	return new_stat_bar


func update_stat_bars_scale(camera_zoom: float) -> void:
	stat_bars_position.scale = Vector2.ONE * 3.775 / camera_zoom


func initialize_unit() -> void:
	debug_menu.populate_options()
	
	animation_manager.wep_spr = RomReader.sprs[RomReader.file_records["WEP.SPR"].type_index]
	animation_manager.wep_shp = RomReader.shps_array[RomReader.file_records["WEP1.SHP"].type_index]
	animation_manager.wep_seq = RomReader.seqs_array[RomReader.file_records["WEP1.SEQ"].type_index]
	
	animation_manager.eff_spr = RomReader.sprs[RomReader.file_records["EFF.SPR"].type_index]
	animation_manager.eff_shp = RomReader.shps_array[RomReader.file_records["EFF1.SHP"].type_index]
	animation_manager.eff_seq = RomReader.seqs_array[RomReader.file_records["EFF1.SEQ"].type_index]
	
	animation_manager.unit_sprites_manager.sprite_effect.texture = animation_manager.eff_spr.create_frame_grid_texture(0, 0, 0, 0, 0)
	
	animation_manager.item_spr = RomReader.sprs[RomReader.file_records["ITEM.BIN"].type_index]
	
	animation_manager.unit_sprites_manager.sprite_item.texture = ImageTexture.create_from_image(RomReader.sprs[RomReader.file_records["ITEM.BIN"].type_index].spritesheet)
	
	animation_manager.other_spr = RomReader.sprs[RomReader.file_records["OTHER.SPR"].type_index]
	animation_manager.other_shp = RomReader.shps_array[RomReader.file_records["OTHER.SHP"].type_index]
	
	# 1 cure
	# 0xc8 blood suck
	# 0x9b stasis sword
	set_ability(0x9b)
	set_primary_weapon("mythril_spear") # 1 - dagger, 72 - mythril gun, 101 - mythril spear
	# TODO use equipment_slots
	set_sprite_by_file_idx(98) # RAMUZA.SPR # TODO use sprite_id?
	#set_sprite_by_file_name("RAMUZA.SPR")
	
	update_unit_facing(FacingVectors[Facings.SOUTH])
	
	var random_name_idx: int = randi_range(0, RomReader.fft_text.unit_names_list_filtered.size() - 1)
	unit_nickname = RomReader.fft_text.unit_names_list_filtered[random_name_idx]

	initialized.emit()


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
	if not RomReader.is_ready:
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


static func generate_leveled_raw_stats(stat_basis_to_use: StatBasis, final_level: int, job: JobData, new_stats_raw: Dictionary[Unit.StatType, float]) -> void:
	generate_level_zero_raw_stats(stat_basis_to_use, new_stats_raw)
	
	for curent_level: int in range(1, final_level + 1):
		grow_raw_stats(curent_level, job, new_stats_raw)


static func generate_level_zero_raw_stats(stat_basis_to_use: StatBasis, new_stats_raw: Dictionary[Unit.StatType, float]) -> void:
	new_stats_raw[StatType.HP_MAX] = generate_level_zero_raw_stat(0, stat_basis_to_use)
	new_stats_raw[StatType.MP_MAX] = generate_level_zero_raw_stat(1, stat_basis_to_use)
	new_stats_raw[StatType.SPEED] = generate_level_zero_raw_stat(2, stat_basis_to_use)
	new_stats_raw[StatType.PHYSICAL_ATTACK] = generate_level_zero_raw_stat(3, stat_basis_to_use)
	new_stats_raw[StatType.MAGIC_ATTACK] = generate_level_zero_raw_stat(4, stat_basis_to_use)


# TODO is this correct for MONSTERs and LUCAVI?
static func generate_level_zero_raw_stat(stat_idx: int, stat_basis_to_use: StatBasis) -> int:
	var raw_stat: int = RomReader.scus_data.unit_base_datas[stat_basis_to_use][stat_idx] * 16384
	raw_stat += randi_range(0, RomReader.scus_data.unit_base_stats_mods[stat_basis_to_use][stat_idx] * 16384)
	return raw_stat


static func grow_raw_stats(current_level: int, current_job: JobData, new_stats_raw: Dictionary[Unit.StatType, float]) -> void:
	new_stats_raw[StatType.HP_MAX] += new_stats_raw[StatType.HP_MAX] / (current_job.hp_growth + current_level)
	new_stats_raw[StatType.MP_MAX] += new_stats_raw[StatType.MP_MAX] / (current_job.mp_growth + current_level)
	new_stats_raw[StatType.SPEED] += new_stats_raw[StatType.SPEED] / (current_job.speed_growth + current_level)
	new_stats_raw[StatType.PHYSICAL_ATTACK] += new_stats_raw[StatType.PHYSICAL_ATTACK] / (current_job.pa_growth + current_level)
	new_stats_raw[StatType.MAGIC_ATTACK] += new_stats_raw[StatType.MAGIC_ATTACK] / (current_job.ma_growth + current_level)


# TODO is this correct for MONSTERs?
static func calc_battle_stats(
		current_job: JobData, 
		new_stats_raw: Dictionary[Unit.StatType, float], 
		new_stats: Dictionary[Unit.StatType, StatValue],
		set_to_max: bool = true,
		use_larger_values: bool = false) -> void:
	var base_hp: int = roundi(new_stats_raw[StatType.HP_MAX] * current_job.hp_multiplier / 0x190000)
	# if ["RUKA.SEQ", "KANZEN.SEQ", "ARUTE.SEQ"].has(animation_manager.global_seq.file_name): # lucavi
	if use_larger_values:
		new_stats[StatType.HP_MAX].max_value = 99999
		base_hp = base_hp * 100
	new_stats[StatType.HP_MAX].base_value = base_hp
	new_stats[StatType.HP_MAX].set_value(new_stats[StatType.HP_MAX].base_value)
	
	var base_mp: int = roundi(new_stats_raw[StatType.MP_MAX] * current_job.mp_multiplier / 0x190000)
	# if ["RUKA.SEQ", "KANZEN.SEQ", "ARUTE.SEQ"].has(animation_manager.global_seq.file_name): # lucavi
	if use_larger_values:
		new_stats[StatType.MP_MAX].max_value = 99999
		base_mp = base_mp * 100
	new_stats[StatType.MP_MAX].base_value = base_mp
	new_stats[StatType.MP_MAX].set_value(new_stats[StatType.MP_MAX].base_value)
	
	new_stats[StatType.SPEED].base_value = roundi(new_stats_raw[StatType.SPEED] * current_job.speed_multiplier / 0x190000)
	new_stats[StatType.SPEED].set_value(new_stats[StatType.SPEED].base_value)
	
	new_stats[StatType.PHYSICAL_ATTACK].base_value = roundi(new_stats_raw[StatType.PHYSICAL_ATTACK] * current_job.pa_multiplier / 0x190000)
	new_stats[StatType.PHYSICAL_ATTACK].set_value(new_stats[StatType.PHYSICAL_ATTACK].base_value)
	
	new_stats[StatType.MAGIC_ATTACK].base_value = roundi(new_stats_raw[StatType.MAGIC_ATTACK] * current_job.ma_multiplier / 0x190000)
	new_stats[StatType.MAGIC_ATTACK].set_value(new_stats[StatType.MAGIC_ATTACK].base_value)
	
	new_stats[StatType.MOVE].base_value = current_job.move
	new_stats[StatType.MOVE].set_value(new_stats[StatType.MOVE].base_value)
	
	new_stats[StatType.JUMP].base_value = current_job.jump
	new_stats[StatType.JUMP].set_value(new_stats[StatType.JUMP].base_value)

	# if global_battle_manager != null:
	# 	if not global_battle_manager.battle_is_running:
	# 		new_stats[StatType.HP].set_value(new_stats[StatType.HP].max_value)
	# 		new_stats[StatType.MP].set_value(new_stats[StatType.MP].max_value)
	
	if set_to_max:
		new_stats[StatType.HP].set_value(new_stats[StatType.HP].max_value)
		new_stats[StatType.MP].set_value(new_stats[StatType.MP].max_value)


func generate_random_abilities() -> void:
	var random_reaction: Ability = RomReader.abilities.values().filter(func(ability: Ability) -> bool: return ability.slot_type == Ability.SlotType.REACTION).pick_random()
	var random_support: Ability = RomReader.abilities.values().filter(func(ability: Ability) -> bool: return ability.slot_type == Ability.SlotType.SUPPORT).pick_random()
	var random_movement: Ability = RomReader.abilities.values().filter(func(ability: Ability) -> bool: return ability.slot_type == Ability.SlotType.MOVEMENT).pick_random()

	ability_slots[2].ability_unique_name = random_reaction.unique_name
	ability_slots[3].ability_unique_name =  random_support.unique_name
	ability_slots[4].ability_unique_name =  random_movement.unique_name

	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects()
	update_passive_effects()


func update_equipable_item_types(all_passive_effects: Array[PassiveEffect]) -> void:
	equipable_item_types = []
	
	for passive_effect: PassiveEffect in all_passive_effects:
		equipable_item_types.append_array(passive_effect.added_equipment_types_equipable)
	
	equipable_item_types.append_array(job_data.equippable_item_types) # TODO job equipable item types should be in passive effect


# TODO generate equipment https://ffhacktics.com/wiki/Calculate/Store_ENTD_Unit_Equipment
func generate_equipment() -> void:
	#if not ["TYPE1.SEQ", "TYPE3.SEQ"].has(animation_manager.global_seq.file_name): # monsters don't have equipment
		#return
	
	equip_slots[0].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.WEAPON, level) # RH
	equip_slots[1].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.SHIELD, level) # LH
	equip_slots[2].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.HEADGEAR, level) # headgear
	equip_slots[3].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.ARMOR, level) # armor
	equip_slots[4].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.ACCESSORY, level, true) # accessory
	
	set_primary_weapon(equip_slots[0].item_unique_name)
	
	update_passive_effects()


func set_equipment_slot(slot: EquipmentSlot, item: ItemData) -> void:
	slot.item_unique_name = item.unique_name
	
	update_passive_effects()


func update_stat_modifiers(all_passive_effects: Array[PassiveEffect]) -> void:
	# remove all to start fresh
	for stat_type: StatType in StatType.values():
		if not stats[stat_type].modifiers.is_empty():
			stats[stat_type].modifiers.clear()

	for passive_effect: PassiveEffect in all_passive_effects:
		for stat_type: StatType in passive_effect.stat_modifiers.keys():
			stats[stat_type].add_modifier(passive_effect.stat_modifiers[stat_type], false)
	
	for stat_type: StatType in StatType.values():
		stats[stat_type].value_changed.emit(stats[stat_type])


func get_item_unique_name_for_slot(slot_type: ItemData.SlotType, item_level: int, random: bool = false) -> String:
	var valid_items: Array[ItemData] = []
	valid_items.assign(RomReader.items.values().filter(func(item: ItemData) -> bool: 
		var slot_type_is_valid: bool = item.slot_type == slot_type
		var level_is_valid: bool = item.min_level <= item_level
		var type_is_valid: bool = equipable_item_types.has(item.item_type) # TODO allow forcing specifc type based on ability requirements
		return slot_type_is_valid and level_is_valid and type_is_valid))
	var item_unique_name: String = ""
	if not valid_items.is_empty():
		if random:
			item_unique_name = valid_items.pick_random().unique_name
		else:
			valid_items.sort_custom(func(item_a: ItemData, item_b: ItemData) -> bool: return item_a.min_level > item_b.min_level)
			item_unique_name = valid_items[0].unique_name # pick highest level item
			#item = valid_items.pick_random()
	return item_unique_name


func equip_ability(slot: AbilitySlot, ability: Ability) -> void:
	slot.ability_unique_name = ability.unique_name

	update_passive_effects()


func update_triggered_actions(all_passive_effects: Array[PassiveEffect]) -> void:
	if job_data != null:
		for ability: Ability in job_data.innate_abilities:
			for triggered_action: TriggeredAction in ability.triggered_actions:
				triggered_action.connect_trigger(self)
	
	for ability_slot: AbilitySlot in ability_slots:
		for triggered_action: TriggeredAction in ability_slot.ability.triggered_actions:
				triggered_action.connect_trigger(self)

	for passive_effect: PassiveEffect in all_passive_effects:
		for triggered_action: TriggeredAction in passive_effect.added_triggered_actions:
			triggered_action.connect_trigger(self)


func update_elemental_affinity(all_passive_effects: Array[PassiveEffect]) -> void:
	elemental_absorb.clear()
	elemental_cancel.clear()
	elemental_half.clear()
	elemental_strengthen.clear()
	elemental_weakness.clear()

	for passive_effect: PassiveEffect in all_passive_effects:
		elemental_absorb = append_element_array_unique(elemental_absorb, passive_effect.element_absorb)
		elemental_cancel = append_element_array_unique(elemental_cancel, passive_effect.element_cancel)
		elemental_half = append_element_array_unique(elemental_half, passive_effect.element_half)
		elemental_strengthen = append_element_array_unique(elemental_strengthen, passive_effect.element_strengthen)
		elemental_weakness = append_element_array_unique(elemental_weakness, passive_effect.element_weakness)


func append_element_array_unique(current_array: Array[Action.ElementTypes], array_to_append: Array[Action.ElementTypes]) -> Array[Action.ElementTypes]:
	for element: Action.ElementTypes in array_to_append:
		if not current_array.has(element):
			current_array.append(element)
	
	return current_array


func start_turn(battle_manager: BattleManager) -> void:
	battle_manager.game_state_label.text = job_nickname + "-" + unit_nickname + " starting turn"
	is_ending_turn = false

	for status_effect: StatusEffect in current_statuses:
		if status_effect.action_on_turn_start != "":
			var action_instance: ActionInstance = ActionInstance.new(RomReader.actions[status_effect.action_on_turn_start], self, battle_manager)
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
	actions.clear()
	actions.append(move_action)
	actions.append(attack_action)
	
	actions.append_array(get_skillset_actions()) # TODO move to skillset ability

	for passive_effect: PassiveEffect in all_passive_effects:
		for action: Action in passive_effect.added_actions:
			if not actions.has(action):
				actions.append(action)
	
	actions.append(wait_action)


func get_skillset_actions() -> Array[Action]:
	var action_list: Array[Action] = []
	for skillset: ScusData.SkillsetData in skillsets:
		for ability_id: int in skillset.action_ability_ids:
			if ability_id != 0:
				var new_action: Action = RomReader.fft_abilities[ability_id].ability_action
				action_list.append(new_action)
	return action_list


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
			var action_instance: ActionInstance = ActionInstance.new(RomReader.actions[status_effect.action_on_turn_end], self, global_battle_manager)
			action_instance.submitted_targets = [tile_position] # TODO allow other targeting for status actions on turn end
			await action_instance.use()
		
		if status_effect.duration_type == StatusEffect.DurationType.TURNS:
			status_effect.duration -= 1
			if status_effect.duration < 0 and status_effect.action_on_complete != "":
				var status_action_instance: ActionInstance = ActionInstance.new(RomReader.actions[status_effect.action_on_complete], self, global_battle_manager)
				status_action_instance.submitted_targets.append(tile_position) # TODO get targets for status action
				global_battle_manager.game_state_label.text = job_nickname + "-" + unit_nickname + " processing " + status_effect.status_effect_name + " completing"
				await status_action_instance.use()

				remove_status(status_effect)

	# set some stats for next turn - move_points_remaining, action_points_remaining, etc.
	move_points_remaining = move_points_start
	action_points_remaining = action_points_start
	
	is_ending_turn = true
	if global_battle_manager.active_unit != self: # prevent accidentally ending a different units turn TODO what if the next turn is also this unit?
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
		await add_status(RomReader.status_effects["dead"].duplicate(), true) # add dead
	elif clamped_value.current_value < critical_hp_threshold: # critical
		if not current_status_ids.has("critical"):
			await add_status(RomReader.status_effects["critical"].duplicate()) # add critical
	elif clamped_value.current_value >= critical_hp_threshold: # not critical
		remove_status_id("critical") # remove critical


func add_status(new_status: StatusEffect, ignore_immunity: bool = false) -> void:
	if not ignore_immunity and immune_statuses.has(new_status.unique_name): # prevent application based on immune statuses
		return
	
	for status_prevents_id: String in new_status.status_cant_stack: # prevent application based on flags
		if current_statuses.any(func(status: StatusEffect) -> bool: return status.unique_name == status_prevents_id):
			return
	
	var existing_statuses: Array[StatusEffect] = current_statuses.filter(func(status: StatusEffect) -> bool: return status.status_id == new_status.status_id) # TODO use filter to allow for multiple of the same status, ex. double charging
	if existing_statuses.size() >= new_status.num_allowed:
		var temp_statuses: Array[StatusEffect] = existing_statuses.filter(func(status: StatusEffect) -> bool: return status.duration_type != StatusEffect.DurationType.PERMANENT)
		if not temp_statuses.is_empty():
			remove_status(temp_statuses[0]) # remove oldest temp status
		else:
			return # if already has max stack of status and they are all permanent
	
	current_statuses.append(new_status)
	# use action_on_apply
	if new_status.action_on_apply != "":
		var action_instance: ActionInstance = ActionInstance.new(RomReader.actions[new_status.action_on_apply], self, global_battle_manager)
		action_instance.submitted_targets = [tile_position] # TODO allow other targeting for status actions on turn end
		await action_instance.use()
	
	var statuses_to_cancel: Array[StatusEffect] = []
	for status_cancelled_id: String in new_status.status_cancels:
		remove_status_id(status_cancelled_id)
	
	update_status_visuals()
	update_passive_effects()


func remove_status_id(status_removed_unique_name: String) -> void:
	var statuses_to_remove: Array[StatusEffect] = []
	statuses_to_remove.append_array(current_statuses.filter(func(status: StatusEffect) -> bool: return status.unique_name == status_removed_unique_name and status.duration_type != StatusEffect.DurationType.PERMANENT))
	for status: StatusEffect in statuses_to_remove:
		remove_status(status)


func remove_status(status_removed: StatusEffect, remove_permanent: bool = false) -> void:
	if status_removed.duration_type == StatusEffect.DurationType.PERMANENT and not remove_permanent:
		push_error("Trying to removing Always status: " + status_removed.status_effect_name)
		return
	
	for stat: StatType in status_removed.passive_effect.stat_modifiers.keys():
		stats[stat].remove_modifier(status_removed.passive_effect.stat_modifiers[stat])
	current_statuses.erase(status_removed)
	update_status_visuals()
	update_passive_effects()


func get_nullify_statuses() -> Array[StatusEffect]:
	return current_statuses.filter(func(status: StatusEffect) -> bool: return status.passive_effect.nullify_targeted)


func update_permanent_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	always_statuses.clear()
	for passive_effect: PassiveEffect in all_passive_effects:
		always_statuses.append_array(passive_effect.status_always)
	
	for status_unique_name: String in RomReader.status_effects.keys():
		if immune_statuses.has(status_unique_name):
			continue
		
		var num_should_have: int = 0

		# check passive sources: equipment, job, abilities, statuses
		for passive_effect: PassiveEffect in all_passive_effects:
			num_should_have += passive_effect.status_always.count(status_unique_name)
		
		var current_permanent: Array[StatusEffect] = current_statuses.filter(func(status: StatusEffect) -> bool: return status.unique_name == status_unique_name and status.duration_type == StatusEffect.DurationType.PERMANENT)
		var num_has: int = current_permanent.size()
		var change: int = num_should_have - num_has
		
		if change == 0:
			continue
		elif change > 0:
			for counter: int in change:
				var new_status: StatusEffect = RomReader.status_effects[status_unique_name].duplicate()
				new_status.duration_type = StatusEffect.DurationType.PERMANENT
				await add_status(new_status)
		elif change < 0:
			for counter: int in -change:
				var status_to_remove: StatusEffect = current_permanent[-counter - 1] # remove most recent permanent stack
				remove_status(status_to_remove, true)


func update_immune_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	immune_statuses.clear()

	for passive_effect: PassiveEffect in all_passive_effects:
		immune_statuses.append_array(passive_effect.status_immune)
	
	#for status: StatusEffect in current_statuses:
		#if immune_statuses.has(status.unique_name):
			#remove_status(status, true)


func update_start_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	start_statuses.clear()

	for passive_effect: PassiveEffect in all_passive_effects:
		start_statuses.append_array(passive_effect.status_start)


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
		set_sprite_by_job_id(job_id)
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
			
			if status.order >= other_type_priority and status.spritesheet_file_name == "OTHER.SPR":
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
		if spritesheet_priority == 0 and sprite_file_name != RomReader.sprs[RomReader.spr_id_file_idxs[job_data.sprite_id]].file_name:
			set_base_animation_ptr_id(0) # prevent out of bounds error in case SEQ is also changing
			set_sprite_by_job_id(job_id)
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
	#push_warning("Animations: " + str(PackedInt32Array([ability_data.animation_start_id, ability_data.animation_charging_id, ability_data.animation_executing_id])))
	#if ability_data.animation_start_id != 0:
		#debug_menu.anim_id_spin.value = ability_data.animation_start_id + int(is_back_facing)
		#await animation_manager.animation_completed
	#
	#if ability_data.animation_charging_id != 0:
		#debug_menu.anim_id_spin.value = ability_data.animation_charging_id + int(is_back_facing)
		#await get_tree().create_timer(0.1 + (ability_data.ticks_charge_time * 0.1)).timeout
	
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
	push_warning("using: " + ability_data.display_name)
	#push_warning("Animations: " + str(PackedInt32Array([ability_data.animation_start_id, ability_data.animation_charging_id, ability_data.animation_executing_id])))
	if ability_data.animation_start_id != 0:
		#debug_menu.anim_id_spin.value = ability_data.animation_start_id + int(is_back_facing)
		current_animation_id_fwd = ability_data.animation_start_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		await animation_manager.animation_completed
	
	if ability_data.animation_charging_id != 0:
		#debug_menu.anim_id_spin.value = ability_data.animation_charging_id + int(is_back_facing)
		current_animation_id_fwd = ability_data.animation_charging_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		await get_tree().create_timer(0.1 + (ability_data.ticks_charge_time * 0.1)).timeout
	
	#if ability_data.animation_executing_id != 0:
	if ability_data.animation_executing_id < 0:
		pass
	elif ability_data.animation_executing_id == 0:
		#animation_executing_id = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#animation_manager.unit_debug_menu.anim_id_spin.value = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#debug_menu.anim_id_spin.value = (RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) + int(is_back_facing) # TODO lookup based on target relative height
		current_animation_id_fwd = roundi(RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) # TODO lookup based on target relative height
		set_base_animation_ptr_id(current_animation_id_fwd)
	else:
		var ability_animation_executing_id: int = ability_data.animation_executing_id
		if ["RUKA.SEQ", "ARUTE.SEQ", "KANZEN.SEQ"].has(RomReader.sprs[sprite_file_idx].seq_name):
			ability_animation_executing_id = 0x2c * 2 # https://ffhacktics.com/wiki/Set_attack_animation_flags_and_facing_3
		#debug_menu.anim_id_spin.value = ability_animation_executing_id + int(is_back_facing)
		current_animation_id_fwd = ability_animation_executing_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		
	#var new_vfx_location: Node3D = Node3D.new()
	#new_vfx_location.position = pos
	##new_vfx_location.position.y += 2 # TODO set position dependent on ability vfx data
	#new_vfx_location.name = "VfxLocation"
	#get_parent().add_child(new_vfx_location)
	active_action.action.show_vfx(active_action, pos)
	
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


func process_targeted() -> void:
	if global_battle_manager.active_unit == self:
		return
	
	# set being targeted frame
	var targeted_frame_index: int = RomReader.battle_bin_data.targeted_front_frame_id[animation_manager.global_spr.seq_id]
	if is_back_facing:
		targeted_frame_index = RomReader.battle_bin_data.targeted_back_frame_id[animation_manager.global_spr.seq_id]
	
	#animation_manager.global_animation_ptr_id = 0
	#debug_menu.anim_id_spin.value = 0
	#var assembled_image: Image = animation_manager.global_shp.get_assembled_frame(targeted_frame_index, animation_manager.global_spr.spritesheet, 0, 
		#0, 0, 0)
	#animation_manager.unit_sprites_manager.sprite_primary.texture = ImageTexture.create_from_image(assembled_image)
	
	await get_tree().create_timer(0.2).timeout
	
	# take damage animation
	#animation_manager.global_animation_ptr_id = taking_damage_animation_id
	#debug_menu.anim_id_spin.value = taking_damage_animation_id
	current_animation_id_fwd = taking_damage_animation_id
	set_base_animation_ptr_id(current_animation_id_fwd)
	
	# show result / damage numbers
	
	# TODO await ability.vfx_completed? Or does ability_completed just need to wait to post numbers? aka WaitWeaponSheathe1/2 opcode?
	await global_battle_manager.active_unit.ability_completed
	# show death animation
	#animation_manager.global_animation_ptr_id = knocked_out_animation_id
	#debug_menu.anim_id_spin.value = knocked_out_animation_id
	current_idle_animation_id = knocked_out_animation_id
	current_animation_id_fwd = current_idle_animation_id
	set_base_animation_ptr_id(current_animation_id_fwd)
	
	knocked_out.emit(self)


func animate_start_action(animation_start_id: int, animation_charging_id: int) -> void:
	if animation_start_id != 0:
		set_base_animation_ptr_id(animation_start_id)
		await animation_manager.animation_completed
	
	if animation_charging_id != 0:
		set_base_animation_ptr_id(animation_charging_id)
		await get_tree().create_timer(0.1 + (ability_data.ticks_charge_time * 0.1)).timeout # TODO allow looping until changed, ie. charging a spell


func animate_execute_action(animation_executing_id: int, vfx: VisualEffectData = null) -> void:
	if animation_executing_id < 0: # no animatione
		return
	
	var ability_animation_executing_id: int = animation_executing_id
	if ["RUKA.SEQ", "ARUTE.SEQ", "KANZEN.SEQ"].has(RomReader.sprs[sprite_file_idx].seq_name):
		ability_animation_executing_id = 0x2c * 2 # https://ffhacktics.com/wiki/Set_attack_animation_flags_and_facing_3
	#debug_menu.anim_id_spin.value = ability_animation_executing_id + int(is_back_facing)
	set_base_animation_ptr_id(ability_animation_executing_id)
	
	await animation_manager.animation_completed # TODO change based on vfx timing data?
	
	if current_animation_id_fwd == animation_executing_id:
		animate_return_to_idle()


func animate_take_hit(vfx: VisualEffectData = null) -> void:
	set_base_animation_ptr_id(taking_damage_animation_id)
	
	#if vfx != null:
		#await vfx.vfx_completed
	#else:
		#await get_tree().create_timer(0.5).timeout # TODO show based on vfx timing data?
	#
	#if current_animation_id_fwd == taking_damage_animation_id:
		#animate_return_to_idle()


func animate_recieve_heal(vfx: VisualEffectData = null) -> void:
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
		var temp_facing: Unit.Facings = facing
		facing = new_facing
		if global_battle_manager != null:
			update_animation_facing(global_battle_manager.camera_controller.camera_facing_vector)


func update_animation_facing(camera_facing_vector: Vector3) -> void:
	var unit_facing_vector: Vector3 = FacingVectors[facing]
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
		# Talcall: the direction the unit is facing gets updated on every parse of the routine, but unless the animation is changing, the instruction pointer byte doesn't get refreshed every vanilla animation is coded such that this swapping between front and back works flawlessly.
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


func set_job_id(new_job_id: int) -> void:
	job_id = new_job_id
	job_data = RomReader.scus_data.jobs_data[job_id]
	set_sprite_by_job_id(new_job_id)
	
	skillsets.clear()
	skillsets.append(RomReader.scus_data.skillsets_data[job_data.skillset_id])
	
	job_nickname = job_data.display_name
	
	if animation_manager.global_spr.flying_flag:
		idle_walk_animation_id = 0x0c
		walk_to_animation_id = 0x1e
		current_idle_animation_id = idle_walk_animation_id
		set_base_animation_ptr_id(idle_walk_animation_id)
	else:
		idle_walk_animation_id = 0x06
		walk_to_animation_id = 0x18
		current_idle_animation_id = idle_walk_animation_id
		set_base_animation_ptr_id(idle_walk_animation_id)
	
	update_passive_effects()


func set_ability(new_ability_id: int) -> void:
	active_ability_id = new_ability_id
	ability_data = RomReader.fft_abilities[new_ability_id]
	
	if not ability_data.vfx_data.is_initialized:
		ability_data.vfx_data.init_from_file()
	
	image_changed.emit(ImageTexture.create_from_image(ability_data.vfx_data.vfx_spr.spritesheet))
	#debug_menu.sprite_viewer.texture = ImageTexture.create_from_image(ability_data.vfx_data.vfx_spr.spritesheet)
	ability_assigned.emit(new_ability_id)


func set_primary_weapon(new_weapon_unique_name: String) -> void:
	equip_slots[0].item_unique_name = new_weapon_unique_name
	primary_weapon = RomReader.items[new_weapon_unique_name]
	#animation_manager.weapon_id = new_weapon_id
	#var weapon_palette_id = RomReader.battle_bin_data.weapon_graphic_palettes_1[primary_weapon.id]
	animation_manager.unit_sprites_manager.sprite_weapon.texture = animation_manager.wep_spr.create_frame_grid_texture(
		primary_weapon.wep_frame_palette, 0, 0, primary_weapon.wep_frame_v_offset, 0, animation_manager.wep_shp.file_name)
	
	attack_action = primary_weapon.weapon_attack_action
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects()
	set_available_actions(all_passive_effects)
	primary_weapon_assigned.emit(new_weapon_unique_name)


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
	var evade: int = 0
	
	for evade_data: EvadeData in job_data.evade_datas:
		if (evade_data.source == evade_source 
				and evade_data.type == evade_type
				and evade_data.directions.has(evade_direction)):
			evade += evade_data.value
	
	for equip_slot: EquipmentSlot in equip_slots:
		for evade_data: EvadeData in equip_slot.item.evade_datas:
			if (evade_data.source == evade_source 
					and evade_data.type == evade_type
					and evade_data.directions.has(evade_direction)):
				evade += evade_data.value
	
	# TODO evade from passive effects (Statuses, R/S/M)

	return evade


func get_evade_values(evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> Dictionary[EvadeData.EvadeSource, int]:
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = {}
	for evade_source: EvadeData.EvadeSource in EvadeData.EvadeSource.values():
		var evade_value: int = get_evade(evade_source, evade_type, evade_direction)
		evade_values[evade_source] = evade_value
	
	return evade_values


func update_passive_effects(exclude_passives: PackedStringArray = []) -> void:
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects(exclude_passives)

	update_permanent_statuses(all_passive_effects)
	update_immune_statuses(all_passive_effects)
	update_start_statuses(all_passive_effects)

	# update passives in case statuses changed
	all_passive_effects = get_all_passive_effects(exclude_passives)
	update_stat_modifiers(all_passive_effects)
	update_elemental_affinity(all_passive_effects)
	update_triggered_actions(all_passive_effects)
	update_equipable_item_types(all_passive_effects)

	update_prohibited_terrain(all_passive_effects)
	update_terrain_costs(all_passive_effects)
	set_available_actions(all_passive_effects)

	if global_battle_manager != null:
		if not global_battle_manager.battle_is_running:
			stats[StatType.HP].set_value(stats[StatType.HP].max_value) # TODO only set hp = max hp when updating unit not in battle, update on passive effects
			stats[StatType.MP].set_value(stats[StatType.MP].max_value)

	data_updated.emit(self)


func get_all_passive_effects(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	var all_passive_effects: Array[PassiveEffect] = []
	
	var native_passive_effects: Array[PassiveEffect] = get_native_passive_effects(exclude_passives)
	var other_passive_effects: Array[PassiveEffect] = get_passive_effects_from_others(exclude_passives)
	all_passive_effects.append_array(native_passive_effects)
	all_passive_effects.append_array(other_passive_effects)
	
	# all_passive_effects.filter(func(passive_effect): return not exclude_passives.has(passive_effect.unique_name))

	return all_passive_effects


func get_native_passive_effects(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	var native_passive_effects: Array[PassiveEffect] = []
	# TODO should all Objects that have PassiveEffect be changed to store Array[PassiveEffect]
	# all_passive_effects.append_array(ability.passive_effects) 
	
	if job_data != null:
		native_passive_effects.append_array(job_data.passive_effects)
		for ability: Ability in job_data.innate_abilities:
			native_passive_effects.append(ability.passive_effect)
	
	for ability_slot: AbilitySlot in ability_slots:
		native_passive_effects.append(ability_slot.ability.passive_effect)
	
	for equipment_slot: EquipmentSlot in equip_slots:
		native_passive_effects.append(equipment_slot.item.passive_effect)
	
	for status: StatusEffect in current_statuses:
		native_passive_effects.append(status.passive_effect)
	
	if global_battle_manager != null:
		native_passive_effects.append_array(global_battle_manager.global_passive_effects)

	native_passive_effects = native_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return passive_effect.effect_range == 0)
	native_passive_effects = native_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return not exclude_passives.has(passive_effect.unique_name))
	
	return native_passive_effects


func get_passive_effects_from_others(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	var shared_passive_effects: Array[PassiveEffect] = []
	
	if global_battle_manager != null:
		for unit: Unit in global_battle_manager.units:
			var unit_passives: Array[PassiveEffect] = unit.get_native_passive_effects()
			for passive_effect: PassiveEffect in unit_passives:
				if passive_effect.effect_range == 0:
					continue
				
				if not passive_effect.unit_team_filter.is_empty():
					if not passive_effect.unit_team_filter.has(PassiveEffect.FilterTeam.FRIENDLY) and unit.team == self.team:
						continue
					elif not passive_effect.unit_team_filter.has(PassiveEffect.FilterTeam.ENEMY) and unit.team != self.team:
						continue
				
				if not passive_effect.unit_basis_filter.is_empty():
					if not passive_effect.unit_basis_filter.has(stat_basis):
						continue
				
				var relative_position: Vector2i = (tile_position.location - unit.tile_position.location).abs()
				var distance_to_unit: int = relative_position.x + relative_position.y
				if distance_to_unit > passive_effect.effect_range:
					continue
				
				var relative_height: float = absf(tile_position.height_mid - unit.tile_position.height_mid)
				if relative_height > passive_effect.vertical_tolerance:
					continue
				
				shared_passive_effects.append(passive_effect)
	
	shared_passive_effects = shared_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return not exclude_passives.has(passive_effect.unique_name))
	
	return shared_passive_effects


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
	on_sprite_idx_selected(new_sprite_file_idx)
	if spr.file_name == "WEP.SPR":
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 32
	else:
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 16 + (16 * spr.sp2s.size())
	update_spritesheet_grid_texture()
	
	debug_menu.anim_id_spin.value = current_idle_animation_id


func set_sprite_by_file_name(new_sprite_file_name: String) -> void:
	var new_sprite_file_idx: int = RomReader.file_records[new_sprite_file_name].type_index
	set_sprite_by_file_idx(new_sprite_file_idx)


func set_sprite_by_id(new_sprite_id: int) -> void:
	var new_sprite_file_idx: int = RomReader.spr_id_file_idxs[new_sprite_id]
	set_sprite_by_file_idx(new_sprite_file_idx)


func set_sprite_by_job_id(new_job_id: int) -> void:
	var job_id_data: JobData = RomReader.scus_data.jobs_data[job_id]
	var new_sprite_id: int = job_id_data.sprite_id
	if new_job_id >= 0x4a and new_job_id <= 0x5d and stat_basis == StatBasis.FEMALE:
		new_sprite_id += 1
	set_sprite_by_id(new_sprite_id)
	if new_job_id >= 0x5e: # monster
		set_sprite_palette(job_data.monster_palette_id)


func set_sprite_palette(new_palette_id: int) -> void:
	if new_palette_id == sprite_palette_id:
		return
	
	sprite_palette_id = new_palette_id
	if sprite_palette_id_override == -1: # don't update grid texture if palette is still being overridden
		update_spritesheet_grid_texture()


func set_sprite_palette_override(new_palette_id: int) -> void:
	if new_palette_id == sprite_palette_id_override:
		return
	
	sprite_palette_id_override = new_palette_id
	update_spritesheet_grid_texture()


func modulate_sprite_color(new_modulate_color: Color) -> void:
	animation_manager.unit_sprites_manager.sprite_primary.modulate = new_modulate_color


func set_submerged_depth(new_depth: int) -> void:
	if new_depth == submerged_depth:
		return
	
	submerged_depth = new_depth
	update_spritesheet_grid_texture()


func update_spritesheet_grid_texture() -> void:
	var new_spr: Spr = RomReader.sprs[sprite_file_idx]
	var palette_idx_final: int = sprite_palette_id_override
	if sprite_palette_id_override < 0:
		palette_idx_final = sprite_palette_id
	animation_manager.unit_sprites_manager.sprite_primary.texture = new_spr.create_frame_grid_texture(palette_idx_final, 0, animation_manager.other_type_index, 0, submerged_depth)


func on_sprite_idx_selected(index: int) -> void:
	var spr: Spr = RomReader.sprs[index]
	if not spr.is_initialized:
		spr.set_data()
		if RomReader.spr_file_name_to_id.keys().has(spr.file_name):
			spr.set_spritesheet_data(RomReader.spr_file_name_to_id[spr.file_name])
		else:
			spr.set_spritesheet_data(-1) # get data for OTHER.SPR
	
	animation_manager.global_spr = spr
	
	var shp: Shp = RomReader.shps_array[RomReader.file_records[spr.shp_name].type_index]
	if not shp.is_initialized:
		shp.set_data_from_shp_bytes(RomReader.get_file_data(shp.file_name))
	
	var seq: Seq = RomReader.seqs_array[RomReader.file_records[spr.seq_name].type_index]
	if not seq.is_initialized:
		seq.set_data_from_seq_bytes(RomReader.get_file_data(seq.file_name))
	
	var animation_changed: bool = false
	if shp.file_name == "TYPE2.SHP":
		if animation_manager.wep_shp.file_name != "WEP2.SHP":
			animation_manager.wep_shp = RomReader.shps_array[RomReader.file_records["WEP2.SHP"].type_index]
			set_primary_weapon(primary_weapon.unique_name) # get new texture based on wep2.shp
			animation_changed = true
		animation_manager.wep_seq = RomReader.seqs_array[RomReader.file_records["WEP2.SEQ"].type_index]
	
	if shp != animation_manager.global_shp or seq != animation_manager.global_seq:
		animation_changed = true
	
	animation_manager.global_spr = spr
	animation_manager.global_shp = shp
	animation_manager.global_seq = seq
	
	
	#spritesheet_changed.emit(animation_manager.unit_sprites_manager.sprite_item.texture) # TODO hook up to sprite for debug purposes
	#spritesheet_changed.emit(ImageTexture.create_from_image(spr.spritesheet)) # TODO hook up to sprite for debug purposes
	#spritesheet_changed.emit(animation_manager.unit_sprites_manager.sprite_weapon.texture) # TODO hook up to sprite for debug purposes
	if animation_changed:
		# if animation_manager.global_animation_id >= animation_manager.global_seq.sequences.size():
		# 	set_base_animation_ptr_id(6) # triggers on_animation_changed
		# else:
		animation_manager._on_animation_changed()


func update_prohibited_terrain(all_passive_effects: Array[PassiveEffect]) -> void:
	var new_prohibited_terrain: Array[int] = []

	for passive_effect: PassiveEffect in all_passive_effects:
		for terrain_id: int in passive_effect.add_prohibited_terrain:
			if not new_prohibited_terrain.has(terrain_id):
				new_prohibited_terrain.append(terrain_id)
	
	for passive_effect: PassiveEffect in all_passive_effects:
		for terrain_id: int in passive_effect.remove_prohibited_terrain:
			if new_prohibited_terrain.has(terrain_id):
				new_prohibited_terrain.erase(terrain_id)
	
	prohibited_terrain = new_prohibited_terrain


func update_terrain_costs(all_passive_effects: Array[PassiveEffect]) -> void:
	var new_terrain_costs: Dictionary[int, int] = {}

	for passive_effect: PassiveEffect in all_passive_effects:
		for terrain_id: int in passive_effect.terrain_cost_modifiers.keys():
			var current_cost: int = 1
			if new_terrain_costs.has(terrain_id):
				current_cost = new_terrain_costs[terrain_id]
			
			new_terrain_costs[terrain_id] = passive_effect.terrain_cost_modifiers[terrain_id].apply(current_cost)
	
	for terrain_id: int in new_terrain_costs.keys():
		new_terrain_costs[terrain_id] = max(0, new_terrain_costs[terrain_id]) # move is never negative

	terrain_costs = new_terrain_costs


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
	
	# if Input.is_action_just_pressed("secondary_action") and UnitControllerRT.unit.char_body.is_on_floor():
	# 	UnitControllerRT.unit.use_ability(char_body.position)
	# 	process_targeted()
