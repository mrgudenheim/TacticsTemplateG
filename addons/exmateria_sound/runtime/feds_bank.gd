class_name FedsBank
## Parse an FFT "feds" sound-definition blob (from E###.BIN or ENV.SED).
##
## feds is the same opcode language as SMD, but wrapped in a different header
## that carries a u16 channel-offset table grouped into pairs. The game picks
## a pair via (config_channel * 4) + 0x14 as a pointer into that table; each
## pair = two channels = two voices.
##
## This parser is a port of research/tools/extract_feds.py.
## Reference: research/wiki_articles/sound_section.txt §1


var magic: String = ""
var data_size: int = 0            # From header; may exclude the magic+header itself
var pair_count_plus1: int = 0     # num_pairs = pair_count_plus1 - 1
var resource_id: int = 0          # Runtime SPU VRAM bank (g_base = id << 16)
var data_offset: int = 0          # Offset (inside feds blob) where opcode streams begin
var channel_offsets: PackedInt32Array = PackedInt32Array()  # Per-channel u16 offsets
var raw: PackedByteArray = PackedByteArray()


var num_pairs: int:
	get:
		return maxi(0, pair_count_plus1 - 1)

var num_channels: int:
	get:
		return num_pairs * 2


static func load_from_file(path: String) -> FedsBank:
	## Auto-detect raw feds blob (ENV.SED / feds.bin / *.feds) vs E###.BIN
	## (slice feds out via header[0x20]).
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("FedsBank: cannot open " + path)
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() >= 4 and bytes[0] == 0x66 and bytes[1] == 0x65 \
			and bytes[2] == 0x64 and bytes[3] == 0x73:
		return parse(bytes)
	return _load_from_effect_bin(bytes, path)


static func _load_from_effect_bin(bytes: PackedByteArray, path: String) -> FedsBank:
	if bytes.size() < 0x28:
		push_error("FedsBank: %s too small for E###.BIN header" % path)
		return null
	# CODE-format E###.BIN files prefix MIPS code (first word 0x27BDxxxx).
	# Header pointers are relative to the embedded header, not file start.
	# For DATA-format files the embedded header is at 0, giving base=0.
	var base := _find_code_header_offset(bytes)
	var sound_def_ptr := base + _read_u32(bytes, base + 0x20)
	var texture_ptr := base + _read_u32(bytes, base + 0x24)
	var raw_u32 := _read_u32(bytes, base + 0x20)
	if raw_u32 == 0 or texture_ptr <= sound_def_ptr or sound_def_ptr >= bytes.size():
		push_error("FedsBank: %s has no feds section" % path)
		return null
	return parse(bytes.slice(sound_def_ptr, mini(texture_ptr, bytes.size())))


static func _find_code_header_offset(bytes: PackedByteArray) -> int:
	# DATA format (most effects): embedded header at offset 0.
	# CODE format: first word matches 0x27BDxxxx (MIPS `addiu sp, sp, -X`).
	if bytes.size() < 4:
		return 0
	var w := _read_u32(bytes, 0)
	if (w & 0xFFFF0000) != 0x27BD0000:
		return 0
	# Scan forward for a plausible header: frames_ptr is typically 0x28 and
	# pointers must be monotonically increasing into the file.
	var limit := mini(bytes.size() - 0x28, 0x400)
	var off := 4
	while off <= limit:
		var frames_ptr := _read_u32(bytes, off + 0x00)
		if frames_ptr == 0x28:
			# Sanity-check: animation_ptr > frames_ptr and < file size.
			var anim_ptr := _read_u32(bytes, off + 0x04)
			if anim_ptr > frames_ptr and (off + anim_ptr) < bytes.size():
				return off
		off += 4
	return 0


static func parse(bytes: PackedByteArray) -> FedsBank:
	if bytes.size() < 0x18:
		push_error("FedsBank: blob too small (%d bytes)" % bytes.size())
		return null

	var fb := FedsBank.new()
	fb.raw = bytes
	fb.magic = bytes.slice(0, 4).get_string_from_ascii()
	if fb.magic != "feds":
		push_error("FedsBank: bad magic %s" % fb.magic)
		return null

	fb.data_size = _read_u32(bytes, 0x04)
	fb.pair_count_plus1 = _read_u16(bytes, 0x08)
	fb.resource_id = _read_u16(bytes, 0x0A)
	fb.data_offset = _read_u32(bytes, 0x0C)

	var offsets := PackedInt32Array()
	offsets.resize(fb.num_channels)
	for i in range(fb.num_channels):
		offsets[i] = _read_u16(bytes, 0x18 + i * 2)
	fb.channel_offsets = offsets
	return fb


func channel_size(channel_idx: int) -> int:
	if channel_idx < 0 or channel_idx >= num_channels:
		return 0
	var start: int = channel_offsets[channel_idx]
	# Walk forward looking for a later, larger offset — channels are not
	# guaranteed to be ordered in the table, but successive channels in a
	# pair usually are.
	var end := data_size
	for j in range(num_channels):
		var o: int = channel_offsets[j]
		if o > start and o < end:
			end = o
	return maxi(0, end - start)


func get_channel_bytes(channel_idx: int) -> PackedByteArray:
	if channel_idx < 0 or channel_idx >= num_channels:
		return PackedByteArray()
	var start: int = channel_offsets[channel_idx]
	var size := channel_size(channel_idx)
	var end := mini(start + size, raw.size())
	return raw.slice(start, end)


func get_channel_events(channel_idx: int) -> Array:
	## Decode one channel's bytes into SMD NoteEvent/OpcodeEvent objects.
	var bytes := get_channel_bytes(channel_idx)
	if bytes.is_empty():
		return []
	return SMDOpcodes.decode_track(bytes, bytes.size())


func get_channel_bytes_from(channel_idx: int) -> PackedByteArray:
	## Bytes from this channel's offset to end-of-feds-data, NOT bounded by
	## the next channel's offset.
	##
	## FFT's bytecode walker advances byte-by-byte through RAM without a
	## per-channel boundary concept — when a stub channel like cure_4 pair 2
	## ch A (`D2 08`, no 0x90 EndBar) finishes its 2 bytes, the dispatcher
	## continues into channel 5's `BA AC 88 ... 60 C1 90` bytecode and
	## dispatches its rk=10 Note. The 0x90 EndBar opcode is what actually
	## terminates a channel; channels without EndBar flow into the next.
	## See VOICE_18_KON_NEVER_FIRES.md follow-up.
	if channel_idx < 0 or channel_idx >= num_channels:
		return PackedByteArray()
	var start: int = channel_offsets[channel_idx]
	var end := mini(data_size, raw.size())
	return raw.slice(start, end)


func get_channel_events_from(channel_idx: int) -> Array:
	## Decode bytes from this channel's offset to end-of-feds-data. The
	## dispatcher will hit a 0x90 EndBar before reaching the end on
	## non-stub channels; stub channels (no EndBar) flow into subsequent
	## channels' bytecode, matching FFT's RAM-byte-walker semantics.
	var bytes := get_channel_bytes_from(channel_idx)
	if bytes.is_empty():
		return []
	return SMDOpcodes.decode_track(bytes, bytes.size())


func get_pair_events(pair_idx: int) -> Array:
	## Returns [channel_a_events, channel_b_events] for a pair.
	if pair_idx < 0 or pair_idx >= num_pairs:
		return [[], []]
	var a := get_channel_events(pair_idx * 2)
	var b := get_channel_events(pair_idx * 2 + 1)
	return [a, b]


## --- chan+0x92 static seed ---
## Mirrors FFT FUN_80013B20 PC 0x80013BEC-0x80013C30 — see
## research/effect_sound/working_documents/CHAN_92_STATIC_PORT_PLAN.md.
##
##     instr_byte = raw[data_offset + sound_id]
##     shifted    = (0x6000 * instr_byte) >> 7
##     chan_92    = 0x7FFF if (shifted >> 15) & 1 else shifted
##
## Phase 0 verified data_offset's upper 16 bits are zero for every
## E###.BIN — no masking needed. sound_id is the low 16 bits of the
## play_sound key (TIER 2 lookup_sound_effect).

const CHAN_92_MULTIPLIER := 0x6000
const CHAN_92_SATURATE := 0x7FFF


func instr_byte_for(sound_id: int) -> int:
	var off := data_offset + sound_id
	if off < 0 or off >= raw.size():
		push_error("FedsBank: sound_id %d -> off %d outside raw size %d"
				% [sound_id, off, raw.size()])
		return 0
	return raw[off]


func chan_92_for(sound_id: int) -> int:
	var b := instr_byte_for(sound_id)
	var shifted := (CHAN_92_MULTIPLIER * b) >> 7
	if (shifted >> 15) & 1:
		return CHAN_92_SATURATE
	return shifted


func make_synthetic_smd(pair_idx: int) -> SMDParser.SMDFile:
	## Wrap a feds pair in an SMDFile-shaped object so Sequencer.load_smd()
	## can consume it unchanged. Track 0 is an empty conductor; tracks 1-2
	## are the pair's two channels, mapped to voice_idx 0 and 1.
	var smd := SMDParser.SMDFile.new()
	smd.track_count = 3
	smd.initial_tempo = 0      # Sequencer falls back to 120 BPM
	smd.initial_volume = 0x7F
	smd.assoc_wds_id = 0       # Share WAVESET.WD with music
	smd.song_title = "feds_pair_%d" % pair_idx
	var pair := get_pair_events(pair_idx)
	smd.track_events = [[], pair[0], pair[1]]
	return smd


static func _read_u16(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8)


static func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] \
		| (bytes[offset + 1] << 8) \
		| (bytes[offset + 2] << 16) \
		| (bytes[offset + 3] << 24)
