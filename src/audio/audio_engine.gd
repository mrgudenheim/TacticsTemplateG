extends Node
## AudioEngine (autoload singleton, accessed globally as `AudioEngine`).
##
## Owns the game's shared FFT audio assets, built ONCE from the loaded ROM:
##   - waveset:   one WavesetParser (the WAVESET.WD instrument bank)
##   - music_spu: the native SPU core that plays music (driven by MusicPlayer)
##   - sfx_spu:   the native SPU core that plays effect sounds (E### FEDS + the
##                global SFX banks, driven by EffectSfxEngine — the one always-on
##                SFX driver)
##
## Two SPUs = 48 voices total, each with its own reverb tank, sharing one
## instrument bank. Unlike godot-learning (which loads WAVESET.WD off disk at
## boot), this project sources the bytes from RomReader, so initialization is
## deferred until a ROM is loaded — call ensure_ready() before first use.
##
## Spu and WavesetParser come from the vendored exmateria_sound addon.

const WAVESET_FILE_NAME: String = "WAVESET.WD"

var waveset: WavesetParser
var music_spu: Spu
var sfx_spu: Spu
var ready_ok: bool = false


## Builds the shared waveset + SPUs from the loaded ROM or, if no ROM is
## loaded, from an imported sound cache (GameData). Safe to call repeatedly;
## only does work the first time it succeeds. Returns false if neither source
## has sound data or the native core fails.
func ensure_ready() -> bool:
	if ready_ok:
		return true

	var waveset_file_bytes: PackedByteArray = waveset_bytes()
	if waveset_file_bytes.is_empty():
		push_error("AudioEngine: no waveset available — load a ROM or import a sound cache first.")
		return false

	waveset = WavesetParser.new()
	if not waveset.parse(waveset_file_bytes):
		push_error("AudioEngine: failed to parse %s." % WAVESET_FILE_NAME)
		return false

	music_spu = Spu.new()
	sfx_spu = Spu.new()
	if not music_spu.load_instruments(waveset) or not sfx_spu.load_instruments(waveset):
		push_error("AudioEngine: failed to load instruments into the SPU cores.")
		return false

	ready_ok = true
	print("[AudioEngine] ready — shared waveset + music/sfx SPUs (48 voices)")
	return true


## Drop cached state so the next ensure_ready() rebuilds from a freshly loaded
## ROM (e.g. after the user loads a different ISO).
func reset() -> void:
	ready_ok = false
	waveset = null
	music_spu = null
	sfx_spu = null


# --- Raw sound byte accessors ---
# Each prefers the loaded ROM (RomReader); if no ROM is loaded, it falls back to
# the imported sound cache (GameData). Returns an empty array if neither has it.

func waveset_bytes() -> PackedByteArray:
	if RomReader.file_records.has(WAVESET_FILE_NAME):
		return RomReader.get_file_data(WAVESET_FILE_NAME)
	return GameData.sound_waveset_bytes


func smd_bytes(file_name: String) -> PackedByteArray:
	if RomReader.file_records.has(file_name):
		return RomReader.get_file_data(file_name)
	return GameData.sound_smd_bytes.get(file_name, PackedByteArray())


func sfx_bank_bytes(file_name: String) -> PackedByteArray:
	if RomReader.file_records.has(file_name):
		return RomReader.get_file_data(file_name)
	return GameData.sound_sfx_bank_bytes.get(file_name, PackedByteArray())


## Raw FEDS section bytes for an effect, keyed by its unique_name (e.g. "E042").
func feds_bytes(effect_unique_name: String) -> PackedByteArray:
	for vfx_data: VisualEffectData in RomReader.vfx:
		if vfx_data.unique_name == effect_unique_name:
			return RomReader.get_feds_bytes(vfx_data)
	return GameData.sound_feds_bytes.get(effect_unique_name, PackedByteArray())
