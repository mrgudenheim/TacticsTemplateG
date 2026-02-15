class_name UnitData
extends Resource

@export var display_name: String = "display name"
@export var level: int = 0
@export var gender: Unit.Gender = Unit.Gender.MALE # male, female, other, monster
@export var zodiac: String = "zodiac" # TODO should zodiac be derived from birthday?
@export var job_unique_name: String = "job_unique_name"
@export var team_idx: int = 0
@export var controller: int = 0 # 0 = AI, 1 = Player 1, etc.
@export var spritesheeet_file_name: String = "spritesheeet_file_name.spr" # TODO get sprite file name?
@export var palette_id: int = 0
@export var facing_direction: Unit.Facings = Unit.Facings.NORTH # north, south, east, west

# job levels
# jp per job
# abilities learned

# Stats
@export var stats: Dictionary[Unit.StatType, StatValue] = {}
@export var stats_raw: Dictionary[Unit.StatType, float] = {}

# equipment
@export var equip_slots: Array[EquipmentSlot] = []

# abilities
@export var ability_slots: Array[AbilitySlot] = []

# position
@export var tile_position: Vector3i # tile_position.get_world_position

# current statuses - to be used for saving/loading mid battle


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
			var new_stats_raw: Dictionary[Unit.StatType, float] = {}
			for stat_type in dict.keys():
				new_stats_raw[int(stat_type)] = dict[stat_type]
			new_unit_data.set(property_name, new_stats_raw)
		elif property_name == "stats":
			var dict: Dictionary = property_dict[property_name]
			var new_stats: Dictionary[Unit.StatType, StatValue] = {}
			for stat_type in dict.keys():
				var new_clamped_value: StatValue = StatValue.create_from_dictionary(dict[stat_type])
				new_stats[Unit.StatType[stat_type]] = new_clamped_value
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


func init_from_unit(unit: Unit) -> void:
	display_name = unit.unit_nickname
	level = unit.level
	gender = unit.gender # male, female, other, monster
	zodiac = "zodiac" # TODO should zodiac be derived from birthday?
	job_unique_name = unit.job_data.unique_name
	team_idx = unit.team_id
	controller = 0 if unit.is_ai_controlled else 1 # 0 = AI, 1 = Player 1, etc.
	spritesheeet_file_name = unit.sprite_file_name
	palette_id = unit.sprite_palette_id
	facing_direction = unit.facing # NORTH, SOUTH, EAST, WEST

	# job levels
	# jp per job
	# abilities learned

	stats = unit.stats
	stats_raw = unit.stats_raw
	equip_slots = unit.equip_slots
	ability_slots = unit.ability_slots
	
	var tile_xz_index: int = unit.global_battle_manager.total_map_tiles.keys().find(unit.tile_position.location)
	var terrain_level: int = unit.global_battle_manager.total_map_tiles[unit.tile_position.location].find(unit.tile_position)
	tile_position = Vector3i(unit.tile_position.location.x, terrain_level, unit.tile_position.location.y)
	if tile_xz_index == -1 or terrain_level == -1:
		push_warning(unit.unit_nickname + " tile_position: " + str(tile_position))
	# tile_position = unit.tile_position.get_world_position()
