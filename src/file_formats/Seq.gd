class_name Seq

var is_initialized: bool = false

static var seq_aliases: Dictionary[String, String] = {
	"ARUTE.SEQ":"Altima/arute",
	"CYOKO.SEQ":"Chocobo/cyoko",
	"EFF1.SEQ":"eff1",
	"EFF2.SEQ":"eff2 (Unused)",
	"KANZEN.SEQ":"Altima2/kanzen",
	"MON.SEQ":"Monster/mon",
	"OTHER.SEQ":"other",
	"RUKA.SEQ":"Lucavi/ruka",
	"TYPE1.SEQ":"type1",
	"TYPE2.SEQ":"type2 (Unused)",
	"TYPE3.SEQ":"type3",
	"TYPE4.SEQ":"type4 (Unused)",
	"WEP1.SEQ":"wep1",
	"WEP2.SEQ":"wep2"}

# LoadFrameAndWait with 0 delay is also an animation end
const ending_opcodes: PackedStringArray = [
	"IncrementLoop",
	"PauseAnimation",
	"EndAnimation",
	"HoldWeapon",
	"ffc2",
	]


var shp_name: String:
	get:
		match file_name.to_upper().trim_suffix(".SEQ"):
			"TYPE1":
				return "TYPE1.SHP"
			"TYPE3":
				return "TYPE2.SHP"
			"CYOKO":
				return "CYOKO.SHP"
			"MON":
				return "MON.SHP"
			"OTHER":
				return "OTHER.SHP"
			"RUKA":
				return "MON.SHP"
			"ARUTE":
				return "ARUTE.SHP"
			"KANZEN":
				return "KANZEN.SHP"
			"WEP1":
				return "WEP1.SHP"
			"WEP2":
				return "WEP2.SHP"
			"EFF1":
				return "EFF1.SHP"
			_:
				push_warning(file_name.to_upper() + " - Can't find associate Shp name")
				return "TYPE1.SHP"


var file_name: String = "default_file_name"
var name_alias: String = "default_name_alias"

# section 1
var AA: int = 0
var BB: int = 0
var section1_length: int = 4

# section 2
var sequence_pointers: Array[int] = []
var section2_length: int = 0x400
	
# section 3
var sequences: Array[Sequence] = []
var section3_length: int = 0:
	get:
		var sum: int = 2
		for sequence: Sequence in sequences:
			sum += sequence.length
		return sum

var toal_length: int = 0:
	get:
		return section1_length + section2_length + section3_length

static var opcode_parameters: Dictionary[String, int] = {}
static var opcode_parameters_by_name: Dictionary[String, int] = {}
static var opcode_names: Dictionary[String, String] = {}
static var seq_names: Dictionary[String, PackedStringArray] = {} # [name_alias, [seq_index, seq_name]]


static func _static_init() -> void:
	load_opcode_data()
	load_seq_name_data()


func _init(new_file_name: String) -> void:
	set_name(new_file_name)


func set_data_from_seq_object(seq_object:Seq) -> void:
	file_name = seq_object.file_name
	name_alias = seq_object.name_alias

	# section 1
	AA = seq_object.AA
	BB = seq_object.BB

	# section 2
	sequence_pointers = seq_object.sequence_pointers.duplicate()
	
	# section 3
	sequences = seq_object.sequences.duplicate()


func set_data_from_seq_file(filepath:String) -> void:
	var new_file_name:String = filepath.get_file()
	set_name(new_file_name)
	
	var bytes:PackedByteArray = FileAccess.get_file_as_bytes(filepath)
	if bytes.size() == 0:
		push_warning("Open Error: " + filepath)
		return


func set_name(new_file_name: String) -> void:
	#new_file_name = new_file_name.trim_suffix(".seq")
	#new_file_name = new_file_name.trim_suffix(".SEQ")
	#new_file_name = new_file_name.trim_suffix(".Seq")
	#new_file_name = new_file_name.to_lower()
	
	file_name = new_file_name
	
	if seq_aliases.has(file_name):
		name_alias = seq_aliases[file_name]
	else:
		name_alias = file_name


func set_data_from_seq_bytes(bytes: PackedByteArray) -> void:
	if is_initialized:
		return
	
	AA = bytes.decode_u16(0)
	BB = bytes.decode_u16(2)
	
	# get pointers
	sequence_pointers.clear()
	for seq_index: int in (section2_length / 4):
		var seq_pointer: int = bytes.decode_u32(section1_length + (seq_index * 4))
		if seq_index > 0 and seq_pointer == 0xFFFFFFFF:
			break # skip to section 3 if no more pointers in section 2
		sequence_pointers.append(seq_pointer)
	
	var sequence_data_start: int = section1_length + section2_length + 2
	var section3_length_temp: int = bytes.decode_u16(sequence_data_start - 2)
	sequences.clear()
	#for seq_pointer in sequence_pointers:
		#var seq_offset:int = sequence_data_start + seq_pointer
	
	var sequence_start_index: int = sequence_data_start
	var sequence_end_index: int = sequence_data_start # will be overwritten
	var byte_index: int = sequence_data_start
	var sequence_bytes: PackedByteArray = []
	while byte_index < (sequence_data_start + section3_length_temp):
		var potential_opcode: String = "%02x%02x" % [bytes.decode_u8(byte_index), bytes.decode_u8(byte_index + 1)]
		if opcode_parameters.has(potential_opcode):
			byte_index += 2 + opcode_parameters[potential_opcode] # move past the opcode and its parameters
			if ending_opcodes.has(opcode_names[potential_opcode]):
				sequence_end_index = byte_index
				sequence_bytes = bytes.slice(sequence_start_index, sequence_end_index)
				sequences.append(get_sequence_data(sequence_bytes))
				sequence_start_index = byte_index
		else:
			byte_index += 2 # move past LoadFrameWait's 2 parameters
			if potential_opcode.right(2) == "00": # if LoadFrameWait with 00 delay
				sequence_end_index = byte_index
				sequence_bytes = bytes.slice(sequence_start_index, sequence_end_index)
				sequences.append(get_sequence_data(sequence_bytes))
				sequence_start_index = byte_index
	
	for index: int in sequence_pointers.size():
		sequence_pointers[index] = get_pointer_from_address(sequence_pointers[index])
	set_sequence_names()
	
	is_initialized = true


func get_pointer_address(pointer: int) -> int:
	var address: int = 0
	var index: int = 0
	while index < pointer:
		address += sequences[index].length
		index += 1
	
	return address


func get_pointer_from_address(address: int) -> int:
	var index: int = 0
	var total_length: int = 0
	while total_length < address:
		total_length += sequences[index].length
		index += 1
	
	return index


func set_sequence_names() -> void:
	if seq_names.has(name_alias):
		#push_warning(sequence_pointers)
		#push_warning(seq_names[name_alias])
		for pointer_index: int in sequence_pointers.size():
			var pointer: int = sequence_pointers[pointer_index]
			if sequences[pointer].seq_name.is_empty() and seq_names[name_alias].size() > pointer_index: # if this is the first pointer to point to the sequence
				sequences[pointer].seq_name = seq_names[name_alias][pointer_index] # set name of the sequence
	
	# get animation names based on ability execution and job / monster type
	for job: JobData in RomReader.scus_data.jobs_data:
		var spr: Spr = RomReader.sprs[RomReader.get_spr_file_idx(job.sprite_id)]
		#spr.set_data()
		spr.set_spritesheet_data(job.sprite_id)
		if spr.seq_name != file_name:
			continue
		
		var job_type_name: String = job.display_name
		if job.job_id >= 0x5e and job.job_id <= 0x8d: # generic monsters
			job_type_name = RomReader.fft_text.job_names[0x5e + ((job.monster_type - 1) * 3)]
		
		for ability_id: int in RomReader.scus_data.skillsets_data[job.skillset_id].action_ability_ids:
			var ability: FftAbilityData = RomReader.fft_abilities[ability_id]
			if ability_id == 0: # skip empty abilities
				continue
			
			var animation_ptr_id: int = ability.animation_executing_id
			if animation_ptr_id == 0 or animation_ptr_id >= sequence_pointers.size(): # skip attack animation and if seq does not have enough pointers
				continue
			
			var sequence_id: int = sequence_pointers[animation_ptr_id]
			if sequences[sequence_id].seq_name.contains(ability.display_name): # skip if ability name is already listed
				continue
			if sequences[sequence_id].seq_name != "":
				sequences[sequence_id].seq_name += "\n"
				sequences[sequence_pointers[animation_ptr_id + 1]].seq_name += "\n"
			else: # indicate front or back
				sequences[sequence_id].seq_name += "(Front)\n"
				sequences[sequence_pointers[animation_ptr_id + 1]].seq_name += "(Back)\n"
			
			if not sequences[sequence_id].seq_name.contains(job_type_name):
				sequences[sequence_id].seq_name += "-" + job_type_name + "-\n"
				sequences[sequence_pointers[animation_ptr_id + 1]].seq_name += "-" + job_type_name + "-\n"
			
			sequences[sequence_id].seq_name += ability.display_name
			sequences[sequence_pointers[animation_ptr_id + 1]].seq_name += ability.display_name


func get_sequence_data(bytes: PackedByteArray) -> Sequence:
	var seq:Sequence = Sequence.new()
	var seq_part_pointer: int = 0
	while seq_part_pointer < bytes.size():
		var seq_part:SeqPart = SeqPart.new()
		var num_params:int = 2
		if bytes.decode_u8(seq_part_pointer) == 0xFF:
			var opcode: String = "%x%x" % [bytes.decode_u8(seq_part_pointer), bytes.decode_u8(seq_part_pointer + 1)]
			#push_warning(opcode)
			seq_part.opcode = opcode
			seq_part.opcode_name = opcode_names[opcode]
			num_params = opcode_parameters[opcode]
			
		for param:int in num_params:
			var offset: int = seq_part_pointer + param
			if seq_part.isOpcode:
				offset += 2
			# signed parameters
			if (seq_part.opcode == "ffc0" # WaitForDistort
				or seq_part.opcode == "ffc4" # MFItemPosFBDU
				or seq_part.opcode == "ffc6" # WaitForInput
				or seq_part.opcode == "ffd3" # WeaponSheatheCheck1
				or seq_part.opcode == "ffd6" # WeaponSheatheCheck2
				or seq_part.opcode == "ffd8" # SetFrameOffset
				or seq_part.opcode == "ffee" # MoveUnitFB
				or seq_part.opcode == "ffef" # MoveUnitDU 
				or seq_part.opcode == "fff0" # MoveUnitRL
				or seq_part.opcode == "fffa" # MoveUnit RL, DU, FB
				or (seq_part.opcode == "fffc" && param == 0) # Wait (first parameter only)
				or seq_part.opcode == "fffd"): # HoldWeapon:
				seq_part.parameters.append(bytes.decode_s8(offset))
			else:
				seq_part.parameters.append(bytes.decode_u8(offset))
		
		seq.seq_parts.append(seq_part)
		seq_part_pointer += seq_part.length
	
	seq.update_length()
	return seq


func get_seq_bytes() -> PackedByteArray:
	#update_seq_pointers()
	var bytes: PackedByteArray = []
	bytes.resize(section1_length + section2_length + section3_length)
	bytes.fill(0)
	
	# section 1
	bytes.encode_u16(0, AA)
	bytes.encode_u16(2, BB)
	
	# section 2
	for seq_pointer_index: int in sequence_pointers.size():
		bytes.encode_u32(section1_length + (4 * seq_pointer_index), get_pointer_address(sequence_pointers[seq_pointer_index]))
	
	var sequence_pointers_length: int = sequence_pointers.size() * 4
	var section2_empty_length: int = section2_length - sequence_pointers_length
	for empty_index: int in section2_empty_length:
		bytes.encode_u8(section1_length + sequence_pointers_length + empty_index, 0xFF)
	
	# section 3
	bytes.encode_u16(section1_length + section2_length, section3_length - 2)
	var offset: int = section1_length + section2_length + 2
	for seq_index: int in sequences.size():
		for seq_part:SeqPart in sequences[seq_index].seq_parts:
			if seq_part.isOpcode:
				bytes.encode_u8(offset, 0xFF)
				bytes.encode_u8(offset + 1, seq_part.opcode.substr(2).hex_to_int())
				offset += 2
			for param:int in seq_part.parameters:
				bytes.encode_u8(offset, param)
				offset += 1
	
	return bytes


func write_seq(path: String) -> void:
	var bytes: PackedByteArray = get_seq_bytes()
	
	# clean up file name
	if path.get_slice(".", 1) != path and path.get_slice(".", 1).to_lower() == path.get_slice(".", 2).to_lower():
		path = path.trim_suffix(path.get_slice(".", 2))
	
	# save file
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var save_file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	save_file.store_buffer(bytes)


func set_data_from_cfg(filepath:String) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(filepath)
	#var err = cfg.load("user://FFTorama/"+file_name+"_shp.cfg")

	if err != OK:
		push_warning("Error Opening: " + str(err) + " - " + filepath)
		return
	
	file_name = filepath.get_file()
	file_name = file_name.trim_suffix("_seq.cfg")
	name_alias = cfg.get_value(file_name, "name_alias")
	
	AA = cfg.get_value(file_name, "AA")
	BB = cfg.get_value(file_name, "BB")
	sequence_pointers = cfg.get_value(file_name, "sequence_pointers")
	
	for seq_index:int in sequence_pointers.size():
		var seq_label: String = file_name + "-" + str(seq_index)
		var seq_data: Sequence = Sequence.new()
		var seq_parts_size: int = cfg.get_value(seq_label, "size")
		seq_data.seq_name = cfg.get_value(seq_label, "seq_name")
		
		for seq_part_index: int in seq_parts_size:
			var seq_part_label: String = seq_label + "-" + str(seq_part_index)
			var seq_part_data: SeqPart = SeqPart.new()
			seq_part_data.opcode = cfg.get_value(seq_part_label, "opcode")
			seq_part_data.opcode_name = cfg.get_value(seq_part_label, "opcode_name")
			seq_part_data.parameters = cfg.get_value(seq_part_label, "parameters")
			
			seq_data.seq_parts.append(seq_part_data)
			
		sequences.append(seq_data)


func write_wiki_table() -> void:
	var table_start: String = '{| class="wikitable mw-collapsible mw-collapsed sortable"\n|+ style="text-align:left; white-space:nowrap" | ' + name_alias + ' Full Table\n'
	var headers: PackedStringArray = [
		"! File",
		#"ID (Dec)",
		"ID (Hex)",
		"Description",
		"Opcodes",
	]
	
	var output: String = table_start + " !! ".join(headers)
	var output_array: PackedStringArray = []
	output_array.append(output)
	
	for seq_ptr_index: int in sequence_pointers.size():
		var seq_idx: int = sequence_pointers[seq_ptr_index]
		var seq_strings: PackedStringArray = []
		var seq_description: String = sequences[seq_idx].seq_name
		if seq_description == "":
			seq_description = "?"
		
		seq_strings.append("| " + name_alias) # File
		#seq_strings.append(str(seq_index)) # ID (Dec)
		seq_strings.append("0x%02x" % seq_ptr_index) # ID (Hex)
		seq_strings.append(seq_description.replace("\n", "<br>")) # Description
		seq_strings.append(sequences[seq_idx].to_string_hex("<br>")) # Opcodes
		output_array.append(" || ".join(seq_strings))
	
	var final_output: String = "\n|-\n".join(output_array)
	final_output += "\n|}"
	
	DirAccess.make_dir_recursive_absolute("user://wiki_tables")
	var save_file: FileAccess = FileAccess.open("user://wiki_tables/wiki_table_" + file_name + ".txt", FileAccess.WRITE)
	save_file.store_string(final_output)


func write_cfg() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(file_name, "file_name", file_name)
	cfg.set_value(file_name, "name_alias", name_alias)
	cfg.set_value(file_name, "AA", AA)
	cfg.set_value(file_name, "BB", BB)
	cfg.set_value(file_name, "sequence_pointers", sequence_pointers)
	
	for seq_index: int in sequences.size():
		var seq_label: String = file_name + "-" + str(seq_index)
		var seq_data:Sequence = sequences[seq_index]
		cfg.set_value(seq_label, "size", seq_data.seq_parts.size())
		cfg.set_value(seq_label, "seq_name", seq_data.seq_name)
		
		for seq_part_index: int in seq_data.seq_parts.size():
			var seq_part_label: String = seq_label + "-" + str(seq_part_index)
			var seq_part_data: SeqPart = seq_data.seq_parts[seq_part_index]
			cfg.set_value(seq_part_label, "opcode", seq_part_data.opcode)
			cfg.set_value(seq_part_label, "opcode_name", seq_part_data.opcode_name)
			cfg.set_value(seq_part_label, "parameters", seq_part_data.parameters)
	
	cfg.save("user://FFTorama/"+file_name+"_seq.cfg")


func set_sequences_from_csv(filepath:String) -> void:
	sequences.clear()
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		push_warning(FileAccess.get_open_error())
		return
	var sequence_data_csv:String = file.get_as_text()
	
	if file_name == "default_file_name":
		var new_file_name:String = filepath.get_file()
		new_file_name = new_file_name.trim_suffix(".csv")
		new_file_name = new_file_name.trim_suffix(".txt")
		new_file_name = new_file_name.trim_prefix("animation_data_")
		new_file_name = new_file_name.to_lower()
		
		file_name = new_file_name
		name_alias = new_file_name
	
	var sequences_split:PackedStringArray = sequence_data_csv.split("\n")
	sequences_split = sequences_split.slice(1, sequences_split.size()) # skip first row of headers
	
	var seq_part_start:int = 3 # skip past label, seq_id, and seq_name
	
	name_alias = sequences_split[0].split(",")[0]
	
	for seq_text:String in sequences_split:
		var seq_text_split:PackedStringArray = seq_text.split(",")
		var new_seq:Sequence = Sequence.new()
		new_seq.seq_name = seq_text_split[2]
		seq_text_split = seq_text_split.slice(seq_part_start)
		
		var index:int = 0
		while index < seq_text_split.size():
			var seq_part:SeqPart = SeqPart.new()
			var initial:String = seq_text_split[index]
			if opcode_names.values().has(initial):
				seq_part.opcode_name = initial
				seq_part.opcode = opcode_parameters.keys()[opcode_parameters.values().find(initial)]
				var num_params:int = opcode_parameters[seq_part.opcode]
				for param_index:int in num_params:
					seq_part.parameters.append(seq_text_split[index + param_index].to_int())
				
				index += num_params + 1
			else:
				for param_index:int in 2:
					seq_part.parameters.append(seq_text_split[index + param_index].to_int())
					
				index += 2
				
			new_seq.seq_parts.append(seq_part)
		
		sequences.append(new_seq)


func write_csv() -> void:
	var headers: PackedStringArray = [
		"label",
		"seq_id",
		"seq_name",
		"frame_id/opcode",
		"delay/parameter",
	]
	
	var output: String = ",".join(headers)
	var seq_data_string: String = ""
	
	var seq_id:int = 0
	for seq:Sequence in sequences:
		var seq_data: PackedStringArray = [
			name_alias,
			str(seq_id),
			str(seq.seq_name),
		]
		seq_data_string = ",".join(seq_data)
		
		for seq_part:SeqPart in seq.seq_parts:
			var text_parts: PackedStringArray = [seq_data_string]
			
			if seq_part.isOpcode:
				text_parts.append(seq_part.opcode_name)
			if seq_part.parameters.size() > 0:
				text_parts.append(",".join(seq_part.parameters))

			seq_data_string = ",".join(text_parts);
		
		var allText: PackedStringArray = [output, seq_data_string];
		output = "\n".join(allText)
	
		seq_id += 1

	DirAccess.make_dir_recursive_absolute("user://FFTorama")
	var save_file: FileAccess = FileAccess.open("user://FFTorama/animation_data_" + file_name + ".txt", FileAccess.WRITE)
	save_file.store_string(output)


# https://ffhacktics.com/wiki/SEQ_%26_Animation_info_page
static func load_opcode_data(use_rewrite_opcodes: bool = false) -> void:
	opcode_names.clear()
	opcode_parameters.clear()
	opcode_parameters_by_name.clear()
	
	var opcode_filepath: String = "res://src/fftae/SeqData/opcodeParameters.txt"
	var animation_rewrite_opcodes_filepath: String = "res://src/fftae/SeqData/animation_rewrite_opcodes.txt"
	
	load_opcode_file(opcode_filepath)
	if use_rewrite_opcodes:
		load_opcode_file(animation_rewrite_opcodes_filepath)


static func load_opcode_file(file_path: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	var input: String = file.get_as_text()
	
	var lines: PackedStringArray = input.split("\n");
	
	# skip first row of headers
	var line_index: int = 1
	while line_index < lines.size():
		var parts: PackedStringArray = lines[line_index].split(",")
		if parts.size() <= 2:
			line_index += 1
			continue
		
		var opcode_code: String = parts[2].substr(0, 4) # ignore any extra characters in text file
		var opcode_name: String = parts[0]
		var opcode_num_parameters: int = parts[1] as int
		
		opcode_names[opcode_code] = opcode_name
		opcode_parameters[opcode_code] = opcode_num_parameters
		opcode_parameters_by_name[opcode_name] = opcode_num_parameters
		
		line_index += 1


static func load_seq_name_data() -> void:
	var filepath: String = "res://src/fftae/SeqData/animation_names.txt"
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	var input: String = file.get_as_text()
	
	var lines: PackedStringArray = input.split("\n");

	# skip first row of headers
	var line_index:int = 1
	while line_index < lines.size():
		var parts: PackedStringArray = lines[line_index].split(",")
		if parts.size() <= 2:
			line_index += 1
			continue
		
		if not seq_names.has(parts[0]):
			seq_names[parts[0]] = PackedStringArray()
		if seq_names[parts[0]].size() <= parts[1].to_int():
			seq_names[parts[0]].resize(parts[1].to_int() + 1)
		
		seq_names[parts[0]][parts[1].to_int()] = parts[2]
		
		line_index += 1
