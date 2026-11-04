class_name UnitData
extends Resource

signal initialized()
signal data_updated(unit_data: UnitData)
signal knocked_out(unit_data: UnitData)
signal ability_completed()
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
@export var gender: UnitData.Gender = UnitData.Gender.MALE # male, female, other, monster
@export var stat_basis: StatBasis = StatBasis.MALE
@export var zodiac: UnitData.Zodiac = UnitData.Zodiac.ARIES
@export var job_unique_name: String = "job_unique_name"
@export var controller: UnitData.Controller = UnitData.Controller.AI # 0 = AI, 1 = Player, etc.
@export var spritesheeet_file_name: String = "spritesheeet_file_name.spr" # TODO get sprite file name?
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

@export var team_id: String = "team_id"
var team: Team

var ai_controller: UnitAi = UnitAi.new()
var job_data: JobData

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
@export var skillsets_names: PackedStringArray = []
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
}

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
var move_action: Action
var wait_action: Action
var actions: Array[Action] = []
var actions_data: Dictionary[String, ActionInstance] = {}
var active_action: ActionInstance

var game_data: GameData
var battle_manager: BattleManager
var unit_actor: UnitActor

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
		else:
			new_unit_data.set(property_name, property_dict[property_name])

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


func init_from_unit(unit: UnitActor) -> void:
	display_name = unit.unit_nickname
	level = unit.level
	gender = unit.gender # male, female, other, monster
	zodiac = "zodiac" # TODO should zodiac be derived from birthday?
	job_unique_name = unit.job_data.unique_name
	team_idx = unit.team_id
	controller = 0 if unit.is_ai_controlled else 1 # 0 = AI, 1 = Player 1, etc.
	spritesheeet_file_name = unit.sprite_file_name.to_lower().trim_suffix(".spr")
	palette_id = unit.sprite_palette_id
	facing_direction = unit.facing # NORTH, SOUTH, EAST, WEST

	# job levels
	# jp per job
	# abilities learned

	stats = unit.stats
	stats_raw = unit.stats_raw
	equip_slots = unit.equip_slots
	skillsets_names = unit.skillsets_names
	ability_slots = unit.ability_slots
	
	var tile_xz_index: int = unit.global_battle_manager.total_map_tiles.keys().find(unit.tile_position.location)
	var terrain_level: int = unit.global_battle_manager.total_map_tiles[unit.tile_position.location].find(unit.tile_position)
	tile_position = Vector3i(unit.tile_position.location.x, terrain_level, unit.tile_position.location.y)
	if tile_xz_index == -1 or terrain_level == -1:
		push_warning(unit.unit_nickname + " tile_position: " + str(tile_position))
	# tile_position = unit.tile_position.get_world_position()


func get_current_status_ids() -> PackedStringArray:
	var status_unique_names: PackedStringArray = []
	for status: StatusEffect in current_statuses:
		if not status_unique_names.has(status.unique_name):
			status_unique_names.append(status.unique_name)
	return status_unique_names


func get_facing_vector() -> Vector3:
	return FACING_VECTORS[facing_direction]


func is_defeated() -> bool:
	return current_statuses.any(func(status: StatusEffect) -> bool: return status.counts_as_ko) # returns false when no statuses


func is_ct_frozen() -> bool:
	return current_statuses.any(func(status: StatusEffect) -> bool: return status.freezes_ct) # returns false when no statuses