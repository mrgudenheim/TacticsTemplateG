class_name WavesetParser
## Parse WAVESET.WD, pre-decode each instrument's ADPCM to PCM.
## Follows PCSX-Redux SPU behavior: voices stop at LOOP_END unless
## LOOP_REPEAT is also set (flags == 3).

const ADPCM_FILTER := [
	[0, 0], [60, 0], [115, -52], [98, -55], [122, -60],
]

const BLOCK_SIZE := 16
const SAMPLES_PER_BLOCK := 28
const FLAG_LOOP_END := 0x01
const FLAG_LOOP_REPEAT := 0x02
const FLAG_LOOP_START := 0x04


class Instrument:
	var index: int = 0
	var fine_tune: int = 0
	var adsr1: int = 0
	var adsr2: int = 0
	# FFT instrument-load (PC 0x80016FFC-0x80017014) writes inst byte
	# 0xd → slot+0x58 (HIGH mode), byte 0xe → slot+0x5c (LOW mode),
	# byte 0xf → slot+0x60 (CA mode). These are full 0-7 mode bytes
	# the walker reads for ADSR2 mode-bit table lookup. Prior parsing
	# extracted only bit 2 of ab[6]/ab[7], losing the input value the
	# walker needs. iter-24: preserve full bytes.
	# See docs/MUSIC_ITER24_WAVESET_MODE_BYTES_DROPPED.md.
	var mode_byte_58: int = 0
	var mode_byte_5c: int = 0
	var mode_byte_60: int = 0
	# Raw release_rate (5 bits, 0-31) from waveset byte 3 low 5 bits.
	# Iter-32: FFT's instrument-load fan-out populates slot+0x6A with
	# this value; the walker's ADSR2-LOW writer reads slot+0x6A as the
	# rate input independent of the standing ADSR2 register's low bits.
	# See docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
	var release_rate_byte: int = 0
	var is_null: bool = true
	var sample_offset: int = 0
	var sample_size: int = 0
	var pcm_data: PackedInt32Array   # Per-instrument decoded PCM
	var pcm_offset: int = 0          # Always 0 for compat with sequencer
	var loop_start: int = -1         # Sample index for loop, -1 if no loop
	var loop_offset_bytes: int = -1  # ADPCM byte offset of LOOP_START, -1 if absent
	var has_explicit_loop_start: bool = false
	var has_loop_repeat: bool = false
	var start_offset_bytes: int = 0
	var start_sample_skip: int = 0


var instruments: Array[Instrument] = []
var adpcm_data: PackedByteArray = PackedByteArray()
# Kept for sequencer compatibility; unused with per-instrument arrays
var shared_pcm: PackedInt32Array = PackedInt32Array()


func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open WAVESET: " + path)
		return false
	var data := file.get_buffer(file.get_length())
	file.close()
	return parse(data)


func parse(data: PackedByteArray) -> bool:
	if data.size() < 0x20:
		return false
	if char(data[0]) != 'd' or char(data[1]) != 'w' or char(data[2]) != 'd' or char(data[3]) != 's':
		return false

	var data_offset := _read_u32(data, 0x10)
	var num_entries := (data_offset - 0x20) / 16
	adpcm_data = data.slice(data_offset, data.size())

	instruments.clear()
	instruments.resize(num_entries)

	for i in range(num_entries):
		var inst := Instrument.new()
		inst.index = i
		var ent_off := 0x20 + i * 16
		var sample_offset := _read_u32(data, ent_off)
		var sample_size := _read_u16(data, ent_off + 4)
		inst.sample_offset = sample_offset
		inst.sample_size = sample_size
		inst.fine_tune = _read_s16(data, ent_off + 6)

		var ab := data.slice(ent_off + 8, ent_off + 16)
		# Mode bits for sustain / release come from bytes 6 and 7 of the
		# waveset entry. `ab[6] bit 2` → sustain_mode_exp, `ab[7] bit 2` →
		# release_mode_exp. Entries with ab[6]=0x03/ab[7]=0x03 produce
		# linear modes; entries with ab[6]=0x07/ab[7]=0x07 produce
		# exponential.
		var ar := ab[0] & 0x7F
		var dr := ab[1] & 0xF
		var sr := ab[2] & 0x7F
		var rr := ab[3] & 0x1F
		var sl := ab[4] & 0xF
		var sm := (ab[6] >> 2) & 1
		var rm := (ab[7] >> 2) & 1
		inst.adsr1 = (ar << 8) | (dr << 4) | sl
		inst.adsr2 = (sm << 15) | (1 << 14) | (sr << 6) | (rm << 5) | rr
		# iter-24: preserve FULL mode bytes (FFT walker reads these
		# as 0-7 mode selectors for ADSR2 HIGH/LOW writer tables).
		# ab[5] = inst byte 0xd → slot+0x58 (HIGH); ab[6] = byte 0xe
		# → slot+0x5c (LOW); ab[7] = byte 0xf → slot+0x60 (0xCA mode).
		inst.mode_byte_58 = ab[5] & 0xFF
		inst.mode_byte_5c = ab[6] & 0xFF
		inst.mode_byte_60 = ab[7] & 0xFF
		inst.release_rate_byte = rr

		if sample_offset == 0 and sample_size == 0:
			inst.is_null = true
			instruments[i] = inst
			continue

		inst.is_null = false
		var adpcm_start := data_offset + sample_offset
		var adpcm_end := adpcm_start + sample_size
		if adpcm_end > data.size():
			adpcm_end = data.size()
		var adpcm_slice := data.slice(adpcm_start, adpcm_end)
		if adpcm_slice.size() >= BLOCK_SIZE and adpcm_slice.slice(0, BLOCK_SIZE) == PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]):
			inst.start_offset_bytes = BLOCK_SIZE
			inst.start_sample_skip = SAMPLES_PER_BLOCK
		var result := _decode_adpcm(adpcm_slice)
		inst.pcm_data = result[0]
		inst.loop_start = result[1]
		inst.loop_offset_bytes = result[2]
		inst.has_explicit_loop_start = result[3]
		inst.has_loop_repeat = result[4]
		instruments[i] = inst

	print("WavesetParser: loaded ", instruments.size(), " instruments (",
		  instruments.filter(func(i): return not i.is_null).size(), " active)")
	return true


func _decode_adpcm(data: PackedByteArray) -> Array:
	var pcm := PackedInt32Array()
	var loop_start := -1
	var loop_offset_bytes := -1
	var has_explicit_loop_start := false
	var has_loop_repeat := false
	var s_1 := 0
	var s_2 := 0
	var num_blocks := data.size() / BLOCK_SIZE

	for block_idx in range(num_blocks):
		var offset := block_idx * BLOCK_SIZE
		var header := data[offset]
		var shift_factor := header & 0x0F
		var predict_nr := mini((header >> 4) & 0x0F, 4)
		var flags := data[offset + 1]

		if flags & FLAG_LOOP_START:
			loop_start = pcm.size()
			loop_offset_bytes = offset
			has_explicit_loop_start = true
		if flags & FLAG_LOOP_REPEAT:
			has_loop_repeat = true

		var f0: int = ADPCM_FILTER[predict_nr][0]
		var f1: int = ADPCM_FILTER[predict_nr][1]

		for byte_idx in range(2, 16):
			var data_byte := data[offset + byte_idx]
			for nibble_shift in [0, 4]:
				var s: int = ((data_byte >> nibble_shift) & 0x0F) << 12
				if s & 0x8000:
					s |= ~0xFFFF
				var fa: int = s >> shift_factor
				fa = fa + ((s_1 * f0) >> 6) + ((s_2 * f1) >> 6)
				s_2 = s_1
				s_1 = fa
				pcm.append(clampi(fa, -32768, 32767))

		# Match PCSX-Redux: flags == 3 means loop back, any LOOP_END stops.
		# The loop_start marker may be set by FLAG_LOOP_START flag.
		if flags & FLAG_LOOP_END:
			if flags == 3 or (flags & FLAG_LOOP_REPEAT):
				# Will loop at playback time — loop_start should be set
				# If not explicitly set, loop from beginning
				if loop_start == -1:
					loop_start = 0
			# Stop decoding either way; playback handles looping
			break

	return [pcm, loop_start, loop_offset_bytes, has_explicit_loop_start, has_loop_repeat]


static func char(b: int) -> String:
	return String.chr(b)

static func _read_u32(data: PackedByteArray, offset: int) -> int:
	return data[offset] | (data[offset+1] << 8) | (data[offset+2] << 16) | (data[offset+3] << 24)

static func _read_u16(data: PackedByteArray, offset: int) -> int:
	return data[offset] | (data[offset+1] << 8)

static func _read_s16(data: PackedByteArray, offset: int) -> int:
	var v := data[offset] | (data[offset+1] << 8)
	if v & 0x8000:
		v -= 0x10000
	return v
