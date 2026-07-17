class_name AttackOutData

# https://ffhacktics.com/wiki/ATTACK.OUT
var scenario_data_start: int = 0x10938
var scenario_data_num_entries: int = 0x1ea
var scenario_data_entry_length: int = 24
var scenario_data: Array[FftScenarioData] = []

var deployment_data_start: int = 0xbbd4
var deployment_data_num_entries: int = 0x2ff + 1
var deployment_data_entry_length: int = 12
var deployment_data: Array[DeploymentZoneData] = []

class FftScenarioData:
	var scenario_id: int = 0
	var map_id: int = 0
	var weather: int = 0
	var is_nighttime: bool = false
	var music_file_one_id: int = 0
	var music_file_two_id: int = 0
	var entd_idx: int = 0
	var first_squad_deployment_idx: int = 0
	var second_squad_deployment_idx: int = 0
	var flags: int = 0 # 0x01 = ramza is mandatory during deployment
	var next_scenario_id: int = 0
	var post_scenario_step: int = 0 # 0x80 = go to world map, 0x81 = go to next scenario, 0x82 = reset game
	var event_script_id: int = 0
	
	func _init(bytes: PackedByteArray) -> void:
		scenario_id = bytes.decode_u16(0)
		map_id = bytes.decode_u8(2)
		weather = bytes.decode_u8(3)
		is_nighttime = bytes.decode_u8(4) == 1
		music_file_one_id = bytes.decode_u8(5)
		music_file_two_id = bytes.decode_u8(6)
		entd_idx = bytes.decode_u16(7)
		first_squad_deployment_idx = bytes.decode_u16(9)
		second_squad_deployment_idx = bytes.decode_u16(11)
		flags = bytes.decode_u8(17) # 0x01 = ramza is mandatory during deployment
		next_scenario_id = bytes.decode_u16(18)
		post_scenario_step = bytes.decode_u8(20) # 0x80 = go to world map, 0x81 = go to next scenario, 0x82 = reset game
		event_script_id = bytes.decode_u16(22)

class DeploymentZoneData:
	var deployment_zone_bitmap: int = 0 # 0x01ffffff is full 5x5 grid
	var deployment_zone_center_x: int = 0
	var deployment_zone_center_y: int = 0
	var unit_facing: int = 0 # relative to deployment zone: 0 = West, 1 = South, 2 = East, 3 = North
	var zone_facing: int = 0 # 0 = West, 1 = South, 2 = East, 3 = North
	var max_squad_size: int = 1
	var map_id: int = 0
	var deployment_id: int = 0
	var deployment_map: Array[Vector2i] = [] # stores map coordinates of deployment tiles
	
	func _init(bytes: PackedByteArray) -> void:
		deployment_zone_bitmap = bytes.decode_u32(0) # 0x01ffffff is full 5x5 grid
		deployment_zone_center_x = bytes.decode_u8(4)
		deployment_zone_center_y = bytes.decode_u8(5)
		unit_facing = (bytes.decode_u8(7) & 0xf0) >> 4 # 0 = West, 1 = South, 2 = East, 3 = North
		zone_facing = bytes.decode_u8(7) & 0x0f # 0 = West, 1 = South, 2 = East, 3 = North
		max_squad_size = bytes.decode_u8(8)
		map_id = bytes.decode_u8(9)
		deployment_id = bytes.decode_u16(10)

		for idx: int in 25:
			var is_present: bool = deployment_zone_bitmap & (idx**2) != 0
			if is_present:
				# get coordinates where 0,0 is center of 5x5 zone
				var base_x: int = (idx % 5) - 2
				var base_y: int = floori(idx / 5.0) - 2
				var rotated_coords: Vector2i = Vector2i(Vector2(base_x, base_y).rotated(zone_facing * PI / 2).round())
				var map_coordinates: Vector2i = rotated_coords + Vector2i(deployment_zone_center_x, deployment_zone_center_y) # convert coords to map coordinates
				
				deployment_map.append(map_coordinates)


func init_from_attack_out() -> void:
	var attack_out_bytes: PackedByteArray = RomReader.get_file_data("ATTACK.OUT")
	
	var scenario_bytes_length: int = scenario_data_num_entries * scenario_data_entry_length
	var scenario_bytes: PackedByteArray = attack_out_bytes.slice(scenario_data_start, scenario_data_start + scenario_bytes_length)
	for idx: int in scenario_data_num_entries:
		var scenario_bytes_start: int = idx * scenario_data_entry_length
		var scenario_entry_bytes: PackedByteArray = scenario_bytes.slice(scenario_bytes_start, scenario_bytes_start + scenario_data_entry_length)

		scenario_data.append(FftScenarioData.new(scenario_entry_bytes))
	
	var deployment_bytes_length: int = deployment_data_num_entries * deployment_data_entry_length
	var deployment_table_bytes: PackedByteArray = attack_out_bytes.slice(deployment_data_start, deployment_data_start + deployment_bytes_length)
	for idx: int in deployment_data_num_entries:
		var deployment_bytes_start: int = idx * deployment_data_entry_length
		var deployment_entry_bytes: PackedByteArray = deployment_table_bytes.slice(deployment_bytes_start, deployment_bytes_start + deployment_data_entry_length)

		deployment_data.append(DeploymentZoneData.new(deployment_entry_bytes))


func get_unique_scenarios() -> Array[Scenario]:
	var all_unique_scenarios: Array[Scenario] = []
	var checked_scenarios: Array[FftScenarioData] = []
	for fft_scenario: FftScenarioData in scenario_data:
		var is_new_scenario: bool = not checked_scenarios.any(
				func(existing_scenario: FftScenarioData) -> bool: 
					return (
						existing_scenario.entd_idx == fft_scenario.entd_idx 
						and existing_scenario.map_id == fft_scenario.map_id
						and existing_scenario.first_squad_deployment_idx == fft_scenario.first_squad_deployment_idx
						and existing_scenario.second_squad_deployment_idx == fft_scenario.second_squad_deployment_idx
					)
		)
		if not is_new_scenario:
			continue
		
		checked_scenarios.append(fft_scenario)

		var new_scenario: Scenario = Scenario.new()

		var map_unique_name_num: String = "map_%03d" % fft_scenario.map_id
		var map_name_idx: int = RomReader.maps.keys().find_custom(func(map_name: String) -> bool: return map_name.begins_with(map_unique_name_num))
		var map_unique_name: String = RomReader.maps.keys()[map_name_idx]

		var new_map_chunk: Scenario.MapChunk = Scenario.MapChunk.new()
		# new_map_chunk.set_mirror_xyz([true, true, false])
		new_map_chunk.unique_name = map_unique_name
		new_scenario.map_chunks.append(new_map_chunk)
		new_scenario.background_gradient_bottom = RomReader.maps[map_unique_name].background_gradient_bottom
		new_scenario.background_gradient_top = RomReader.maps[map_unique_name].background_gradient_top

		var scenario_entd: FftEntd = RomReader.fft_entds[fft_scenario.entd_idx]
		new_scenario.units_data = scenario_entd.get_units_data()

		new_scenario.unique_name = map_unique_name
		all_unique_scenarios.append(new_scenario)

	return all_unique_scenarios
