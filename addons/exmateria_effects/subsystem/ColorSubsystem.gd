extends RefCounted
## Base for the **color** family of subsystems — the shared scaffolding behind
## [ScreenSubsystem] and [PaletteSubsystem] (which are color-family subtypes,
## not separate subsystems). Renamed from ColorTrackController as part of the
## Track→Subsystem migration (#31).
##
## NOTE: this base intentionally omits `class_name` and is extended **by path**
## (`extends "res://addons/exmateria_effects/subsystem/ColorSubsystem.gd"`). A newly-added `class_name`
## base is invisible until Godot rebuilds its global class cache in the editor,
## which breaks fresh/headless loads of the path-preloaded subtypes. Path-based
## `extends` resolves the supertype with no cache dependency. Same reasoning as
## ADR-0004's extend-by-path convention.
##
## Screen is the background color; palette is map / unit tinting. See CONTEXT.md
## "Effect orchestration".
##
## A color subsystem is pumped once per frame by [EffectTimeline] via
## [method advance]. This base owns everything the two subtypes share:
##   - the once-per-frame guard,
##   - the per-(channel, phase) keyframe **cursor** (`current_keyframe` +
##     `frame_within_kf`) and its advance,
##   - the per-(channel, phase) transition state and the from→to lerp helper
##     ([method _run_transition]),
##   - `owner_id` for overlay ownership, and
##   - the [method reset] skeleton.
##
## Subtypes own only their **channel set** and their PSX blend math, expressed
## as [method _evaluate] (one keyframe step for one channel in one phase) and
## [method _reset_outputs] (clear their color output state). A subtype with a
## single channel (screen) is the degenerate one-channel case of the N-channel
## model (palette: affected_units / caster / target).
##
## The orchestrator owns the clock AND the phase and passes both to
## [method advance]; a color subsystem never recomputes the phase from the frame.
## Vault: [[Color Track Interpolation]]

const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")

# Channel names this subsystem processes. One implicit channel for screen; three
# for palette. Set once by the subtype via _setup_channels().
var channels: Array = []

# Per (channel, phase) keyframe cursor.
var current_keyframe: Dictionary = {}   # channel -> phase -> int
var frame_within_kf: Dictionary = {}     # channel -> phase -> int

# Per (channel, phase) transition (from→to interpolation over a duration).
var transition_from: Dictionary = {}     # channel -> phase -> Color
var transition_to: Dictionary = {}       # channel -> phase -> Color
var transition_active: Dictionary = {}   # channel -> phase -> bool

# Once-per-frame guard: the timeline may call advance() more than once for the
# same frame; only the first does work, the rest are no-ops (outputs hold).
var _frame: int = 0
var _has_processed_frame: bool = false

# The dominant phase currently playing, and the frame it began — so a subtype can
# evaluate a declarative timeline (the ADR-0067 ColorStack) at a PHASE-RELATIVE
# `now` (_phase_now()), matching keyframe start frames that count from 0 within the
# phase. Reset whenever the dominant phase changes.
var _active_phase: String = ""
var _phase_start_frame: int = 0

# Absolute frame at which each phase first became dominant. The color engine has no
# phase concept on PSX (one stateful CLUT DDA); this lets a subtype rebuild the WHOLE
# keyframe stream at its true offsets (ColorStack via build_stream) instead of a
# per-phase slice that resets at each boundary and pops. Populated as phases start.
var _phase_first_frame: Dictionary = {}   # phase -> absolute start frame

# Unique ID for this controller, used by the overlays to own their layer.
var owner_id: int = 0

# Debug-only per-lane mute filter (Effect Studio Solo/Mute). A set-style Dictionary of
# the subtype's own lane keys whose EVENTS are excluded from build_stream (screen keys by
# phase, palette by "<phase>/<channel>"). Muting every key ⇒ an empty stream ⇒ neutral
# output (the tint is removed, not frozen). Never set by the runtime; the Studio host
# toggles it via set_muted(). See CONTEXT.md "Subsystem".
var _muted_ops: Dictionary = {}


func _setup_channels(channel_names: Array) -> void:
	"""Declare this subsystem's channels and zero every per-(channel, phase) cell.

	Call once from the subtype's initialize(), after owner_id is wanted.
	"""
	channels = channel_names
	owner_id = randi()
	for ch in channels:
		current_keyframe[ch] = {}
		frame_within_kf[ch] = {}
		transition_from[ch] = {}
		transition_to[ch] = {}
		transition_active[ch] = {}
		for phase in EffectPhaseClass.ALL:
			current_keyframe[ch][phase] = 0
			frame_within_kf[ch][phase] = 0
			transition_from[ch][phase] = Color.BLACK
			transition_to[ch][phase] = Color.BLACK
			transition_active[ch][phase] = false


# --- Subsystem contract ---------------------------------------------------

func advance(frame: int, phase) -> void:
	"""Process one frame for every channel.

	`phase` is the open phase-window SET (phase model C; ADR-0012). A color
	subsystem is single-valued (one background, one tint), so it plays the
	**dominant** open window — the set collapses harmlessly here. (A plain
	string is also accepted, for direct/test callers.) The orchestrator owns
	the phase; the subsystem never recomputes it. Calling twice for the same
	frame is a no-op.
	"""
	if frame == _frame and _has_processed_frame:
		return
	_has_processed_frame = true
	_frame = frame
	var dominant_phase: String = phase if phase is String else EffectPhaseClass.dominant(phase)
	if dominant_phase != _active_phase:
		# New phase (or the first) — its keyframe timeline starts counting here.
		_active_phase = dominant_phase
		_phase_start_frame = frame
		# Record the phase's absolute start once (the single-pass timeline never
		# re-enters an earlier phase), so build_stream can place its ops in the one
		# continuous stream at their true offsets.
		if not _phase_first_frame.has(dominant_phase):
			_phase_first_frame[dominant_phase] = frame
	for ch in channels:
		_evaluate(ch, dominant_phase)
	# Self-deliver this subsystem's held output to its overlay sink (ADR-0014). The
	# subsystem owns its I/O; EffectInstance is not a courier. Pushed only on frames
	# that did work (the once-per-frame guard above) — the overlay retains the
	# layer between ticks, so frame cadence is equivalent to the old render-cadence
	# push and drops the redundant per-render-frame recomposite.
	_deliver_output()


## Force an in-place re-fold + re-deliver at the CURRENT frame WITHOUT advancing the clock
## (#255 authoring re-fold). The once-per-frame guard holds each subsystem's folded output
## between ticks, so a live-keyframe edit (colour is read-live) needs the held output
## rebuilt from the now-mutated keyframes to reach the overlay — a repaint in place, NOT a
## reset + re-pump (ADR-0070). Re-evaluates every channel at the already-active phase and
## re-delivers. A no-op-equivalent when nothing changed (folds identical live data).
func redeliver() -> void:
	for ch in channels:
		_evaluate(ch, _active_phase)
	_deliver_output()


func reset() -> void:
	"""Reset every cursor and transition to its initial state."""
	for ch in channels:
		for phase in EffectPhaseClass.ALL:
			current_keyframe[ch][phase] = 0
			frame_within_kf[ch][phase] = 0
			transition_from[ch][phase] = Color.BLACK
			transition_to[ch][phase] = Color.BLACK
			transition_active[ch][phase] = false
	_frame = 0
	_has_processed_frame = false
	_active_phase = ""
	_phase_start_frame = 0
	_phase_first_frame = {}
	_reset_outputs()


func get_owner_id() -> int:
	return owner_id


## Set the per-lane mute filter (Studio Solo/Mute) and re-fold the current frame
## immediately, so a toggle shows even while the preview is parked (no next tick):
## build_stream skips the muted keys, so the re-delivered stream drops those lanes' events
## (all keys muted ⇒ empty ⇒ neutral). Keys are subtype-defined (screen: phase; palette:
## "<phase>/<channel>"). _active_phase is left untouched so the re-fold stays in phase.
func set_muted(filter: Dictionary) -> void:
	_muted_ops = filter
	_has_processed_frame = false
	advance(_frame, _active_phase)


func is_muted(key: String) -> bool:
	return _muted_ops.has(key)


func _phase_now() -> int:
	"""Frames elapsed since the current dominant phase began — the phase-relative
	clock a declarative ColorStack timeline (ADR-0067) is evaluated at."""
	return _frame - _phase_start_frame


# --- Shared scaffolding for subtypes --------------------------------------

func _advance_cursor(channel: String, phase: String) -> void:
	"""Advance a channel's cursor to the next keyframe (state only; subtypes
	add their own KF_DEBUG trace around this)."""
	current_keyframe[channel][phase] = current_keyframe[channel].get(phase, 0) + 1
	frame_within_kf[channel][phase] = 0
	transition_active[channel][phase] = false


func _run_transition(from_color: Color, to_color: Color, frame: int, duration: int) -> Color:
	"""Linearly interpolate from→to over `duration` frames.

	progress = (frame + 1) / duration, so the value reaches `to` on the last
	frame (frame == duration - 1). Shared by screen and palette; each subtype
	decides what `from`/`to`/`duration` are.
	"""
	var progress := clampf(float(frame + 1) / float(maxi(1, duration)), 0.0, 1.0)
	return from_color.lerp(to_color, progress)


# --- Hooks subtypes must / may override -----------------------------------

func _evaluate(_channel: String, _phase: String) -> void:
	"""Process one keyframe step for one channel in one phase. Override."""
	push_error("ColorSubsystem._evaluate must be overridden by %s" % get_script().resource_path)


func _reset_outputs() -> void:
	"""Reset subtype-specific color output state (called by reset()). Override
	if the subtype holds output colors / registers beyond the cursor state."""
	pass


func _deliver_output() -> void:
	"""Push this subsystem's held output to its overlay sink (ADR-0014). Override in
	subtypes that have a sink (screen → screen overlay, palette → map/unit tint
	overlays); the base default is inert, for a-la-carte / test callers that drive
	advance() without an overlay."""
	pass
