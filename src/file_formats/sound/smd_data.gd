class_name SmdData
extends Resource
## Parses an FFT MUSIC_##.SMD file (a "smds" music sequence) into track event
## lists. Lives in SOUND/ on the ISO and is read via RomReader.get_file_data().
##
## Header layout (little-endian):
##   0x00  4    magic "smds"
##   0x08  u16  file_size
##   0x14  u8   track_count
##   0x16  u16  associated_waveset_id (which WAVESET bank to use)
##   0x18  u8   initial_volume
##   0x1A  u8   initial_tempo (-> BPM via SmdOpcodes.fft_tempo_to_bpm)
##   0x1E  u16  song_title_ptr
##   0x20  u16  drumkit_ptr
##   0x22  u16[track_count]  track pointer table (offsets into the file)
##
## Each track's bytes run from its pointer to the next track's pointer (the
## last track ends at file_size), decoded via SmdOpcodes.decode_track().
##
## Ported from the godot-learning project (addons/exmateria_sound/runtime/
## smd_parser.gd) in this project's lazy-init / RomReader style.

const MAGIC: String = "smds"

@export var unique_name: String = "[smd_name]"

var is_initialized: bool = false
var file_name: String = ""
var music_id: int = 0

@export var track_count: int = 0
@export var initial_tempo: int = 0
@export var initial_volume: int = 0
@export var associated_waveset_id: int = 0
@export var song_title: String = ""

## One entry per track; each entry is an Array of SmdOpcodes.NoteEvent /
## SmdOpcodes.OpcodeEvent objects.
var track_events: Array = []

var initial_bpm: float:
	get:
		return SmdOpcodes.fft_tempo_to_bpm(initial_tempo)


func _init(new_file_name: String = "") -> void:
	if new_file_name == "":
		return

	file_name = new_file_name
	unique_name = new_file_name.get_basename()
	# MUSIC_##.SMD -> ##
	music_id = unique_name.trim_prefix("MUSIC_").to_int()


func init_from_file(smd_bytes: PackedByteArray = RomReader.get_file_data(file_name), overwrite: bool = false) -> void:
	if is_initialized and not overwrite:
		return

	if smd_bytes.size() < 0x22:
		push_warning(file_name + ": SMD too small (" + str(smd_bytes.size()) + " bytes). Skipping.")
		return

	if smd_bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		push_warning(file_name + ": invalid SMD magic. Skipping.")
		return

	var file_size: int = smd_bytes.decode_u16(0x08)
	track_count = smd_bytes.decode_u8(0x14)
	associated_waveset_id = smd_bytes.decode_u16(0x16)
	initial_volume = smd_bytes.decode_u8(0x18)
	initial_tempo = smd_bytes.decode_u8(0x1A)

	var song_title_ptr: int = smd_bytes.decode_u16(0x1E)

	# Track pointer table at 0x22.
	var track_pointers: PackedInt32Array = []
	for track_index: int in track_count:
		var pointer_offset: int = 0x22 + (track_index * 2)
		if pointer_offset + 2 > smd_bytes.size():
			break
		track_pointers.append(smd_bytes.decode_u16(pointer_offset))

	# Song title is the ASCII string from song_title_ptr to the first track.
	if song_title_ptr > 0 and song_title_ptr < smd_bytes.size():
		var title_end: int = track_pointers[0] if track_pointers.size() > 0 else smd_bytes.size()
		title_end = mini(title_end, smd_bytes.size())
		var title_bytes: PackedByteArray = smd_bytes.slice(song_title_ptr, title_end)
		song_title = _string_until_null(title_bytes)

	# Decode each track.
	track_events = []
	for track_index: int in track_pointers.size():
		var track_start: int = track_pointers[track_index]
		var track_end: int
		if track_index + 1 < track_pointers.size():
			track_end = track_pointers[track_index + 1]
		elif file_size > 0:
			track_end = file_size
		else:
			track_end = smd_bytes.size()
		track_start = mini(track_start, smd_bytes.size())
		track_end = mini(track_end, smd_bytes.size())

		var track_bytes: PackedByteArray = smd_bytes.slice(track_start, track_end)
		track_events.append(SmdOpcodes.decode_track(track_bytes, track_bytes.size()))

	is_initialized = true


func _string_until_null(bytes: PackedByteArray) -> String:
	var end_index: int = bytes.size()
	for byte_index: int in bytes.size():
		if bytes[byte_index] == 0:
			end_index = byte_index
			break
	return bytes.slice(0, end_index).get_string_from_ascii()
