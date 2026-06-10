extends Node
## EffectSfxEngine (autoload singleton, accessed globally as `EffectSfxEngine`).
##
## The single, always-running FFT effect-sound (FEDS) driver. Replaces the
## per-play EffectSoundPlayer: instead of building a fresh SPU/pool/runtime for
## each sound and tearing it down when the sound ends, this models the PSX SPU
## faithfully — a fixed-clock SPU that never stops. Once the ROM's sound data is
## available the pool + sequencer runtime are built once and tick every frame
## forever; keyed-off voices release and the reverb tank decays on that clock
## whether or not any effect is feeding new notes, so tails are never trimmed.
##
## Voice budget (two modes; the toggle preserves PSX parity):
##   FAITHFUL ("legacy") — exact FFT effect pool on one SPU: 8 slots, voices
##              16-23, slots 6-7 reserved -> 3 concurrent stereo pairs. For
##              parity / A-B comparison against the hardware.
##   UNLOCKED ("unlimited") — each SPU uses all 24 voices (base 0) -> 12 pairs,
##              AND the engine spins up additional stacked SPU "units" on demand
##              (up to MAX_UNITS) so many simultaneous effects don't starve.
##              Idle units aren't rendered, so cost scales with concurrent
##              activity, not the cap. This is the game default.
##
## A "unit" = one Spu + its own pool/flush/walker/runtime AND its own entity
## list (so each unit's Runtime drives only its own casts — see the per-unit
## entity-list injection in runtime.gd / play_sound.gd). Each effect cast binds
## to one unit at its first dispatch, routed to a unit with free voice pairs (or
## a freshly spawned one). Binding at first dispatch (not at begin_effect) means
## many casts that begin in the same frame spread across units as they actually
## allocate, instead of all piling onto unit 0.
##
## Music coexists on the separate AudioEngine.music_spu; SFX units never touch
## it. Unlike godot-learning (which loads its waveset off disk at boot), this
## project sources sound bytes from the loaded ROM, so the engine can only build
## after a ROM (or imported sound cache) is available — initialization is
## deferred and triggered lazily on first use / when RomReader emits rom_loaded.

const _Pool := preload("res://addons/exmateria_sound/runtime/effect_sound/pool.gd")
const _Play := preload("res://addons/exmateria_sound/runtime/effect_sound/play_sound.gd")
const _Flush := preload("res://addons/exmateria_sound/runtime/shared/flush_tick.gd")
const _Walker := preload("res://addons/exmateria_sound/runtime/shared/spu_irq_walker.gd")
const _RuntimeClass := preload("res://addons/exmateria_sound/runtime/runtime.gd")
const _EntityList := preload("res://addons/exmateria_sound/runtime/shared/entity_list.gd")

# A fresh effect entity (channel_count > 2 marks it the active one); every other
# field defaults to FUN_800137d8 init inside the SFX path's seed handling.
const SYNTHETIC_SEED: Dictionary = {"entities": [{"channel_count": 8}]}
const LEAD_SUBS: int = 6            # generator lead (~25 ms) — low latency
const MAX_SUBS_PER_FRAME: int = 24  # per-frame catch-up cap
# Extra (non-base) units stop rendering this many sub-ticks after their last
# activity (release + reverb fully decay first, ~3 s at 240 Hz), then sleep
# until a new cast lands on them — idle-skip keeps cost ~ concurrent activity.
const UNIT_IDLE_TAIL_SUBS: int = 720
# UNLOCKED hard cap on stacked SPUs. 4 x 24 voices = 96 voices / 48 pairs —
# effectively unlimited for a tactics game; each rendered unit adds one reverb
# tank's per-sample cost, so the cap bounds worst-case CPU.
const MAX_UNITS: int = 4
# Safety cap for an orphaned cast (visual ended) whose sound never reaches
# EndBar (e.g. a looping ambient) — force it to release after ~15 s so it can't
# drone/leak forever. Normal effects reap as soon as their FEDS sequence ends.
const ORPHAN_MAX_SUBS: int = 3600

enum VoiceMode { FAITHFUL, UNLOCKED }
var voice_mode: int = VoiceMode.UNLOCKED

var ready_ok: bool = false

var _units: Array = []              # Array of unit dicts (see _make_unit)
var _sessions: Dictionary = {}      # token -> {play, entity, unit, orphan_sub}
var _cast_token: int = 0
var _abs_sub: int = 0
var _sample_acc: int = 0            # global 183/184 drift accumulator (shared by all units)

var _generator: AudioStreamGenerator
var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _buffer_capacity: int = 0


func _ready() -> void:
	_Play._entity_state_seed = SYNTHETIC_SEED   # fresh per-cast plays seed from this static
	# Start the always-on SPU as soon as a ROM makes sound data available. If a
	# ROM (or imported sound cache) is already loaded at boot, start now;
	# otherwise wait for rom_loaded (and fall back to lazy init on first use).
	if RomReader.has_signal("rom_loaded"):
		RomReader.rom_loaded.connect(_on_rom_loaded)
	if AudioEngine.ready_ok or not AudioEngine.waveset_bytes().is_empty():
		ensure_ready()


func _on_rom_loaded() -> void:
	ensure_ready()


## Build the continuous SFX SPU once. Requires AudioEngine (and therefore a
## loaded ROM or imported sound cache). Safe to call repeatedly; only does work
## the first time it succeeds. Returns false until sound data is available.
func ensure_ready() -> bool:
	if ready_ok:
		return true
	if not AudioEngine.ensure_ready():
		return false

	AudioEngine.sfx_spu.reset()                 # unit 0 reuses the shared, boot-loaded SFX SPU
	_units.append(_make_unit(AudioEngine.sfx_spu))

	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = Spu.SAMPLE_RATE
	_generator.buffer_length = 0.25
	_audio = AudioStreamPlayer.new()
	_audio.stream = _generator
	_audio.bus = "Master"
	add_child(_audio)
	_audio.play()
	_playback = _audio.get_stream_playback()
	_buffer_capacity = int(_generator.mix_rate * _generator.buffer_length)
	ready_ok = true
	print("[EffectSfxEngine] ready — continuous SFX SPU (mode=%s, units=%d)"
		% [_mode_name(), _units.size()])
	return true


func _mode_name() -> String:
	return "FAITHFUL" if voice_mode == VoiceMode.FAITHFUL else "UNLOCKED"


func unit_count() -> int:
	return _units.size()


func debug_snapshot() -> Dictionary:
	## Live SPU/unit state for monitoring (stress scene / debug overlay).
	var units_info: Array = []
	var total_voices: int = 0
	for index: int in range(_units.size()):
		var unit: Dictionary = _units[index]
		var voice_count: int = unit["mixer"].get_active_voice_count()
		total_voices += voice_count
		units_info.append({
			"voices": voice_count,
			"sessions": int(unit["session_count"]),
			"active": _unit_active(unit, index),
		})
	return {
		"mode": _mode_name(),
		"units": units_info,
		"total_voices": total_voices,
		"sessions": _sessions.size(),
		"max_units": MAX_UNITS,
	}


func _make_pool():
	if voice_mode == VoiceMode.FAITHFUL:
		return _Pool.new(8, 16, 6)   # exact FFT pool: voices 16-23, slots 6-7 reserved (3 pairs)
	return _Pool.new(24, 0, 24)      # UNLOCKED: all 24 voices base 0 (12 pairs)


func _make_unit(mixer: Spu) -> Dictionary:
	mixer.set_irq_period_samples(512)
	var pool = _make_pool()
	var flush = _Flush.new(pool, mixer)
	pool.set_flush_tick(flush)
	var walker = _Walker.new(pool, mixer)
	var entity_list = _EntityList.new()       # PER-UNIT entity list (isolates this unit's casts)
	var runtime = _RuntimeClass.new(mixer, flush, walker)
	runtime.sfx_only = true
	runtime.entity_list = entity_list
	return {
		"mixer": mixer, "pool": pool, "flush": flush, "walker": walker,
		"runtime": runtime, "list": entity_list, "session_count": 0, "last_active_sub": 0,
	}


func _spawn_unit():
	## Add a stacked SPU unit (UNLOCKED only). Returns the unit or null if at the
	## cap / upload failed. The instrument upload is the one-time per-unit cost,
	## paid lazily the first time concurrency overflows the existing units.
	if _units.size() >= MAX_UNITS:
		return null
	var mixer := Spu.new()
	if not mixer.load_instruments(AudioEngine.waveset):
		push_warning("EffectSfxEngine: extra SPU instrument load failed")
		return null
	mixer.reset()
	var unit := _make_unit(mixer)
	_units.append(unit)
	print("[EffectSfxEngine] spawned SFX unit %d (now %d)" % [_units.size() - 1, _units.size()])
	return unit


func _has_free_pair(unit: Dictionary) -> bool:
	var alloc: Dictionary = unit["pool"].find_free_pair_slot(2)
	return int(alloc.get("slot_idx", -1)) >= 0 and not bool(alloc.get("preempted", false))


func _pick_unit() -> Dictionary:
	## Route a cast (at first dispatch): prefer a unit with a free pair; else
	## spawn one (under the cap); else the least-loaded unit (LRU-preempts).
	if voice_mode == VoiceMode.FAITHFUL:
		return _units[0]
	for unit: Dictionary in _units:
		if _has_free_pair(unit):
			return unit
	var spawned = _spawn_unit()
	if spawned != null:
		return spawned
	var best: Dictionary = _units[0]
	for unit: Dictionary in _units:
		if int(unit["session_count"]) < int(best["session_count"]):
			best = unit
	return best


func set_voice_mode(mode: int) -> void:
	## Switch FAITHFUL <-> UNLOCKED ("legacy" <-> "unlimited"). Stops all SFX and
	## rebuilds units (the voice base/slot count change). Safe live (e.g. from a
	## debug toggle); brief silence as active casts drop. Extra UNLOCKED units are
	## torn down on FAITHFUL.
	if not ready_ok or mode == voice_mode:
		return
	stop_all()
	voice_mode = mode
	AudioEngine.sfx_spu.reset()
	_units = [_make_unit(AudioEngine.sfx_spu)]
	_abs_sub = 0
	print("[EffectSfxEngine] voice_mode -> %s" % _mode_name())


func begin_effect() -> int:
	## Open a cast. Unit binding is deferred to the first play_pair so concurrent
	## begins spread across units. Returns a token for play_pair()/end_effect().
	if not ensure_ready():
		return 0
	_cast_token += 1
	_sessions[_cast_token] = {"play": null, "entity": null, "unit": null, "orphan_sub": -1}
	return _cast_token


func play_pair(token: int, feds_bank: FedsBank, pair_idx: int, sound_id: int) -> bool:
	## Dispatch one FEDS pair for the cast into a free pool slot on its unit
	## (binding the unit on first call). pair_idx + sound_id come from the caller
	## (sound_id = resolved config_channel; -1 = default chan+0x92).
	if not ready_ok or feds_bank == null:
		return false
	var session: Variant = _sessions.get(token)
	if session == null:
		return false
	if pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		push_warning("EffectSfxEngine: pair %d out of range (num_pairs=%d)"
				% [pair_idx, feds_bank.num_pairs])
		return false
	# Bind to a unit on the first dispatch (real occupancy known now).
	if session["unit"] == null:
		var unit := _pick_unit()
		var play = _Play.new(unit["pool"], AudioEngine.waveset)
		play.set_flush_tick(unit["flush"])
		play.set_entity_list(unit["list"])
		unit["session_count"] = int(unit["session_count"]) + 1
		session["unit"] = unit
		session["play"] = play
	var unit_bound = session["unit"]
	var play_bound = session["play"]
	var alloc: Dictionary = unit_bound["pool"].find_free_pair_slot(2)
	var slot_idx := int(alloc.get("slot_idx", -1))
	if slot_idx < 0:
		push_warning("EffectSfxEngine: unit pool exhausted (pair=%d)" % pair_idx)
		return false
	if bool(alloc.get("preempted", false)):
		play_bound.free_pair(slot_idx)
	if not play_bound.play_feds_pair(feds_bank, pair_idx, slot_idx, sound_id):
		push_warning("EffectSfxEngine: play_feds_pair failed (pair=%d slot=%d sid=%d)"
				% [pair_idx, slot_idx, sound_id])
		return false
	if session["entity"] == null:
		session["entity"] = play_bound._entity_catchup
	unit_bound["last_active_sub"] = _abs_sub
	return true


func end_effect(token: int) -> void:
	## End a cast: key-off its held voices (release tail, not a cut) and unlink
	## its entity from its unit's list. Voices ring out on the continuous clock.
	var session: Variant = _sessions.get(token)
	if session == null:
		return
	var play = session["play"]
	var unit = session["unit"]
	if play != null:
		play.release_and_free()
	if unit != null:
		var entity = session["entity"]
		if entity != null:
			entity.is_done = true
			unit["list"].unlink(entity)
		unit["session_count"] = maxi(0, int(unit["session_count"]) - 1)
		unit["last_active_sub"] = _abs_sub
	_sessions.erase(token)


func orphan_effect(token: int) -> void:
	## The cast's VISUAL ended (its EffectInstance was freed) but let its SOUND
	## finish: stop expecting new pairs, keep the dispatched ones sequencing to
	## their natural EndBar, and reap once done (or after ORPHAN_MAX_SUBS). This is
	## what keeps whole effects audible after the particles stop — the alternative
	## (end_effect) cuts the sound the instant the visual completes.
	var session: Variant = _sessions.get(token)
	if session == null:
		return
	if session["play"] == null:
		end_effect(token)  # never dispatched — nothing to ring out
		return
	session["orphan_sub"] = _abs_sub


func _reap_orphans() -> void:
	var done: Array = []
	for token: int in _sessions:
		var session: Dictionary = _sessions[token]
		if int(session["orphan_sub"]) < 0:
			continue  # still live (visual not ended)
		var play = session["play"]
		if play == null or play.is_sequencing_done() \
				or (_abs_sub - int(session["orphan_sub"])) > ORPHAN_MAX_SUBS:
			done.append(token)
	for token: int in done:
		end_effect(token)


## One-shot audition of an E### FEDS section for the test scenes. `feds_bytes`
## is a raw "feds" blob (sliced from RomReader via AudioEngine.feds_bytes /
## get_feds_bytes). sound_id < 0 = default chan+0x92. Returns a cast token (0 on
## failure) so the caller can end_effect() it later.
func audition_feds_bytes(feds_bytes: PackedByteArray, pair_idx: int, sound_id: int = -1) -> int:
	if not ensure_ready():
		return 0
	var feds_bank: FedsBank = FedsBank.parse(feds_bytes)
	if feds_bank == null or pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		push_warning("EffectSfxEngine: cannot audition feds blob pair %d" % pair_idx)
		return 0
	var token := begin_effect()
	if not play_pair(token, feds_bank, pair_idx, sound_id):
		end_effect(token)
		return 0
	return token


## One-shot audition of a sound_id from a global SFX bank (SYSTEM.SED / ENV.SED).
## A bank's stride-2 offset table makes FFT sound_id N map to FedsBank pair_idx
## N-1; the real sound_id is passed through so the chan+0x92 static gain is read
## from the bank's volume table (FedsBank.chan_92_for).
func audition_bank_bytes(bank_bytes: PackedByteArray, sound_id: int) -> int:
	if not ensure_ready():
		return 0
	var feds_bank: FedsBank = FedsBank.parse(bank_bytes)
	if feds_bank == null:
		push_warning("EffectSfxEngine: cannot parse SFX bank")
		return 0
	var pair_idx: int = sound_id - 1
	if pair_idx < 0 or pair_idx >= feds_bank.num_pairs:
		push_warning("EffectSfxEngine: sound_id %d out of range (num_pairs=%d)"
				% [sound_id, feds_bank.num_pairs])
		return 0
	var token := begin_effect()
	if not play_pair(token, feds_bank, pair_idx, sound_id):
		end_effect(token)
		return 0
	return token


func stop_all() -> void:
	## End every cast on every unit (ring-out).
	for token: int in _sessions.keys():
		var session: Dictionary = _sessions[token]
		var play = session["play"]
		var unit = session["unit"]
		if play != null:
			play.release_and_free()
		if unit != null and session["entity"] != null:
			session["entity"].is_done = true
			unit["list"].unlink(session["entity"])
	_sessions.clear()
	for unit: Dictionary in _units:
		unit["session_count"] = 0


func panic() -> void:
	## Hard reset to silence: end all casts AND clear every unit's SPU voices/
	## reverb. NOT used in the normal gameplay loop — scene transitions / tests only.
	stop_all()
	for unit: Dictionary in _units:
		var mixer: Spu = unit["mixer"]
		mixer.reset()
		mixer.set_irq_period_samples(512)
	_abs_sub = 0


func _render_sub_pcm() -> PackedInt32Array:
	# One global 183/184-sample IRQ, summed across active units so all units
	# render the SAME sample count. Unit 0 always renders (feeds the generator);
	# other units render only while busy or within their idle tail.
	# Reap orphaned casts whose sound has finished (~8x/sec is plenty).
	if _abs_sub % 30 == 0 and not _sessions.is_empty():
		_reap_orphans()
	var samples := _RuntimeClass.SAMPLES_PER_IRQ_BASE
	_sample_acc += _RuntimeClass.SAMPLES_PER_IRQ_REM
	if _sample_acc >= _RuntimeClass.IRQ_HZ:
		samples += 1
		_sample_acc -= _RuntimeClass.IRQ_HZ
	var mixed := PackedInt32Array()
	var have_mix := false
	for index: int in range(_units.size()):
		var unit: Dictionary = _units[index]
		if not _unit_active(unit, index):
			continue
		unit["runtime"].tick_irq_start(_abs_sub)
		unit["runtime"].tick(_abs_sub)
		var pcm: PackedInt32Array = unit["mixer"].render_interleaved_pcm16(samples)
		if not have_mix:
			mixed = pcm
			have_mix = true
		else:
			var common := mini(mixed.size(), pcm.size())
			for sample_index: int in range(common):
				mixed[sample_index] += pcm[sample_index]
	_abs_sub += 1
	if not have_mix:
		mixed.resize(samples * 2)  # silence (shouldn't happen — unit 0 is always active)
	return mixed


func _unit_active(unit: Dictionary, index: int) -> bool:
	if index == 0:
		return true  # base unit always renders (continuous clock + generator feed)
	if int(unit["session_count"]) > 0:
		return true
	return (_abs_sub - int(unit["last_active_sub"])) < UNIT_IDLE_TAIL_SUBS


func _process(_delta: float) -> void:
	if not ready_ok or _playback == null:
		return
	var lead_frames := _RuntimeClass.SAMPLES_PER_IRQ_BASE * LEAD_SUBS
	var subs_this_frame := 0
	while subs_this_frame < MAX_SUBS_PER_FRAME:
		var available := _playback.get_frames_available()
		var buffered := _buffer_capacity - available
		if buffered >= lead_frames:
			break
		if available < _RuntimeClass.SAMPLES_PER_IRQ_BASE + 1:
			break
		_playback.push_buffer(_pcm_to_frames(_render_sub_pcm()))
		subs_this_frame += 1


func _pcm_to_frames(pcm: PackedInt32Array) -> PackedVector2Array:
	# PCM is interleaved stereo (always even length); size/2 = frame count.
	@warning_ignore("integer_division")
	var frame_count := pcm.size() / 2
	var frames := PackedVector2Array()
	frames.resize(frame_count)
	var inverse := 1.0 / 32767.0
	for frame_index: int in range(frame_count):
		frames[frame_index] = Vector2(clampf(float(pcm[frame_index * 2]) * inverse, -1.0, 1.0),
				clampf(float(pcm[frame_index * 2 + 1]) * inverse, -1.0, 1.0))
	return frames
