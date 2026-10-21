extends RefCounted
## The **particle subsystem** for an effect cast. Owns three [PhaseBlock]
## instances (one per phase), the emitter pool, and the particle physics step;
## duck-typed to the [Subsystem] contract (`advance(frame, phase)` / `reset()` /
## `is_done()`). No clock, no phase mirror (ADR-0014) — the [EffectTimeline]
## owns those; this subsystem owns its keyframe-cursor state, produces particle
## output, and re-emits the per-block emitter lifecycle signals as one unified
## surface for [EffectInstance]. See CONTEXT.md "Effect orchestration" for the
## vocabulary.
## Vault: [[E001 Emitter Interaction]]
## Vault: [[E001.BIN Memory Mapping]]
## Vault: [[Effect Execution Model]]
## Vault: [[Effect Frame Pacing]]
## Vault: [[Emitter Anchor Modes]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const ActiveEmitter = preload("res://addons/exmateria_effects/particles/ActiveEmitter.gd")
const EffectCurve = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const EffectEmitter = preload("res://addons/exmateria_effects/file_model/EffectEmitter.gd")
const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")
const ParticlePhysics = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")
const ParticlePool = preload("res://addons/exmateria_effects/particles/ParticlePool.gd")

## ADR-0212 dec. 1 — alias a published member back so every use site stays
## spelled the way it was (ADR-0211 dec. 4).
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


const PhaseBlockClass = preload("res://addons/exmateria_effects/subsystem/PhaseBlock.gd")
const ParticleAnimatorClass = preload("res://addons/exmateria_effects/particles/ParticleAnimator.gd")
const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")

var effect_data: EffectData

var particle_pool: ParticlePool
var physics: ParticlePhysics
var animator = null  # ParticleAnimator - untyped to avoid load order issues

# Per-instance RNG (ADR-0070). Set by the owning EffectInstance BEFORE
# initialize(); forwarded to `physics` so every stochastic spawn draw (spread,
# velocity cone) is deterministic within the instance. null = global fallback.
var rng: RandomNumberGenerator = null

# Back-reference to the cast's EffectTimeline — set by EffectInstance after
# constructing both. Single source of truth for clock + phase boundary state.
var timeline = null

var for_each_block = null      # PhaseBlock for the for-each (for_each) phase — lane 0's
## The for_each LANES (N36): lane k plays the ROM's for_each CHILD for target-table entry k
## (`outer_phases_timeline_tick` 0x801A4838 spawns one child per target; each runs
## `for_each_phase_timeline_tick` 0x801A3408 on its own target slot, ctx+0x26). Each lane is
## its own PhaseBlock, opened `for_each_lane_offsets[k]` frames after phase 1, and its
## emitters anchor at its own target. Lane 0 is `for_each_block`. ONE lane (the default) is
## the single-target document: its emitters are the document's, on `anchor_target`.
## `set_for_each_lanes` adds the others; then every lane's emitters are its own, keyed
## `k + 1` (0 stays the outer phases'), and anchor at `lane_targets[k + 1]`.
var for_each_lanes: Array = []
var for_each_lane_offsets: PackedInt32Array = PackedInt32Array([0])
## Effect-relative target position per emitter lane key; entry 0 is unused (the document's).
var lane_targets: Array = [Vector3.ZERO]
var phase1_block = null        # PhaseBlock for phase1
var phase2_block = null        # PhaseBlock for phase2

var phase1_duration: int = 0        # Frames until phase1 ends
var phase2_start: int = 0           # Frame when phase2 begins (runs parallel to for_each)
var effect_frame: int = 0           # Current effect frame counter

# Phase boundary state — read-through against the timeline's single source of
# truth (#30 step 6); the timeline computes them from its own effect_frame +
# boundaries. Falls back to false when the timeline isn't wired yet.
var phase1_finished: bool:
	get:
		return timeline != null and timeline.phase1_finished()
var phase2_started: bool:
	get:
		return timeline != null and timeline.phase2_started()


var active_emitters: Array[ActiveEmitter] = []

var _midlife_debug_logged: bool = false

# Per-edge child-spawn suppression (ADR-0075). Keyed by "<parent_index>:<edge>" where
# edge is "death" (child-on-death) or "midlife" (child-mid-life). A suppressed edge skips
# its child spawn at the two sites below — the child and its descendants never spawn. This
# is a SIMULATION change (a counterfactual), not the render-filter hide. It is config, not
# state: it deliberately survives reset() so every deterministic re-pump re-applies it.
var _suppressed_edges: Dictionary = {}

## A driven particle's lifetime: long enough that only its callback ends it.
const DRIVEN_LIFETIME: int = 1 << 30

var anchor_world: Vector3 = Vector3.ZERO
var anchor_cursor: Vector3 = Vector3.ZERO
var anchor_origin: Vector3 = Vector3.ZERO
var anchor_target: Vector3 = Vector3.ZERO
var anchor_camera: Vector3 = Vector3.ZERO  # PSX CAMERA anchor: (tile*14/28, 0, tile*14/28) relative to effect
var caster_facing_angle: float = 0.0  # Radians, Y-axis rotation for OUTWARD_UNIT_ORIENTED

var callback_manager = null  # CallbackManager

# Unified emitter lifecycle signal surface — re-emitted from the three inner
# phase controllers; EffectInstance subscribes once per signal type instead of
# nine times. Payload shape matches PhaseBlock's signals.
signal emitter_started(emitter_index: int, channel_index: int, frame: int)
signal emitter_stopped(emitter_index: int, channel_index: int, frame: int)
signal action_flags_triggered(flags: int, channel_index: int, frame: int)
## The phase lane (EffectPhase.PHASE1 / PHASE_FOR_EACH / PHASE2) of the keyframe the latest
## `action_flags_triggered` came from, set just before that emission. A listener reads it
## synchronously: the ROM runs the two kinds of lane differently (see EffectInstance
## `action_scope`).
var last_action_phase: String = ""
## The for_each lane (0 for an outer phase) of that same keyframe.
var last_action_lane: int = 0


func initialize(data: EffectData, pool_size: int = 256) -> void:
	"""Initialize manager with effect data"""
	effect_data = data
	particle_pool = ParticlePool.new(pool_size)
	physics = ParticlePhysics.new()
	animator = ParticleAnimatorClass.new()

	physics.gravity = data.gravity
	physics.inertia_threshold = data.inertia_threshold
	physics.effect_data = data  # For homing curve lookups
	physics.rng = rng  # Forward the instance RNG (ADR-0070) into the physics helpers

	animator.initialize(data)

	active_emitters.clear()
	effect_frame = 0

	if data.timeline:
		phase1_duration = data.timeline.phase1_duration
		var phase2_delay = data.timeline.phase2_delay
		phase2_start = phase1_duration + phase2_delay  # Single target formula

		phase1_block = _create_phase_block(data.timeline, EffectPhaseClass.PHASE1)
		phase2_block = _create_phase_block(data.timeline, EffectPhaseClass.PHASE2)
		for_each_block = _create_phase_block(data.timeline, EffectPhaseClass.PHASE_FOR_EACH)
		for_each_lanes = [for_each_block] if for_each_block != null else []
		for_each_lane_offsets = PackedInt32Array([0])
		lane_targets = [Vector3.ZERO]

		# Wire each controller's signals into the unified surface above so
		# EffectInstance can subscribe once instead of nine times (#30 step 4).
		var lanes := {EffectPhaseClass.PHASE1: phase1_block, EffectPhaseClass.PHASE2: phase2_block,
			EffectPhaseClass.PHASE_FOR_EACH: for_each_block}
		for lane in lanes:
			var ctrl = lanes[lane]
			if ctrl == null:
				continue
			ctrl.emitter_started.connect(_relay_emitter_started)
			ctrl.emitter_stopped.connect(_relay_emitter_stopped)
			ctrl.action_flags_triggered.connect(_relay_action_flags_triggered.bind(lane, 0))


## Give the document one for_each lane per target (N36): lane k opens `offsets[k]` frames
## after phase 1 (offsets[0] is lane 0's and must be 0 — the stride is relative to the first
## target). Called once, after initialize, before the clock runs. Its lanes k >= 1 are fresh
## PhaseBlocks over the same for_each channels; their emitters anchor at `set_lane_target(k)`.
## Their keyframes' emitter start/stop is not relayed (the document's lifecycle surface is
## lane 0's), and their ACTION keyframes are relayed with their lane, so the host can tell
## them apart (EffectInstance keeps lane 0's).
func set_for_each_lanes(offsets: PackedInt32Array) -> void:
	if for_each_block == null or offsets.size() <= 1:
		return
	for_each_lanes = [for_each_block]
	for_each_lane_offsets = offsets.duplicate()
	for_each_lane_offsets[0] = 0
	lane_targets = [Vector3.ZERO, anchor_target]
	# Phase 2 opens `phase2_delay` after the LAST child starts (0x801A4838:
	# phase1 + (N - 1) * spawn_delay + phase2_delay) — here, after the last lane's offset.
	phase2_start = phase1_duration + offsets[offsets.size() - 1] + effect_data.timeline.phase2_delay
	for k in range(1, offsets.size()):
		var block = _create_phase_block(effect_data.timeline, EffectPhaseClass.PHASE_FOR_EACH)
		block.action_flags_triggered.connect(
			_relay_action_flags_triggered.bind(EffectPhaseClass.PHASE_FOR_EACH, k))
		for_each_lanes.append(block)
		lane_targets.append(anchor_target)


func for_each_lane_count() -> int:
	return for_each_lanes.size()


## Where lane `k`'s emitters anchor (effect-relative), live: a lane's emitters move with it.
## A no-op on a single-lane document (its lane is the document's, on `anchor_target`).
func set_lane_target(k: int, target: Vector3) -> void:
	var key := _lane_key(k)
	if key <= 0 or key >= lane_targets.size():
		return
	lane_targets[key] = target
	for emitter in active_emitters:
		if emitter.for_each_lane == key:
			emitter.anchor_world = target
			emitter.anchor_cursor = target
			emitter.anchor_target = target


## The emitter lane key of for_each lane `k`: 0 on a single-lane document, else k + 1.
func _lane_key(k: int) -> int:
	return k + 1 if for_each_lanes.size() > 1 else 0


## True once every for_each lane has played its channels out (none = true).
func for_each_finished() -> bool:
	for block in for_each_lanes:
		if not block.is_finished():
			return false
	return true


## Every PhaseBlock the document runs: the outer phases and each for_each lane.
func _all_blocks() -> Array:
	var out: Array = []
	for block in [phase1_block, phase2_block]:
		if block != null:
			out.append(block)
	out.append_array(for_each_lanes)
	return out



func _create_phase_block(timeline_data, context: String):
	"""Create a timeline controller for a phase if it has channels, else null"""
	var channels = timeline_data.get_channels(context)
	if channels.is_empty():
		return null
	var ctrl = PhaseBlockClass.new()
	ctrl.initialize(timeline_data, context)
	return ctrl


func _relay_emitter_started(emitter_index: int, channel_index: int, frame: int) -> void:
	emitter_started.emit(emitter_index, channel_index, frame)


func _relay_emitter_stopped(emitter_index: int, channel_index: int, frame: int) -> void:
	emitter_stopped.emit(emitter_index, channel_index, frame)


func _relay_action_flags_triggered(flags: int, channel_index: int, frame: int, lane: String,
		lane_index: int = 0) -> void:
	last_action_phase = lane
	last_action_lane = lane_index
	action_flags_triggered.emit(flags, channel_index, frame)


func advance(frame: int, phase: Array) -> void:
	"""Process one fixed 30 Hz frame as the effect's **particle Subsystem**
	(ADR-0012). The [EffectTimeline] owns the clock and the accumulator and
	passes `(frame, open-phase-set)`; this:

	  1. mirrors `frame` into `effect_frame` for the internal reads (child
	     spawns, debug) and derives the phase flags its spawn logic needs,
	  2. ticks the spawn controllers for **every open phase** (multi-valued:
	     phase-2 runs parallel with for-each — model C), fulfilling spawns,
	  3. steps physics with `effect_frame = frame + 1` — matching the old path,
	     where `_process_timeline_frame` incremented the frame before the
	     separate physics accumulator ran, so child-spawn frame counters are
	     preserved exactly.

	Manual mode is gone: every real effect is timeline-driven (the only
	timeline-less effects are 0-byte empty slots; see ADR-0012)."""
	effect_frame = frame

	var spawn_requests: Array = []
	if EffectPhaseClass.PHASE1 in phase and phase1_block:
		spawn_requests.append_array(phase1_block.advance_frame())
	if EffectPhaseClass.PHASE_FOR_EACH in phase:
		# Lane k is the child for target k: it opens its offset after phase 1.
		for k in for_each_lanes.size():
			if frame - phase1_duration < for_each_lane_offsets[k]:
				continue
			for request in for_each_lanes[k].advance_frame():
				request["lane"] = _lane_key(k)
				spawn_requests.append(request)
	if EffectPhaseClass.PHASE2 in phase and phase2_block:
		spawn_requests.append_array(phase2_block.advance_frame())
	for request in spawn_requests:
		_process_spawn_request(request)

	# Physics tick — one fixed step, with effect_frame advanced to f+1 to match
	# the old two-accumulator order (timeline incremented the frame, then the
	# physics loop ran). Cleanup is inline so dead particles persist across
	# render frames between ticks.
	effect_frame = frame + 1
	_process_particle_deaths()
	particle_pool.cleanup_dead()
	_physics_step()
	_cleanup_finished_emitters()


func _process_spawn_request(request: Dictionary) -> void:
	"""Process a single spawn request from any phase controller."""
	var emitter_idx: int = request.emitter_index
	var spawn_counter: int = request.spawn_counter
	var channel_idx: int = request.get("channel_index", 0)
	var action_flags: int = request.get("action_flags", 0)
	var lane: int = request.get("lane", 0)

	# PSX disassembly at 0x801A40F0: andi v0,v0,0x7 → if non-zero, invoke callback
	var callback_slot: int = action_flags & 0x7
	if callback_slot != 0 and callback_manager:
		# The ROM gives each child its own callback slots (ctx+0xD4); the port has one
		# CallbackManager per document, so only lane 0 drives it (N36, ADR-0372 "Not claimed").
		if lane > 1:
			return
		# A seek invokes callbacks without a render pass. Launches and cached banks
		# need the authoritative subsystem anchors now, not next _process.
		callback_manager.update_anchors(anchor_origin, anchor_target,
			anchor_world, anchor_cursor, caster_facing_angle)
		var duration_remaining: int = request.get("duration_remaining", -1)
		callback_manager.invoke(callback_slot - 1, emitter_idx, spawn_counter, channel_idx, duration_remaining)
		return

	# Find or create an ActiveEmitter for this index
	var emitter = _get_or_create_emitter(emitter_idx, channel_idx, lane)
	if emitter:
		# Spawn particles for this frame
		emitter.spawn_particles_for_timeline(spawn_counter)


func current_phase() -> Array:
	"""The open phase-window SET for the frame just processed — what the timeline
	hands its subsystems via Subsystem.advance(frame, phase) (phase model C;
	ADR-0012). `phase2` overlaps `for_each`, so this is a set, not one
	value: multi-valued subsystems (particle/sound) run all open windows,
	single-valued subsystems (color) reduce it via EffectPhase.dominant().

	Valid after process_timeline_frame(): the flags are set from effect_frame
	before it is incremented, so they describe the frame just processed.
	"""
	if not phase1_finished:
		return [EffectPhaseClass.PHASE1]
	var open := [EffectPhaseClass.PHASE_FOR_EACH]
	if phase2_started:
		open.append(EffectPhaseClass.PHASE2)
	return open


func _get_or_create_emitter(emitter_index: int, channel_idx: int = 0, lane: int = 0) -> ActiveEmitter:
	"""Get existing emitter or create new one for timeline spawning. `lane` is the emitter
	lane key: a fanned-out document's for_each lanes have their own emitters, anchored at
	their own target (N36)."""
	for emitter in active_emitters:
		if emitter.emitter_index == emitter_index and emitter.for_each_lane == lane:
			return emitter

	# Create new emitter with very long duration (timeline controls lifetime)
	var config = effect_data.get_emitter(emitter_index)
	if config == null:
		push_error("Invalid emitter index: " + str(emitter_index))
		return null

	var emitter = ActiveEmitter.new()
	emitter.initialize(config, effect_data, particle_pool, physics, 10000)
	emitter.channel_index = channel_idx  # Set channel for Z-ordering

	emitter.anchor_world = anchor_world
	emitter.anchor_cursor = anchor_cursor
	emitter.anchor_origin = anchor_origin
	emitter.anchor_target = anchor_target
	emitter.anchor_camera = anchor_camera
	emitter.caster_facing_angle = caster_facing_angle
	if lane > 0 and lane < lane_targets.size():
		emitter.for_each_lane = lane
		emitter.anchor_world = lane_targets[lane]
		emitter.anchor_cursor = lane_targets[lane]
		emitter.anchor_target = lane_targets[lane]

	active_emitters.append(emitter)
	return emitter


func _physics_step() -> void:
	"""Execute one 30 FPS physics frame — PSX-accurate order from update_all_particles:
	1. Physics integration (velocity, position, accel — no age change)
	2. Homing arrival check
	3. Mid-life child spawn (parent has MOVED but age hasn't incremented)
	4. Age increment (separate from physics, matching PSX lifetime_counter -= 1)
	5. Animation tick
	"""
	var particles = particle_pool.get_active_particles()

	# Homing arrival check (PSX: runs before physics integration)
	for particle in particles:
		_check_homing_arrival(particle)

	# Physics integration (velocity, position, accel — NO age increment)
	physics.update_particles_fixed(particles)

	# Mid-life children AFTER physics (parent has moved) but BEFORE age increment
	_process_midlife_children()

	# Age increment (equivalent to PSX lifetime_counter -= 1)
	for particle in particles:
		particle.age += 1

	for particle in particles:
		animator.tick(particle)

	if callback_manager:
		callback_manager.physics_step()


func _check_homing_arrival(particle: Particle) -> void:
	if particle.homing_arrival_threshold <= 0.0:
		return
	if particle.lifetime == -1:
		return  # Already animation-driven
	var threshold: float = particle.homing_arrival_threshold
	if absf(particle.position.x - particle.homing_target.x) >= threshold:
		return
	if absf(particle.position.y - particle.homing_target.y) >= threshold:
		return
	if absf(particle.position.z - particle.homing_target.z) >= threshold:
		return
	particle.animation_held = false  # Clear hold so terminal frame can trigger death
	particle.lifetime = -1


func _process_particle_deaths() -> void:
	"""Spawn child emitters from dead particles before they are cleaned up."""
	var child_spawn_requests: Array = []

	for particle in particle_pool.get_active_particles():
		if particle.is_dead() or not particle.active:
			var parent_config = effect_data.get_emitter(particle.emitter_index)
			if parent_config and parent_config.is_child_death_enabled():
				if particle.child_emitter_on_death >= 0 and not is_child_edge_suppressed(particle.emitter_index, "death"):
					child_spawn_requests.append({
						"child_index": particle.child_emitter_on_death,
						"position": particle.position,
						"channel_index": particle.channel_index,
						"lane": particle.for_each_lane
					})

	# PSX uses effect_state->frame_counter for spawn interval gating, not particle age
	for request in child_spawn_requests:
		_spawn_child_emitter(request.child_index, request.position, effect_frame,
			request.get("channel_index", 0), request.get("lane", 0))


func _process_midlife_children() -> void:
	"""Spawn child emitters from alive particles with mid-life spawning enabled."""
	if not _midlife_debug_logged and EffectsDebug.particle():
		_midlife_debug_logged = true
		for i in range(effect_data.emitters.size()):
			var cfg = effect_data.get_emitter(i)
			if cfg and cfg.is_child_midlife_enabled():
				print("[MidLife] Emitter %d: child_mid=%d lifetime=%d..%d" % [
					i, cfg.child_emitter_mid_life, cfg.lifetime_min_start, cfg.lifetime_max_start])

	var child_spawn_requests: Array = []
	var dead_count: int = 0
	var no_mid_count: int = 0
	var flag_disabled_count: int = 0

	for particle in particle_pool.get_active_particles():
		if particle.is_dead() or not particle.active:
			dead_count += 1
			continue
		if particle.child_emitter_mid_life < 0:
			no_mid_count += 1
			continue
		var parent_config = effect_data.get_emitter(particle.emitter_index)
		if parent_config and parent_config.is_child_midlife_enabled() \
				and not is_child_edge_suppressed(particle.emitter_index, "midlife"):
			child_spawn_requests.append({
				"child_index": particle.child_emitter_mid_life,
				"position": particle.position,
				"channel_index": particle.channel_index,
				"lane": particle.for_each_lane
			})
		else:
			flag_disabled_count += 1

	if EffectsDebug.particle() and effect_frame % 30 == 0:
		var pool_size = particle_pool.get_active_count()
		print("[MidLife] frame=%d pool=%d dead=%d no_mid=%d disabled=%d requests=%d" % [
			effect_frame, pool_size, dead_count, no_mid_count, flag_disabled_count, child_spawn_requests.size()])

	# PSX uses effect_state->frame_counter for spawn interval gating, not particle age
	for request in child_spawn_requests:
		_spawn_child_emitter(request.child_index, request.position, effect_frame,
			request.get("channel_index", 0), request.get("lane", 0))


func _cleanup_finished_emitters() -> void:
	"""Remove finished emitters from active list."""
	var still_active: Array[ActiveEmitter] = []
	for emitter in active_emitters:
		if not emitter.is_done():
			still_active.append(emitter)
	active_emitters = still_active


func spawn_child_from_callback(child_emitter_index: int, parent_pos: Vector3, frame: int) -> void:
	"""Spawn child particles from a callback at a given position."""
	_spawn_child_emitter(child_emitter_index, parent_pos, frame, 0)


func _spawn_child_emitter(child_emitter_index: int, parent_pos: Vector3, frame_counter: int,
		channel_idx: int = 0, lane: int = 0) -> void:
	"""One-shot particle emission at parent's death position.

	Child emitters don't create persistent ActiveEmitters - they do a single
	emission of particles using the child emitter's config. The child emitter's
	spawn_interval determines if spawning happens this frame.
	"""
	var config = effect_data.get_emitter(child_emitter_index)
	if config == null:
		return

	var interval = config.spawn_interval_start
	if interval > 0 and frame_counter % interval != 0:
		return  # Interval check failed - no emission this frame

	var count = config.particle_count_start
	for i in range(count):
		var particle = particle_pool.acquire()
		if particle == null:
			if EffectsDebug.particle():
				print("[MidLife] POOL FULL for child emitter %d" % child_emitter_index)
			break
		_initialize_child_particle(particle, config, parent_pos, frame_counter, channel_idx, lane)


func _initialize_child_particle(particle: Particle, config: EffectEmitter,
								parent_pos: Vector3, frame: int, channel_idx: int = 0, lane: int = 0) -> void:
	"""Initialize particle from child emitter config at parent's death position.

	Child emitters use PARENT anchor mode - position is relative to parent particle's
	death location. Other physics properties come from the child emitter config.
	Child particles inherit the parent's channel_index for Z-ordering.
	"""
	var velocity_inward_flag = config.flags.get("velocity_inward", false)
	var align_to_facing_flag = config.flags.get("align_to_facing", false)
	var is_unit_oriented = velocity_inward_flag and align_to_facing_flag

	var offset = _interpolate_vec3_for_child("position", config.position_start,
											  config.position_end, config, frame)
	var spread = _interpolate_vec3_for_child("spread", config.spread_start,
											  config.spread_end, config, frame)

	# OUTWARD_UNIT_ORIENTED: rotate position offset and spread by facing
	if is_unit_oriented:
		offset = ActiveEmitter._rotate_y(offset, caster_facing_angle)
		spread = ActiveEmitter._rotate_y(spread, caster_facing_angle)

	var base_pos = parent_pos + offset
	var final_pos = base_pos + _apply_spread_for_child(spread, config)

	# Radial velocity (already Godot units/frame)
	var radial_vel = _interpolate_range_for_child("radial_velocity",
		config.radial_velocity_min_start, config.radial_velocity_max_start,
		config.radial_velocity_min_end, config.radial_velocity_max_end, config, frame)

	# 4-mode velocity dispatch based on velocity_inward + align_to_facing flags
	var velocity: Vector3
	if is_unit_oriented:
		# OUTWARD_UNIT_ORIENTED: outward (angle-based) + rotated by caster facing
		var vel_angle = _interpolate_vec3_for_child("velocity_base_angle",
			config.velocity_base_angle_start, config.velocity_base_angle_end, config, frame)
		var vel_spread = _interpolate_vec3_for_child("velocity_dir_spread",
			config.velocity_direction_spread_start, config.velocity_direction_spread_end, config, frame)
		var base_dir = ParticlePhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
		var final_dir = ParticlePhysics.random_cone_direction(base_dir, vel_spread, physics.rng)
		velocity = ActiveEmitter._rotate_y(final_dir * radial_vel, caster_facing_angle)
	elif velocity_inward_flag:
		# INWARD: direction from particle toward emitter center
		var to_center = base_pos - final_pos
		if to_center.length_squared() < 0.0001:
			velocity = Vector3(0, -radial_vel, 0)
		else:
			velocity = to_center.normalized() * radial_vel
	elif align_to_facing_flag:
		# SKIP: zero velocity (unimplemented in PSX, falls through)
		velocity = Vector3.ZERO
	else:
		# OUTWARD: standard angle-based direction
		var vel_angle = _interpolate_vec3_for_child("velocity_base_angle",
			config.velocity_base_angle_start, config.velocity_base_angle_end, config, frame)
		var vel_spread = _interpolate_vec3_for_child("velocity_dir_spread",
			config.velocity_direction_spread_start, config.velocity_direction_spread_end, config, frame)
		var base_dir = ParticlePhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
		var final_dir = ParticlePhysics.random_cone_direction(base_dir, vel_spread, physics.rng)
		velocity = final_dir * radial_vel

	# Lifetime (frames) - -1 means animation-driven (dies when animation completes)
	var lifetime: int = int(_interpolate_range_for_child("lifetime",
		float(config.lifetime_min_start), float(config.lifetime_max_start),
		float(config.lifetime_min_end), float(config.lifetime_max_end), config, frame))
	# Ensure positive lifetimes are at least 1, but preserve -1 for animation-driven
	if lifetime >= 0:
		lifetime = maxi(1, lifetime)

	particle.initialize(
		final_pos,
		velocity,
		lifetime,
		config.index,  # Child emitter is now the parent for further chaining
		config.child_emitter_on_death,
		config.child_emitter_mid_life
	)

	# Physics (inertia/weight are raw values)
	particle.inertia = _interpolate_range_for_child("inertia",
		config.inertia_min_start, config.inertia_max_start,
		config.inertia_min_end, config.inertia_max_end, config, frame)

	particle.weight = _interpolate_range_for_child("weight",
		config.weight_min_start, config.weight_max_start,
		config.weight_min_end, config.weight_max_end, config, frame)

	# Acceleration/drag (already Godot units)
	particle.acceleration = _interpolate_vec3_range_for_child("acceleration",
		config.acceleration_min_start, config.acceleration_max_start,
		config.acceleration_min_end, config.acceleration_max_end, config, frame)

	particle.drag = _interpolate_vec3_range_for_child("drag",
		config.drag_min_start, config.drag_max_start,
		config.drag_min_end, config.drag_max_end, config, frame)

	# Homing (already Godot units)
	particle.homing_strength = _interpolate_range_for_child("homing",
		config.homing_strength_min_start, config.homing_strength_max_start,
		config.homing_strength_min_end, config.homing_strength_max_end, config, frame)

	particle.homing_curve_index = config.curves.get("homing_blend", 0)

	var arrival_raw: int = config.flags.get("homing_arrival_threshold", 0)
	particle.homing_arrival_threshold = PsxMagnitude.tile_to_game(arrival_raw * 16.0) if arrival_raw > 0 else 0.0

	# Any NON-ZERO strength homes (negative = repel, e.g. E142 emitter 15's outward
	# dispersal); a `> 0` guard would strand the target. See HOMING_SYSTEM_ANALYSIS.md §7.
	if not is_zero_approx(particle.homing_strength):
		var target_offset = _interpolate_vec3_for_child("target_offset",
			config.target_offset_start, config.target_offset_end, config, frame)
		# For child particles, homing target uses anchors from manager
		particle.homing_target = _get_target_anchor_for_child(config, lane) + target_offset

	particle.anim_index = config.anim_index
	particle.channel_index = channel_idx  # Inherit parent's channel for Z-ordering
	particle.for_each_lane = lane  # and its for_each lane, so a grandchild homes on the same target

	# Set frameset group offset from anim_param (the one derivation — EffectData)
	particle.frameset_group_offset = effect_data.frameset_group_offset(config.anim_param)


func _get_target_anchor_for_child(config: EffectEmitter, lane: int = 0) -> Vector3:
	"""Get target anchor position for child emitter homing (a for_each lane's own target)."""
	if lane > 0 and lane < lane_targets.size():
		match config.get_target_anchor_mode():
			EffectEmitter.AnchorMode.ORIGIN: return anchor_origin
			EffectEmitter.AnchorMode.CAMERA: return anchor_camera
		return lane_targets[lane]
	match config.get_target_anchor_mode():
		EffectEmitter.AnchorMode.CURSOR: return anchor_cursor
		EffectEmitter.AnchorMode.ORIGIN: return anchor_origin
		EffectEmitter.AnchorMode.TARGET: return anchor_target
		# PARENT mode for target doesn't make sense for homing, use target
		EffectEmitter.AnchorMode.PARENT: return anchor_target
		EffectEmitter.AnchorMode.CAMERA: return anchor_camera
	return anchor_world


func _apply_spread_for_child(spread: Vector3, config: EffectEmitter) -> Vector3:
	"""Apply spread for child emitter."""
	if config.get_spread_mode() == EffectEmitter.SpreadMode.SPHERICAL:
		return _random_sphere(spread)
	return _random_box(spread)


func _random_sphere(spread: Vector3) -> Vector3:
	var theta = physics.rand() * TAU
	var phi = acos(2.0 * physics.rand() - 1.0)
	var r = pow(physics.rand(), 1.0/3.0)
	return Vector3(
		r * spread.x * sin(phi) * cos(theta),
		r * spread.y * cos(phi),
		r * spread.z * sin(phi) * sin(theta)
	)


func _random_box(spread: Vector3) -> Vector3:
	return Vector3(
		physics.rand_range(-spread.x, spread.x),
		physics.rand_range(-spread.y, spread.y),
		physics.rand_range(-spread.z, spread.z)
	)



func _interpolate_vec3_for_child(param: String, start: Vector3, end: Vector3,
								  config: EffectEmitter, frame: int) -> Vector3:
	var curve = _get_curve_for_child(param, config)
	return ParticlePhysics.interpolate_vec3(start, end, curve, frame)


func _interpolate_range_for_child(param: String, min_s: float, max_s: float,
								   min_e: float, max_e: float,
								   config: EffectEmitter, frame: int) -> float:
	var curve = _get_curve_for_child(param, config)
	return ParticlePhysics.interpolate_range(min_s, max_s, min_e, max_e, curve, frame, physics.rng)


func _interpolate_vec3_range_for_child(param: String, min_s: Vector3, max_s: Vector3,
										min_e: Vector3, max_e: Vector3,
										config: EffectEmitter, frame: int) -> Vector3:
	var curve = _get_curve_for_child(param, config)
	return ParticlePhysics.interpolate_vec3_range(min_s, max_s, min_e, max_e, curve, frame, physics.rng)


func _get_curve_for_child(param: String, config: EffectEmitter) -> EffectCurve:
	if not config.curves.has(param):
		return null
	var idx = config.curves[param]
	if idx < 0:
		return null
	return effect_data.get_curve(idx)


func acquire_driven_particle(emitter_index: int, pos: Vector3) -> Particle:
	"""A particle a CALLBACK positions itself each physics step, rather than one the
	emitter launches (ADR-0369 — TrapOrbitalCallback's orbs). It renders through the
	ordinary sprite path with the emitter's animation and frameset group; it has no
	velocity or weight, so the integrator leaves it where the callback put it, and an
	effectively endless lifetime, so it lives until the callback deactivates it. Null
	when the pool is exhausted or the emitter does not exist."""
	var config = effect_data.get_emitter(emitter_index)
	if config == null:
		return null
	var particle = particle_pool.acquire()
	if particle == null:
		return null
	particle.initialize(pos, Vector3.ZERO, DRIVEN_LIFETIME, emitter_index)
	particle.inertia = 4096.0
	particle.weight = 0.0
	particle.anim_index = config.anim_index
	particle.frameset_group_offset = effect_data.frameset_group_offset(config.anim_param)
	return particle


func get_active_particles() -> Array[Particle]:
	"""Return active particles directly (no dict copy)"""
	return particle_pool.get_active_particles()


func get_active_particle_count() -> int:
	return particle_pool.get_active_count()


func get_last_active_effect_frame() -> int:
	"""Get the last effect_frame that will spawn particles across all phases."""
	var last: int = 0
	if phase1_block:
		last = maxi(last, phase1_block.last_active_keyframe_time)
	if for_each_block:
		last = maxi(last, for_each_block.last_active_keyframe_time + phase1_duration
			+ for_each_lane_offsets[for_each_lane_offsets.size() - 1])
	if phase2_block:
		last = maxi(last, phase2_block.last_active_keyframe_time + phase2_start)
	return last


func stop_spawning() -> void:
	"""End every timeline channel NOW (EffectInstance.release): no new spawn request or
	callback invoke is issued again, and the particles already alive run out their lives."""
	for block in _all_blocks():
		for state in block.channel_states:
			state.finished = true


func is_quiescent() -> bool:
	"""Nothing will ever draw again: every timeline channel has finished (or was stopped),
	no particle is alive and no callback is active. Unlike is_done() this ignores the
	ActiveEmitter list — a timeline-driven emitter is created with a 10000-frame duration
	and never deactivates, so it says nothing about whether the effect is over."""
	for block in _all_blocks():
		if not block.is_finished():
			return false
	if particle_pool.get_active_count() > 0:
		return false
	if callback_manager and callback_manager.has_active_callbacks():
		return false
	return true


func is_done() -> bool:
	"""Check if all emitters finished, no particles remain, and no active callbacks"""
	if not active_emitters.is_empty():
		return false
	if particle_pool.get_active_count() > 0:
		return false
	if callback_manager and callback_manager.has_active_callbacks():
		return false
	return true


## Per-edge child-spawn suppression (ADR-0075). `edge` is "death" or "midlife".
static func _edge_key(parent_index: int, edge: String) -> String:
	return "%d:%s" % [int(parent_index), edge]


func set_child_edge_suppressed(parent_index: int, edge: String, suppressed: bool) -> void:
	"""Suppress (or restore) a parent emitter's spawn of one child edge. Off-only in
	practice — the caller re-seeks the instance to re-derive the frame (ADR-0070)."""
	var key := _edge_key(parent_index, edge)
	if suppressed:
		_suppressed_edges[key] = true
	else:
		_suppressed_edges.erase(key)


func is_child_edge_suppressed(parent_index: int, edge: String) -> bool:
	return _suppressed_edges.has(_edge_key(parent_index, edge))


func reset() -> void:
	"""Reset the effect - clear all particles and restart all timelines"""
	active_emitters.clear()

	particle_pool.clear()

	effect_frame = 0
	_midlife_debug_logged = false

	if callback_manager:
		callback_manager.reset()

	if effect_data.timeline:
		if phase1_block:
			phase1_block.initialize(effect_data.timeline, EffectPhaseClass.PHASE1)
		if phase2_block:
			phase2_block.initialize(effect_data.timeline, EffectPhaseClass.PHASE2)
		for block in for_each_lanes:
			block.initialize(effect_data.timeline, EffectPhaseClass.PHASE_FOR_EACH)


func set_anchors(world: Vector3, cursor: Vector3, origin: Vector3, target: Vector3) -> void:
	"""Set all anchor positions"""
	anchor_world = world
	anchor_cursor = cursor
	anchor_origin = origin
	anchor_target = target

	for emitter in active_emitters:
		emitter.anchor_origin = origin
		if emitter.for_each_lane > 0:
			continue  # a lane's own target (set_lane_target)
		emitter.anchor_world = world
		emitter.anchor_cursor = cursor
		emitter.anchor_target = target


func get_emitter_count() -> int:
	"""Get number of emitters in effect data"""
	return effect_data.emitters.size() if effect_data else 0
