class_name FedsBankData
extends Resource
## Parses an FFT "feds" sound-definition blob. The same "feds" container shows
## up in two places, with slightly different header/table layouts:
##
##   1. Per-effect FEDS — section 8 (SOUND_EFFECTS) of an E###.BIN, sliced
##      between section_offsets[SOUND_EFFECTS] and section_offsets[TEXTURE].
##      Channels are grouped into pairs; the channel offset table starts at
##      0x18 and the game selects a pair via (channel * 4) + 0x14.
##
##   2. Global SFX banks — SYSTEM.SED / ENV.SED in SOUND/. These are standalone
##      "feds" blobs whose table starts at 0x14, with two u16 offsets per
##      sound_id (slot 0 / slot 1). category_key (sound_id >> 16) selects the
##      bank at runtime.
##
## Both use the same opcode language as SMD (decoded via SmdOpcodes).
##
## Header layout (little-endian):
##   0x00  4    magic "feds"
##   0x04  u32  data_size (== blob size)
##   0x08  u16  per-effect: pair_count + 1 | sfx bank: sound_id entry_count
##   0x0A  u16  per-effect: resource_id (SPU VRAM bank) | sfx bank: category_key
##   0x0C  u32  gain/volume table offset (per-effect: data_offset)
##   0x10  u32  sfx bank only: next-bank pointer (0 on disc)
##   0x14  sfx bank channel table (2 x u16 per sound_id)
##   0x18  per-effect channel table (u16 per channel)
##
## Ported from the godot-learning project (addons/exmateria_sound/runtime/
## feds_bank.gd and tools/parse_sfx_banks.py).

const MAGIC: String = "feds"

const EFFECT_CHANNEL_TABLE_OFFSET: int = 0x18
const SFX_BANK_CHANNEL_TABLE_OFFSET: int = 0x14

# chan+0x92 static voice-gain seed (FFT FUN_80013B20).
const CHAN_92_MULTIPLIER: int = 0x6000
const CHAN_92_SATURATE: int = 0x7FFF


## One playable unit: a pair (per-effect) or a sound_id (sfx bank). Holds up to
## two channel byte streams, each decoded into SmdOpcodes events.
class FedsSound:
	var index: int = 0                                ## pair index or sound_id
	var gain_byte: int = 0
	var channel_offsets: PackedInt32Array = PackedInt32Array()
	var channel_events: Array = []                    ## Array of Array (per channel)


@export var unique_name: String = "[feds_bank]"

var is_initialized: bool = false
var file_name: String = ""
var is_sfx_bank: bool = false

var magic: String = ""
var data_size: int = 0
var resource_id: int = 0       ## per-effect: SPU VRAM bank
var category_key: int = 0      ## sfx bank: sound_id >> 16 selects this bank
var gain_table_offset: int = 0 ## per-effect data_offset / sfx volume table offset

var raw: PackedByteArray = PackedByteArray()
var sounds: Array[FedsSound] = []


func _init(new_file_name: String = "") -> void:
	if new_file_name == "":
		return
	file_name = new_file_name
	unique_name = new_file_name.get_basename()


## Lazy-init entry point for standalone SFX bank files (SYSTEM.SED / ENV.SED).
func init_from_file(bytes: PackedByteArray = RomReader.get_file_data(file_name), overwrite: bool = false) -> void:
	if is_initialized and not overwrite:
		return
	parse_sfx_bank(bytes)


## Parses a standalone SFX bank blob (SYSTEM.SED / ENV.SED). One FedsSound per
## non-empty sound_id, each with up to two channel slots.
func parse_sfx_bank(bytes: PackedByteArray) -> bool:
	if not _parse_header(bytes, true):
		return false

	var entry_count: int = bytes.decode_u16(0x08)
	var channel_starts: PackedInt32Array = _collect_sfx_channel_starts(bytes, entry_count)
	var blob_end: int = mini(data_size, raw.size())

	sounds.clear()
	for sound_id: int in entry_count:
		var slot_0: int = bytes.decode_u16(SFX_BANK_CHANNEL_TABLE_OFFSET + (sound_id * 4))
		var slot_1: int = bytes.decode_u16(SFX_BANK_CHANNEL_TABLE_OFFSET + (sound_id * 4) + 2)
		if slot_0 == 0 and slot_1 == 0:
			continue  # empty slot (sound_id 0 and a few holes)

		var sound: FedsSound = FedsSound.new()
		sound.index = sound_id
		sound.gain_byte = _gain_byte_for(sound_id)
		for slot_offset: int in [slot_0, slot_1]:
			if slot_offset == 0:
				continue
			sound.channel_offsets.append(slot_offset)
			var channel_end: int = _channel_end(slot_offset, channel_starts, blob_end)
			var channel_bytes: PackedByteArray = raw.slice(slot_offset, channel_end)
			sound.channel_events.append(SmdOpcodes.decode_track(channel_bytes, channel_bytes.size()))
		sounds.append(sound)

	is_initialized = true
	return true


## Parses a per-effect FEDS blob (section 8 of an E###.BIN). One FedsSound per
## pair, each with exactly two channels.
func parse_effect_feds(bytes: PackedByteArray) -> bool:
	if not _parse_header(bytes, false):
		return false

	var pair_count_plus_one: int = bytes.decode_u16(0x08)
	var num_pairs: int = maxi(0, pair_count_plus_one - 1)
	var num_channels: int = num_pairs * 2

	var channel_offsets: PackedInt32Array = PackedInt32Array()
	channel_offsets.resize(num_channels)
	for channel_index: int in num_channels:
		channel_offsets[channel_index] = bytes.decode_u16(EFFECT_CHANNEL_TABLE_OFFSET + (channel_index * 2))

	var channel_starts: PackedInt32Array = PackedInt32Array(channel_offsets)
	channel_starts.sort()
	var blob_end: int = mini(data_size, raw.size())

	sounds.clear()
	for pair_index: int in num_pairs:
		var sound: FedsSound = FedsSound.new()
		sound.index = pair_index
		for channel_in_pair: int in 2:
			var channel_index: int = (pair_index * 2) + channel_in_pair
			var channel_start: int = channel_offsets[channel_index]
			sound.channel_offsets.append(channel_start)
			var channel_end: int = _channel_end(channel_start, channel_starts, blob_end)
			var channel_bytes: PackedByteArray = raw.slice(channel_start, channel_end)
			sound.channel_events.append(SmdOpcodes.decode_track(channel_bytes, channel_bytes.size()))
		sounds.append(sound)

	is_initialized = true
	return true


## chan+0x92 voice gain seed for a given sound_id.
func chan_92_for(sound_id: int) -> int:
	var shifted: int = (CHAN_92_MULTIPLIER * _gain_byte_for(sound_id)) >> 7
	if (shifted >> 15) & 1:
		return CHAN_92_SATURATE
	return shifted


## Slices the per-effect FEDS bytes (section 8) out of an E###.BIN's full file
## bytes, given the file's section-offset header start. Returns an empty array
## if the file has no valid FEDS section.
static func extract_effect_feds_bytes(vfx_bytes: PackedByteArray, header_start: int) -> PackedByteArray:
	var sound_section_index: int = VisualEffectData.VfxSections.SOUND_EFFECTS
	var texture_section_index: int = VisualEffectData.VfxSections.TEXTURE
	var sound_entry_offset: int = header_start + (sound_section_index * 4)
	var texture_entry_offset: int = header_start + (texture_section_index * 4)
	if texture_entry_offset + 4 > vfx_bytes.size():
		return PackedByteArray()

	var sound_section_start: int = vfx_bytes.decode_u32(sound_entry_offset) + header_start
	var texture_section_start: int = vfx_bytes.decode_u32(texture_entry_offset) + header_start
	if texture_section_start <= sound_section_start or sound_section_start >= vfx_bytes.size():
		return PackedByteArray()

	var feds_bytes: PackedByteArray = vfx_bytes.slice(sound_section_start, mini(texture_section_start, vfx_bytes.size()))
	if feds_bytes.size() < 4 or feds_bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return PackedByteArray()
	return feds_bytes


func _parse_header(bytes: PackedByteArray, sfx_bank: bool) -> bool:
	if bytes.size() < 0x18:
		push_warning(file_name + ": feds blob too small (" + str(bytes.size()) + " bytes).")
		return false
	magic = bytes.slice(0, 4).get_string_from_ascii()
	if magic != MAGIC:
		push_warning(file_name + ": bad feds magic '" + magic + "'.")
		return false

	raw = bytes
	is_sfx_bank = sfx_bank
	data_size = bytes.decode_u32(0x04)
	gain_table_offset = bytes.decode_u32(0x0C)
	if sfx_bank:
		category_key = bytes.decode_u16(0x0A)
	else:
		resource_id = bytes.decode_u16(0x0A)
	return true


func _gain_byte_for(sound_id: int) -> int:
	var offset: int = gain_table_offset + sound_id
	if offset < 0 or offset >= raw.size():
		return 0
	return raw[offset]


# All distinct nonzero sound_id channel offsets, sorted — used to bound a
# channel's byte stream at the next channel that starts later.
func _collect_sfx_channel_starts(bytes: PackedByteArray, entry_count: int) -> PackedInt32Array:
	var starts: Dictionary = {}
	for sound_id: int in entry_count:
		for half: int in [0, 2]:
			var offset: int = bytes.decode_u16(SFX_BANK_CHANNEL_TABLE_OFFSET + (sound_id * 4) + half)
			if offset != 0:
				starts[offset] = true
	var sorted_starts: PackedInt32Array = PackedInt32Array(starts.keys())
	sorted_starts.sort()
	return sorted_starts


# A channel runs from its start to the next larger start offset (or blob end).
func _channel_end(start: int, sorted_starts: PackedInt32Array, blob_end: int) -> int:
	var channel_end: int = blob_end
	for other_start: int in sorted_starts:
		if other_start > start:
			channel_end = other_start
			break
	return mini(channel_end, raw.size())
