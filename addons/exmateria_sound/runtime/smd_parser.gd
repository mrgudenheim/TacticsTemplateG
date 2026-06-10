class_name SMDParser
## Parse MUSIC_##.SMD files into track event lists.


class SMDFile:
	var track_count: int = 0
	var initial_tempo: int = 0
	var initial_volume: int = 0
	var assoc_wds_id: int = 0
	var song_title: String = ""
	var track_events: Array = []  # Array of Array[NoteEvent|OpcodeEvent]

	var initial_bpm: float:
		get:
			return SMDOpcodes.fft_tempo_to_bpm(initial_tempo)


static func load_from_file(path: String) -> SMDFile:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open SMD: " + path)
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	return parse(data)


static func parse(data: PackedByteArray) -> SMDFile:
	if data.size() < 0x22:
		push_error("SMD too small")
		return null

	# Check magic "smds"
	if char(data[0]) != 's' or char(data[1]) != 'm' or char(data[2]) != 'd' or char(data[3]) != 's':
		push_error("Invalid SMD magic")
		return null

	var smd := SMDFile.new()
	var file_size := _read_u16(data, 0x08)
	smd.track_count = data[0x14]
	smd.assoc_wds_id = _read_u16(data, 0x16)
	smd.initial_volume = data[0x18]
	smd.initial_tempo = data[0x1A]

	var song_title_ptr := _read_u16(data, 0x1E)
	var drumkit_ptr := _read_u16(data, 0x20)

	# Track pointers at 0x22
	var track_ptrs: PackedInt32Array = []
	for i in range(smd.track_count):
		var offset := 0x22 + i * 2
		if offset + 2 > data.size():
			break
		track_ptrs.append(_read_u16(data, offset))

	# Song title
	if song_title_ptr > 0 and song_title_ptr < data.size():
		var title_end := track_ptrs[0] if track_ptrs.size() > 0 else data.size()
		title_end = mini(title_end, data.size())
		var title_bytes := data.slice(song_title_ptr, title_end)
		# Strip trailing nulls
		var end_idx := title_bytes.size()
		for i in range(title_bytes.size()):
			if title_bytes[i] == 0:
				end_idx = i
				break
		smd.song_title = title_bytes.slice(0, end_idx).get_string_from_ascii()

	# Decode each track
	smd.track_events = []
	for i in range(track_ptrs.size()):
		var ptr: int = track_ptrs[i]
		var end: int
		if i + 1 < track_ptrs.size():
			end = track_ptrs[i + 1]
		elif file_size > 0:
			end = file_size
		else:
			end = data.size()
		ptr = mini(ptr, data.size())
		end = mini(end, data.size())

		var track_data := data.slice(ptr, end)
		var events := SMDOpcodes.decode_track(track_data, track_data.size())
		smd.track_events.append(events)

	return smd


static func char(b: int) -> String:
	return String.chr(b)

static func _read_u16(data: PackedByteArray, offset: int) -> int:
	return data[offset] | (data[offset+1] << 8)
