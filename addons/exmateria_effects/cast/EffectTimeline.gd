extends RefCounted
## The effect-cast orchestrator (ADR-0011 / ADR-0012 / ADR-0014). Owns the
## **fixed-timestep accumulator**, the `effect_frame` clock, the phase boundaries,
## and **time-modulation outright** — it holds the pacing curve and computes the
## factor from its own frame + phase (ADR-0014, superseding ADR-0012 coupling 1;
## no longer reads it back from the particle subsystem). Pumps an **ordered
## list of subsystems** once per fixed 30 Hz frame via
## `Subsystem.advance(frame, phase)`.
##
## It is **output-agnostic**: it pumps *time* only and never learns what a
## subsystem produces — each subsystem **self-delivers** its own output
## (ADR-0014). Three clock planes meet here (ADR-0011): variable render
## `delta` in → fixed 30 Hz `effect_frame` out; the SPU (audio rate) is
## downstream of the sound subsystem's key-on and not pumped here.
##
## NOTE: no `class_name` — instantiated **by path** (`preload(...).new()`), per
## the ADR-0004 cache-safety pattern (a new class_name is invisible to fresh
## headless loads until the editor rebuilds the global class cache).
## Vault: [[Effect Frame Pacing]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")
const PHYSICS_TIMESTEP: float = 1.0 / 30.0  # FFT game-loop rate
const BASE_PACING: int = 2                   # FFT pacing baseline; factor = BASE/pacing

# Phase boundaries (from the timeline header) — used to resolve the open
# phase-window set each frame (phase model C, ADR-0012).
var phase1_duration: int = 0
var phase2_start: int = 0

# The fixed clock this orchestrator owns.
var effect_frame: int = 0

# Ordered subsystems, pumped in registration order (particle → sound → color → camera).
var _subsystems: Array = []

# Time-modulation — the timeline owns it outright (ADR-0014, superseding ADR-0012
# coupling 1): it holds the pacing curve and computes the factor from its OWN
# frame + phase, no longer reading it back from the particle subsystem.
var _time_scale_data: Dictionary = {}
var _time_scale_factor: float = 1.0
var _current_pacing_value: int = BASE_PACING
var _phase1_was_finished_last_frame: bool = false
# Phase-local cursors into the pacing curve, incremented once per open-phase
# frame — the faithful index the old particle phase-controllers' `current_frame`
# supplied. `for-each`-local is **B-shaped**: today the single-target for-each
# frame; the per-target for-each-pass cursor under the backlogged ROM
# multi-target model (project backlog).
var _p1_local_frame: int = 0
var _for_each_local_frame: int = 0

var _accumulator: float = 0.0
var _first_tick: bool = true
var _started: bool = false

# Per-instance RNG (ADR-0070). The timeline doesn't OWN the randomness — the
# subsystems draw from this same reference — but it holds the seed and re-applies
# it in reset(), because reset() is the one place both a loop-restart AND a
# backward seek (reset + re-pump) funnel through. Re-seeding here is what makes
# in-instance replay bit-identical.
var _rng: RandomNumberGenerator = null
var _rng_seed: int = 0
var _has_rng: bool = false


func setup(p1_duration: int, p2_start: int, time_scale_data: Dictionary = {}) -> void:
	"""Phase boundaries from the timeline header (single-target formula), plus the
	time-modulation pacing curve the timeline now owns (ADR-0014). Empty dict =
	no time-modulation (factor stays 1.0)."""
	phase1_duration = p1_duration
	phase2_start = p2_start
	_time_scale_data = time_scale_data


func set_subsystems(subsystems: Array) -> void:
	"""Register the ordered subsystem list, pumped in order each fixed frame;
	nulls are skipped (a cast may lack a color/camera/sound subsystem)."""
	_subsystems = subsystems


func start() -> void:
	"""Begin advancing. Mirrors the old ParticleSubsystem.enable_timeline() gate:
	the cast is set up (anchors, controllers) before the clock runs."""
	_started = true


func tick(delta: float) -> void:
	"""Advance the fixed clock by `delta` of (time-scaled) wall-clock and pump
	every subsystem once per elapsed fixed frame. No-op until start()."""
	if not _started:
		return
	# Clamp the first delta after init/reset so a load hitch doesn't skip frames.
	if _first_tick:
		delta = minf(delta, PHYSICS_TIMESTEP)
		_first_tick = false
	# Time-modulation: the factor computed on the previous frame scales this
	# accumulation (one-frame lag, identical to the old particle-subsystem path).
	_accumulator += delta * _time_scale_factor
	while _accumulator >= PHYSICS_TIMESTEP:
		_accumulator -= PHYSICS_TIMESTEP
		_advance_one_frame()


func _advance_one_frame() -> void:
	"""Pump every subsystem for the CURRENT `effect_frame`, step the pacing
	cursors + time-scale factor, then advance the clock by one. The single
	frame-quantum shared by wall-clock [method tick] and the deterministic
	[method seek] — so seek(N) reproduces exactly what N ticks would (ADR-0070)."""
	var phase: Array = EffectPhaseClass.open_phases(effect_frame, phase1_duration, phase2_start)
	for subsystem in _subsystems:
		if subsystem != null:
			subsystem.advance(effect_frame, phase)
	# Time-modulation (ADR-0014): advance the phase-local cursors for the
	# open phases (mirroring the old phase-controllers), then recompute the
	# factor for the next accumulation. Order matches the old path: cursors
	# step inside the frame, the factor reads the stepped value.
	if EffectPhaseClass.PHASE1 in phase:
		_p1_local_frame += 1
	if EffectPhaseClass.PHASE_FOR_EACH in phase:
		_for_each_local_frame += 1
	_update_time_scale(phase)
	effect_frame += 1


func set_rng(rng: RandomNumberGenerator, seed_value: int) -> void:
	"""Register the cast's per-instance RNG + its spawn seed (ADR-0070). The
	timeline re-applies `seed_value` on every reset() so a loop restart or a
	backward seek replays the identical stochastic cloud."""
	_rng = rng
	_rng_seed = seed_value
	_has_rng = rng != null


func seek(target_frame: int) -> void:
	"""Frame-exact deterministic seek (CONTEXT "Playhead / scrub"). Forward:
	pump the delta from the current frame. Backward: reset() (re-seeds the RNG,
	restarts every subsystem) then re-pump from 0. NEVER wall-clock `tick(delta)`
	— the accumulator's one-frame time-mod lag would drift the landing frame."""
	target_frame = maxi(0, target_frame)
	if not _started:
		return
	if target_frame < effect_frame:
		reset()
	while effect_frame < target_frame:
		_advance_one_frame()


func rescrub() -> void:
	"""Re-fold the CURRENT frame in place: reset() then re-pump from 0 back to the
	current effect_frame. Unlike `seek(effect_frame)` — a same-frame no-op that folds
	nothing — this forces every subsystem to recompute, so an authoring edit to a
	FOLDED channel (camera framing, unlike the read-live screen colour) shows without
	scrubbing away and back. Deterministic: the reset re-seeds the RNG (ADR-0070), so
	the re-pump reproduces the identical state at the same frame."""
	var target := effect_frame
	if not _started:
		return
	reset()
	while effect_frame < target:
		_advance_one_frame()


func current_phase() -> Array:
	"""The open phase-window set at the current frame (for callers that need it
	outside a tick)."""
	return EffectPhaseClass.open_phases(effect_frame, phase1_duration, phase2_start)


func phase1_finished() -> bool:
	"""True once the clock has advanced past phase1's last frame. The single
	source of truth for the boundary — callers (e.g. ParticleSubsystem) read
	through this instead of mirroring the flag locally."""
	return effect_frame >= phase1_duration


func phase2_started() -> bool:
	"""True once the clock has reached phase2's start frame. Counterpart to
	[method phase1_finished]; same single-source-of-truth discipline."""
	return effect_frame >= phase2_start


func is_started() -> bool:
	return _started


func _update_time_scale(phase: Array) -> void:
	"""Recompute `_time_scale_factor` from the pacing curve at the current
	phase-local cursor (ADR-0014; ported verbatim from the old
	`ParticleSubsystem._update_time_scale_for_frame`, with the particle-controller
	`current_frame` replaced by the timeline's own `_p1_local_frame` /
	`_for_each_local_frame`). Pattern 1 keys off phase-1, pattern 2 off for-each;
	the phase-1→for-each edge resets pacing to base."""
	if _time_scale_data.is_empty():
		return
	var phase1_finished: bool = not (EffectPhaseClass.PHASE1 in phase)
	var flags: Dictionary = _time_scale_data.get("flags", {})
	var new_pacing: int = 0  # 0 = no override

	# Pattern 1: outer_phases — during phase1, keyed by the phase-1 local cursor.
	if flags.get("time_scale_pattern1", false) and not phase1_finished:
		var outer_phases: Array = _time_scale_data.get("outer_phases", [])
		if _p1_local_frame >= 0 and _p1_local_frame < outer_phases.size():
			new_pacing = int(outer_phases[_p1_local_frame])

	# Pattern 2: for_each — during for-each, keyed by the for-each local cursor.
	if flags.get("time_scale_pattern2", false) and phase1_finished:
		var for_each: Array = _time_scale_data.get("for_each", [])
		if _for_each_local_frame >= 0 and _for_each_local_frame < for_each.size():
			new_pacing = int(for_each[_for_each_local_frame])

	# Reset to base when phase1 just finished.
	if phase1_finished and not _phase1_was_finished_last_frame:
		new_pacing = BASE_PACING
	_phase1_was_finished_last_frame = phase1_finished

	# Apply: values 1-9 valid, override only when > base.
	if new_pacing >= 1 and new_pacing <= 9 and new_pacing > BASE_PACING:
		_current_pacing_value = new_pacing
		_time_scale_factor = float(BASE_PACING) / float(_current_pacing_value)
	elif new_pacing >= 1 and new_pacing <= BASE_PACING:
		_current_pacing_value = BASE_PACING
		_time_scale_factor = 1.0
	# 0 and 10-15: leave current pacing unchanged

	if EffectsDebug.timeline() and _current_pacing_value != BASE_PACING:
		print("[TimeScale] frame=%d pacing=%d factor=%.3f" % [effect_frame, _current_pacing_value, _time_scale_factor])


func reset() -> void:
	"""Restart the clock, time-modulation, and every subsystem. Re-applies the
	per-instance RNG seed FIRST (ADR-0070) so the re-pump after a reset — a loop
	restart or a backward seek — reproduces the identical cloud."""
	if _has_rng:
		_rng.seed = _rng_seed
	effect_frame = 0
	_accumulator = 0.0
	_first_tick = true
	_time_scale_factor = 1.0
	_current_pacing_value = BASE_PACING
	_phase1_was_finished_last_frame = false
	_p1_local_frame = 0
	_for_each_local_frame = 0
	for subsystem in _subsystems:
		if subsystem != null:
			subsystem.reset()
