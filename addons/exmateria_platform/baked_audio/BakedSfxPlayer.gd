extends Node

## The game's sound driver, with no SPU in it.
##
## Autoloaded as `BakedSfx`. It answers the same verbs `ExMateriaEffectSfx` answered —
## `begin_effect` / `play_pair` / `end_effect`, the one-shots, the click, the `{6B}` bed —
## so `SfxPort`, `SfxRouter` and `EffectInstance` keep their call sites. What it does NOT
## do is synthesise: every sound is a finished WAV from the baked corpus, played on an
## `AudioStreamPlayer`.
##
## 🔴 **WHY THIS EXISTS AS A SEPARATE NODE RATHER THAN A FLAG ON THE OLD ENGINE.** The old
## engine `preload`s `spu.gd`, and `preload` binds at PARSE time — so merely having it in
## the project loads the PCSX-derived GPL core, whatever any runtime flag says. A flag can
## stop the core being USED; only a different file can stop it being LOADED. That is the
## whole reason this is a new script and not a branch inside the old one.
##
## ⚠️ **AND IT IS DELIBERATELY NOT A DRIVER.** There is no voice pool, no unit, no reap,
## no scheduler thread, because a finished stereo render needs none of them: the mixer
## does the mixing. The concepts the old engine exported that were ABOUT the SPU — voice
## mode, units, capture mode, `render_subs` — are gone rather than reimplemented, and
## anything still calling them is named in `docs/NATIVE-SPU-CENSUS.md`.

const BakedAudio = preload("res://addons/exmateria_platform/baked_audio/BakedAudio.gd")

## Effect SFX and the game-event blips land here; ambient beds on their own bus, so a
## loud bed and combat reach Master through independent limiters. Same two buses the SPU
## engine used, on purpose — a source swap that also moved buses would be comparing two
## mixes rather than two sources.
const OUTPUT_BUS := &"SFX"
const BG_OUTPUT_BUS := &"Ambient"

## Concurrent fire-and-forget players. Past the cap the oldest is recycled: a dropped
## effect is worse than a clipped tail.
const POOL_MAX := 32

const BAKED_ENABLED_SLUG := "audio.baked_enabled"
const AUDIO_MONITOR_SLUG := "audio.monitor_enabled"
static var audio_monitor_enabled := false

## True once `_ready` has run. Kept because ~7 production sites gate on it, and because a
## host that answered `true` before its pool existed would hand out players that are null.
var ready_ok := false

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
## Players bound to a cast TOKEN — everything whose caller comes back for it: `{6B}` beds
## (`set_bg_gain`, `stop_bg`) and the auditions (`end_effect`). The pool above cannot
## serve these, because it recycles by age and a bed's ramp would land on a stranger.
var _tokens: Dictionary = {}
var _token_seq := 0
## The reserved retrigger player for the per-glyph typewriter: one player, cut and
## restarted per glyph, which is what the PSX did with one channel.
var _click: AudioStreamPlayer = null
var _bg_level := 1.0


func _ready() -> void:
	ready_ok = true
	print("[BakedSfx] ready — WAV playback, no SPU (bus=%s/%s)" % [OUTPUT_BUS, BG_OUTPUT_BUS])


# --- the cast lifecycle -------------------------------------------------------

func begin_effect() -> int:
	_token_seq += 1
	return _token_seq


## Dispatch one pair of a cast, BY EFFECT ID.
##
## 🔴 **IT TAKES AN ID, NOT A PARSED BANK, AND THAT IS THE POINT.** The old signature was
## `play_pair(token, feds_bank, pair_idx, sound_id)` — the caller parsed an FFT opcode
## bank out of `feds.bin` and handed the object over so the engine could sequence it. To
## play a PRE-RENDERED WAV that is backwards: the bank was doing two jobs, naming the
## effect and carrying the opcodes, and only the NAME is still needed. `EffectInstance`
## knows its own `data_path`, so the id is free, and what is playable is decided by the
## baked manifest rather than by a pair count read off a parsed header.
##
## `single_track` (authoring per-track isolation) cannot be expressed by a finished stereo
## render, so it is REFUSED rather than silently ignored — a caller that asked for one
## track and got two would be measuring the wrong thing.
func play_pair(token: int, effect_id: String, pair_idx: int, sound_id: int = -1,
		single_track: int = -1) -> bool:
	if not ready_ok or effect_id.is_empty():
		return false
	if single_track >= 0:
		push_warning("BakedSfx: single_track isolation needs a renderer; not served here")
		return false
	return _fire(effect_id, pair_idx, OUTPUT_BUS)


## Is this pair playable? The manifest answers, which is what replaces the bounds check
## `pair_idx < feds_bank.num_pairs` used to make against a parsed header.
func has_pair(effect_id: String, pair_idx: int) -> bool:
	return not BakedAudio.sfx_row(effect_id, pair_idx).is_empty()


func end_effect(token: int) -> void:
	var pl: AudioStreamPlayer = _tokens.get(token)
	if pl != null:
		if is_instance_valid(pl):
			pl.stop()
			pl.queue_free()
		_tokens.erase(token)


## The cast's VISUAL ended but its SOUND should finish. A baked render already carries its
## own tail, so letting the player run out IS the orphan behaviour — the token is dropped
## so nothing comes back for it, and the player frees itself when it stops.
func orphan_effect(token: int) -> void:
	var pl: AudioStreamPlayer = _tokens.get(token)
	if pl != null:
		_tokens.erase(token)
		if is_instance_valid(pl) and not pl.playing:
			pl.queue_free()


# --- the global banks ---------------------------------------------------------

func play_one_shot(feds_path: String, pair_idx: int, sound_id: int = -1) -> int:
	return _audition(feds_path, pair_idx)


func audition(feds_path: String, pair_idx: int, sound_id: int = -1) -> int:
	return _audition(feds_path, pair_idx)


## Audition one pair by effect id — the Effect Studio's ▶ on a container or a pair.
func audition_id(effect_id: String, pair_idx: int, sound_id: int = -1) -> int:
	return _audition_id(effect_id, pair_idx) if not effect_id.is_empty() else 0


func _audition(feds_path: String, pair_idx: int) -> int:
	var id := BakedAudio.effect_id_from_feds_path(feds_path)
	return _audition_id(id, pair_idx) if not id.is_empty() else 0


func _audition_id(id: String, pair_idx: int) -> int:
	var st := BakedAudio.sfx_stream(id, pair_idx)
	if st == null:
		return 0
	_token_seq += 1
	return _token_seq if _bind(_token_seq, st, OUTPUT_BUS) else 0


## The per-glyph typewriter blip. Retrigger is stop-and-play on one reserved player.
func play_click(feds_path: String, pair_idx: int, sound_id: int = -1) -> int:
	var id := BakedAudio.effect_id_from_feds_path(feds_path)
	if id.is_empty():
		return 0
	var st := BakedAudio.sfx_stream(id, pair_idx)
	if st == null:
		return 0
	if _click == null:
		_click = AudioStreamPlayer.new()
		_click.bus = OUTPUT_BUS
		add_child(_click)
	_click.stop()
	_click.stream = st
	_click.play()
	return -1          # live and non-zero; this path's caller never ends it


# --- {6B} ambient beds --------------------------------------------------------
#
# The bed LOOPS and rides a volume ramp, and neither needs a sequencer: `loop` is the
# CALLER's answer (`SfxCatalog.is_loop`) and the ramp is `ScenarioBgSound`'s, which is a
# pure model computing `vol` 0..127 per 60 Hz tick from the event script's operands. All
# this layer does is turn that byte into `volume_db`.

func begin_bg(feds_path: String, pair_idx: int, sound_id: int, loop: bool = false) -> int:
	var id := BakedAudio.effect_id_from_feds_path(feds_path)
	if id.is_empty():
		return 0
	var st := BakedAudio.sfx_stream(id, pair_idx, loop)
	if st == null:
		return 0
	_token_seq += 1
	if not _bind(_token_seq, st, BG_OUTPUT_BUS):
		return 0
	_apply_bg_level(_tokens[_token_seq])
	return _token_seq


## Drive a bed's current volume (0..127). `0` keyed the SPU voice off; it stops here.
func set_bg_gain(token: int, vol_byte: int) -> void:
	var pl: AudioStreamPlayer = _tokens.get(token)
	if pl == null or not is_instance_valid(pl):
		return
	var v := clampi(vol_byte, 0, 127)
	if v <= 0:
		pl.stop()
		return
	if not pl.playing:
		pl.play()
	pl.volume_db = linear_to_db(clampf(float(v) / 127.0, 0.0001, 1.0) * _bg_level)


func stop_bg(token: int) -> void:
	end_effect(token)


## Ambient sub-level trim (0..1), seating a persistent bed UNDER combat SFX. A LEVEL, not
## limiting, applied on the players rather than the bus so it still works in a host that
## declares no bus layout.
func set_bg_level(level: float) -> void:
	_bg_level = clampf(level, 0.0, 1.0)
	for tk in _tokens:
		_apply_bg_level(_tokens[tk])


func get_bg_level() -> float:
	return _bg_level


func _apply_bg_level(pl) -> void:
	if pl != null and is_instance_valid(pl) and pl.bus == BG_OUTPUT_BUS:
		pl.volume_db = linear_to_db(clampf(_bg_level, 0.0001, 1.0))


# --- teardown + observability -------------------------------------------------

func stop_all() -> void:
	for pl in _pool:
		if is_instance_valid(pl):
			pl.stop()
	if _click != null and is_instance_valid(_click):
		_click.stop()
	for tk in _tokens.keys():
		var pl: AudioStreamPlayer = _tokens[tk]
		if is_instance_valid(pl):
			pl.stop()
			pl.queue_free()
	_tokens.clear()


## Hard reset to silence. Identical to `stop_all` here and that is not an oversight: the
## old engine's `panic` additionally cleared SPU voices and reverb tanks, and there are
## none. Kept as its own verb because ~36 call sites name it.
func panic() -> void:
	stop_all()


## How many baked renders are sounding. The ONLY way to tell this host apart from a
## synthesising one from outside, and what every test asserts on — `play_pair` and friends
## answer the same on both, so a test on the return value cannot see the difference.
func baked_playing_count() -> int:
	var n := 0
	for pl in _pool:
		if is_instance_valid(pl) and pl.playing:
			n += 1
	for tk in _tokens:
		var pl: AudioStreamPlayer = _tokens[tk]
		if is_instance_valid(pl) and pl.playing:
			n += 1
	if _click != null and is_instance_valid(_click) and _click.playing:
		n += 1
	return n


func debug_snapshot() -> Dictionary:
	return {
		"backend": "baked",
		"pool": _pool.size(),
		"sounding": baked_playing_count(),
		"bound_tokens": _tokens.size(),
		"bg_level": _bg_level,
		"corpus": BakedAudio.available(),
	}


# --- tunables (ADR-0113: declared here, bound by the host adapter) -------------

func tunables() -> Array[Dictionary]:
	return [
		{"slug": BAKED_ENABLED_SLUG, "label": "Baked WAVs",
			"default": true, "hint": {}, "setter": set_baked_enabled},
		{"slug": AUDIO_MONITOR_SLUG, "label": "Audio Monitor",
			"default": false, "hint": {}, "setter": set_audio_monitor_enabled},
	]


static var tunable_writer := func(_slug: String, _value: Variant) -> void: pass


func write_tunable(slug: String, value: Variant) -> void:
	tunable_writer.call(slug, value)


## `false` here no longer means "synthesise" — there is nothing to synthesise with. It
## means SILENCE for anything the corpus does not cover, which is why it is still worth
## having: it is the A/B that says whether a sound came from the corpus at all.
func set_baked_enabled(on: bool) -> void:
	BakedAudio.enabled = on


func set_audio_monitor_enabled(on: bool) -> void:
	audio_monitor_enabled = on


# --- internals ----------------------------------------------------------------

func _fire(id: String, pair_idx: int, bus: StringName) -> bool:
	var st := BakedAudio.sfx_stream(id, pair_idx)
	if st == null:
		return false
	var pl := _free_player(bus)
	if pl == null:
		return false
	pl.stream = st
	pl.play()
	if audio_monitor_enabled:
		print("[baked] %s pair %d" % [id, pair_idx])
	return true


func _free_player(bus: StringName) -> AudioStreamPlayer:
	for pl in _pool:
		if is_instance_valid(pl) and not pl.playing:
			pl.bus = bus
			return pl
	if _pool.size() < POOL_MAX:
		var pl := AudioStreamPlayer.new()
		pl.bus = bus
		add_child(pl)
		_pool.append(pl)
		return pl
	var victim := _pool[_next % _pool.size()]
	_next += 1
	victim.bus = bus
	return victim


func _bind(token: int, stream: AudioStreamWAV, bus: StringName) -> bool:
	if stream == null:
		return false
	var pl := AudioStreamPlayer.new()
	pl.bus = bus
	pl.stream = stream
	add_child(pl)
	_tokens[token] = pl
	pl.play()
	return true
