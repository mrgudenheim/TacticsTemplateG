class_name UnitData
extends Resource

signal data_changed(unit_data: UnitData)
signal statuses_changed(unit_data: UnitData)
signal appearance_changed(unit_data: UnitData)
signal primary_weapon_changed(weapon_unique_name: String)

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

const FACING_VECTORS: Dictionary[Facings, Vector3] = {
	Facings.NORTH: Vector3.BACK,
	Facings.EAST: Vector3.RIGHT,
	Facings.SOUTH: Vector3.FORWARD,
	Facings.WEST: Vector3.LEFT,
}

@export var display_name: String = "display name"
@export var level: int = 0
@export var gender: Gender = Gender.MALE: # male, female, other, monster
	set(value):
		gender = value
		if not _stat_basis_overridden:
			stat_basis = int(value) as StatBasis
			_stat_basis_overridden = false
@export var zodiac: String = "zodiac" # TODO should zodiac be derived from birthday?
@export var job_unique_name: String = "job_unique_name"
@export var team_idx: int = 0
@export var controller: int = 0 # 0 = AI, 1 = Player 1, etc.
@export var spritesheeet_file_name: String = "spritesheeet_file_name.spr" # TODO get sprite file name?
@export var palette_id: int = 0
@export var facing_direction: Facings = Facings.NORTH # north, south, east, west

# job levels
# jp per job
# abilities learned

# Stats
@export var stats: Dictionary[StatType, StatValue] = {}
@export var stats_raw: Dictionary[StatType, float] = {}

# equipment
@export var equip_slots: Array[EquipmentSlot] = []

# abilities
@export var skillsets_names: PackedStringArray = []
@export var ability_slots: Array[AbilitySlot] = []

# position
@export var tile_position: Vector3i = Vector3i.ZERO # tile_position.get_world_position

# current statuses - to be used for saving/loading mid battle

var spritesheet_file_name: String:
	get:
		return spritesheeet_file_name
	set(value):
		spritesheeet_file_name = value

var _stat_basis_overridden: bool = false
var stat_basis: StatBasis = StatBasis.MALE:
	get:
		return stat_basis
	set(value):
		stat_basis = value
		_stat_basis_overridden = true

var job_data: JobData
var primary_weapon: ItemData
var equipable_item_types: Array[ItemData.ItemType] = []

var always_statuses: PackedStringArray = []
var immune_statuses: PackedStringArray = []
var start_statuses: PackedStringArray = []
var current_statuses: Array[StatusEffect] = [] # entry will be duplicate of status definition with modified values (duration_left, delayed action, etc)
var current_status_ids: PackedStringArray = []:
	get:
		var status_unique_names: PackedStringArray = []
		for status: StatusEffect in current_statuses:
			if not status_unique_names.has(status.unique_name):
				status_unique_names.append(status.unique_name)
		return status_unique_names

var elemental_absorb: Array[Action.ElementTypes] = []
var elemental_cancel: Array[Action.ElementTypes] = []
var elemental_half: Array[Action.ElementTypes] = []
var elemental_weakness: Array[Action.ElementTypes] = []
var elemental_strengthen: Array[Action.ElementTypes] = []

var immortal: bool = false
var immune_knockback: bool = false
var prohibited_terrain: Array[int] = [] # TileTerrain.surface_type_id
var terrain_costs: Dictionary[int, int] = {} # [TileTerrain.surface_type_id, cost]
var ignore_height: bool = false

var current_tile: TerrainTile = null
var move_points_start: int = 1
var move_points_remaining: int = 1
var action_points_start: int = 1
var action_points_remaining: int = 1

var charging_abilities_ids: PackedInt32Array = []
var charging_abilities_remaining_ct: PackedInt32Array = []
var learned_abilities: Array = []
var job_levels: Dictionary[JobData, int] = {}
var job_jp: Dictionary[JobData, int] = {}

var auto_apply_hp_threshold_statuses: bool = false
var passive_context_getter: Callable = Callable()
var _is_initialized: bool = false

var unit_exp: int = 0:
	get:
		return stats[StatType.EXP].current_value
var brave: int = 70:
	get:
		return stats[StatType.BRAVE].modified_value
var faith: int = 70:
	get:
		return stats[StatType.FAITH].modified_value
var ct_current: int = 0:
	get:
		return stats[StatType.CT].current_value
var ct_max: int = 100:
	get:
		return stats[StatType.CT].max_value
var hp_max: int = 100:
	get:
		return stats[StatType.HP_MAX].modified_value
var hp: int = 70:
	get:
		return stats[StatType.HP].current_value
var mp_max: int = 100:
	get:
		return stats[StatType.MP_MAX].modified_value
var mp: int = 70:
	get:
		return stats[StatType.MP].current_value
var physical_attack: int = 5:
	get:
		return stats[StatType.PHYSICAL_ATTACK].modified_value
var magical_attack: int = 5:
	get:
		return stats[StatType.MAGIC_ATTACK].modified_value
var speed: int = 5:
	get:
		return stats[StatType.SPEED].modified_value
var move: int = 5:
	get:
		return stats[StatType.MOVE].modified_value
var jump: int = 3:
	get:
		return stats[StatType.JUMP].modified_value

var is_defeated: bool:
	get:
		return current_statuses.any(func(status: StatusEffect) -> bool: return status.counts_as_ko)

var is_ct_frozen: bool:
	get:
		return current_statuses.any(func(status: StatusEffect) -> bool: return status.freezes_ct)

var facing_vector: Vector3:
	get:
		return FACING_VECTORS[facing_direction]

var is_ai_controlled: bool:
	get:
		return controller == 0
	set(value):
		controller = 0 if value else 1


func initialize_defaults() -> void:
	equip_slots = [
		EquipmentSlot.new("RH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
		EquipmentSlot.new("LH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
		EquipmentSlot.new("Head", [ItemData.SlotType.HEADGEAR]),
		EquipmentSlot.new("Body", [ItemData.SlotType.ARMOR]),
		EquipmentSlot.new("Accesory", [ItemData.SlotType.ACCESSORY]),
	]
	ability_slots = [
		AbilitySlot.new("Reaction", [Ability.SlotType.REACTION]),
		AbilitySlot.new("Support", [Ability.SlotType.SUPPORT]),
		AbilitySlot.new("Movement", [Ability.SlotType.MOVEMENT]),
	]
	skillsets_names = PackedStringArray(["", ""])
	stats = {
		StatType.HP_MAX: StatValue.new(0, 999, 150),
		StatType.HP: StatValue.new(0, 150, 100),
		StatType.MP_MAX: StatValue.new(0, 999, 100),
		StatType.MP: StatValue.new(0, 100, 70),
		StatType.CT: StatValue.new(0, 999, 25),
		StatType.MOVE: StatValue.new(0, 100, 3),
		StatType.JUMP: StatValue.new(0, 100, 3),
		StatType.SPEED: StatValue.new(0, 100, 10),
		StatType.PHYSICAL_ATTACK: StatValue.new(0, 100, 11),
		StatType.MAGIC_ATTACK: StatValue.new(0, 100, 12),
		StatType.BRAVE: StatValue.new(0, 100, 70),
		StatType.FAITH: StatValue.new(0, 100, 65),
		StatType.EXP: StatValue.new(0, 999, 99),
		StatType.LEVEL: StatValue.new(0, 99, 20),
	}
	stats_raw = {
		StatType.HP_MAX: 0.0,
		StatType.MP_MAX: 0.0,
		StatType.SPEED: 0.0,
		StatType.PHYSICAL_ATTACK: 0.0,
		StatType.MAGIC_ATTACK: 0.0,
	}
	wire_internal_stat_links()


func wire_internal_stat_links() -> void:
	if not stats.has(StatType.HP_MAX) or not stats.has(StatType.HP):
		return
	if not stats[StatType.HP_MAX].value_changed.is_connected(stats[StatType.HP].update_max_from_clamped_value):
		stats[StatType.HP_MAX].value_changed.connect(stats[StatType.HP].update_max_from_clamped_value)
	if stats.has(StatType.MP_MAX) and stats.has(StatType.MP):
		if not stats[StatType.MP_MAX].value_changed.is_connected(stats[StatType.MP].update_max_from_clamped_value):
			stats[StatType.MP_MAX].value_changed.connect(stats[StatType.MP].update_max_from_clamped_value)
	if not stats[StatType.HP].value_changed.is_connected(_on_hp_changed):
		stats[StatType.HP].value_changed.connect(_on_hp_changed)


func ensure_initialized() -> void:
	if stats.is_empty():
		initialize_defaults()
	else:
		if equip_slots.is_empty():
			equip_slots = [
				EquipmentSlot.new("RH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
				EquipmentSlot.new("LH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
				EquipmentSlot.new("Head", [ItemData.SlotType.HEADGEAR]),
				EquipmentSlot.new("Body", [ItemData.SlotType.ARMOR]),
				EquipmentSlot.new("Accesory", [ItemData.SlotType.ACCESSORY]),
			]
		if ability_slots.is_empty():
			ability_slots = [
				AbilitySlot.new("Reaction", [Ability.SlotType.REACTION]),
				AbilitySlot.new("Support", [Ability.SlotType.SUPPORT]),
				AbilitySlot.new("Movement", [Ability.SlotType.MOVEMENT]),
			]
		if skillsets_names.size() < 2:
			skillsets_names.resize(2)
		if stats_raw.is_empty():
			stats_raw = {
				StatType.HP_MAX: 0.0,
				StatType.MP_MAX: 0.0,
				StatType.SPEED: 0.0,
				StatType.PHYSICAL_ATTACK: 0.0,
				StatType.MAGIC_ATTACK: 0.0,
			}
		wire_internal_stat_links()

	if not _stat_basis_overridden:
		stat_basis = int(gender) as StatBasis
		_stat_basis_overridden = false

	if stats.has(StatType.LEVEL):
		if level > 0 and stats[StatType.LEVEL].current_value != level:
			stats[StatType.LEVEL].set_value(level)
		elif level == 0 and stats[StatType.LEVEL].current_value > 0:
			level = stats[StatType.LEVEL].current_value

	if job_data == null and job_unique_name != "" and job_unique_name != "job_unique_name":
		if GameData.job_paths.has(job_unique_name) or GameData.jobs_data.has(job_unique_name):
			job_data = GameData.get_job(job_unique_name)

	if primary_weapon == null and not equip_slots.is_empty():
		var weapon_name: String = equip_slots[0].item_unique_name
		if weapon_name != "" and (GameData.item_paths.has(weapon_name) or GameData.items.has(weapon_name)):
			primary_weapon = GameData.get_item(weapon_name)
		else:
			primary_weapon = ItemData.new()

	if not _is_initialized:
		_is_initialized = true
		if job_data != null:
			update_passive_effects(PackedStringArray(), false)


func duplicate_persistent() -> UnitData:
	var cloned: UnitData = UnitData.new()
	cloned.display_name = display_name
	cloned.level = level
	cloned.gender = gender
	cloned.stat_basis = stat_basis
	cloned._stat_basis_overridden = _stat_basis_overridden
	cloned.zodiac = zodiac
	cloned.job_unique_name = job_unique_name
	cloned.job_data = job_data
	cloned.team_idx = team_idx
	cloned.controller = controller
	cloned.spritesheeet_file_name = spritesheeet_file_name.to_lower().trim_suffix(".spr")
	cloned.palette_id = palette_id
	cloned.facing_direction = facing_direction
	cloned.tile_position = tile_position
	cloned.current_tile = current_tile
	cloned.immortal = immortal
	cloned.immune_knockback = immune_knockback

	cloned.stats_raw = stats_raw.duplicate()
	cloned.stats = {}
	for stat_type: StatType in stats.keys():
		var src_stat: StatValue = stats[stat_type]
		var cloned_stat: StatValue = StatValue.new(src_stat.min_value, src_stat.max_value, src_stat.current_value)
		cloned_stat.base_value = src_stat.base_value
		cloned.stats[stat_type] = cloned_stat
	cloned.wire_internal_stat_links()

	cloned.equip_slots = []
	for slot: EquipmentSlot in equip_slots:
		var cloned_equip: EquipmentSlot = EquipmentSlot.new(slot.equipment_slot_name, slot.slot_types.duplicate())
		cloned_equip.item_unique_name = slot.item_unique_name
		cloned.equip_slots.append(cloned_equip)
	cloned.primary_weapon = primary_weapon

	cloned.skillsets_names = skillsets_names.duplicate()
	cloned.ability_slots = []
	for slot: AbilitySlot in ability_slots:
		var cloned_ab: AbilitySlot = AbilitySlot.new(slot.ability_slot_name, slot.slot_types.duplicate())
		cloned_ab.ability_unique_name = slot.ability_unique_name
		cloned.ability_slots.append(cloned_ab)

	cloned.ensure_initialized()
	return cloned


func duplicate_for_sim() -> UnitData:
	var sim: UnitData = UnitData.new()
	sim.display_name = display_name
	sim.level = level
	sim.gender = gender
	sim.stat_basis = stat_basis
	sim._stat_basis_overridden = _stat_basis_overridden
	sim.zodiac = zodiac
	sim.job_unique_name = job_unique_name
	sim.job_data = job_data
	sim.team_idx = team_idx
	sim.controller = controller
	sim.spritesheeet_file_name = spritesheeet_file_name
	sim.palette_id = palette_id
	sim.facing_direction = facing_direction
	sim.tile_position = tile_position
	sim.current_tile = current_tile
	sim.immortal = immortal
	sim.immune_knockback = immune_knockback
	sim.move_points_start = move_points_start
	sim.move_points_remaining = move_points_remaining
	sim.action_points_start = action_points_start
	sim.action_points_remaining = action_points_remaining
	sim.charging_abilities_ids = charging_abilities_ids.duplicate()
	sim.charging_abilities_remaining_ct = charging_abilities_remaining_ct.duplicate()
	sim.auto_apply_hp_threshold_statuses = true

	sim.stats_raw = stats_raw.duplicate()
	sim.stats = {}
	for stat_type: StatType in stats.keys():
		var src_stat: StatValue = stats[stat_type]
		var cloned_stat: StatValue = StatValue.new(src_stat.min_value, src_stat.max_value, src_stat.current_value)
		cloned_stat.base_value = src_stat.base_value
		cloned_stat.modifiers = src_stat.modifiers.duplicate()
		sim.stats[stat_type] = cloned_stat
	sim.wire_internal_stat_links()

	sim.equip_slots = []
	for slot: EquipmentSlot in equip_slots:
		var cloned_equip: EquipmentSlot = EquipmentSlot.new(slot.equipment_slot_name, slot.slot_types.duplicate())
		cloned_equip.item_unique_name = slot.item_unique_name
		sim.equip_slots.append(cloned_equip)
	sim.primary_weapon = primary_weapon

	sim.skillsets_names = skillsets_names.duplicate()
	sim.ability_slots = []
	for slot: AbilitySlot in ability_slots:
		var cloned_ab: AbilitySlot = AbilitySlot.new(slot.ability_slot_name, slot.slot_types.duplicate())
		cloned_ab.ability_unique_name = slot.ability_unique_name
		sim.ability_slots.append(cloned_ab)

	sim.current_statuses = []
	for status: StatusEffect in current_statuses:
		var cloned_status: StatusEffect = status.duplicate()
		cloned_status.passive_effect = status.get_passive_effect()
		cloned_status.delayed_action = status.delayed_action
		sim.current_statuses.append(cloned_status)

	sim.always_statuses = always_statuses.duplicate()
	sim.immune_statuses = immune_statuses.duplicate()
	sim.start_statuses = start_statuses.duplicate()
	sim.elemental_absorb = elemental_absorb.duplicate()
	sim.elemental_cancel = elemental_cancel.duplicate()
	sim.elemental_half = elemental_half.duplicate()
	sim.elemental_weakness = elemental_weakness.duplicate()
	sim.elemental_strengthen = elemental_strengthen.duplicate()
	sim.equipable_item_types = equipable_item_types.duplicate()
	sim.prohibited_terrain = prohibited_terrain.duplicate()
	sim.terrain_costs = terrain_costs.duplicate()
	sim.ignore_height = ignore_height
	sim._is_initialized = true
	return sim


func sync_tile_coords_from_map(total_map_tiles: Dictionary) -> void:
	if current_tile == null:
		return
	var tile_xz_index: int = total_map_tiles.keys().find(current_tile.location)
	var terrain_level: int = -1
	if total_map_tiles.has(current_tile.location):
		terrain_level = total_map_tiles[current_tile.location].find(current_tile)
	tile_position = Vector3i(current_tile.location.x, terrain_level, current_tile.location.y)
	if tile_xz_index == -1 or terrain_level == -1:
		push_warning(display_name + " tile_position: " + str(tile_position))


static func create_from_dictionary(property_dict: Dictionary) -> UnitData:
	var new_unit_data: UnitData = UnitData.new()
	for property_name: String in property_dict.keys():
		if property_name == "tile_position":
			var vector_as_array: Array = property_dict[property_name]
			var new_tile_position: Vector3i = Vector3i(roundi(vector_as_array[0]), roundi(vector_as_array[1]), roundi(vector_as_array[2]))
			new_unit_data.set(property_name, new_tile_position)
		elif property_name == "ability_slots":
			var array: Array = property_dict[property_name]
			var new_ability_slots: Array[AbilitySlot] = []
			for ability_slot_dictionary: Dictionary in array:
				var new_ability_slot: AbilitySlot = AbilitySlot.create_from_dictionary(ability_slot_dictionary)
				new_ability_slots.append(new_ability_slot)
			new_unit_data.set(property_name, new_ability_slots)
		elif property_name == "equip_slots":
			var array: Array = property_dict[property_name]
			var new_equip_slots: Array[EquipmentSlot] = []
			for equip_slot_dictionary: Dictionary in array:
				var new_equip_slot: EquipmentSlot = EquipmentSlot.create_from_dictionary(equip_slot_dictionary)
				new_equip_slots.append(new_equip_slot)
			new_unit_data.set(property_name, new_equip_slots)
		elif property_name == "stats_raw":
			var dict: Dictionary = property_dict[property_name]
			var new_stats_raw: Dictionary[StatType, float] = {}
			for stat_type: String in dict.keys():
				new_stats_raw[StatType[stat_type]] = dict[stat_type]
			new_unit_data.set(property_name, new_stats_raw)
		elif property_name == "stats":
			var dict: Dictionary = property_dict[property_name]
			var new_stats: Dictionary[StatType, StatValue] = {}
			for stat_type: String in dict.keys():
				var new_clamped_value: StatValue = StatValue.create_from_dictionary(dict[stat_type])
				new_stats[StatType[stat_type]] = new_clamped_value
			new_unit_data.set(property_name, new_stats)
		elif property_name == "gender":
			var gender_val: Variant = property_dict[property_name]
			if gender_val is String:
				new_unit_data.gender = Gender[gender_val]
			else:
				new_unit_data.gender = int(gender_val) as Gender
		elif property_name == "facing_direction":
			var facing_val: Variant = property_dict[property_name]
			if facing_val is String:
				new_unit_data.facing_direction = Facings[facing_val]
			else:
				new_unit_data.facing_direction = int(facing_val) as Facings
		elif property_name == "spritesheet_file_name" or property_name == "spritesheeet_file_name":
			new_unit_data.spritesheeet_file_name = str(property_dict[property_name])
		else:
			new_unit_data.set(property_name, property_dict[property_name])

	new_unit_data.ensure_initialized()
	new_unit_data.emit_changed()
	return new_unit_data


func to_dictionary() -> Dictionary:
	var properties_to_exclude: PackedStringArray = [
		"RefCounted",
		"Resource",
		"resource_local_to_scene",
		"resource_path",
		"resource_name",
		"resource_scene_unique_id",
		"script",
	]
	
	return Utilities.object_properties_to_dictionary(self, properties_to_exclude)


func init_from_unit(unit: Unit) -> void:
	var cloned: UnitData = unit.data.duplicate_persistent()
	display_name = cloned.display_name
	level = cloned.level
	gender = cloned.gender
	stat_basis = cloned.stat_basis
	zodiac = cloned.zodiac
	job_unique_name = cloned.job_unique_name
	job_data = cloned.job_data
	team_idx = cloned.team_idx
	controller = cloned.controller
	spritesheeet_file_name = cloned.spritesheeet_file_name
	palette_id = cloned.palette_id
	facing_direction = cloned.facing_direction
	stats = cloned.stats
	stats_raw = cloned.stats_raw
	equip_slots = cloned.equip_slots
	skillsets_names = cloned.skillsets_names
	ability_slots = cloned.ability_slots
	current_tile = unit.tile_position
	if unit.global_battle_manager != null and unit.tile_position != null:
		sync_tile_coords_from_map(unit.global_battle_manager.total_map_tiles)
	else:
		tile_position = cloned.tile_position


func is_lucavi() -> bool:
	var clean_sprite: String = spritesheeet_file_name.to_lower().trim_suffix(".spr")
	if GameData.unit_spritesheet_data_paths.has(clean_sprite) or GameData.unit_spritesheets_data.has(clean_sprite):
		var seq_uname: String = GameData.get_spritesheet_data(clean_sprite).seq_name.to_lower().trim_suffix(".seq")
		return ["ruka", "arute", "kanzen"].has(seq_uname)
	return ["ruka", "arute", "kanzen", "ruka.seq", "arute.seq", "kanzen.seq"].has(clean_sprite)


func recalculate_stats_for_level(new_level: int, regenerate_raw: bool = true, set_to_max: bool = true, use_rom: bool = false) -> void:
	level = new_level
	if stats.has(StatType.LEVEL):
		stats[StatType.LEVEL].set_value(new_level)
	if job_data == null and job_unique_name != "" and job_unique_name != "job_unique_name":
		if GameData.job_paths.has(job_unique_name) or GameData.jobs_data.has(job_unique_name):
			job_data = GameData.get_job(job_unique_name)
		elif RomReader.jobs_data.has(job_unique_name):
			job_data = RomReader.jobs_data[job_unique_name]
	if job_data == null:
		return
	if regenerate_raw:
		UnitData.generate_leveled_raw_stats(stat_basis, new_level, job_data, stats_raw, use_rom)
	UnitData.calc_battle_stats(job_data, stats_raw, stats, set_to_max, is_lucavi())
	update_passive_effects(PackedStringArray(), set_to_max)


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
		raw_stat = randi_range(stat_range.x, stat_range.y)
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
	if use_larger_values:
		new_stats[StatType.HP_MAX].max_value = 99999
		base_hp = base_hp * 100
	new_stats[StatType.HP_MAX].base_value = base_hp
	new_stats[StatType.HP_MAX].set_value(new_stats[StatType.HP_MAX].base_value)
	
	var base_mp: int = roundi(new_stats_raw[StatType.MP_MAX] * current_job.mp_multiplier / 0x190000)
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

	if set_to_max:
		new_stats[StatType.HP].set_value(new_stats[StatType.HP].max_value)
		new_stats[StatType.MP].set_value(new_stats[StatType.MP].max_value)


static func create_random(job_uname: String, unit_level: int, unit_team_idx: int) -> UnitData:
	var new_data: UnitData = UnitData.new()
	new_data.initialize_defaults()
	new_data._is_initialized = true
	new_data.team_idx = unit_team_idx

	var resolved_job: JobData = GameData.get_job(job_uname)
	new_data.gender = [Gender.MALE, Gender.FEMALE].pick_random()
	if resolved_job.job_id >= 0x5e:
		new_data.gender = Gender.MONSTER
	new_data.stat_basis = int(new_data.gender) as StatBasis
	new_data._stat_basis_overridden = false

	if GameData.names.has("all_no_empty") and not GameData.names["all_no_empty"].is_empty():
		var random_name_idx: int = randi_range(0, GameData.names["all_no_empty"].size() - 1)
		new_data.display_name = GameData.names["all_no_empty"][random_name_idx]
	new_data.zodiac = "Ares"

	new_data.set_job(job_uname, true)
	if not GameData.skillset_paths.is_empty():
		var random_skillset: Skillset = GameData.get_skillset(GameData.skillset_paths.keys().pick_random())
		new_data.equip_skillset(1, random_skillset)
	new_data.generate_random_abilities()
	new_data.recalculate_stats_for_level(unit_level, true, true, false)
	new_data.generate_equipment()

	new_data.stats[StatType.BRAVE].set_value(randi_range(40, 70))
	new_data.stats[StatType.FAITH].set_value(randi_range(40, 70))
	new_data.stats[StatType.HP].set_value(new_data.stats[StatType.HP].max_value)
	new_data.stats[StatType.MP].set_value(new_data.stats[StatType.MP].max_value)
	return new_data


func set_job(new_job_name: String, update_default_sprite: bool = true) -> void:
	job_unique_name = new_job_name
	if GameData.job_paths.has(new_job_name) or GameData.jobs_data.has(new_job_name):
		job_data = GameData.get_job(new_job_name)
	if skillsets_names.size() < 2:
		skillsets_names.resize(2)
	if job_data != null:
		if update_default_sprite:
			var sprite_name: String = job_data.sprite_name
			if (job_data.job_id >= 0x4a and job_data.job_id <= 0x5a or job_data.job_id == 0x5d) and stat_basis == StatBasis.FEMALE:
				sprite_name = sprite_name.replace("_m", "_w")
			spritesheeet_file_name = sprite_name
			if job_data.default_palette_idx != -1:
				palette_id = job_data.default_palette_idx
			else:
				palette_id = randi_range(0, 4)
			appearance_changed.emit(self)
		if job_data.skillset_unique_name != "" and (GameData.skillset_paths.has(job_data.skillset_unique_name) or GameData.skillsets.has(job_data.skillset_unique_name)):
			skillsets_names[0] = job_data.skillset_unique_name
	update_passive_effects()


func set_primary_weapon(new_weapon_unique_name: String) -> void:
	if equip_slots.is_empty():
		initialize_defaults()
	equip_slots[0].item_unique_name = new_weapon_unique_name
	if new_weapon_unique_name != "" and (GameData.item_paths.has(new_weapon_unique_name) or GameData.items.has(new_weapon_unique_name)):
		primary_weapon = GameData.get_item(new_weapon_unique_name)
	else:
		primary_weapon = ItemData.new()
	primary_weapon_changed.emit(new_weapon_unique_name)
	data_changed.emit(self)


func set_equipment_slot(slot: EquipmentSlot, item: ItemData) -> void:
	slot.item_unique_name = item.unique_name
	if slot.equipment_slot_name == "RH":
		set_primary_weapon(item.unique_name)
	update_passive_effects()


func equip_ability(slot: AbilitySlot, ability: Ability) -> void:
	slot.ability_unique_name = ability.unique_name
	update_passive_effects()


func equip_skillset(skillset_idx: int, new_skillset: Skillset) -> void:
	if skillsets_names.size() <= skillset_idx:
		skillsets_names.resize(skillset_idx + 1)
	skillsets_names[skillset_idx] = new_skillset.unique_name
	data_changed.emit(self)


func generate_random_abilities() -> void:
	if GameData.ability_paths.is_empty():
		return
	var random_reaction_name: String = GameData.ability_paths.keys().filter(func(ability_name: String) -> bool: return GameData.get_ability(ability_name).slot_type == Ability.SlotType.REACTION).pick_random()
	var random_reaction: Ability = GameData.get_ability(random_reaction_name)

	var random_support_name: String = GameData.ability_paths.keys().filter(func(ability_name: String) -> bool: return GameData.get_ability(ability_name).slot_type == Ability.SlotType.SUPPORT).pick_random()
	var random_support: Ability = GameData.get_ability(random_support_name)
	
	var random_movement_name: String = GameData.ability_paths.keys().filter(func(ability_name: String) -> bool: return GameData.get_ability(ability_name).slot_type == Ability.SlotType.MOVEMENT).pick_random()
	var random_movement: Ability = GameData.get_ability(random_movement_name)

	ability_slots[0].ability_unique_name = random_reaction.unique_name
	ability_slots[1].ability_unique_name = random_support.unique_name
	ability_slots[2].ability_unique_name = random_movement.unique_name

	update_passive_effects()


func generate_equipment() -> void:
	equip_slots[0].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.WEAPON, level) # RH
	equip_slots[1].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.SHIELD, level) # LH
	equip_slots[2].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.HEADGEAR, level) # headgear
	equip_slots[3].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.ARMOR, level) # armor
	equip_slots[4].item_unique_name = get_item_unique_name_for_slot(ItemData.SlotType.ACCESSORY, level, true) # accessory
	
	set_primary_weapon(equip_slots[0].item_unique_name)
	update_passive_effects()


func get_item_unique_name_for_slot(slot_type: ItemData.SlotType, item_level: int, random: bool = false) -> String:
	var valid_items_names: Array[String] = []
	valid_items_names.assign(GameData.item_paths.keys().filter(func(item_name: String) -> bool:
		var item: ItemData = GameData.get_item(item_name)
		var slot_type_is_valid: bool = item.slot_type == slot_type
		var level_is_valid: bool = item.min_level <= item_level
		var type_is_valid: bool = equipable_item_types.has(item.item_type)
		return slot_type_is_valid and level_is_valid and type_is_valid))
	var item_unique_name: String = ""
	if not valid_items_names.is_empty():
		if random:
			item_unique_name = valid_items_names.pick_random()
		else:
			valid_items_names.sort_custom(func(item_a_name: String, item_b_name: String) -> bool: return GameData.get_item(item_a_name).min_level > GameData.get_item(item_b_name).min_level)
			item_unique_name = valid_items_names[0]
	return item_unique_name


func _on_hp_changed(clamped_value: StatValue) -> void:
	if not auto_apply_hp_threshold_statuses:
		return

	@warning_ignore("integer_division")
	var critical_hp_threshold: int = clamped_value.max_value / 5

	if clamped_value.current_value == 0:
		if GameData.status_effect_paths.has("dead") or GameData.status_effects.has("dead"):
			var dead_status: StatusEffect = GameData.get_status_effect("dead").duplicate()
			dead_status.passive_effect = GameData.get_status_effect("dead").get_passive_effect()
			apply_status(dead_status, true)
	elif clamped_value.current_value < critical_hp_threshold:
		if not current_status_ids.has("critical"):
			if GameData.status_effect_paths.has("critical") or GameData.status_effects.has("critical"):
				var crit_status: StatusEffect = GameData.get_status_effect("critical").duplicate()
				crit_status.passive_effect = GameData.get_status_effect("critical").get_passive_effect()
				apply_status(crit_status)
	elif clamped_value.current_value >= critical_hp_threshold:
		remove_status_id("critical")


func apply_status(new_status: StatusEffect, ignore_immunity: bool = false) -> bool:
	if not ignore_immunity and immune_statuses.has(new_status.unique_name):
		return false
	
	for status_prevents_id: String in new_status.status_cant_stack:
		if current_statuses.any(func(status: StatusEffect) -> bool: return status.unique_name == status_prevents_id):
			return false
	
	var existing_statuses: Array[StatusEffect] = current_statuses.filter(func(status: StatusEffect) -> bool: return status.status_id == new_status.status_id)
	if existing_statuses.size() >= new_status.num_allowed:
		var temp_statuses: Array[StatusEffect] = existing_statuses.filter(func(status: StatusEffect) -> bool: return status.duration_type != StatusEffect.DurationType.PERMANENT)
		if not temp_statuses.is_empty():
			remove_status(temp_statuses[0])
		else:
			return false
	
	new_status.passive_effect = new_status.get_passive_effect()
	current_statuses.append(new_status)
	if new_status.unique_name == "dead" and stats.has(StatType.HP) and stats[StatType.HP].current_value > 0:
		stats[StatType.HP].set_value(0)
	
	for status_cancelled_id: String in new_status.status_cancels:
		remove_status_id(status_cancelled_id)
	
	statuses_changed.emit(self)
	update_passive_effects()
	return true


func remove_status_id(status_removed_unique_name: String) -> void:
	var statuses_to_remove: Array[StatusEffect] = []
	statuses_to_remove.append_array(current_statuses.filter(func(status: StatusEffect) -> bool: return status.unique_name == status_removed_unique_name and status.duration_type != StatusEffect.DurationType.PERMANENT))
	for status: StatusEffect in statuses_to_remove:
		remove_status(status)


func remove_status(status_removed: StatusEffect, remove_permanent: bool = false) -> void:
	if status_removed.duration_type == StatusEffect.DurationType.PERMANENT and not remove_permanent:
		push_error("Trying to removing Always status: " + status_removed.status_effect_name)
		return
	
	var status_passive: PassiveEffect = status_removed.get_passive_effect()
	for stat: StatType in status_passive.stat_modifiers.keys():
		stats[stat].remove_modifier(status_passive.stat_modifiers[stat])
	current_statuses.erase(status_removed)
	statuses_changed.emit(self)
	update_passive_effects()


func get_nullify_statuses() -> Array[StatusEffect]:
	return current_statuses.filter(func(status: StatusEffect) -> bool: return status.get_passive_effect().nullify_targeted)


func update_permanent_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	always_statuses.clear()
	for passive_effect: PassiveEffect in all_passive_effects:
		always_statuses.append_array(passive_effect.status_always)
	
	for status_unique_name: String in GameData.status_effect_paths.keys():
		if immune_statuses.has(status_unique_name):
			continue
		
		var num_should_have: int = 0
		for passive_effect: PassiveEffect in all_passive_effects:
			num_should_have += passive_effect.status_always.count(status_unique_name)
		
		var current_permanent: Array[StatusEffect] = current_statuses.filter(func(status: StatusEffect) -> bool: return status.unique_name == status_unique_name and status.duration_type == StatusEffect.DurationType.PERMANENT)
		var num_has: int = current_permanent.size()
		var change: int = num_should_have - num_has
		
		if change == 0:
			continue
		elif change > 0:
			for counter: int in change:
				var base_status: StatusEffect = GameData.get_status_effect(status_unique_name)
				var new_status: StatusEffect = base_status.duplicate()
				new_status.passive_effect = base_status.get_passive_effect()
				new_status.duration_type = StatusEffect.DurationType.PERMANENT
				apply_status(new_status)
		elif change < 0:
			for counter: int in -change:
				var status_to_remove: StatusEffect = current_permanent[-counter - 1]
				remove_status(status_to_remove, true)


func update_immune_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	immune_statuses.clear()

	for passive_effect: PassiveEffect in all_passive_effects:
		immune_statuses.append_array(passive_effect.status_immune)


func update_start_statuses(all_passive_effects: Array[PassiveEffect]) -> void:
	start_statuses.clear()

	for passive_effect: PassiveEffect in all_passive_effects:
		start_statuses.append_array(passive_effect.status_start)


func update_passive_effects(exclude_passives: PackedStringArray = [], refill_hp_mp_to_max: bool = false) -> void:
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects(exclude_passives)

	update_permanent_statuses(all_passive_effects)
	update_immune_statuses(all_passive_effects)
	update_start_statuses(all_passive_effects)

	all_passive_effects = get_all_passive_effects(exclude_passives)
	update_stat_modifiers(all_passive_effects)
	update_elemental_affinity(all_passive_effects)
	update_equipable_item_types(all_passive_effects)
	update_prohibited_terrain(all_passive_effects)
	update_terrain_costs(all_passive_effects)
	ignore_height = all_passive_effects.any(func(passive_effect: PassiveEffect) -> bool: return passive_effect.ignore_height)

	if refill_hp_mp_to_max:
		stats[StatType.HP].set_value(stats[StatType.HP].max_value)
		stats[StatType.MP].set_value(stats[StatType.MP].max_value)

	data_changed.emit(self)


func get_all_passive_effects(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	var all_passive_effects: Array[PassiveEffect] = []
	var native_passive_effects: Array[PassiveEffect] = get_native_passive_effects(exclude_passives)
	var other_passive_effects: Array[PassiveEffect] = get_passive_effects_from_others(exclude_passives)
	all_passive_effects.append_array(native_passive_effects)
	all_passive_effects.append_array(other_passive_effects)
	return all_passive_effects


func get_native_passive_effects(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	var native_passive_effects: Array[PassiveEffect] = []
	
	if job_data != null:
		native_passive_effects.append_array(job_data.get_passive_effects())
		for ability: Ability in job_data.innate_abilities:
			if ability != null and (ability.passive_effect_name != "" or GameData.passive_effect_paths.has(ability.passive_effect_name)):
				native_passive_effects.append(ability.get_passive_effect())
	
	for ability_slot: AbilitySlot in ability_slots:
		if ability_slot.ability_unique_name != "" and (GameData.ability_paths.has(ability_slot.ability_unique_name) or GameData.abilities.has(ability_slot.ability_unique_name)):
			var slot_ability: Ability = ability_slot.get_ability()
			if slot_ability.passive_effect_name != "" or GameData.passive_effect_paths.has(slot_ability.passive_effect_name):
				native_passive_effects.append(slot_ability.get_passive_effect())
	
	for equipment_slot: EquipmentSlot in equip_slots:
		if equipment_slot.item_unique_name != "" and (GameData.item_paths.has(equipment_slot.item_unique_name) or GameData.items.has(equipment_slot.item_unique_name)):
			var slot_item: ItemData = equipment_slot.get_item()
			if slot_item.passive_effect_name != "" or GameData.passive_effect_paths.has(slot_item.passive_effect_name):
				native_passive_effects.append(slot_item.get_passive_effect())
	
	for status: StatusEffect in current_statuses:
		native_passive_effects.append(status.get_passive_effect())
	
	if passive_context_getter.is_valid():
		var context: Dictionary = passive_context_getter.call()
		if context.has("global_passives"):
			var global_passives: Array = context["global_passives"]
			for global_passive: PassiveEffect in global_passives:
				native_passive_effects.append(global_passive)

	native_passive_effects = native_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return passive_effect != null and passive_effect.effect_range == 0)
	native_passive_effects = native_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return not exclude_passives.has(passive_effect.unique_name))
	
	return native_passive_effects


func get_passive_effects_from_others(exclude_passives: PackedStringArray = []) -> Array[PassiveEffect]:
	var shared_passive_effects: Array[PassiveEffect] = []
	if not passive_context_getter.is_valid() or current_tile == null:
		return shared_passive_effects

	var context: Dictionary = passive_context_getter.call()
	if not context.has("units_data"):
		return shared_passive_effects

	var other_units: Array = context["units_data"]
	for other_data: UnitData in other_units:
		if other_data == null or other_data.current_tile == null:
			continue
		var unit_passives: Array[PassiveEffect] = other_data.get_native_passive_effects()
		for passive_effect: PassiveEffect in unit_passives:
			if passive_effect.effect_range == 0:
				continue
			
			if not passive_effect.unit_team_filter.is_empty():
				if not passive_effect.unit_team_filter.has(PassiveEffect.FilterTeam.FRIENDLY) and other_data.team_idx == self.team_idx:
					continue
				elif not passive_effect.unit_team_filter.has(PassiveEffect.FilterTeam.ENEMY) and other_data.team_idx != self.team_idx:
					continue
			
			if not passive_effect.unit_basis_filter.is_empty():
				if not passive_effect.unit_basis_filter.has(stat_basis):
					continue
			
			var relative_position: Vector2i = (current_tile.location - other_data.current_tile.location).abs()
			var distance_to_unit: int = relative_position.x + relative_position.y
			if distance_to_unit > passive_effect.effect_range:
				continue
			
			var relative_height: float = absf(current_tile.height_mid - other_data.current_tile.height_mid)
			if relative_height > passive_effect.vertical_tolerance:
				continue
			
			shared_passive_effects.append(passive_effect)

	shared_passive_effects = shared_passive_effects.filter(func(passive_effect: PassiveEffect) -> bool: return not exclude_passives.has(passive_effect.unique_name))
	return shared_passive_effects


func update_stat_modifiers(all_passive_effects: Array[PassiveEffect]) -> void:
	for stat_type: StatType in StatType.values():
		if stats.has(stat_type) and not stats[stat_type].modifiers.is_empty():
			stats[stat_type].modifiers.clear()

	for passive_effect: PassiveEffect in all_passive_effects:
		for stat_type: StatType in passive_effect.stat_modifiers.keys():
			if stats.has(stat_type):
				stats[stat_type].add_modifier(passive_effect.stat_modifiers[stat_type], false)
	
	for stat_type: StatType in StatType.values():
		if stats.has(stat_type):
			stats[stat_type].value_changed.emit(stats[stat_type])


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


func update_equipable_item_types(all_passive_effects: Array[PassiveEffect]) -> void:
	equipable_item_types = []
	for passive_effect: PassiveEffect in all_passive_effects:
		equipable_item_types.append_array(passive_effect.added_equipment_types_equipable)
	if job_data != null:
		equipable_item_types.append_array(job_data.equippable_item_types)


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


func get_evade(evade_source: EvadeData.EvadeSource, evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> int:
	var evade: int = 0
	
	if job_data != null:
		for evade_data: EvadeData in job_data.evade_datas:
			if (evade_data.source == evade_source
					and evade_data.type == evade_type
					and evade_data.directions.has(evade_direction)):
				evade += evade_data.value
	
	for equip_slot: EquipmentSlot in equip_slots:
		if equip_slot.item_unique_name != "" and (GameData.item_paths.has(equip_slot.item_unique_name) or GameData.items.has(equip_slot.item_unique_name)):
			for evade_data: EvadeData in equip_slot.get_item().evade_datas:
				if (evade_data.source == evade_source
						and evade_data.type == evade_type
						and evade_data.directions.has(evade_direction)):
					evade += evade_data.value
	
	return evade


func get_evade_values(evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> Dictionary[EvadeData.EvadeSource, int]:
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = {}
	for evade_source: EvadeData.EvadeSource in EvadeData.EvadeSource.values():
		var evade_value: int = get_evade(evade_source, evade_type, evade_direction)
		evade_values[evade_source] = evade_value
	
	return evade_values


func get_attack_action() -> Action:
	if not equip_slots.is_empty():
		return equip_slots[0].get_item().get_attack_action()
	return Action.new()


func get_skillsets() -> Array[Skillset]:
	var skillsets: Array[Skillset] = []
	for skillset_name: String in skillsets_names:
		if skillset_name != null and not skillset_name.is_empty():
			if GameData.skillset_paths.has(skillset_name) or GameData.skillsets.has(skillset_name):
				skillsets.append(GameData.get_skillset(skillset_name))
	
	return skillsets


func get_skillset_actions() -> Array[Action]:
	var action_list: Array[Action] = []
	for skillset: Skillset in get_skillsets():
		for ability_name: String in skillset.ability_names:
			if not GameData.ability_paths.has(ability_name) and not GameData.abilities.has(ability_name):
				continue
			var ability_is_action: bool = not [Ability.SlotType.REACTION, Ability.SlotType.SUPPORT, Ability.SlotType.MOVEMENT].has(GameData.get_ability(ability_name).slot_type)
			if ability_is_action and (GameData.action_paths.has(ability_name) or GameData.actions.has(ability_name)):
				var new_action: Action = GameData.get_action(ability_name)
				action_list.append(new_action)
	return action_list


func get_available_actions(move_act: Action = null, wait_act: Action = null, all_passive_effects: Array[PassiveEffect] = []) -> Array[Action]:
	var result_actions: Array[Action] = []
	if move_act != null:
		result_actions.append(move_act)
	result_actions.append(get_attack_action())
	result_actions.append_array(get_skillset_actions())

	var passives_to_use: Array[PassiveEffect] = all_passive_effects
	if passives_to_use.is_empty():
		passives_to_use = get_all_passive_effects()
	for passive_effect: PassiveEffect in passives_to_use:
		for action: Action in passive_effect.added_actions:
			if not result_actions.has(action):
				result_actions.append(action)

	if wait_act != null:
		result_actions.append(wait_act)
	return result_actions
