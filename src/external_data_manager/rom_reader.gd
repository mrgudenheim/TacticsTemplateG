#class_name RomReader
extends Node

signal rom_loaded
signal message(message: String)

const DIRECTORY_DATA_SECTORS_ROOT: PackedInt32Array = [22]
const OFFSET_RECORD_DATA_START: int = 0x60

# https://en.wikipedia.org/wiki/CD-ROM#CD-ROM_XA_extension
const BYTES_PER_SECTOR: int = 2352
const BYTES_PER_SECTOR_HEADER: int = 24
const BYTES_PER_SECTOR_FOOTER: int = 280
const DATA_BYTES_PER_SECTOR: int = 2048

const NUM_ABILITIES: int = 512
const NUM_ACTIVE_ABILITIES: int = 0x1C6
const NUM_SPRITESHEETS: int = 0x9f
const NUM_SKILLSETS: int = 0xe0
const NUM_UNIT_SKILLSETS: int = 0xb0
const NUM_MONSTER_SKILLSETS: int = 0xe0 - 0xb0
const NUM_JOBS: int = 0xa0
const NUM_VFX: int = 511
const NUM_ITEMS: int = 254 # 256?
const NUM_WEAPONS: int = 122

var is_ready: bool = false

var rom: PackedByteArray = []
var file_records: Dictionary[String, FileRecord] = {} # {file_name, FileRecord}
var lba_to_file_name: Dictionary[int, String] = {} # {int, String}

var sprs: Array[Spr] = []
var spr_file_name_to_id: Dictionary[String, int] = {}
var spr_id_file_idxs: PackedInt32Array = [] # 0x60 starts generic jobs
var spritesheets: Dictionary[String, Spr] = {} # [unique_name (eg. filename without extension), Spr] TODO fill with data

var shps_array: Array[Shp] = []
var shps: Dictionary[String, Shp] = {} # [unique_name (eg. filename without extension), Shp] TODO fill with data
var seqs_array: Array[Seq] = []
var seqs: Dictionary[String, Seq] = {} # [unique_name (eg. filename without extension), Seq] TODO fill with data
var maps_array: Array[FftMapData] = []
var maps: Dictionary[String, FftMapData] = {}
var vfx: Array[VisualEffectData] = []
var fft_abilities: Array[FftAbilityData] = []
var fft_entds: Array[FftEntd] = []
var items_array: Array[ItemData] = []
# var status_effects: Array[StatusEffect] = [] # TODO reference scus_data.status_effects
var items: Dictionary[String, ItemData] = {} # [unique_name, ItemData]
var status_effects: Dictionary[String, StatusEffect] = {} # [unique_name, StatusEffect]
var jobs_data: Dictionary[String, JobData] = {} # [unique_name, JobData]
var actions: Dictionary[String, Action] = {} # [unique_name, Action]
var triggered_actions: Dictionary[String, TriggeredAction] = {} # [unique_name, TriggeredAction]
var passive_effects: Dictionary[String, PassiveEffect] = {} # [unique_name, PassiveEffect]
var abilities: Dictionary[String, Ability] = {} # [unique_name, Ability]
var scenarios: Dictionary[String, Scenario] = {} # [unique_name, Scenario]

var rom_load_times: Array[Dictionary] = [] # [{name: String, time_ms: int}]

var battle_bin_data: BattleBinData = BattleBinData.new() # BATTLE.BIN tables
var scus_data: ScusData = ScusData.new() # SCUS.942.41 tables
var wldcore_data: WldcoreData = WldcoreData.new() # WLDCORE.BIN tables
var attack_out_data: AttackOutData = AttackOutData.new() # ATTACK.OUT tables
var trap_effect_data: TrapEffectData = TrapEffectData.new() # TRAP particle effects from BATTLE.BIN

# Images
# https://github.com/Glain/FFTPatcher/blob/master/ShishiSpriteEditor/PSXImages.xml#L148
var frame_bin: Bmp = Bmp.new()
var frame_bin_texture: Texture2D
var item_bin_texture: Texture2D

# Text
var fft_text: FftText = FftText.new()


func _profile_section(section_name: String, start_ms: int) -> int:
	var elapsed: int = Time.get_ticks_msec() - start_ms
	rom_load_times.append({"name": section_name, "time_ms": elapsed})
	return Time.get_ticks_msec()


func on_load_rom_dialog_file_selected(path: String) -> void:
	var start_time: int = Time.get_ticks_msec()
	rom = FileAccess.get_file_as_bytes(path)
	push_warning("Time to load file (ms): " + str(Time.get_ticks_msec() - start_time))
	
	process_rom()


func clear_data() -> void:
	file_records.clear()
	lba_to_file_name.clear()
	sprs.clear()
	spr_file_name_to_id.clear()
	shps_array.clear()
	seqs_array.clear()
	maps_array.clear()
	maps.clear()
	vfx.clear()
	fft_abilities.clear()
	fft_entds.clear()
	items_array.clear()
	items.clear()
	status_effects.clear()
	jobs_data.clear()
	actions.clear()
	triggered_actions.clear()
	passive_effects.clear()
	abilities.clear()
	scenarios.clear()


func process_rom() -> void:
	clear_data()
	rom_load_times.clear()
	var section_start: int = Time.get_ticks_msec()
	var total_start: int = section_start

	RomReader.spr_id_file_idxs.resize(NUM_SPRITESHEETS)

	# http://wiki.osdev.org/ISO_9660#Directories
	process_file_records(DIRECTORY_DATA_SECTORS_ROOT)
	section_start = _profile_section("process_file_records", section_start)

	process_frame_bin()
	section_start = _profile_section("process_frame_bin", section_start)

	fft_text.init_text()
	section_start = _profile_section("fft_text.init_text", section_start)

	scus_data.init_from_scus()
	section_start = _profile_section("scus_data.init_from_scus", section_start)

	battle_bin_data.init_from_battle_bin()
	section_start = _profile_section("battle_bin_data.init_from_battle_bin", section_start)

	var scenario_dir: DirAccess = DirAccess.open("user://overrides/" + Scenario.SAVE_FOLDER)
	var fft_scenarios_pre_extracted: bool = scenario_dir != null and Array(scenario_dir.get_files()).any(func(scenario_file_name: String) -> bool: return scenario_file_name.ends_with(".scenario.json"))
	fft_scenarios_pre_extracted = false

	if not fft_scenarios_pre_extracted:
		wldcore_data.init_from_wldcore()
		section_start = _profile_section("wldcore_data.init_from_wldcore", section_start)

		attack_out_data.init_from_attack_out()
		section_start = _profile_section("attack_out_data.init_from_attack_out", section_start)
	else:
		section_start = _profile_section("SKIPPED wldcore+attack_out (pre-extracted)", section_start)

	cache_associated_files()
	section_start = _profile_section("cache_associated_files", section_start)

	trap_effect_data.init_from_rom()
	section_start = _profile_section("trap_effect_data.init_from_rom", section_start)

	for map_idx: int in maps_array.size():
		var map_data: FftMapData = maps_array[map_idx]
		map_data.unique_name = map_data.file_name.trim_suffix(".GNS")
		if map_idx != 0 and map_idx <= RomReader.fft_text.map_names.size():
			map_data.display_name = RomReader.fft_text.map_names[map_idx - 1]
			map_data.unique_name += " " + map_data.display_name
		map_data.unique_name = map_data.unique_name.to_snake_case().remove_char('"'.unicode_at(0))
		maps[map_data.unique_name] = map_data
	section_start = _profile_section("map_naming", section_start)

	for ability_id: int in NUM_ABILITIES:
		var new_fft_ability: FftAbilityData = FftAbilityData.new(ability_id)
		fft_abilities.append(new_fft_ability)
		var new_ability: Ability = new_fft_ability.create_ability()
		new_ability.add_to_global_list()

	for fft_ability: FftAbilityData in fft_abilities:
		if fft_ability.ability_type == FftAbilityData.AbilityType.NORMAL:
			fft_ability.set_action()
	section_start = _profile_section("abilities (512 + set_action)", section_start)

	# must be after fft_abilities to set secondary actions
	items_array.resize(NUM_ITEMS)
	for id: int in NUM_ITEMS:
		items_array[id] = ItemData.new(id)
	section_start = _profile_section("items (254)", section_start)

	scus_data.init_statuses()
	section_start = _profile_section("scus_data.init_statuses", section_start)

	for job_data: JobData in jobs_data.values():
		job_data.sprite_name = sprs[spr_id_file_idxs[job_data.sprite_id]].file_name.to_lower().trim_suffix(".spr")
		job_data.skillset_unique_name = scus_data.skillsets_data[job_data.skillset_id].unique_name

		for innate_ability_id: int in job_data.innate_abilities_ids:
			# var ability_uname: String = fft_abilities[innate_ability_id].display_name.to_snake_case()
			var ability_uname: String = abilities.keys()[innate_ability_id]
			if not job_data.innate_ability_names.has(ability_uname):
				job_data.innate_ability_names.append(ability_uname)

	if not fft_scenarios_pre_extracted:
		add_entds("ENTD1.ENT")
		add_entds("ENTD2.ENT")
		add_entds("ENTD3.ENT")
		add_entds("ENTD4.ENT")
		section_start = _profile_section("add_entds (4 files)", section_start)

		var wldcore_scenarios: Array[Scenario] = wldcore_data.get_all_scenarios()
		for new_scenario: Scenario in wldcore_scenarios:
			var number: int = 1
			var new_unique_name: String = new_scenario.unique_name + ("_%02d" % number)
			while scenarios.keys().has(new_unique_name):
				number += 1
				new_unique_name = new_scenario.unique_name + ("_%02d" % number)
			new_scenario.unique_name = new_unique_name

			RomReader.scenarios[new_scenario.unique_name] = new_scenario

		var attack_out_scenarios: Array[Scenario] = attack_out_data.get_unique_scenarios()
		for new_scenario: Scenario in attack_out_scenarios:
			var number: int = 1
			var new_unique_name: String = new_scenario.unique_name + ("_%02d" % number)
			while scenarios.keys().has(new_unique_name):
				number += 1
				new_unique_name = new_scenario.unique_name + ("_%02d" % number)
			new_scenario.unique_name = new_unique_name

			RomReader.scenarios[new_scenario.unique_name] = new_scenario
		section_start = _profile_section("scenario_extraction", section_start)
	else:
		section_start = _profile_section("SKIPPED entds+scenarios (pre-extracted)", section_start)

	# for status_: int in status_effects.size():
		# status_effects[idx].ai_score_formula.values[0] = battle_bin_data.ai_status_priorities[idx] / 128.0
		# TODO implement ai formulas that are modified by other statuses (ex. stop is worth zero if target is already confused/charm/blood suck) or action properties (ex. evadeable, silenceable)
	
	
	# testing vfx vram data
	#for ability_id: int in NUM_ACTIVE_ABILITIES:
		#if not fft_abilities[ability_id].vfx_data.is_initialized:
			#fft_abilities[ability_id].vfx_data.init_from_file()
		#var ability: FftAbilityData = fft_abilities[ability_id]
		#for frameset_idx: int in ability.vfx_data.frame_sets.size():
			#for frame_idx: int in ability.vfx_data.frame_sets[frameset_idx].frame_set.size():
				#var frame_data: VfxFrame = ability.vfx_data.frame_sets[frameset_idx].frame_set[frame_idx]
				#if ((frame_data.vram_bytes[1] & 0x02) >> 1) == 0:
					#push_warning([ability_id, ability.name, ability.vfx_data.vfx_id, frameset_idx, frame_idx])
	
	# for seq: Seq in seqs_array:
	# 	seq.set_data_from_seq_bytes(get_file_data(seq.file_name))
	# 	seq.write_wiki_table()
	
	# write_all_spritesheet_region_data()

	# var json_file = FileAccess.open("user://overrides/action2_to_json.json", FileAccess.WRITE)
	# json_file.store_line(fft_abilities[2].ability_action.to_json())
	# json_file.close()
	
	# import_custom_data()
	section_start = _profile_section("import_custom_data (~200 JSON files)", section_start)

	connect_data_references()
	section_start = _profile_section("connect_data_references", section_start)

	var total_ms: int = Time.get_ticks_msec() - total_start
	print("=== ROM Load Profile ===")
	for entry: Dictionary in rom_load_times:
		var pct: float = (entry.time_ms / float(total_ms)) * 100.0
		print("  %6d ms (%5.1f%%) — %s" % [entry.time_ms, pct, entry.name])
	print("  %6d ms (TOTAL)" % total_ms)

	# var new_scenario: Scenario = Scenario.new()
	# new_scenario.unique_name = "test1"

	# var new_zone: PackedVector2Array = []
	# new_zone.append(Vector2(0, 0))
	# new_zone.append(Vector2(1, 1))
	# new_scenario.deployment_zones.append(new_zone)

	# var new_map_chunk: Scenario.MapChunk = Scenario.MapChunk.new()
	# new_map_chunk.unique_name = maps_array[116].unique_name
	# new_map_chunk.mirror_xyz = [false, true, false]
	# new_map_chunk.corner_position = Vector3i.ZERO
	# new_scenario.map_chunks.append(new_map_chunk)
	# Utilities.save_json(new_scenario)

	# var output_array: PackedStringArray = []
	# for key: String in vfx_scripts.keys():
	# 	output_array.append(key + ": " + ", ".join(vfx_scripts[key]))

	# var final_output: String = "\n".join(output_array)
	
	# DirAccess.make_dir_recursive_absolute("user://wiki_tables")
	# var file_name: String = "vfx_animation_params"
	# var save_file: FileAccess = FileAccess.open("user://wiki_tables/" + file_name + ".txt", FileAccess.WRITE)
	# save_file.store_string(final_output)

	# generate_passive_effects()

	is_ready = true
	# rom_loaded.emit()


func process_file_records(sectors: PackedInt32Array, folder_name: String = "") -> void:
	for sector: int in sectors:
		
		var offset_start: int = 0
		if sector == sectors[0]:
			offset_start = OFFSET_RECORD_DATA_START
		var directory_start: int = sector * BYTES_PER_SECTOR
		var directory_data: PackedByteArray = rom.slice(directory_start + BYTES_PER_SECTOR_HEADER, directory_start + DATA_BYTES_PER_SECTOR + BYTES_PER_SECTOR_HEADER)
		
		var byte_index: int = offset_start
		while byte_index < DATA_BYTES_PER_SECTOR:
			var record_length: int = directory_data.decode_u8(byte_index)
			var record_data: PackedByteArray = directory_data.slice(byte_index, byte_index + record_length)
			var record: FileRecord = FileRecord.new(record_data)
			record.record_location_sector = sector
			record.record_location_offset = byte_index
			file_records[record.name] = record
			lba_to_file_name[record.sector_location] = record.name
			
			var file_extension: String = record.name.get_extension()
			if record.flags & 0b10 == 0b10: # folder
				#push_warning("Getting files from folder: " + record.name)
				var data_length_sectors: int = ceil(float(record.size) / DATA_BYTES_PER_SECTOR)
				var directory_sectors: PackedInt32Array = range(record.sector_location, record.sector_location + data_length_sectors)
				process_file_records(directory_sectors, record.name)
			elif folder_name == "EFFECT":
				record.type_index = vfx.size()
				vfx.append(VisualEffectData.new(record.name))
			elif file_extension == "SPR":
				record.type_index = sprs.size()
				var new_spr: Spr = Spr.new(record.name)
				sprs.append(new_spr)
				spritesheets[new_spr.file_name] = new_spr
			elif file_extension == "SHP":
				record.type_index = shps_array.size()
				var new_shp: Shp = Shp.new(record.name)
				shps_array.append(new_shp)
				shps[new_shp.file_name] = new_shp
			elif file_extension == "SEQ":
				record.type_index = seqs_array.size()
				var new_seq: Seq = Seq.new(record.name)
				seqs_array.append(new_seq)
				seqs[new_seq.file_name] = new_seq
			elif file_extension == "GNS":
				record.type_index = maps_array.size()
				maps_array.append(FftMapData.new(record.name))
			
			byte_index += record_length
			if byte_index < DATA_BYTES_PER_SECTOR:
				if directory_data.decode_u8(byte_index) == 0: # end of data, rest of sector will be padded with zeros
					break


func cache_associated_files() -> void:
	var associated_file_names: PackedStringArray = [
		"WEP1.SEQ",
		"WEP2.SEQ",
		"EFF1.SEQ",
		"WEP1.SHP",
		"WEP2.SHP",
		"EFF1.SHP",
		"WEP.SPR",
	]

	for file_name: String in associated_file_names:
		var type_index: int = file_records[file_name].type_index
		match file_name.get_extension():
			"SPR":
				var spr: Spr = sprs[type_index]
				spr.set_data(get_file_data(file_name))
				if file_name != "WEP.SPR":
					spr.set_spritesheet_data(spr_file_name_to_id[file_name])
			"SHP":
				var shp: Shp = shps_array[type_index]
				shp.set_data_from_shp_bytes(get_file_data(file_name))
			"SEQ":
				var seq: Seq = seqs_array[type_index]
				seq.set_data_from_seq_bytes(get_file_data(file_name))
	
	# getting effect / weapon trail / glint
	var eff_spr_name: String = "EFF.SPR"
	var eff_spr: Spr = Spr.new(eff_spr_name)
	eff_spr.height = 144
	var eff_spr_record: FileRecord = FileRecord.new()
	eff_spr_record.name = eff_spr_name
	eff_spr_record.type_index = sprs.size()
	file_records[eff_spr_name] = eff_spr_record
	eff_spr.set_data(get_file_data("WEP.SPR").slice(0x8200, 0x10400))
	eff_spr.shp_name = "EFF1.SHP"
	eff_spr.seq_name = "EFF1.SEQ"
	sprs.append(eff_spr)
	spritesheets["EFF"] = eff_spr
	
	# TRAP effects parsed in process_rom() via trap_effect_data.init_from_rom()
	
	# crop wep spr
	var wep_spr_start: int = 0
	var wep_spr_end: int = 256 * 256 # wep is 256 pixels tall
	var wep_spr_index: int = file_records["WEP.SPR"].type_index
	var wep_spr: Spr = sprs[wep_spr_index].get_sub_spr("WEP.SPR", wep_spr_start, wep_spr_end)
	wep_spr.shp_name = "WEP1.SHP"
	wep_spr.seq_name = "WEP1.SEQ"
	wep_spr.is_initialized = true
	sprs[wep_spr_index] = wep_spr
	spritesheets["WEP.SPR"] = wep_spr
	
	# get item graphics
	var item_record: FileRecord = FileRecord.new()
	item_record.sector_location = 6297 # ITEM.BIN is in EVENT not BATTLE, so needs a new record created
	item_record.size = 33280
	item_record.name = "ITEM.BIN"
	item_record.type_index = sprs.size()
	file_records[item_record.name] = item_record
	
	var item_spr_data: PackedByteArray = RomReader.get_file_data(item_record.name)
	var item_spr: Spr = Spr.new(item_record.name)
	item_spr.height = 256
	item_spr.set_palette_data(item_spr_data.slice(0x8000, 0x8200))
	item_spr.color_indices = item_spr.set_color_indices(item_spr_data.slice(0, 0x8000))
	item_spr.set_pixel_colors()
	item_spr.spritesheet = item_spr.get_rgba8_image()
	item_spr.is_initialized = true
	sprs.append(item_spr)
	spritesheets["ITEM.BIN"] = item_spr

	item_bin_texture = ImageTexture.create_from_image(item_spr.spritesheet)


func get_file_data(file_name: String) -> PackedByteArray:
	var file_data: PackedByteArray = []
	var sector_location: int = file_records[file_name].sector_location
	var file_size: int = file_records[file_name].size
	var file_data_start: int = (sector_location * BYTES_PER_SECTOR) + BYTES_PER_SECTOR_HEADER
	var num_sectors_full: int = floor(file_size / float(DATA_BYTES_PER_SECTOR))
	
	for sector_index: int in num_sectors_full:
		var sector_data_start: int = file_data_start + (sector_index * BYTES_PER_SECTOR)
		var sector_data_end: int = sector_data_start + DATA_BYTES_PER_SECTOR
		var sector_data: PackedByteArray = rom.slice(sector_data_start, sector_data_end)
		file_data.append_array(sector_data)
	
	# add data from last sector
	var last_sector_data_start: int = file_data_start + (num_sectors_full * BYTES_PER_SECTOR)
	var last_sector_data_end: int = last_sector_data_start + (file_size % DATA_BYTES_PER_SECTOR)
	var last_sector_data: PackedByteArray = rom.slice(last_sector_data_start, last_sector_data_end)
	file_data.append_array(last_sector_data)
	
	return file_data


func get_spr_file_idx(sprite_id: int) -> int:
	return sprs.find_custom(func(spr: Spr) -> bool: return spr.sprite_id == sprite_id)


func init_abilities() -> void:
	for ability_id: int in NUM_ABILITIES:
		fft_abilities[ability_id] = FftAbilityData.new(ability_id)


func process_frame_bin() -> void:
	var file_name: String = "FRAME.BIN"
	frame_bin.file_name = file_name
	var frame_bin_bytes: PackedByteArray = get_file_data(file_name)
	
	frame_bin.num_colors = 22 * 16
	frame_bin.bits_per_pixel = 4
	frame_bin.palette_data_start = frame_bin_bytes.size() - (frame_bin.num_colors * 2) # 2 bytes per color - 1 bit for alpha, followed by 5 bits per channel (B,G,R)
	frame_bin.pixel_data_start = 0
	frame_bin.width = 256 # pixels
	frame_bin.height = 288
	frame_bin.num_pixels = frame_bin.width * frame_bin.height
	
	var palette_bytes: PackedByteArray = frame_bin_bytes.slice(frame_bin.palette_data_start)
	var pixel_bytes: PackedByteArray = frame_bin_bytes.slice(frame_bin.pixel_data_start, frame_bin.palette_data_start)
	
	# set palette data
	frame_bin.color_palette.resize(frame_bin.num_colors)
	for i: int in frame_bin.num_colors:
		var color: Color = Color.BLACK
		var color_bits: int = palette_bytes.decode_u16(i * 2)
		# var alpha_bit: int = (color_bits & 0b1000_0000_0000_0000) >> 15 # first bit is alpha
		#color.a8 = 1 - () # first bit is alpha (if bit is zero, color is opaque)
		color.b8 = (color_bits & 0b0111_1100_0000_0000) >> 10 # then 5 bits each: blue, green, red
		color.g8 = (color_bits & 0b0000_0011_1110_0000) >> 5
		color.r8 = color_bits & 0b0000_0000_0001_1111
		
		# convert 5 bit channels to 8 bit
		#color.a8 = 255 * color.a8 # first bit is alpha (if bit is zero, color is opaque)
		color.a8 = 255 # TODO use alpha correctly
		color.b8 = roundi(255 * (color.b8 / 31.0)) # then 5 bits each: blue, green, red
		color.g8 = roundi(255 * (color.g8 / 31.0))
		color.r8 = roundi(255 * (color.r8 / 31.0))
		
		# psx transparency: https://www.psxdev.net/forum/viewtopic.php?t=953
		# TODO use Material3D blend mode Add for mode 1 or 3, where brightness builds up from a dark background instead of normal "mix" transparency
		if color == Color.BLACK:
			color.a8 = 0
		
		# if first color in 16 color palette is black, treat it as transparent
		if (i % 16 == 0
			and color == Color.BLACK):
				color.a8 = 0
		frame_bin.color_palette[i] = color
	
	# set color indicies
	var new_color_indicies: Array[int] = []
	@warning_ignore("integer_division")
	new_color_indicies.resize(pixel_bytes.size() * (8 / frame_bin.bits_per_pixel))
	
	for i: int in new_color_indicies.size():
		@warning_ignore("integer_division")
		var pixel_offset: int = (i * frame_bin.bits_per_pixel) / 8
		var byte: int = pixel_bytes.decode_u8(pixel_offset)
		
		if frame_bin.bits_per_pixel == 4:
			if i % 2 == 1: # get 4 leftmost bits
				new_color_indicies[i] = byte >> 4
			else:
				new_color_indicies[i] = byte & 0b0000_1111 # get 4 rightmost bits
		elif frame_bin.bits_per_pixel == 8:
			new_color_indicies[i] = byte
	
	frame_bin.color_indices = new_color_indicies
	
	# set_pixel_colors()
	var palette_id: int = 5
	var new_pixel_colors: PackedColorArray = []
	var new_size: int = frame_bin.color_indices.size()
	var err: int = new_pixel_colors.resize(new_size)
	if err != OK:
		push_error(err)
	#pixel_colors.resize(color_indices.size())
	new_pixel_colors.fill(Color.BLACK)
	for i: int in frame_bin.color_indices.size():
		new_pixel_colors[i] = frame_bin.color_palette[frame_bin.color_indices[i] + (16 * palette_id)]
	
	frame_bin.pixel_colors = new_pixel_colors
	
	# get_rgba8_image() -> Image:
	@warning_ignore("integer_division")
	frame_bin.height = frame_bin.color_indices.size() / frame_bin.width
	var image: Image = Image.create_empty(frame_bin.width, frame_bin.height, false, Image.FORMAT_RGBA8)
	for x: int in frame_bin.width:
		for y: int in frame_bin.height:
			var color: Color = frame_bin.pixel_colors[x + (y * frame_bin.width)]
			var color8: Color = Color8(color.r8, color.g8, color.b8, color.a8) # use Color8 function to prevent issues with format conversion changing color by 1/255
			image.set_pixel(x, y, color8) # spr stores pixel data left to right, top to bottm

	frame_bin_texture = ImageTexture.create_from_image(image)


func connect_data_references() -> void:
	# actions have no direct references, stores StatusEffect names in several places
	# for action: Action in actions:
		
	for triggered_action: TriggeredAction in triggered_actions.values():
		if actions.has(triggered_action.action_unique_name):
			triggered_action.action = actions[triggered_action.action_unique_name]

	for status_effect: StatusEffect in status_effects.values():
		if passive_effects.has(status_effect.passive_effect_name):
			status_effect.passive_effect = passive_effects[status_effect.passive_effect_name]
	
	for job_data: JobData in jobs_data.values():
		for passive_effect_name_idx: int in job_data.passive_effect_names.size():
			var passive_effect_name: String = job_data.passive_effect_names[passive_effect_name_idx]
			if passive_effect_name == "" and passive_effects.has(job_data.unique_name):
				passive_effect_name = job_data.unique_name
				job_data.passive_effect_names[passive_effect_name_idx] = passive_effect_name
				job_data.passive_effects.append(passive_effects[passive_effect_name])
			elif passive_effects.has(passive_effect_name):
				job_data.passive_effects.append(passive_effects[passive_effect_name])
			
		
		for innate_ability_id: int in job_data.innate_abilities_ids:
			# var ability_uname: String = fft_abilities[innate_ability_id].display_name.to_snake_case()
			var ability_uname: String = abilities.values()[innate_ability_id].unique_name
			if not job_data.innate_ability_names.has(ability_uname):
				job_data.innate_ability_names.append(ability_uname)

		for ability_name: String in job_data.innate_ability_names:
			if abilities.has(ability_name):
				job_data.innate_abilities.append(abilities[ability_name])

	for ability: Ability in abilities.values():
		if ability.passive_effect_name == "" and passive_effects.has(ability.unique_name):
			ability.passive_effect_name = ability.unique_name
			ability.passive_effect = passive_effects[ability.passive_effect_name]
		elif passive_effects.has(ability.passive_effect_name):
			ability.passive_effect = passive_effects[ability.passive_effect_name]

		for triggered_action_name: String in ability.triggered_actions_names:
			if triggered_actions.has(triggered_action_name):
				ability.triggered_actions.append(triggered_actions[triggered_action_name])
		
		if ability.triggered_actions_names.is_empty():
			if triggered_actions.has(ability.unique_name):
				ability.triggered_actions_names = [ability.unique_name]
				ability.triggered_actions.append(triggered_actions[ability.unique_name])

	for passive_effect: PassiveEffect in passive_effects.values():
		for action_name: String in passive_effect.added_actions_names:
			if actions.has(action_name):
				passive_effect.added_actions.append(actions[action_name])
		for triggered_action_name: String in passive_effect.added_triggered_actions_names:
			if triggered_actions.has(triggered_action_name):
				passive_effect.added_triggered_actions.append(triggered_actions[triggered_action_name])

	for item: ItemData in items.values():
		if passive_effects.has(item.passive_effect_name):
			item.passive_effect = passive_effects[item.passive_effect_name]
		if actions.has(item.weapon_attack_action_name):
			item.weapon_attack_action = actions[item.weapon_attack_action_name]


func write_all_spritesheet_region_data() -> void:
	# SEQs: 0 - arute, 1 - cyoko, 4 - kanzen, 5 - mon, 8 - type1, 10 - type3
	# SHPs: 0 - arute, 1 - cyoko, 4 - kanzen, 5 - mon, 7 - type1, 8 - type2
	var seq_indicies: PackedInt32Array = [
		0,
		1,
		4,
		5,
		8,
		10,
	]
	var shp_indicies: PackedInt32Array = [
		0,
		1,
		4,
		5,
		7,
		8,
	]

	for idx: int in seq_indicies.size():
		write_spritesheet_region_data(seq_indicies[idx], shp_indicies[idx])


func write_spritesheet_region_data(seq_index: int, shp_index: int) -> void:
	var regions: Array[SpritesheetRegionData] = []
	
	var seq: Seq = seqs_array[seq_index] # 0 - arute, 1 - cyoko, 4 - kanzen, 5 - mon, 8 - type1, 10 - type3
	var shp: Shp = shps_array[shp_index] # 0 - arute, 1 - cyoko, 4 - kanzen, 5 - mon, 7 - type1, 8 - type2

	if not seq.is_initialized:
		seq.set_data_from_seq_bytes(RomReader.get_file_data(seq.file_name))

	if not shp.is_initialized:
		shp.set_data_from_shp_bytes(RomReader.get_file_data(shp.file_name))
	
	for seq_ptr_index: int in seq.sequence_pointers.size():
		var seq_idx: int = seq.sequence_pointers[seq_ptr_index]
		var animation: Sequence = seq.sequences[seq_idx]
		var seq_description: String = animation.seq_name
		if seq_description == "":
			seq_description = "?"
		
		for part: SeqPart in animation.seq_parts:
			if part.opcode == "LoadFrameAndWait":
				var shp_frame_id: int = part.parameters[0]
				var frame: FrameData = shp.frames[shp_frame_id]
				
				for subframe_idx: int in frame.subframes.size():
					var subframe: SubFrameData = frame.subframes[subframe_idx]
					var subframe_region_size: Vector2i = subframe.rect_size
					var subframe_region_location: Vector2i = Vector2i(subframe.load_location_x, subframe.load_location_y)

					var region_id: int = regions.find_custom(
						func(region_data: SpritesheetRegionData) -> bool:
							return region_data.region_size == subframe_region_size and region_data.region_location == subframe_region_location
					)

					var modified_description: String = seq_description.replace("\n", ", ").replace("-, ", "-<br>").replace(", -", "<br>-")
					if modified_description.contains("-"):
						modified_description = "<br>" + modified_description

					if region_id != -1: # add data to existing region
						var existing_region: SpritesheetRegionData = regions[region_id]
						var new_shp_frame_id_label: String = str(shp_frame_id)

						if not existing_region.shp_frame_ids.has(shp_frame_id):
							existing_region.shp_frame_ids.append(shp_frame_id)

						if not existing_region.shp_frame_id_labels.has(new_shp_frame_id_label):
							existing_region.shp_frame_id_labels.append(new_shp_frame_id_label)
						
						if not existing_region.animation_ids.has(seq_ptr_index):
							existing_region.animation_ids.append(seq_ptr_index)
							existing_region.animation_descriptions.append(modified_description)
					else: # add new region if an existing region does not have the same location and size
						var new_region: SpritesheetRegionData = SpritesheetRegionData.new()
						new_region.shp_type = shp.file_name
						new_region.region_id = regions.size()
						new_region.region_size = subframe_region_size
						new_region.region_location = subframe_region_location
						new_region.shp_frame_ids.append(shp_frame_id)
						new_region.animation_ids.append(seq_ptr_index)

						var new_shp_frame_id_label: String = str(shp_frame_id)
						new_region.shp_frame_id_labels.append(new_shp_frame_id_label)

						modified_description = modified_description.trim_prefix("<br>")
						new_region.animation_descriptions.append(modified_description)
						regions.append(new_region)
				
				if shp.has_submerged_data:
					var frame_submerged: FrameData = shp.frames_submerged[shp_frame_id]
					
					for subframe_idx: int in frame_submerged.subframes.size():
						var subframe: SubFrameData = frame_submerged.subframes[subframe_idx]
						var subframe_region_size: Vector2i = subframe.rect_size
						var subframe_region_location: Vector2i = Vector2i(subframe.load_location_x, subframe.load_location_y)

						var region_id: int = regions.find_custom(
							func(region_data: SpritesheetRegionData) -> bool:
								return region_data.region_size == subframe_region_size and region_data.region_location == subframe_region_location
						)

						var modified_description: String = seq_description.replace("\n", ", ").replace("-, ", "-<br>").replace(", -", "<br>-")
						if modified_description.contains("-"):
							modified_description = "<br>" + modified_description

						if region_id != -1: # add data to existing region
							var existing_region: SpritesheetRegionData = regions[region_id]
							var new_shp_frame_id_label: String = str(shp_frame_id) + "-S"

							if not existing_region.shp_frame_ids.has(shp_frame_id):
								existing_region.shp_frame_ids.append(shp_frame_id)
							
							if not existing_region.shp_frame_id_labels.has(new_shp_frame_id_label):
								existing_region.shp_frame_id_labels.append(new_shp_frame_id_label)
							
							if not existing_region.animation_ids.has(seq_ptr_index):
								existing_region.animation_ids.append(seq_ptr_index)
								existing_region.animation_descriptions.append(modified_description)
						else: # add new region if an existing region does not have the same location and size
							var new_region: SpritesheetRegionData = SpritesheetRegionData.new()
							new_region.shp_type = shp.file_name
							new_region.region_id = regions.size()
							new_region.region_size = subframe_region_size
							new_region.region_location = subframe_region_location
							new_region.shp_frame_ids.append(shp_frame_id)
							new_region.animation_ids.append(seq_ptr_index)

							var new_shp_frame_id_label: String = str(shp_frame_id) + "-S"
							new_region.shp_frame_id_labels.append(new_shp_frame_id_label)

							modified_description = modified_description.trim_prefix("<br>")
							new_region.animation_descriptions.append(modified_description)
							regions.append(new_region)
	
	# convert data to text file
	var table_start: String = '{| class="wikitable mw-collapsible mw-collapsed sortable"\n|+ style="text-align:left; white-space:nowrap" | ' + shp.file_name + ' Regions\n'
	var headers: PackedStringArray = [
		"! SHP Type",
		"Region ID",
		"Region Location",
		"Region Size",
		"SHP Frame IDs",
		"SEQ Animation IDs",
		"Animation Descriptions",
	]
	
	var output: String = table_start + " !! ".join(headers)
	var output_array: PackedStringArray = []
	output_array.append(output)
	for region: SpritesheetRegionData in regions:
		var row_strings: PackedStringArray = []
		row_strings.append("| " + region.shp_type)
		row_strings.append(str(region.region_id))
		row_strings.append(str(region.region_location))
		row_strings.append(str(region.region_size))
		row_strings.append(str(region.shp_frame_id_labels).remove_chars('[]"'))
		row_strings.append(str(region.animation_ids).remove_chars("[]"))
		row_strings.append(str(region.animation_descriptions).remove_chars('[]"'))
		
		# var description_list: String = str(region.animation_descriptions)
		# description_list = description_list.replace("\n", "<br>")
		# row_strings.append(description_list)

		output_array.append(" || ".join(row_strings))
	
	var final_output: String = "\n|-\n".join(output_array)
	final_output += "\n|}"

	var file_name: String = shp.file_name.to_snake_case().replace(".", "_") + "_regions"
	DirAccess.make_dir_recursive_absolute("user://wiki_tables")
	var save_file: FileAccess = FileAccess.open("user://wiki_tables/wiki_table_" + file_name + ".txt", FileAccess.WRITE)
	save_file.store_string(final_output)


func add_entds(file_name: String) -> void:
	var entd_data_length: int = 40 * 16
	var entds_per_file: int = 0x80
	var file_bytes: PackedByteArray = file_records[file_name].get_file_data(rom)
	for idx: int in entds_per_file:
		var entd_bytes: PackedByteArray = file_bytes.slice(idx * entd_data_length, (idx + 1) * entd_data_length)
		var new_entd: FftEntd = FftEntd.new(entd_bytes)
		fft_entds.append(new_entd)


func export_data(save_path: String) -> void:
	# get other content data not in ROM data tables
	var predifined_abilities: Dictionary[String, Ability] = ContentGenerator.get_predefined_abilities()
	var predifined_passive_effects: Dictionary[String, PassiveEffect] = ContentGenerator.get_predefined_passive_effects()
	var predifined_actions: Dictionary[String, Action] = ContentGenerator.get_predefined_actions(abilities)
	var predifined_triggered_actions: Dictionary[String, TriggeredAction] = ContentGenerator.get_predefined_triggered_actions()

	abilities.merge(predifined_abilities, true)
	passive_effects.merge(predifined_passive_effects, true)
	actions.merge(predifined_actions, true)
	triggered_actions.merge(predifined_triggered_actions, true)

	# TODO rename content better

	DirAccess.make_dir_recursive_absolute(save_path)

	# var maps_path: String = save_path + "/maps/"
	# export_map(maps_path, maps["map_032_slums_in_dorter"])

	await export_unit_spritesheets(save_path)
	await export_other_images(save_path)
	await export_text(save_path)
	await export_unit_animations(save_path)
	await export_maps(save_path) # needs to be before data tables so maps will be initialized
	await export_data_tables(save_path)
	await export_vfx(save_path)


func export_unit_spritesheets(save_path: String) -> void:
	message.emit("Exporting unit spritesheets...")
	await get_tree().process_frame
	
	var spritesheet_path: String = save_path + "/unit_spritesheets/"
	DirAccess.make_dir_recursive_absolute(spritesheet_path)
	for unit_spr: Spr in spritesheets.values():
		if unit_spr.file_name == "ITEM.BIN":
			continue
		
		if not unit_spr.is_initialized:
			unit_spr.set_data()
			var job_using_spr: JobData = jobs_data.values()[jobs_data.values().find_custom(func(job_data: JobData) -> bool: return RomReader.sprs[RomReader.spr_id_file_idxs[job_data.sprite_id]] == unit_spr)]
			unit_spr.set_spritesheet_data(job_using_spr.sprite_id)

		var spritesheet_data: UnitSpritesheetData = UnitSpritesheetData.new(unit_spr)
		var spritesheet_data_file_path: String = spritesheet_path.path_join(spritesheet_data.unique_name.to_lower() + ".unit_spritesheet.tres")
		var error: Error = ResourceSaver.save(spritesheet_data, spritesheet_data_file_path)
		if error != Error.OK:
			push_warning("error saving unit spritesheet data " + spritesheet_data.unique_name + ": " + str(error))

		var index_image: Image = unit_spr.get_index_image(true)
		var unit_spritesheet_texture_webp_file_path: String = spritesheet_path.path_join(spritesheet_data.unique_name.to_lower() + ".texture.webp")
		index_image.save_webp(unit_spritesheet_texture_webp_file_path)
		
		for palette_idx: int in 8:
			var grid_image: Image = unit_spr.create_frame_grid_texture(palette_idx).get_image()
			var unit_grid_spritesheet_texture_webp_file_path: String = spritesheet_path.path_join(spritesheet_data.unique_name.to_lower() + "_" + str(palette_idx) + ".grid_texture.webp")
			grid_image.save_webp(unit_grid_spritesheet_texture_webp_file_path)


func export_other_images(save_path: String) -> void:
	message.emit("Exporting other images...")
	await get_tree().process_frame
	
	var other_images_path: String = save_path + "/other_images/"
	DirAccess.make_dir_recursive_absolute(other_images_path)
	# frame.bin
	var misc_index_image: Image = frame_bin.get_index_image(true)
	var misc_texture_webp_file_path: String = other_images_path.path_join("misc.texture.webp")
	misc_index_image.save_webp(misc_texture_webp_file_path)

	var misc_texture_palettes_file_path: String = other_images_path.path_join("misc.palette.tres")
	var misc_color_palette: ColorPalette = ColorPalette.new()
	misc_color_palette.colors = frame_bin.color_palette
	var error: Error = ResourceSaver.save(misc_color_palette, misc_texture_palettes_file_path)
	if error != Error.OK:
		push_warning("error saving palette data misc.palette.tres: " + str(error))

	# item_bin
	var item_spr: Spr = spritesheets["ITEM.BIN"]
	var items_index_image: Image = item_spr.get_index_image(true)
	var items_texture_webp_file_path: String = other_images_path.path_join("items.texture.webp")
	items_index_image.save_webp(items_texture_webp_file_path)
	
	var items_texture_palettes_file_path: String = other_images_path.path_join("items.palette.tres")
	var items_color_palette: ColorPalette = ColorPalette.new()
	items_color_palette.colors = item_spr.color_palette
	error = ResourceSaver.save(items_color_palette, items_texture_palettes_file_path)
	if error != Error.OK:
		push_warning("error saving palette data items.palette.tres: " + str(error))


func export_data_tables(save_path: String) -> void:
	message.emit("Exporting data tables...")
	await get_tree().process_frame
	
	for item: ItemData in items.values():
		Utilities.save_json(item, save_path)
	for status_effect: StatusEffect in status_effects.values():
		Utilities.save_json(status_effect, save_path)
		var status_file_path: String = save_path.path_join(StatusEffect.SAVE_FOLDER).path_join(".".join([status_effect.unique_name, status_effect.FILE_SUFFIX, "tres"]))
		var error: Error = ResourceSaver.save(status_effect, status_file_path)
	for job_data: JobData in jobs_data.values():
		Utilities.save_json(job_data, save_path)
	for action: Action in actions.values():
		Utilities.save_json(action, save_path)
	for triggered_action: TriggeredAction in triggered_actions.values():
		Utilities.save_json(triggered_action, save_path)
	for passive_effect: PassiveEffect in passive_effects.values():
		Utilities.save_json(passive_effect, save_path)
	for ability: Ability in abilities.values():
		Utilities.save_json(ability, save_path)
	for scenario: Scenario in scenarios.values():
		# mirror unit placement in scenarios to align with mirrored maps
		var map_chunk: Scenario.MapChunk = scenario.map_chunks[0]
		var map_chunk_data: FftMapData = maps[map_chunk.unique_name]
		scenario.units_data = Scenario.transform_units_data_tile_location(scenario.units_data, map_chunk_data.terrain_tiles, Vector2(-1, 1))
		Utilities.save_json(scenario, save_path)
	for skillset: Skillset in scus_data.skillsets_data:
		var skillset_path: String = save_path.path_join("/skillsets/")
		DirAccess.make_dir_recursive_absolute(skillset_path)

		for ability_id: int in skillset.action_ability_ids:
			if ability_id != 0:
				skillset.ability_names.append(abilities.keys()[ability_id])
		for ability_id: int in skillset.rsm_ability_ids:
			if ability_id != 0:
				skillset.ability_names.append(abilities.keys()[ability_id])

		var skillset_file_path: String = skillset_path.path_join(skillset.unique_name + ".skillset.tres")
		var error: Error = ResourceSaver.save(skillset, skillset_file_path)
	
	var initial_unit_data: InitialUnitData = InitialUnitData.new()
	var initial_unit_raw_stats: Array[Dictionary] = []
	var stat_name_lookup: Dictionary[String, int] = {
		"HP_MAX" : 0,
		"MP_MAX" : 1,
		"SPEED" : 2,
		"PHYSICAL_ATTACK" : 3,
		"MAGIC_ATTACK" : 4,
	}
	for stat_basis_name: String in Unit.StatBasis.keys():
		var initial_stats: Dictionary[String, Vector2i] = {}
		for stat_name: String in stat_name_lookup.keys():
			var stat_idx: int = stat_name_lookup[stat_name]
			
			var stat_range: Vector2i = Vector2i.ZERO
			stat_range.x = RomReader.scus_data.unit_base_datas[Unit.StatBasis[stat_basis_name]][stat_idx] * 16384
			stat_range.y = stat_range.x + (RomReader.scus_data.unit_base_stats_mods[Unit.StatBasis[stat_basis_name]][stat_idx] * 16384)
			initial_stats[stat_name] = stat_range
		initial_unit_raw_stats.append(initial_stats)
	initial_unit_data.initial_unit_raw_stats = initial_unit_raw_stats

	var initial_unit_equipment: Array[Dictionary] = []
	var equipment_slot_name_lookup: Dictionary[String, int] = {
		"Head" : 5,
		"Body" : 6,
		"Accessory" : 7,
		"RH_weapon" : 8,
		"RH_shield" : 9,
		"LH_weapon" : 10,
		"LH_shield" : 11,
	}
	for stat_basis_name: String in Unit.StatBasis.keys():
		var initial_equipment: Dictionary[String, String] = {}
		for slot_name: String in equipment_slot_name_lookup.keys():
			var slot_idx: int = equipment_slot_name_lookup[slot_name]
			var item_idx: int = RomReader.scus_data.unit_base_datas[Unit.StatBasis[stat_basis_name]][slot_idx]
			var item_name: String = RomReader.items_array[0].unique_name
			if item_idx != 255:
				item_name = RomReader.items_array[item_idx].unique_name
			initial_equipment[slot_name] = item_name
		initial_unit_equipment.append(initial_equipment)
	initial_unit_data.initial_unit_equipment = initial_unit_equipment

	var initial_unit_data_file_path: String = save_path.path_join("initial_unit_data.tres")
	var error: Error = ResourceSaver.save(initial_unit_data, initial_unit_data_file_path)
	if error != Error.OK:
		push_warning("error saving unit initial_unit_data: " + str(error))


func export_text(save_path: String) -> void:
	message.emit("Exporting text...")
	await get_tree().process_frame
	
	var text_path: String = save_path + "/text/"
	DirAccess.make_dir_recursive_absolute(text_path)
	var names: PackedStringArray = fft_text.unit_names_list
	var names_string: String = JSON.stringify(names, "\t")
	var names_filepath: String = text_path + "names.text.json"
	var names_file: FileAccess = FileAccess.open(names_filepath, FileAccess.WRITE)
	names_file.store_line(names_string)
	names_file.close()


func export_unit_animations(save_path: String) -> void:
	message.emit("Exporting SHPs and SEQs...")
	await get_tree().process_frame
	
	var animation_dir_path: String = save_path.path_join("animations/")
	DirAccess.make_dir_recursive_absolute(animation_dir_path)

	for shp: Shp in shps.values():
		if not shp.is_initialized:
			shp.set_data_from_shp_bytes(get_file_data(shp.file_name))

		var shp_file_path: String = animation_dir_path.path_join(shp.file_name.to_lower().trim_suffix(".shp") + ".shp.tres")
		var error: Error = ResourceSaver.save(shp, shp_file_path)
		if error != Error.OK:
			push_warning("error saving shp " + shp.file_name + ": " + str(error))

	for seq: Seq in seqs.values():
		if not seq.is_initialized:
			seq.set_data_from_seq_bytes(get_file_data(seq.file_name))

		var seq_file_path: String = animation_dir_path.path_join(seq.file_name.to_lower().trim_suffix(".seq") + ".seq.tres")
		var error: Error = ResourceSaver.save(seq, seq_file_path)
		if error != Error.OK:
			push_warning("error saving shp " + seq.file_name + ": " + str(error))
	
	var animation_data: AnimationData = AnimationData.new()
	animation_data.animation_layer_priorities = battle_bin_data.animation_layer_priorities
	var animation_data_file_path: String = animation_dir_path.path_join("animation_data.tres")
	var error: Error = ResourceSaver.save(animation_data, animation_data_file_path)


func export_maps(save_path: String) -> void:
	# message.emit("Exporting maps...")
	# await get_tree().process_frame

	#var map_tile_80_test: PackedStringArray
	#var map_tile_40_test: PackedStringArray
	
	var maps_path: String = save_path + "/maps/"
	DirAccess.make_dir_recursive_absolute(maps_path)
	var last_frame_time: int = Time.get_ticks_msec()
	for fft_map_data: FftMapData in maps.values():
		var elapsed_time: float = (Time.get_ticks_msec() - last_frame_time) / 1000.0
		if elapsed_time > (1 / 60.0):
			message.emit("Exporting map: " + fft_map_data.unique_name)
			await get_tree().process_frame
			last_frame_time = Time.get_ticks_msec()
		
		if fft_map_data.unique_name == "map_000":
			continue # skip map 0 - causes crash

		export_map(maps_path, fft_map_data)
		
		#var map_tiles_80: PackedStringArray = []
		#var map_tiles_40: PackedStringArray = []
		#for tile: TerrainTile in fft_map_data.terrain_tiles:
			#if tile.bytes[0] & 0x40 == 0x40:
				#map_tiles_40.append(str(tile.location))
			#if tile.bytes[0] & 0x80 == 0x80:
				#map_tiles_80.append(str(tile.location))
		#
		#if not map_tiles_80.is_empty():
			#map_tile_80_test.append(fft_map_data.unique_name + ": " + ",".join(map_tiles_80))
		#if not map_tiles_40.is_empty():
			#map_tile_40_test.append(fft_map_data.unique_name + ": " + ",".join(map_tiles_40))
	#
	#var map_tile_80_test_total: String = "\n".join(map_tile_80_test)
	#var map_tile_80_file: FileAccess = FileAccess.open(maps_path.path_join("map_tile_0x80.txt"), FileAccess.WRITE)
	#map_tile_80_file.store_string(map_tile_80_test_total)
	#map_tile_80_file.close()
#
	#var map_tile_40_test_total: String = "\n".join(map_tile_40_test)
	#var map_tile_40_file: FileAccess = FileAccess.open(maps_path.path_join("map_tile_0x40.txt"), FileAccess.WRITE)
	#map_tile_40_file.store_string(map_tile_40_test_total)
	#map_tile_40_file.close()


func export_map(save_path: String, fft_map_data: FftMapData) -> void:
	# var new_map_node: MapChunkNodes = fft_map_data.get_map_scene(Vector3(-1.0, -1.0, 1.0), Vector3(0, -FftMapData.HEIGHT_SCALE, 0))
	# mirror map so positive y is up, mirror x so it ends up looking un-mirrored
	var new_map_node: MapChunkNodes = fft_map_data.get_map_scene(Vector3(-1.0, -1.0, 1.0))
	GltfManager.save_node(new_map_node, save_path, fft_map_data.unique_name + ".map.glb")
	
	var map_texture_webp_file_path: String = save_path.path_join(fft_map_data.unique_name + ".texture.webp")
	fft_map_data.albedo_texture_indexed.get_image().save_webp(map_texture_webp_file_path)

	#var map_texture_webp_file_path2: String = maps_path.path_join(fft_map_data.unique_name + "_full_color.texture.webp")
	#fft_map_data.albedo_texture.get_image().save_webp(map_texture_webp_file_path2)
	
	var new_map_data: MapData = MapData.init_from_fft_map_data(fft_map_data)
	new_map_data.terrain_tiles = new_map_data.get_transformed_tiles(Vector2.ZERO, Vector2(-1, 1), 0)
	var map_data_file_path: String = save_path.path_join(fft_map_data.unique_name + ".map_data.tres")
	var error: Error = ResourceSaver.save(new_map_data, map_data_file_path)
	if error != Error.OK:
		push_warning("error saving map data " + fft_map_data.unique_name + ": " + str(error))


func export_vfx(save_path: String) -> void:
	message.emit("Exporting vfx...")
	await get_tree().process_frame
	
	var vfx_path: String = save_path + "/vfx/"
	DirAccess.make_dir_recursive_absolute(vfx_path)
	for vfx_file: VisualEffectData in vfx:
		vfx_file.init_from_file()
		if not vfx_file.is_initialized: # skip empty vfx files
			continue

		var vfx_data_file_path: String = vfx_path.path_join(vfx_file.unique_name + ".vfx_data.tres")
		var error: Error = ResourceSaver.save(vfx_file, vfx_data_file_path)
		if error != Error.OK:
			push_warning("error saving map data " + vfx_file.unique_name + ": " + str(error))

		var vfx_texture_webp_file_path: String = vfx_path.path_join(vfx_file.unique_name + ".texture.webp")
		vfx_file.texture.get_image().save_webp(vfx_texture_webp_file_path)

	
	var trap_texture_webp_file_path: String = vfx_path.path_join("shared_vfx.texture.webp")
	trap_effect_data.trap_spr.get_index_image().save_webp(trap_texture_webp_file_path)
	
	var shared_vfx_data_file_path: String = vfx_path.path_join("shared_vfx.data.tres")
	var error: Error = ResourceSaver.save(trap_effect_data, shared_vfx_data_file_path)
	if error != Error.OK:
		push_warning("error saving shared vfx data: " + str(error))

	var shared_vfx_texture_palettes_file_path: String = vfx_path.path_join("shared_vfx.palette.tres")
	var shared_vfx_color_palette: ColorPalette = ColorPalette.new()
	shared_vfx_color_palette.colors = trap_effect_data.trap_spr.color_palette
	error = ResourceSaver.save(shared_vfx_color_palette, shared_vfx_texture_palettes_file_path)
	if error != Error.OK:
		push_warning("error saving palette data shared_vfx.palette.tres: " + str(error))
	
	for palette_idx: int in 16:
		var full_color_texture_webp_file_path: String = vfx_path.path_join("shared_vfx_%02d.texture.webp" % palette_idx)
		trap_effect_data.trap_spr.set_pixel_colors(palette_idx)
		trap_effect_data.trap_spr.get_rgba8_image().save_webp(full_color_texture_webp_file_path)

	# projectiles
	var models_data: Dictionary = RomReader.battle_bin_data.projectile_model_data
	for model_id: int in models_data:
		var verts: Array[Vector3] = models_data[model_id]["vertices"]
		var faces: Array = models_data[model_id]["faces"]

		var new_mesh_instance: MeshInstance3D = MeshInstance3D.new()
		new_mesh_instance.mesh = ProjectileEffectInstance.build_mesh(verts, faces)
		new_mesh_instance.name = "projectile_" + ProjectileEffectInstance.ProjectileType.keys()[model_id]
		GltfManager.save_node(new_mesh_instance, vfx_path, new_mesh_instance.name + ".projectile.glb")
		new_mesh_instance.queue_free()


static func export_tile_meshes(path: String, scale: Vector3 = Vector3.ONE) -> void:
	for slope_type: TerrainTile.SlopeType in TerrainTile.SlopeType.values():
		var mesh: ArrayMesh = TerrainTile.get_normalized_slope_mesh(TerrainTile.SLOPE_TYPE_CODE[slope_type], scale)
		var mesh_name: String = TerrainTile.SlopeType.keys()[slope_type].to_lower()

		var mesh_file_path: String = path.path_join("tile_mesh_" + mesh_name + ".tres")
		var error: Error = ResourceSaver.save(mesh, mesh_file_path)
		if error != Error.OK:
			push_warning("error saving tile mesh " + mesh_name + ": " + str(error))


class SpritesheetRegionData:
	var shp_type: String
	var region_id: int
	var region_location: Vector2i
	var region_size: Vector2i
	var shp_frame_ids: PackedInt32Array = []
	var shp_frame_id_labels: PackedStringArray = []
	var animation_ids: PackedInt32Array = []
	var animation_descriptions: PackedStringArray = []
