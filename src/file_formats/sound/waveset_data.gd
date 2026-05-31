class_name WavesetData
extends Resource
## Parses WAVESET.WD (a "dwds" instrument bank) and pre-decodes each
## instrument's PSX 4-bit ADPCM into PCM. Shared by SMD music and FEDS
## effect sounds. Lives in SOUND/ on the ISO.
##
## Header layout (little-endian):
##   0x00  4    magic "dwds"
##   0x10  u32  data_offset (start of ADPCM sample data)
##   0x20  instrument table: 16-byte entries until data_offset
##           +0x00 u32  sample_offset (relative to data_offset)
##           +0x04 u16  sample_size
##           +0x06 s16  fine_tune
##           +0x08 8 bytes  ADSR / mode bytes
##
## Follows PCSX-Redux SPU behaviour: voices stop at LOOP_END unless
## LOOP_REPEAT is also set (flags == 3).
##
## Ported from the godot-learning project (addons/exmateria_sound/runtime/
## waveset_parser.gd). The ADSR mode-byte and release-rate handling preserves
## the project's iter-24 / iter-32 fixes (see comments inline).

const MAGIC: String = "dwds"

const ADPCM_FILTER: Array = [
	[0, 0], [60, 0], [115, -52], [98, -55], [122, -60],
]

const BLOCK_SIZE: int = 16
const SAMPLES_PER_BLOCK: int = 28
const FLAG_LOOP_END: int = 0x01
const FLAG_LOOP_REPEAT: int = 0x02
const FLAG_LOOP_START: int = 0x04


class Instrument:
	var index: int = 0
	var fine_tune: int = 0
	var adsr1: int = 0
	var adsr2: int = 0
	# iter-24: preserve the FULL instrument-load mode bytes. The FFT walker
	# reads these as 0-7 mode selectors for the ADSR2 HIGH/LOW writer tables.
	# inst byte 0xd -> slot+0x58 (HIGH); 0xe -> slot+0x5c (LOW); 0xf -> slot+0x60.
	var mode_byte_58: int = 0
	var mode_byte_5c: int = 0
	var mode_byte_60: int = 0
	# iter-32: raw release_rate (5 bits) is fanned out to slot+0x6A, which the
	# ADSR2-LOW writer reads independently of the standing ADSR2 register.
	var release_rate_byte: int = 0
	var is_null: bool = true
	var sample_offset: int = 0
	var sample_size: int = 0
	var pcm_data: PackedInt32Array          # decoded PCM samples
	var pcm_offset: int = 0                  # always 0 (per-instrument arrays)
	var loop_start: int = -1                 # sample index for loop, -1 if none
	var loop_offset_bytes: int = -1          # ADPCM byte offset of LOOP_START
	var has_explicit_loop_start: bool = false
	var has_loop_repeat: bool = false
	var start_offset_bytes: int = 0
	var start_sample_skip: int = 0


@export var unique_name: String = "WAVESET"

var is_initialized: bool = false
var file_name: String = "WAVESET.WD"

var instruments: Array[Instrument] = []
var adpcm_data: PackedByteArray = PackedByteArray()


func _init(new_file_name: String = "") -> void:
	if new_file_name == "":
		return
	file_name = new_file_name
	unique_name = new_file_name.get_basename()


func init_from_file(waveset_bytes: PackedByteArray = RomReader.get_file_data(file_name), overwrite: bool = false) -> void:
	if is_initialized and not overwrite:
		return

	if waveset_bytes.size() < 0x20:
		push_warning(file_name + ": WAVESET too small (" + str(waveset_bytes.size()) + " bytes). Skipping.")
		return
	if waveset_bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		push_warning(file_name + ": invalid WAVESET magic. Skipping.")
		return

	var data_offset: int = waveset_bytes.decode_u32(0x10)
	var num_entries: int = (data_offset - 0x20) / 16
	adpcm_data = waveset_bytes.slice(data_offset, waveset_bytes.size())

	instruments.clear()
	instruments.resize(num_entries)

	for instrument_index: int in num_entries:
		var instrument: Instrument = Instrument.new()
		instrument.index = instrument_index
		var entry_offset: int = 0x20 + (instrument_index * 16)
		var sample_offset: int = waveset_bytes.decode_u32(entry_offset)
		var sample_size: int = waveset_bytes.decode_u16(entry_offset + 4)
		instrument.sample_offset = sample_offset
		instrument.sample_size = sample_size
		instrument.fine_tune = waveset_bytes.decode_s16(entry_offset + 6)

		var attribute_bytes: PackedByteArray = waveset_bytes.slice(entry_offset + 8, entry_offset + 16)
		# Mode bits for sustain / release come from bytes 6 and 7 of the entry.
		var attack_rate: int = attribute_bytes[0] & 0x7F
		var decay_rate: int = attribute_bytes[1] & 0xF
		var sustain_rate: int = attribute_bytes[2] & 0x7F
		var release_rate: int = attribute_bytes[3] & 0x1F
		var sustain_level: int = attribute_bytes[4] & 0xF
		var sustain_mode: int = (attribute_bytes[6] >> 2) & 1
		var release_mode: int = (attribute_bytes[7] >> 2) & 1
		instrument.adsr1 = (attack_rate << 8) | (decay_rate << 4) | sustain_level
		instrument.adsr2 = (sustain_mode << 15) | (1 << 14) | (sustain_rate << 6) | (release_mode << 5) | release_rate
		# iter-24: preserve full mode bytes (0-7 selectors for ADSR2 tables).
		instrument.mode_byte_58 = attribute_bytes[5] & 0xFF
		instrument.mode_byte_5c = attribute_bytes[6] & 0xFF
		instrument.mode_byte_60 = attribute_bytes[7] & 0xFF
		instrument.release_rate_byte = release_rate

		if sample_offset == 0 and sample_size == 0:
			instrument.is_null = true
			instruments[instrument_index] = instrument
			continue

		instrument.is_null = false
		var adpcm_start: int = data_offset + sample_offset
		var adpcm_end: int = mini(adpcm_start + sample_size, waveset_bytes.size())
		var adpcm_slice: PackedByteArray = waveset_bytes.slice(adpcm_start, adpcm_end)
		# A leading all-zero block is a silent priming block FFT skips.
		if adpcm_slice.size() >= BLOCK_SIZE:
			var leading_block: PackedByteArray = adpcm_slice.slice(0, BLOCK_SIZE)
			if leading_block.count(0) == BLOCK_SIZE:
				instrument.start_offset_bytes = BLOCK_SIZE
				instrument.start_sample_skip = SAMPLES_PER_BLOCK
		var decoded: Array = _decode_adpcm(adpcm_slice)
		instrument.pcm_data = decoded[0]
		instrument.loop_start = decoded[1]
		instrument.loop_offset_bytes = decoded[2]
		instrument.has_explicit_loop_start = decoded[3]
		instrument.has_loop_repeat = decoded[4]
		instruments[instrument_index] = instrument

	is_initialized = true


func active_instrument_count() -> int:
	return instruments.filter(func(instrument: Instrument) -> bool: return not instrument.is_null).size()


## Returns [pcm: PackedInt32Array, loop_start, loop_offset_bytes,
## has_explicit_loop_start, has_loop_repeat].
func _decode_adpcm(data: PackedByteArray) -> Array:
	var pcm: PackedInt32Array = PackedInt32Array()
	var loop_start: int = -1
	var loop_offset_bytes: int = -1
	var has_explicit_loop_start: bool = false
	var has_loop_repeat: bool = false
	var sample_minus_1: int = 0
	var sample_minus_2: int = 0
	var num_blocks: int = data.size() / BLOCK_SIZE

	for block_index: int in num_blocks:
		var block_offset: int = block_index * BLOCK_SIZE
		var header: int = data[block_offset]
		var shift_factor: int = header & 0x0F
		var predict_number: int = mini((header >> 4) & 0x0F, 4)
		var flags: int = data[block_offset + 1]

		if flags & FLAG_LOOP_START:
			loop_start = pcm.size()
			loop_offset_bytes = block_offset
			has_explicit_loop_start = true
		if flags & FLAG_LOOP_REPEAT:
			has_loop_repeat = true

		var filter_0: int = ADPCM_FILTER[predict_number][0]
		var filter_1: int = ADPCM_FILTER[predict_number][1]

		for byte_index: int in range(2, 16):
			var data_byte: int = data[block_offset + byte_index]
			for nibble_shift: int in [0, 4]:
				var sample: int = ((data_byte >> nibble_shift) & 0x0F) << 12
				if sample & 0x8000:
					sample |= ~0xFFFF
				var filtered: int = sample >> shift_factor
				filtered = filtered + ((sample_minus_1 * filter_0) >> 6) + ((sample_minus_2 * filter_1) >> 6)
				sample_minus_2 = sample_minus_1
				sample_minus_1 = filtered
				pcm.append(clampi(filtered, -32768, 32767))

		# Match PCSX-Redux: flags == 3 means loop back; any LOOP_END stops.
		if flags & FLAG_LOOP_END:
			if flags == 3 or (flags & FLAG_LOOP_REPEAT):
				if loop_start == -1:
					loop_start = 0
			break

	return [pcm, loop_start, loop_offset_bytes, has_explicit_loop_start, has_loop_repeat]
