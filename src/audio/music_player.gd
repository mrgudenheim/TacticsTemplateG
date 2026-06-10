extends Node
## MusicPlayer (autoload singleton, accessed globally as `MusicPlayer`).
##
## Plays Final Fantasy Tactics .SMD music through the vendored exmateria_sound
## addon (SMDPlayer), sourcing the SMD bytes from RomReader (the loaded ISO)
## rather than from files on disk.
##
## Usage:
##   MusicPlayer.play_slot(31)              # play MUSIC_31.SMD
##   MusicPlayer.play_file("MUSIC_04.SMD")  # play by file name
##   MusicPlayer.stop()
##
## The addon's SMDPlayer only exposes path-based loaders (load_smd(path)); to
## play from in-memory ROM bytes we replicate load_smd() via its public members
## (parse the bytes with SMDParser, assign smd_file, hand it to the sequencer).

var _player: SMDPlayer
var _engine_attached: bool = false


func _ready() -> void:
	_player = SMDPlayer.new()
	_player.name = "SMDPlayer"
	add_child(_player)


## Play MUSIC_<slot>.SMD (e.g. play_slot(31) -> "MUSIC_31.SMD").
func play_slot(slot: int) -> bool:
	return play_file("MUSIC_%02d.SMD" % slot)


## Play an SMD by its file name (e.g. "MUSIC_04.SMD"). Sourced from the loaded
## ROM or, if none, the imported sound cache (via AudioEngine).
func play_file(file_name: String) -> bool:
	var smd_file_bytes: PackedByteArray = AudioEngine.smd_bytes(file_name)
	if smd_file_bytes.is_empty():
		push_error("MusicPlayer: %s not available (no ROM loaded and not in sound cache)." % file_name)
		return false
	var smd_file: SMDParser.SMDFile = SMDParser.parse(smd_file_bytes)
	if smd_file == null:
		push_error("MusicPlayer: failed to parse %s." % file_name)
		return false
	return _play_smd_file(smd_file)


## Play one FEDS effect-sound pair through the MUSIC pipeline (sequencer + SPU),
## wrapped as a synthetic SMD. `feds_bytes` is a raw "feds" blob (an E### sound
## section or an SFX bank). This is the simpler music-path audition; the
## disassembly-faithful SFX path lives in EffectSfxEngine.
func play_feds_bytes(feds_bytes: PackedByteArray, pair_idx: int = 0) -> bool:
	var feds_bank: FedsBank = FedsBank.parse(feds_bytes)
	if feds_bank == null:
		push_error("MusicPlayer: failed to parse feds blob.")
		return false
	if pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		push_error("MusicPlayer: pair %d out of range (num_pairs=%d)." % [pair_idx, feds_bank.num_pairs])
		return false
	return _play_smd_file(feds_bank.make_synthetic_smd(pair_idx))


func stop() -> void:
	if _player:
		_player.stop_music()


func is_playing() -> bool:
	return _player != null and _player.is_playing()


func _play_smd_file(smd_file: SMDParser.SMDFile) -> bool:
	if not _attach_engine():
		return false
	# Replicate SMDPlayer.load_smd() from bytes: stop_music() first to join the
	# render thread before mutating the sequencer (avoids the song-switch race),
	# then load the pre-parsed SMDFile into the sequencer.
	_player.stop_music()
	_player.smd_file = smd_file
	_player.seq.load_smd(smd_file)
	_player.play_music()
	return true


func _attach_engine() -> bool:
	if _engine_attached:
		return true
	if not AudioEngine.ensure_ready():
		return false
	# Use the shared, ROM-built music SPU + waveset instead of the player's own
	# self-constructed mixer, so the instrument bank is uploaded only once.
	_player.attach_shared_engine(AudioEngine.music_spu, AudioEngine.waveset)
	_engine_attached = true
	return true
