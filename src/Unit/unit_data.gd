class_name UnitData
extends Resource

signal data_updated(unit_data: UnitData)
signal statuses_updated()
signal actions_updated(unit_data: UnitData)
@warning_ignore("unused_signal")
signal targeted_pre_action(unit_data: UnitData, action_instance: ActionInstance) # emited in action_instance
@warning_ignore("unused_signal")
signal targeted_post_action(unit_data: UnitData, action_instance: ActionInstance) # emited in action_instance
@warning_ignore("unused_signal")
signal reached_tile() # emited in use_move
@warning_ignore("unused_signal")
signal completed_move(unit_data: UnitData, tile_moved: int) # emited in use_move
signal paths_updated()
signal turn_started(unit_data: UnitData)
signal turn_ended(unit_data: UnitData)

signal job_changed(new_job_name: String)
signal sprite_changed(new_sprite_name: String)
signal palette_changed(new_palette_id: int, new_palette_override_id: int)
signal primary_weapon_changed(new_weapon: ItemData)
signal facing_changed(new_facing: GameData.Directions)
signal tile_position_changed(new_tile: TerrainTile)

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

enum Zodiac {
	ARIES,
	TAURUS,
	GEMINI,
	CANCER,
	LEO,
	VIRGO,
	LIBRA,
	SCORPIO,
	SAGITTARIUS,
	CAPRICORN,
	AQUARIUS,
	PISCES,
	SERPENTARIUS,
}

enum Controller {
	AI,
	PLAYER,
}

const FACING_VECTORS: Dictionary[GameData.Directions, Vector3] = {
	GameData.Directions.NORTH: Vector3.BACK,
	GameData.Directions.EAST: Vector3.RIGHT,
	GameData.Directions.SOUTH: Vector3.FORWARD,
	GameData.Directions.WEST: Vector3.LEFT,
}

@export var unit_unique_name: String = "unit unique_name"
@export var display_name: String = "display name"
@export var gender: Gender = Gender.MALE # male, female, other, monster
@export var stat_basis: StatBasis = StatBasis.MALE
@export var zodiac: Zodiac = Zodiac.ARIES
@export var job_unique_name: String = "job_unique_name"
@export var controller: Controller = Controller.AI # 0 = AI, 1 = Player, etc.
@export var spritesheet_file_name: String = "spritesheet_file_name.spr" # TODO get sprite file name?
@export var palette_id: int = 0
@export var palette_id_override: int = -1
@export var facing_direction: GameData.Directions = GameData.Directions.NORTH

@export var tile_position: Vector3i = Vector3i.ONE * -999 # tile_position.get_world_position? (x, y_level, z)
@export var prohibited_terrain: Array[int] = [] # TileTerrain.surface_type_id
@export var terrain_costs: Dictionary[int, int] = {} # [TileTerrain.surface_type_id, cost]
var ignore_height: bool = false
var terrain_tile_position: TerrainTile
var map_paths: Dictionary[TerrainTile, TerrainTile]
var path_costs: Dictionary[TerrainTile, float]
var paths_set: bool = false

@export var job_levels: Dictionary[String, int] = {}
@export var job_total_jp: Dictionary[String, int] = {}
@export var job_current_jp: Dictionary[String, int] = {}
@export var abilities_learned: PackedStringArray = []

@export var team_name: String = "team_name"
@export var team_idx: int = -1
var team: Team

var ai_controller: UnitAi = UnitAi.new()
var job_data: JobData = JobData.new()

@export var immortal: bool = false
@export var immune_knockback: bool = false
@export var game_over_trigger: bool = false

var equipable_item_types: Array[ItemData.ItemType] = []
@export var equip_slots: Array[EquipmentSlot] = [
	EquipmentSlot.new("RH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
	EquipmentSlot.new("LH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
	EquipmentSlot.new("Head", [ItemData.SlotType.HEADGEAR]),
	EquipmentSlot.new("Body", [ItemData.SlotType.ARMOR]),
	EquipmentSlot.new("Accesory", [ItemData.SlotType.ACCESSORY]),
]

@export var innate_ability_ids: PackedStringArray = []
@export var skillsets_names: PackedStringArray = ["", ""]
@export var ability_slots: Array[AbilitySlot] = [
	# AbilitySlot.new("Skillset 1", [Ability.SlotType.SKILLSET]),
	# AbilitySlot.new("Skillset 2", [Ability.SlotType.SKILLSET]),
	AbilitySlot.new("Reaction", [Ability.SlotType.REACTION]),
	AbilitySlot.new("Support", [Ability.SlotType.SUPPORT]),
	AbilitySlot.new("Movement", [Ability.SlotType.MOVEMENT]),
]

@export var stats: Dictionary[StatType, StatValue] = {
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
}:
	set(value):
		stats = value
		_connect_stats_signals()

@export var stats_raw: Dictionary[StatType, float] = {
	StatType.HP_MAX : 0.0, 
	StatType.MP_MAX : 0.0, 
	StatType.SPEED : 0.0, 
	StatType.PHYSICAL_ATTACK : 0.0, 
	StatType.MAGIC_ATTACK : 0.0, 
}

@export var always_statuses: PackedStringArray = []
@export var immune_statuses: PackedStringArray = []
@export var start_statuses: PackedStringArray = []
@export var current_statuses: Array[StatusEffect] = [] # entries will be duplicates of base status definition with modified values (duration_left, delayed action, etc)

@export var elemental_absorb: Array[Action.ElementTypes] = []
@export var elemental_cancel: Array[Action.ElementTypes] = []
@export var elemental_half: Array[Action.ElementTypes] = []
@export var elemental_weakness: Array[Action.ElementTypes] = []
@export var elemental_strengthen: Array[Action.ElementTypes] = []

@export var move_points_start: int = 1
@export var move_points_remaining: int = 1
@export var action_points_start: int = 1
@export var action_points_remaining: int = 1
var is_ending_turn: bool = false

@export var move_action_name: String = "move"
@export var wait_action_name: String = "wait"
var move_action: Action
var wait_action: Action
var actions: Array[Action] = []
var actions_data: Dictionary[String, ActionInstance] = {}
var active_action: ActionInstance

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

var battle_manager: BattleManager
var unit_actor: UnitActor


static func generate_leveled_raw_stats(stat_basis_to_use: StatBasis, final_level: int, job: JobData, new_stats_raw: Dictionary[StatType, float], use_rom: bool = false) -> void:
	generate_level_zero_raw_stats(stat_basis_to_use, new_stats_raw, use_rom)
	
	for curent_level: int in range(1, final_level + 1):
		grow_raw_stats(curent_level, job, new_stats_raw)


static func generate_level_zero_raw_stats(stat_basis_to_use: StatBasis, new_stats_raw: Dictionary[StatType, float], use_rom: bool = false) -> void:
	new_stats_raw[StatType.HP_MAX] = generate_level_zero_raw_stat("HP_MAX", stat_basis_to_use, use_rom)
	new_stats_raw[StatType.MP_MAX] = generate_level_zero_raw_stat("MP_MAX", stat_basis_to_use, use_rom)
	new_stats_raw[StatType.SPEED] = generate_level_zero_raw_stat("SPEED", stat_basis_to_use, use_rom)
	new_stats_raw[StatType.PHYSICAL_ATTACK] = generate_level_zero_raw_stat("PHYSICAL_ATTACK", stat_basis_to_use, use_rom)
	new_stats_raw[StatType.MAGIC_ATTACK] = generate_level_zero_raw_stat("MAGIC_ATTACK", stat_basis_to_use, use_rom)


# TODO is this correct for MONSTERs and LUCAVI?
static func generate_level_zero_raw_stat(stat_name: String, stat_basis_to_use: StatBasis, use_rom: bool = false) -> int:
	var raw_stat: int = -1
	if not use_rom:
		var stat_range: Vector2i = GameData.initial_unit_data.initial_unit_raw_stats[stat_basis_to_use][stat_name]
		raw_stat = randi_range(stat_range.x , stat_range.y)
		return raw_stat
	
	var stat_idx: int = -1
	if stat_name == "HP_MAX": stat_idx = 0
	elif stat_name == "MP_MAX": stat_idx = 1
	elif stat_name == "SPEED": stat_idx = 2
	elif stat_name == "PHYSICAL_ATTACK": stat_idx = 3
	elif stat_name == "MAGIC_ATTACK": stat_idx = 4
	
	raw_stat = RomReader.scus_data.unit_base_datas[stat_basis_to_use][stat_idx] * 16384
	raw_stat += randi_range(0, RomReader.scus_data.unit_base_stats_mods[stat_basis_to_use][stat_idx] * 16384)
	return raw_stat

	
static func grow_raw_stats(current_level: int, current_job: JobData, new_stats_raw: Dictionary[StatType, float]) -> void:
	new_stats_raw[StatType.HP_MAX] += new_stats_raw[StatType.HP_MAX] / (current_job.hp_growth + current_level)
	new_stats_raw[StatType.MP_MAX] += new_stats_raw[StatType.MP_MAX] / (current_job.mp_growth + current_level)
	new_stats_raw[StatType.SPEED] += new_stats_raw[StatType.SPEED] / (current_job.speed_growth + current_level)
	new_stats_raw[StatType.PHYSICAL_ATTACK] += new_stats_raw[StatType.PHYSICAL_ATTACK] / (current_job.pa_growth + current_level)
	new_stats_raw[StatType.MAGIC_ATTACK] += new_stats_raw[StatType.MAGIC_ATTACK] / (current_job.ma_growth + current_level)


# TODO is this correct for MONSTERs?
static func calc_battle_stats(
		current_job: JobData, 
		new_stats_raw: Dictionary[StatType, float], 
		new_stats: Dictionary[StatType, StatValue],
		set_to_max: bool = true,
		use_larger_values: bool = false) -> void:
	var base_hp: int = roundi(new_stats_raw[StatType.HP_MAX] * current_job.hp_multiplier / 0x190000)
	if use_larger_values: # lucavi
		new_stats[StatType.HP_MAX].max_value = 99999
		base_hp = base_hp * 100
	new_stats[StatType.HP_MAX].base_value = base_hp
	new_stats[StatType.HP_MAX].set_value(new_stats[StatType.HP_MAX].base_value)
	
	var base_mp: int = roundi(new_stats_raw[StatType.MP_MAX] * current_job.mp_multiplier / 0x190000)
	if use_larger_values: # lucavi
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
	
	if set_to_max:
		new_stats[StatType.HP].set_value(new_stats[StatType.HP].max_value)
		new_stats[StatType.MP].set_value(new_stats[StatType.MP].max_value)


func _init() -> void:
	_connect_stats_signals()


func _connect_stats_signals() -> void:
	if not stats.has(StatType.HP_MAX) or not stats.has(StatType.HP) or not stats.has(StatType.MP_MAX) or not stats.has(StatType.MP):
		return
	
	var hp_callable: Callable = stats[StatType.HP].update_max_from_clamped_value
	if not stats[StatType.HP_MAX].value_changed.is_connected(hp_callable):
		stats[StatType.HP_MAX].value_changed.connect(hp_callable)
	var mp_callable: Callable = stats[StatType.MP].update_max_from_clamped_value
	if not stats[StatType.MP_MAX].value_changed.is_connected(mp_callable):
		stats[StatType.MP_MAX].value_changed.connect(mp_callable)
	
	if not stats[StatType.HP].value_changed.is_connected(process_hp_changed):
		stats[StatType.HP].value_changed.connect(process_hp_changed)


func init_derived_properties(new_battle_manager: BattleManager, create_unit_actor: bool = false) -> void:
	battle_manager = new_battle_manager
	
	# TODO set all derived non-exported properties
	# var ignore_height
	# var terrain_tile_position
	# var team
	# var ai_controller
	# var job_data
	# var equipable_item_types
	# var actions
	# var actions_data
	# var submerged_depth


	if create_unit_actor:
		unit_actor = UnitActor.instantiate()
		unit_actor.bind_unit_data(self)


func has_status(status_unique_name: String) -> bool:
	return current_statuses.any(func(status: StatusEffect) -> bool: return status.unique_name == status_unique_name)


func get_facing_vector() -> Vector3:
	return FACING_VECTORS[facing_direction]


func update_unit_facing(dir: Vector3) -> void:
	var angle_deg: float = rad_to_deg(atan2(dir.z, dir.x))
	angle_deg = fposmod(angle_deg, 359.99) + 45 # add 45 so EAST is just < 90 instead of < 45 and > 315
	angle_deg = fposmod(angle_deg, 359.99) # correction for values over 360 due to adding 45
	var new_facing: GameData.Directions = facing_direction
	if angle_deg < 90:
		new_facing = GameData.Directions.EAST
	elif angle_deg < 180:
		new_facing = GameData.Directions.NORTH
	elif angle_deg < 270:
		new_facing = GameData.Directions.WEST
	elif angle_deg < 360:
		new_facing = GameData.Directions.SOUTH
	
	if new_facing != facing_direction:
		set_facing_direction(new_facing)


func set_facing_direction(new_facing: GameData.Directions) -> void:
	facing_direction = new_facing
	facing_changed.emit(facing_direction)


func set_terrain_tile_position(new_tile: TerrainTile) -> void:
	terrain_tile_position = new_tile
	if new_tile != null:
		tile_position = Vector3i(new_tile.xz_location.x, new_tile.layer, new_tile.xz_location.y)
	tile_position_changed.emit(terrain_tile_position)


func is_defeated() -> bool:
	return current_statuses.any(func(status: StatusEffect) -> bool: return status.counts_as_ko) # returns false when no statuses


func is_ct_frozen() -> bool:
	return current_statuses.any(func(status: StatusEffect) -> bool: return status.freezes_ct) # returns false when no statuses


func get_nullify_statuses() -> Array[StatusEffect]:
	return current_statuses.filter(func(status: StatusEffect) -> bool: return status.passive_effect.nullify_targeted)


func set_sprite_by_file_name(new_sprite_file_name: String) -> void:
	spritesheet_file_name = new_sprite_file_name
	sprite_changed.emit(spritesheet_file_name)
	data_updated.emit(self)


func set_sprite_palette(new_palette_id: int) -> void:
	palette_id = new_palette_id
	palette_changed.emit(palette_id, palette_id_override)
	data_updated.emit(self)


func set_sprite_palette_override(new_palette_id: int) -> void:
	palette_id_override = new_palette_id
	palette_changed.emit(palette_id, palette_id_override)
	data_updated.emit(self)


# TODO should these be triggered actions on the statuses?
func process_hp_changed(stat_value: StatValue) -> void:
	if not GameData.is_ready:
		return
	
	@warning_ignore("integer_division")
	var critical_hp_threshold: int = stat_value.max_value / 5

	if stat_value.current_value == 0:
		await add_status(GameData.get_status_effect("dead").duplicate(), true) # add dead
	elif stat_value.current_value < critical_hp_threshold: # critical
		if not has_status("critical"):
			await add_status(GameData.get_status_effect("critical").duplicate()) # add critical
	elif stat_value.current_value >= critical_hp_threshold: # not critical
		remove_status_id("critical") # remove critical


func start_turn() -> void:
	battle_manager.game_state_label.text = job_data.display_name + "-" + display_name + " starting turn"
	is_ending_turn = false

	for status_effect: StatusEffect in current_statuses:
		if status_effect.action_on_turn_start != "":
			var action_instance: ActionInstance = ActionInstance.new(GameData.get_action(status_effect.action_on_turn_start), self, battle_manager)
			action_instance.submitted_targets = [terrain_tile_position] # TODO allow other targeting for status actions on turn start
			await action_instance.use()

	# set CT
	stats[StatType.CT].add_value(-100)
	
	turn_started.emit(self)

	await update_actions()


func update_actions() -> void:
	if is_ending_turn:
		await end_turn()
		return
	
	if battle_manager.active_unit != self:
		return
	
	battle_manager.game_state_label.text = job_data.display_name + "-" + display_name + " updating available actions"
	
	# get possible actions
	for action_instance: ActionInstance in actions_data.values():
		action_instance.clear()
	
	actions_data.clear()
	
	# show list UI for selecting an action TODO should action list be toggle/button group?
	# update_available_actions(get_all_passive_effects())
	for action: Action in actions:
		var modified_action: Action = Action.get_modified_action(action, self)
		var new_action_instance: ActionInstance = ActionInstance.new(modified_action, self, battle_manager)
		actions_data[modified_action.unique_name] = new_action_instance
		
		if new_action_instance.is_usable():
			await new_action_instance.update_potential_targets()
		new_action_instance.action_completed.connect(update_actions)
	
	actions_updated.emit(self) # update_action_buttons() is connected in battle_manager
	await select_default_action()


func select_default_action() -> void:
	# select first usable action by default (usually Move)
	active_action = null
	if battle_manager.active_unit != self: # TODO improve game flow to prevent this state from ever occuring
		return
	
	for action_instance: ActionInstance in actions_data.values():
		if action_instance.is_usable() and action_instance != actions_data[wait_action.unique_name]:
			active_action = action_instance
			if not controller == Controller.AI:
				active_action.start_targeting()
			break
	
	# end turn when no actions left
	if active_action == null or is_defeated():
		await end_turn()
	else:
		if controller == Controller.AI:
			await ai_controller.choose_action(self)


func end_turn() -> void:
	battle_manager.game_state_label.text = job_data.display_name + "-" + display_name + " ending turn"
	
	if active_action != null:
		active_action.clear()
		active_action.stop_targeting()
	
	for status_effect: StatusEffect in current_statuses:
		if status_effect.action_on_turn_end != "":
			var action_instance: ActionInstance = ActionInstance.new(GameData.get_action(status_effect.action_on_turn_end), self, battle_manager)
			action_instance.submitted_targets = [terrain_tile_position] # TODO allow other targeting for status actions on turn end
			await action_instance.use()
		
		if status_effect.duration_type == StatusEffect.DurationType.TURNS:
			status_effect.duration -= 1
			if status_effect.duration < 0 and status_effect.action_on_complete != "":
				var status_action_instance: ActionInstance = ActionInstance.new(GameData.get_action(status_effect.action_on_complete), self, battle_manager)
				status_action_instance.submitted_targets.append(terrain_tile_position) # TODO get targets for status action
				battle_manager.game_state_label.text = job_data.display_name + "-" + display_name + " processing " + status_effect.status_effect_name + " completing"
				await status_action_instance.use()

				remove_status(status_effect)

	# set some stats for next turn - move_points_remaining, action_points_remaining, etc.
	move_points_remaining = move_points_start
	action_points_remaining = action_points_start
	
	is_ending_turn = true
	if is_instance_valid(battle_manager.active_unit) and battle_manager.active_unit != self: # prevent accidentally ending a different units turn TODO what if the next turn is also this unit?
		push_error(job_data.display_name + "-" + display_name + " trying to end turn, but active unit is: " + battle_manager.active_unit.unit_unique_name)
	else:
		turn_ended.emit(self)


func update_available_actions(all_passive_effects: Array[PassiveEffect]) -> void:
	move_action = GameData.get_action(move_action_name)
	wait_action = GameData.get_action(wait_action_name)
	
	actions.clear()
	actions.append(move_action)
	actions.append_array(get_equipment_actions())
	actions.append_array(get_skillset_actions())

	for passive_effect: PassiveEffect in all_passive_effects:
		for action: Action in passive_effect.added_actions:
			if not actions.has(action):
				actions.append(action)
	
	actions.append(wait_action)


func get_attack_action() -> Action:
	# TODO handle two swords? other abilities?
	var equipment_actions: Array[Action] = get_equipment_actions()
	if equipment_actions.is_empty():
		push_error("Unit " + display_name + " has no equipment actions, cannot get attack action")
		return null

	return get_equipment_actions()[0]


func get_equipment_actions() -> Array[Action]:
	var action_list: Array[Action] = []
	for equip_slot: EquipmentSlot in equip_slots:
		if is_instance_valid(equip_slot.get_item()):
			var item_actions: Array[Action] = equip_slot.get_item().get_equipped_actions()
			for action: Action in item_actions:
				if not action_list.has(action):
					action_list.append(action)
	return action_list


func get_skillsets() -> Array[Skillset]:
	var skillsets: Array[Skillset] = []
	for skillset_name: String in skillsets_names:
		if skillset_name != null and not skillset_name.is_empty():
			skillsets.append(GameData.get_skillset(skillset_name))
	
	return skillsets


func get_skillset_actions() -> Array[Action]:
	var action_list: Array[Action] = []
	for skillset: Skillset in get_skillsets():
		for ability_name: String in skillset.ability_names:
			var ability_is_action: bool = not [Ability.SlotType.REACTION, Ability.SlotType.SUPPORT, Ability.SlotType.MOVEMENT].has(GameData.get_ability(ability_name).slot_type)
			if ability_is_action and GameData.action_paths.has(ability_name):
				var new_action: Action = GameData.get_action(ability_name)
				action_list.append(new_action)
	return action_list


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
		var action_instance: ActionInstance = ActionInstance.new(GameData.get_action(new_status.action_on_apply), self, battle_manager)
		await action_instance.start_targeting()
		# await action_instance.use()
	
	for status_cancelled_id: String in new_status.status_cancels:
		remove_status_id(status_cancelled_id)
	
	statuses_updated.emit()
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
	statuses_updated.emit()
	update_passive_effects()


func get_current_status_ids() -> PackedStringArray:
	var status_unique_names: PackedStringArray = []
	for status: StatusEffect in current_statuses:
		if not status_unique_names.has(status.unique_name):
			status_unique_names.append(status.unique_name)
	return status_unique_names


func get_evade(evade_source: EvadeData.EvadeSource, evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> int:
	var evade: int = 0
	
	for evade_data: EvadeData in job_data.evade_datas:
		if (evade_data.source == evade_source 
				and evade_data.type == evade_type
				and evade_data.directions.has(evade_direction)):
			evade += evade_data.value
	
	for equip_slot: EquipmentSlot in equip_slots:
		for evade_data: EvadeData in equip_slot.get_item().evade_datas:
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

	await update_permanent_statuses(all_passive_effects)
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
	update_available_actions(all_passive_effects)

	if battle_manager != null:
		if not battle_manager.battle_is_running:
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
		native_passive_effects.append_array(job_data.get_passive_effects())
		for ability: Ability in job_data.innate_abilities:
			native_passive_effects.append(ability.get_passive_effect())
	
	for ability_slot: AbilitySlot in ability_slots:
		native_passive_effects.append(ability_slot.get_ability().get_passive_effect())
	
	for equipment_slot: EquipmentSlot in equip_slots:
		native_passive_effects.append(equipment_slot.get_item().get_passive_effect())
	
	for status: StatusEffect in current_statuses:
		native_passive_effects.append(status.passive_effect)
	
	if battle_manager != null:
		native_passive_effects.append_array(battle_manager.global_passive_effects)

	native_passive_effects = native_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return passive_effect.effect_range == 0)
	native_passive_effects = native_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return not exclude_passives.has(passive_effect.unique_name))
	
	return native_passive_effects


func get_passive_effects_from_others(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	var shared_passive_effects: Array[PassiveEffect] = []
	
	if battle_manager != null:
		for unit: UnitData in battle_manager.units:
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
				
				var relative_position: Vector2i = (terrain_tile_position.xz_location - unit.terrain_tile_position.xz_location).abs()
				var distance_to_unit: int = relative_position.x + relative_position.y
				if distance_to_unit > passive_effect.effect_range:
					continue
				
				var relative_height: float = absf(terrain_tile_position.height_mid - unit.terrain_tile_position.height_mid)
				if relative_height > passive_effect.vertical_tolerance:
					continue
				
				shared_passive_effects.append(passive_effect)
	
	shared_passive_effects = shared_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return not exclude_passives.has(passive_effect.unique_name))
	
	return shared_passive_effects


func update_permanent_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	always_statuses.clear()
	for passive_effect: PassiveEffect in all_passive_effects:
		always_statuses.append_array(passive_effect.status_always)
	
	for status_unique_name: String in GameData.status_effect_paths.keys():
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
				var new_status: StatusEffect = GameData.get_status_effect(status_unique_name).duplicate()
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


func update_equipable_item_types(all_passive_effects: Array[PassiveEffect]) -> void:
	equipable_item_types = []
	
	for passive_effect: PassiveEffect in all_passive_effects:
		equipable_item_types.append_array(passive_effect.added_equipment_types_equipable)
	
	equipable_item_types.append_array(job_data.equippable_item_types) # TODO job equipable item types should be in passive effect


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


func equip_random_abilities() -> void:
	ability_slots[0].ability_unique_name = get_random_ability_name(Ability.SlotType.REACTION)
	ability_slots[1].ability_unique_name = get_random_ability_name(Ability.SlotType.SUPPORT)
	ability_slots[2].ability_unique_name = get_random_ability_name(Ability.SlotType.MOVEMENT)

	update_passive_effects()


func get_random_ability_name(ability_slot_type: Ability.SlotType) -> String:
	var random_ability_name: String = GameData.ability_paths.keys().filter(func(ability_name: String) -> bool: return GameData.get_ability(ability_name).slot_type == ability_slot_type).pick_random()
	return random_ability_name


func equip_ability(slot: AbilitySlot, ability: Ability) -> void:
	slot.ability_unique_name = ability.unique_name

	update_passive_effects()


func equip_skillset(skillset_idx: int, new_skillset_name: String) -> void:
	skillsets_names[skillset_idx] = new_skillset_name
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects()
	update_available_actions(all_passive_effects)
	data_updated.emit(self)


# generate equipment https://ffhacktics.com/wiki/Calculate/Store_ENTD_Unit_Equipment
func equip_items_leveled() -> void:
	var original_weapon: ItemData = get_primary_weapon()

	var level: int = stats[StatType.LEVEL].current_value
	equip_slots[0].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.WEAPON, level) # RH
	equip_slots[1].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.SHIELD, level) # LH
	equip_slots[2].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.HEADGEAR, level) # headgear
	equip_slots[3].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.ARMOR, level) # armor
	equip_slots[4].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.ACCESSORY, level, true) # accessory
	
	update_passive_effects()
	var new_primary_weapon: ItemData = get_primary_weapon()
	if original_weapon != new_primary_weapon:
		primary_weapon_changed.emit(new_primary_weapon)


func get_item_unique_name_for_slot(slot_type: ItemData.SlotType, item_level: int, random: bool = false) -> String:
	# var valid_items: Array[ItemData] = []
	var valid_items_names: Array[String] = []
	valid_items_names.assign(GameData.item_paths.keys().filter(func(item_name: String) -> bool: 
		var item: ItemData = GameData.get_item(item_name)
		var slot_type_is_valid: bool = item.slot_type == slot_type
		var level_is_valid: bool = item.min_level <= item_level
		var type_is_valid: bool = equipable_item_types.has(item.item_type) # TODO allow forcing specifc type based on ability requirements
		return slot_type_is_valid and level_is_valid and type_is_valid))
	var item_unique_name: String = ""
	if not valid_items_names.is_empty():
		if random:
			item_unique_name = valid_items_names.pick_random()
		else:
			valid_items_names.sort_custom(func(item_a_name: String, item_b_name: String) -> bool: return GameData.get_item(item_a_name).min_level > GameData.get_item(item_b_name).min_level)
			item_unique_name = valid_items_names[0] # pick highest level item
			#item = valid_items.pick_random()
	return item_unique_name


func equip_item(slot: EquipmentSlot, item: ItemData) -> void:
	var original_weapon: ItemData = get_primary_weapon()

	slot.item_unique_name = item.unique_name
	
	update_passive_effects()
	var new_primary_weapon: ItemData = get_primary_weapon()
	if original_weapon != new_primary_weapon:
		primary_weapon_changed.emit(new_primary_weapon)


# TODO is the first item with an action always the primary weapon?
func get_primary_weapon() -> ItemData:
	for equip_slot: EquipmentSlot in equip_slots:
		if equip_slot.item_unique_name != "":
			var item: ItemData = GameData.get_item(equip_slot.item_unique_name)
			if not item.equipped_action_names.is_empty():
				return item
	return null


func set_job(new_job_name: String) -> void:
	job_unique_name = new_job_name
	job_data = GameData.get_job(new_job_name)
	
	var new_skillset_name: String = job_data.skillset_unique_name
	
	# if the new job's skillset is already equipped in a different slot, swap it to the first slot
	var skillset_current_slot_idx: int = skillsets_names.find(new_skillset_name)
	if skillset_current_slot_idx > 0:
		skillsets_names[skillset_current_slot_idx] = skillsets_names[0]

	equip_skillset(0, new_skillset_name)

	var sprite_name: String = job_data.sprite_name
	if (job_data.job_id >= 0x4a and job_data.job_id <= 0x5a or job_data.job_id == 0x5d) and stat_basis == StatBasis.FEMALE:
		sprite_name = sprite_name.replace("_m", "_w")
	set_sprite_by_file_name(sprite_name)
	
	if job_data.default_palette_idx != -1:
		set_sprite_palette(job_data.default_palette_idx)

	update_passive_effects()
	job_changed.emit(new_job_name)


func update_map_paths(map_tiles: Dictionary[Vector2i, Array], units: Array[UnitData], max_cost: int = 9999) -> void:
	paths_set = false
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects()
	update_prohibited_terrain(all_passive_effects)
	update_terrain_costs(all_passive_effects)
	ignore_height = all_passive_effects.any(func(passive_effect: PassiveEffect) -> bool: return passive_effect.ignore_height)
	
	if move_action.targeting_strategy.has_method("get_map_paths"):
		map_paths = await move_action.targeting_strategy.get_map_paths(self, map_tiles, units, max_cost)
		paths_set = true
		paths_updated.emit()
