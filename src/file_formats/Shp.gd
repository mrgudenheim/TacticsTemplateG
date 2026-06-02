class_name Shp
extends Resource

var is_initialized: bool = false

# https://ffhacktics.com/wiki/Sprite_Y_Rotation_Table
# TODO use table from SCUS? 
const ROTATIONS_DEGREES: PackedFloat64Array = [
	0,
	15.996,
	23.027,
	26.455,
	26.719,
	26.982,
	29.971,
	42.979,
	45.000,
	55.020,
	60.029,
	70.049,
	90.000,
	119.971,
	120.059,
	124.980,
	127.969,
	129.990,
	135.000,
	140.010,
	145.020,
	150.029,
	153.018,
	154.951,
	160.049,
	164.971,
]

var frame_size: Vector2i:
	get:
		if (file_name.to_lower().contains("kanzen") or file_name.to_lower().contains("arute")):
			return Vector2i(120, 180)
		else:
			return Vector2i(120, 120)

const PIXELS_PER_TILE: int = 8

static var shp_aliases: Dictionary[String, String] = {
	"arute":"Altima/arute",
	"cyoko":"Chocobo/cyoko",
	"eff1":"eff1",
	"eff2":"eff2 (Unused)",
	"kanzen":"Altima2/kanzen",
	"mon":"Monster/Lucavi/mon",
	"other":"other",
	"type1":"type1",
	"type2":"type2",
	"wep1":"wep1",
	"wep2":"wep2",
	"item":"item",
}

const SP2_START_ANIMATION_ID: int = 194
const SP2_V_OFFSET: int = 232 # pixels
const SP2_V_OFFSET2: int = 256 # pixels
#const CONSTANT_SP2_V_OFFSETS: Dictionary[int, int] = { # using ShiShi spritesheet, sp2s loaded in order of ability id
	#234: SP2_V_OFFSET,
	#235: SP2_V_OFFSET,
	#236: SP2_V_OFFSET + (SP2_V_OFFSET2 * 1),
	#237: SP2_V_OFFSET + (SP2_V_OFFSET2 * 1),
	#232: SP2_V_OFFSET + (SP2_V_OFFSET2 * 2),
	#233: SP2_V_OFFSET + (SP2_V_OFFSET2 * 2),
	#230: SP2_V_OFFSET + (SP2_V_OFFSET2 * 3),
	#231: SP2_V_OFFSET + (SP2_V_OFFSET2 * 3),
	#}

# ptr 230 - Destroy (electric fist) - IRON5.SP2
# ptr 232 - Compress (hammer) - IRON4.SP2
# ptr 234 - Dispose (cannon) - IRON2.SP2
# ptr 236 - Crush (drill) - IRON3.SP2
const CONSTANT_SP2_V_OFFSETS: Dictionary[int, int] = { # spritesheet with sp2s appended in order of file name
	234: SP2_V_OFFSET + (SP2_V_OFFSET2 * 1),
	235: SP2_V_OFFSET + (SP2_V_OFFSET2 * 1),
	236: SP2_V_OFFSET + (SP2_V_OFFSET2 * 2),
	237: SP2_V_OFFSET + (SP2_V_OFFSET2 * 2),
	232: SP2_V_OFFSET + (SP2_V_OFFSET2 * 3),
	233: SP2_V_OFFSET + (SP2_V_OFFSET2 * 3),
	230: SP2_V_OFFSET + (SP2_V_OFFSET2 * 4),
	231: SP2_V_OFFSET + (SP2_V_OFFSET2 * 4),
}
const CONSTANT_SP2_FILES: Dictionary[int, int] = { # spritesheet with sp2s appended in order of file name
	234: 1,
	235: 1,
	236: 2,
	237: 2,
	232: 3,
	233: 3,
	230: 4,
	231: 4,
}

@export var file_name: String = "default_file_name"
@export var name_alias: String = "default_name_alias"

# section 1
@export var swim_pointer: int = 0
@export var attack_start_index: int = 9999
@export var sp_extra: int = 0
@export var zero_frames: Array[int] = [] # only used in wep or eff
var section1_length: int = 0:
	get:
		return 0x44 if (file_name.begins_with("WEP") or file_name.begins_with("EFF")) else 8

# section 2
@export var frame_pointers: Array[int] = []
var section2_length: int = 0:
	get:
		return 0x800 if (file_name.begins_with("WEP") or file_name.begins_with("EFF")) else 0x400
	
# section 3
@export var frames: Array[FrameData] = []
var section3_length: int = 0:
	get:
		var sum: int = 0
		for frame: FrameData in frames:
			sum += frame.length
		return sum + 2 # bytes

# submerged section
var has_submerged_data: bool = false:
	get:
		return swim_pointer > 0
@export var frame_pointers_submerged: Array[int] = []
@export var frames_submerged: Array[FrameData] = []
var frames_submerged_length: int = 0:
	get:
		var sum: int = 0
		for frame: FrameData in frames_submerged:
			sum += frame.length
		return sum + 2 # bytes


func _init(new_file_name: String = "") -> void:
	if new_file_name == "":
		return
	
	set_file_name(new_file_name)


func get_frame(frame_index: int, submerged_depth: int = 0) -> FrameData:
	if submerged_depth == 0 or not has_submerged_data:
		return frames[frame_index]
	elif submerged_depth == 1:
		return frames_submerged[frame_index]
	else:
		return frames_submerged[0]


func set_data_from_shp_object(shp_object: Shp) -> void:
	file_name = shp_object.file_name
	name_alias = shp_object.name_alias
	
	# section 1
	swim_pointer = shp_object.swim_pointer
	attack_start_index = shp_object.attack_start_index
	sp_extra = shp_object.sp_extra
	zero_frames = shp_object.zero_frames.duplicate()
	
	# section 2
	frame_pointers = shp_object.frame_pointers.duplicate()
	frame_pointers_submerged = shp_object.frame_pointers_submerged.duplicate()
	
	# section 3
	frames = shp_object.frames.duplicate()
	frames_submerged = shp_object.frames_submerged.duplicate()


func set_data_from_shp_file(filepath:String) -> void:
	var new_file_name:String = filepath.get_file()
	
	var bytes:PackedByteArray = FileAccess.get_file_as_bytes(filepath)
	if bytes.size() == 0:
		push_warning("Open Error: " + filepath)
		return
	else:
		set_data_from_shp_bytes(bytes)


func set_file_name(new_file_name: String) -> void:
	#new_file_name = new_file_name.trim_suffix(".shp")
	#new_file_name = new_file_name.trim_suffix(".SHP")
	#new_file_name = new_file_name.trim_suffix(".Shp")
	#new_file_name = new_file_name.to_lower()
	
	file_name = new_file_name
	
	if shp_aliases.has(file_name):
		name_alias = shp_aliases[file_name]
	else:
		name_alias = file_name


func set_data_from_shp_bytes(bytes: PackedByteArray) -> void:
	swim_pointer = bytes.decode_u32(0)
	attack_start_index = bytes.decode_u16(4)
	sp_extra = bytes.decode_u16(6)
	
	# these shapes have a slightly different format
	if (file_name.begins_with("WEP") or file_name.begins_with("EFF")):
		attack_start_index = 9999; # these types do not have a second (lower) half
		
		var initial_offset: int = 4 # skip first bytes
		@warning_ignore("integer_division")
		var num_zero_frames: int = (section1_length - initial_offset) / 2
		for index: int in num_zero_frames:
			var zero_frame: int = bytes.decode_u16(initial_offset + (index * 2))
			zero_frames.append(zero_frame)
		
	@warning_ignore("integer_division")
	var num_frame_pointers: int = (section2_length / 4)
	for frame_index: int in num_frame_pointers:
		var frame_pointer: int = bytes.decode_u32(section1_length + (frame_index * 4))
		if frame_index > 0 and frame_pointer == 0:
			break # skip to section 3 if no more pointers in section 2
		frame_pointers.append(frame_pointer)
		if has_submerged_data:
			var frame_pointer_submerged: int = bytes.decode_u32(swim_pointer + (frame_index * 4))
			frame_pointers_submerged.append(frame_pointer_submerged)
	
	var frame_data_start: int = section1_length + section2_length + 2
	frames.clear()
	for frame_pointer: int in frame_pointers:
		var frame_offset: int = frame_data_start + frame_pointer
		if frame_offset >= bytes.size():
			push_warning(str(frame_offset) + " > " + str(bytes.size()))
		var num_subframes: int = 1 + (bytes.decode_u8(frame_offset) & 0b00000111)
		var frame_length: int = 2 + (num_subframes * 4)
		frames.append(_get_frame_data(bytes.slice(frame_offset, frame_offset + frame_length)))
	
	# submerged frames
	if has_submerged_data:
		var frame_submerged_data_start: int = swim_pointer + section2_length + 2
		frames_submerged.clear()
		for frame_pointer_submerged: int in frame_pointers_submerged:
			var frame_offset: int = frame_submerged_data_start + frame_pointer_submerged
			var num_subframes: int = 1 + (bytes.decode_u8(frame_offset) & 0b00000111)
			var frame_length: int = 2 + (num_subframes * 4)
			frames_submerged.append(_get_frame_data(bytes.slice(frame_offset, frame_offset + frame_length)))
	
	is_initialized = true


func _get_frame_data(bytes: PackedByteArray) -> FrameData:
	var frame_data: FrameData = FrameData.new()
	
	frame_data.num_subframes = 1 + (bytes.decode_u8(0) & 0x07)
	var y_rotation_pointer: int = (bytes.decode_u8(0) & 0xF8) >> 3
	frame_data.y_rotation = ROTATIONS_DEGREES[y_rotation_pointer]
	frame_data.transparency_type = (bytes.decode_u8(1) & 0x60) >> 5
	frame_data.transparency_flag = (bytes.decode_u8(1) & 0x01) == 1
	frame_data.byte2_3 = (bytes.decode_u8(1) & 0x1E) >> 1
	frame_data.byte2_4 = (bytes.decode_u8(1) & 0x80) >> 7
	
	for subframe_index: int in frame_data.num_subframes:
		var subframe_start: int = 2 + (subframe_index * 4)
		var subframe_bytes: PackedByteArray = bytes.slice(subframe_start, subframe_start + 4)
		frame_data.subframes.append(_get_subframe_data(subframe_bytes))
	
	return frame_data


func _get_subframe_data(bytes: PackedByteArray) -> SubFrameData:
	var subframe: SubFrameData = SubFrameData.new()
	
	subframe.shift_x = bytes.decode_s8(0)
	subframe.shift_y = bytes.decode_s8(1)
	
	var bytes23: int = bytes.decode_u16(2)
	subframe.load_location_x = (bytes23 & 0x001F) * PIXELS_PER_TILE # pixels
	subframe.load_location_y = ((bytes23 & 0x03E0) >> 5) * PIXELS_PER_TILE # pixels
	var rect_size_index: int = (bytes23 & 0x3C00) >> 10
	subframe.rect_size = RomReader.battle_bin_data.shp_subframe_sizes[rect_size_index]
	subframe.flip_x = (bytes23 & 0x4000) != 0
	subframe.flip_y = (bytes23 & 0x8000) != 0
	
	return subframe


func write_shp(path: String = "user://FFTorama") -> void:
	var bytes: PackedByteArray = []
	var total_size: int = section1_length + section2_length + section3_length
	if has_submerged_data:
		total_size += section2_length + frames_submerged_length
	bytes.resize(total_size)
	bytes.fill(0)
	
	# section 1
	# wep and eff shapes have a slightly different format
	if (file_name.begins_with("WEP") or file_name.begins_with("EFF")):
		var initial_offset: int = 6
		
		# skip zero bytes and unarmed
		bytes.encode_u8(0, 0)
		bytes.encode_u8(1, 0)
		bytes.encode_u8(2, 0)
		bytes.encode_u8(3, 0)
		bytes.encode_u8(4, 0)
		bytes.encode_u8(5, 0)
				
		for zero_frame_index: int in zero_frames.size():
			bytes.encode_u16(initial_offset + (zero_frame_index*2), zero_frames[zero_frame_index])
	else:
		bytes.encode_u32(0, swim_pointer)
		bytes.encode_u16(4, attack_start_index)
		bytes.encode_u16(6, sp_extra)
	
	bytes = _write_sections23_bytes(bytes, section1_length, frame_pointers, frames, section3_length)
	if swim_pointer > section2_length:
		bytes = _write_sections23_bytes(bytes, swim_pointer, frame_pointers_submerged, frames_submerged, frames_submerged_length)
	
	DirAccess.make_dir_recursive_absolute(path)
	var save_file: FileAccess = FileAccess.open(path.path_join(file_name), FileAccess.WRITE)
	save_file.store_buffer(bytes)


func _write_sections23_bytes(bytes: PackedByteArray,  data_start_pointer: int, pointers: Array[int], frames_list: Array[FrameData], section3data_length: int) -> PackedByteArray:
	# section 2
	for frame_index: int in pointers.size():
		bytes.encode_u32(data_start_pointer + (frame_index * 4), pointers[frame_index])	
	
	# section 3
	bytes.encode_u16(data_start_pointer + section2_length, section3data_length)
	
	var frame_data_start_pointer: int = data_start_pointer + section2_length + 2
	for frame_index: int in pointers.size():
		var frame_offset: int = frame_data_start_pointer + pointers[frame_index]
		var frame_data: FrameData = frames_list[frame_index]
		var b1: int = frame_data.num_subframes - 1
		var b1_2: int = ROTATIONS_DEGREES.find(frame_data.y_rotation) << 3
		b1 = b1 | b1_2
		
		var b2: int = (frame_data.transparency_flag as int) & 0b01
		var b2_2: int = frame_data.byte2_3 << 1
		var b2_3: int = frame_data.transparency_type << 5
		var b2_4: int = frame_data.byte2_4 << 7
		b2 = b2 | b2_2
		b2 = b2 | b2_3
		b2 = b2 | b2_4
		
		bytes.encode_u8(frame_offset, b1)
		bytes.encode_u8(frame_offset + 1, b2)
		
		for subframe_index: int in frame_data.subframes.size():
			var subframe: SubFrameData = frame_data.subframes[subframe_index]
			@warning_ignore("integer_division")
			var b56: int = (subframe.load_location_x / PIXELS_PER_TILE)
			@warning_ignore("integer_division")
			var b56_2: int = (subframe.load_location_y / PIXELS_PER_TILE) << 5
			var b56_3: int = RomReader.battle_bin_data.shp_subframe_sizes.find(subframe.rect_size) << 10
			var b56_4: int = (subframe.flip_x as int) << 14
			var b56_5: int = (subframe.flip_y as int) << 15
			
			b56 = b56 | b56_2
			b56 = b56 | b56_3
			b56 = b56 | b56_4
			b56 = b56 | b56_5
			
			bytes.encode_s8(frame_offset + 2 + (subframe_index * 4), subframe.shift_x)
			bytes.encode_s8(frame_offset + 3 + (subframe_index * 4), subframe.shift_y)
			bytes.encode_u16(frame_offset + 4 + (subframe_index * 4), b56)
	
	return bytes


func set_data_from_cfg(filepath: String) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(filepath)
	#var err = cfg.load("user://FFTorama/"+file_name+"_shp.cfg")
	
	if err != OK:
		push_warning("Error Opening: " + str(err) + " - " + filepath)
		return
	
	file_name = filepath.get_file()
	file_name = file_name.trim_suffix("_shp.cfg")
	name_alias = cfg.get_value(file_name, "name_alias")
	swim_pointer = cfg.get_value(file_name, "swim_pointer")
	attack_start_index = cfg.get_value(file_name, "attack_start_index")
	sp_extra = cfg.get_value(file_name, "sp_extra")
	zero_frames = cfg.get_value(file_name, "zero_frames")
	frame_pointers = cfg.get_value(file_name, "frame_pointers")
	frame_pointers_submerged = cfg.get_value(file_name, "frame_pointers_submerged")
	
	frames.clear()
	frames = _get_frames_from_cfg(cfg, frame_pointers, file_name)
	if has_submerged_data:
		frames_submerged = _get_frames_from_cfg(cfg, frame_pointers_submerged, file_name + "-submerged")


func _get_frames_from_cfg(cfg: ConfigFile, pointers: Array[int], cfg_file_name: String) -> Array[FrameData]:
	var temp_frames: Array[FrameData] = []
	
	for frame_index: int in pointers.size():
		var frame_label: String = cfg_file_name + "-" + str(frame_index)
		temp_frames.append(FrameData.new())
		temp_frames[frame_index].num_subframes = cfg.get_value(frame_label, "num_subframes")
		temp_frames[frame_index].y_rotation = cfg.get_value(frame_label, "y_rotation")
		temp_frames[frame_index].transparency_type = cfg.get_value(frame_label, "transparency_type")
		temp_frames[frame_index].transparency_flag = cfg.get_value(frame_label, "transparency_flag")
		temp_frames[frame_index].byte2_3 = cfg.get_value(frame_label, "byte2_3")
		temp_frames[frame_index].byte2_4 = cfg.get_value(frame_label, "byte2_4")
		
		for subframe_index: int in temp_frames[frame_index].num_subframes:
			var subframe_label: String = frame_label + "-" + str(subframe_index)
			temp_frames[frame_index].subframes.append(SubFrameData.new())
			temp_frames[frame_index].subframes[subframe_index].shift_x = cfg.get_value(subframe_label, "shift_x")
			temp_frames[frame_index].subframes[subframe_index].shift_y = cfg.get_value(subframe_label, "shift_y")
			temp_frames[frame_index].subframes[subframe_index].load_location_x = cfg.get_value(subframe_label, "load_location_x")
			temp_frames[frame_index].subframes[subframe_index].load_location_y = cfg.get_value(subframe_label, "load_location_y")
			temp_frames[frame_index].subframes[subframe_index].rect_size = cfg.get_value(subframe_label, "rect_size")
			temp_frames[frame_index].subframes[subframe_index].flip_x = cfg.get_value(subframe_label, "flip_x")
			temp_frames[frame_index].subframes[subframe_index].flip_y = cfg.get_value(subframe_label, "flip_y")
	
	return temp_frames


func write_cfg() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(file_name, "file_name", file_name)
	cfg.set_value(file_name, "name_alias", name_alias)
	cfg.set_value(file_name, "swim_pointer", swim_pointer)
	cfg.set_value(file_name, "attack_start_index", attack_start_index)
	cfg.set_value(file_name, "sp_extra", sp_extra)
	cfg.set_value(file_name, "zero_frames", zero_frames)
	cfg.set_value(file_name, "frame_pointers", frame_pointers)
	cfg.set_value(file_name, "frame_pointers_submerged", frame_pointers_submerged)
	
	cfg = _write_cfg_frames(cfg, frames, file_name)
	if has_submerged_data:
		cfg = _write_cfg_frames(cfg, frames_submerged, file_name + "-submerged")
	
	cfg.save("user://FFTorama/"+file_name+"_shp.cfg")


func _write_cfg_frames(cfg: ConfigFile, temp_frames: Array[FrameData], cfg_file_name: String) -> ConfigFile:
	for frame_index: int in temp_frames.size():
		var frame_label: String = cfg_file_name + "-" + str(frame_index)
		var frame_data: FrameData = temp_frames[frame_index]
		cfg.set_value(frame_label, "num_subframes", frame_data.num_subframes)
		cfg.set_value(frame_label, "y_rotation", frame_data.y_rotation)
		cfg.set_value(frame_label, "transparency_type", frame_data.transparency_type)
		cfg.set_value(frame_label, "transparency_flag", frame_data.transparency_flag)
		cfg.set_value(frame_label, "byte2_3", frame_data.byte2_3)
		cfg.set_value(frame_label, "byte2_4", frame_data.byte2_4)
		
		cfg = _write_cfg_subframes(cfg, frame_data, frame_label)
	
	return cfg


func _write_cfg_subframes(cfg: ConfigFile, temp_frame_data: FrameData, frame_label: String) -> ConfigFile:
	for subframe_index: int in temp_frame_data.num_subframes:
		var subframe_label: String = frame_label + "-" + str(subframe_index)
		var subframe_data: SubFrameData = temp_frame_data.subframes[subframe_index]
		cfg.set_value(subframe_label, "shift_x", subframe_data.shift_x)
		cfg.set_value(subframe_label, "shift_y", subframe_data.shift_y)
		cfg.set_value(subframe_label, "load_location_x", subframe_data.load_location_x)
		cfg.set_value(subframe_label, "load_location_y", subframe_data.load_location_y)
		cfg.set_value(subframe_label, "rect_size", subframe_data.rect_size)
		cfg.set_value(subframe_label, "flip_x", subframe_data.flip_x)
		cfg.set_value(subframe_label, "flip_y", subframe_data.flip_y)
	
	return cfg


#func set_frames_from_csv(frame_data_csv:String) -> void:
func set_frames_from_csv(filepath:String) -> void:
	frames.clear()
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		push_warning(FileAccess.get_open_error())
		return
	var frame_data_csv: String = file.get_as_text()
	
	if file_name == "default_file_name":
		var new_file_name: String = filepath.get_file()
		new_file_name = new_file_name.trim_suffix(".csv")
		new_file_name = new_file_name.trim_suffix(".txt")
		new_file_name = new_file_name.trim_prefix("frame_data_")
		new_file_name = new_file_name.to_lower()
		
		file_name = new_file_name
		name_alias = new_file_name
	
	var frames_split: PackedStringArray = frame_data_csv.split("\n")
	frames_split = frames_split.slice(1, frames_split.size()) # skip first row of headers
	
	var subframe_offset: int = 6 # skip past label, frame_id, num_subframes, rotation_degrees, transparency_type, transparency_flag
	var subframe_length: int = 8
	
	for frame_text: String in frames_split:
		var frame_text_split: PackedStringArray = frame_text.split(",")
		
		if(frame_text[0] == ""):
			continue
		
		var new_frame: FrameData = FrameData.new()
		
		new_frame.num_subframes = frame_text_split[2] as int
		new_frame.y_rotation = frame_text_split[3] as float
		new_frame.transparency_type = frame_text_split[4] as int
		new_frame.transparency_flag = frame_text_split[5].to_lower() == "true" as bool
		#var frame_data = [num_subframe, rotation_degrees]
		
		for i: int in new_frame.num_subframes:
			var new_subframe: SubFrameData = SubFrameData.new()
			
			new_subframe.shift_x = frame_text_split[subframe_offset + (subframe_length*i)] as int
			new_subframe.shift_y = frame_text_split[subframe_offset + 1 + (subframe_length*i)] as int
			new_subframe.load_location_x = frame_text_split[subframe_offset + 2 + (subframe_length*i)] as int
			new_subframe.load_location_y = frame_text_split[subframe_offset + 3 + (subframe_length*i)] as int
			var rect_size_x: int = frame_text_split[subframe_offset + 4 + (subframe_length*i)] as int
			var rect_size_y: int = frame_text_split[subframe_offset + 5 + (subframe_length*i)] as int
			new_subframe.rect_size = Vector2i(rect_size_x, rect_size_y)
			new_subframe.flip_x = frame_text_split[subframe_offset + 6 + (subframe_length*i)].to_lower() == "true" as bool
			new_subframe.flip_y = frame_text_split[subframe_offset + 7 + (subframe_length*i)].to_lower() == "true" as bool
			
			new_frame.subframes.append(new_subframe)
		
		frames.append(new_frame)
		# print(frame_data)


func set_zero_frames_from_csv(filepath: String) -> void:
	zero_frames.clear()
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		push_warning(FileAccess.get_open_error())
		return
	var frame_offsets_data_csv: String = file.get_as_text()
	
	if file_name == "default_file_name":
		var new_file_name: String = filepath.get_file()
		new_file_name = new_file_name.trim_suffix(".csv")
		new_file_name = new_file_name.trim_suffix(".txt")
		new_file_name = new_file_name.trim_prefix("frame_offset_data_")
		new_file_name = new_file_name.to_lower()
		
		file_name = new_file_name
		name_alias = new_file_name
	
	var offsets_split: PackedStringArray = frame_offsets_data_csv.split("\n")
	offsets_split = offsets_split[1].split(",")
	for offset: String in offsets_split:
		zero_frames.append(offset as int)
	pass


func write_csvs() -> void:
	var headers: PackedStringArray = [
		"label",
		"frame_id",
		"num_subframes",
		"rotation_degrees",
		"transparency_type",
		"transparency_flag",
		"shift_x",
		"shift_y",
		"top_left_x_pixels",
		"top_left_y_pixels",
		"sizeX",
		"sizeY",
		"flip_x",
		"flip_y",
	]
	var output: String = ",".join(headers)
	var frame_data_string:String = ""
	
	var frame_id: int = 0
	for frame: FrameData in frames:
		var frame_data: PackedStringArray = [
			name_alias,
			str(frame_id),
			str(frame.num_subframes),
			str(frame.y_rotation),
			str(frame.transparency_type),
			str(frame.transparency_flag),
		]
		frame_data_string = ",".join(frame_data)
		
		for subframe: SubFrameData in frame.subframes:
			var text_parts: PackedStringArray = [
				frame_data_string,
				str(subframe.shift_x),
				str(subframe.shift_y),
				str(subframe.load_location_x),
				str(subframe.load_location_y),
				str(subframe.rect_size.x),
				str(subframe.rect_size.y),
				str(subframe.flip_x),
				str(subframe.flip_y)]
			
			frame_data_string = ",".join(text_parts);
		
		var all_text: PackedStringArray = [output, frame_data_string]
		output = "\n".join(all_text)
		
		frame_id += 1
	
	# submerged frames
	var frame_id_submerged: int = 0
	for frame: FrameData in frames_submerged:
		var frame_data: PackedStringArray = [
			name_alias + "-submerged",
			str(frame_id_submerged),
			str(frame.num_subframes),
			str(frame.y_rotation),
			str(frame.transparency_type),
			str(frame.transparency_flag),
		]
		frame_data_string = ",".join(frame_data)
		
		for subframe: SubFrameData in frame.subframes:
			var text_parts: PackedStringArray = [
				frame_data_string,
				str(subframe.shift_x),
				str(subframe.shift_y),
				str(subframe.load_location_x),
				str(subframe.load_location_y),
				str(subframe.rect_size.x),
				str(subframe.rect_size.y),
				str(subframe.flip_x),
				str(subframe.flip_y)]
			
			frame_data_string = ",".join(text_parts);
		
		var all_text: PackedStringArray = [output, frame_data_string]
		output = "\n".join(all_text)
		
		frame_id_submerged += 1
	
	DirAccess.make_dir_recursive_absolute("user://FFTae")
	var save_file: FileAccess = FileAccess.open("user://FFTae/frame_data_"+file_name+".txt", FileAccess.WRITE)
	save_file.store_string(output)
	
	if (file_name.begins_with("wep") || file_name.begins_with("eff")):
		var frame_offset_headers: PackedStringArray = [
			"Knife",
			"Ninja Sword",
			"Sword",
			"Knight Sword",
			"Katana",
			"Axe",
			"Rod",
			"Staff",
			"Flail",
			"Gun",
			"Crossbow",
			"Bow",
			"Instrument",
			"Book",
			"Spear",
			"Pole",
			"Bag",
			"Cloth",
			"Shield",
			"Shuriken",
			"Ball",
		]
		var frame_offset_data:String = ",".join(frame_offset_headers)
		frame_offset_data = frame_offset_data + "\n"
		
		frame_offset_data = frame_offset_data + ",".join(zero_frames)
		var save_file_offset:FileAccess = FileAccess.open("user://FFTorama/frame_offset_data_"+file_name+".txt", FileAccess.WRITE)
		save_file_offset.store_string(frame_offset_data);


func create_blank_frame(color: Color = Color.TRANSPARENT, new_frame_size: Vector2i = frame_size) -> Image:
	var blank_image: Image = Image.create(
		new_frame_size.x, new_frame_size.y, false, Image.FORMAT_RGBA8
	)
	blank_image.fill(color)
	
	return blank_image


func get_assembled_frame(frame_index: int, source_image: Image, animation_ptr_index: int, 
		other_type_index: int, weapon_v_offset: int, submerged_depth: int, new_frame_size: Vector2i = frame_size, y_offset: int = 40) -> Image:
	var frame: FrameData = get_frame(frame_index, submerged_depth)
	var assembled_image: Image = create_blank_frame(Color.TRANSPARENT, new_frame_size)
	
	for subframe_index: int in range(frame.num_subframes-1, -1, -1): # reverse order to layer them correctly
		var v_offset: int = get_v_offset(frame_index, subframe_index, animation_ptr_index, other_type_index, weapon_v_offset, submerged_depth)
		assembled_image = add_subframe(frame.subframes[subframe_index], source_image, assembled_image, v_offset, new_frame_size, y_offset)
	
	return assembled_image


func get_v_offset(frame_index:int, subframe_index:int, animation_ptr_index: int, other_type_index: int, weapon_v_offset: int, submerged_depth: int) -> int:
	var v_offset: int = 0
	#var y_top: int = get_frame(frame_index, submerged_depth).subframes[subframe_index].load_location_y
	if frame_index >= attack_start_index:
		v_offset += 256
	
	if file_name.contains("WEP"):
		v_offset = weapon_v_offset
	elif file_name.contains("OTHER"):
		v_offset = other_type_index * 24 * 2 # 2 rows each of chicken and frog frames
	elif file_name.contains("MON"): # if y_top left is in bottom half, check if it should look into sp2
		if CONSTANT_SP2_V_OFFSETS.has(animation_ptr_index):
			v_offset = CONSTANT_SP2_V_OFFSETS[animation_ptr_index]
		elif animation_ptr_index >= SP2_START_ANIMATION_ID:
			v_offset = SP2_V_OFFSET + SP2_V_OFFSET2
	
	return v_offset


func add_subframe(subframe: SubFrameData, source_image: Image, assembled_image: Image, v_offset: int, new_frame_size: Vector2i = frame_size, y_offset: int = 40) -> Image:
	var y_top_left: int = subframe.load_location_y + v_offset
	
	@warning_ignore("integer_division")
	var destination_pos: Vector2i = Vector2i(subframe.shift_x + (new_frame_size.x / 2), subframe.shift_y + new_frame_size.y - y_offset) # adjust by 40 (for full 120px size frame) to prevent frame from spilling over bottom
	var source_rect: Rect2i = Rect2i(subframe.load_location_x, y_top_left, subframe.rect_size.x, subframe.rect_size.y)
	
	if (subframe.flip_x or subframe.flip_y):
		var flipped_image: Image = Image.create(
			source_rect.size.x, source_rect.size.y, false, Image.FORMAT_RGBA8
		)
		flipped_image.blend_rect(source_image, source_rect, Vector2i.ZERO)
		if (subframe.flip_x):
			flipped_image.flip_x()
		if (subframe.flip_y):
			flipped_image.flip_y()
		
		source_rect = Rect2i(0, 0, subframe.rect_size.x, subframe.rect_size.y)
		source_image = flipped_image
	
	assembled_image.blend_rect(source_image, source_rect, destination_pos)
	#assembled_image.blit_rect(source_image, source_rect, destination_pos)
	return assembled_image
