class_name WldcoreData

# https://ffhacktics.com/wiki/WLDCORE.BIN_Random_Battle_Data
var world_random_battle_data_start: int = 0x2fa64
var world_random_battle_data_num_entries: int = 57
var world_random_battle_data_entry_length: int = 24
var world_random_battle_data: Array[RandomBattle] = []

var dungeon_random_battle_data_start: int = 0x2ffc0
var dungeon_random_battle_data_num_entries: int = 10
var dungeon_random_battle_data_entry_length: int = 10
var dungeon_random_battle_data: Array[DungeonBattle] = []

class RandomBattle:
	var path_id: int = 0
	var squad_id: int = 0
	var battle_sets: Array[PackedByteArray] = []
	var entds: PackedInt32Array = []
	var map_id: int = 0
	var variable_id: int = 0
	
	func _init(bytes: PackedByteArray) -> void:
		path_id = bytes.decode_u8(0)
		squad_id = bytes.decode_u8(1) + 0x200
		
		for idx: int in 4:
			var battle_set_start: int = (idx * 3) + 2
			var battle_set_bytes: PackedByteArray = bytes.slice(battle_set_start, battle_set_start + 3)
			battle_sets.append(battle_set_bytes)
		
		for idx: int in 8:
			entds.append(bytes.decode_u8(idx + 0x0e))
		
		map_id = bytes.decode_u8(0x16)
		variable_id = bytes.decode_u8(0x17)

class DungeonBattle:
	var map_id: int = 0
	var squad_id: int = 0
	var entds: PackedByteArray = []
	
	func _init(bytes: PackedByteArray) -> void:
		map_id = bytes.decode_u8(0)
		squad_id = bytes.decode_u8(1) + 0x200
		
		for idx: int in 8:
			entds.append(bytes.decode_u8(idx + 0x02))


static func get_scenarios_from_random_battle(fft_random_battle: Variant) -> Array[Scenario]:
	## fft_random_battle should be of type WldcoreData.RandomBattle or WldcoreData.DungeonBattle
	if not (fft_random_battle is WldcoreData.RandomBattle or fft_random_battle is WldcoreData.DungeonBattle):
		push_error("random battle data is not expected type")

	var new_scenarios: Array[Scenario] = []
	var new_scenario_base: Scenario = Scenario.new()
	new_scenario_base.is_fft_scenario = true

	var map_unique_name_num: String = "map_%03d" % fft_random_battle.map_id
	var map_name_idx: int = RomReader.maps.keys().find_custom(func(map_name: String) -> bool: return map_name.begins_with(map_unique_name_num))
	var map_unique_name: String = RomReader.maps.keys()[map_name_idx]
	
	var new_map_chunk: Scenario.MapChunk = Scenario.MapChunk.new()
	new_map_chunk.unique_name = map_unique_name
	# new_map_chunk.set_mirror_xyz([true, true, false])
	new_scenario_base.map_chunks.append(new_map_chunk)
	
	var unique_entds: PackedInt64Array = []
	for entd_idx: int in fft_random_battle.entds:
		if unique_entds.has(entd_idx):
			continue
		unique_entds.append(entd_idx)

		var new_scenario: Scenario = new_scenario_base.duplicate()
		var scenario_entd: FftEntd = RomReader.fft_entds[entd_idx]
		new_scenario.units_data = scenario_entd.get_units_data()
		new_scenario.unique_name = map_unique_name
		
		new_scenarios.append(new_scenario)

	return new_scenarios


func init_from_wldcore() -> void:
	var wldcore_bytes: PackedByteArray = RomReader.get_file_data("WLDCORE.BIN")
	
	var world_random_battle_bytes_length: int = world_random_battle_data_num_entries * world_random_battle_data_entry_length
	var world_random_battle_table_bytes: PackedByteArray = wldcore_bytes.slice(world_random_battle_data_start, world_random_battle_data_start + world_random_battle_bytes_length)
	for idx: int in world_random_battle_data_num_entries:
		var world_random_battle_bytes_start: int = idx * world_random_battle_data_entry_length
		var world_random_battle_bytes: PackedByteArray = world_random_battle_table_bytes.slice(world_random_battle_bytes_start, world_random_battle_bytes_start + world_random_battle_data_entry_length)

		world_random_battle_data.append(RandomBattle.new(world_random_battle_bytes))
	
	var dungeon_random_battle_bytes_length: int = dungeon_random_battle_data_num_entries * dungeon_random_battle_data_entry_length
	var dungeon_random_battle_table_bytes: PackedByteArray = wldcore_bytes.slice(dungeon_random_battle_data_start, dungeon_random_battle_data_start + dungeon_random_battle_bytes_length)
	for idx: int in dungeon_random_battle_data_num_entries:
		var dungeon_random_battle_bytes_start: int = idx * dungeon_random_battle_data_entry_length
		var dungeon_random_battle_bytes: PackedByteArray = dungeon_random_battle_table_bytes.slice(dungeon_random_battle_bytes_start, dungeon_random_battle_bytes_start + dungeon_random_battle_data_entry_length)

		dungeon_random_battle_data.append(DungeonBattle.new(dungeon_random_battle_bytes))


func get_all_scenarios() -> Array[Scenario]:
	var new_scenarios: Array[Scenario] = []

	for random_battle: RandomBattle in world_random_battle_data:
		var random_battle_scenarios: Array[Scenario] = get_scenarios_from_random_battle(random_battle)
		new_scenarios.append_array(random_battle_scenarios)
	
	for dungeon_battle: DungeonBattle in dungeon_random_battle_data:
		var random_battle_scenarios: Array[Scenario] = get_scenarios_from_random_battle(dungeon_battle)
		new_scenarios.append_array(random_battle_scenarios)

	return new_scenarios
