class_name VfxEffectManager
extends RefCounted
## Orchestrator — manages active emitters, physics, animation, timelines, and child spawning
## Port of godot-learning's EmitterManager.gd

const PHYSICS_TIMESTEP: float = VfxConstants.TICK_DURATION

# Effect data
var vfx_data: VisualEffectData

# (physics + animator owned per-emitter in VfxActiveEmitter)

# Active emitters
var active_emitters: Array[VfxActiveEmitter] = []

# Timeline controllers (one per phase)
var phase1_controller: VfxTimelineController
var phase2_controller: VfxTimelineController
var animate_tick_controller: VfxTimelineController
var timeline_enabled: bool = false

# Phase timing (from timeline header)
var phase1_duration: int = 0
var phase2_start: int = 0
var effect_frame: int = 0

# Phase state
var phase1_finished: bool = false
var phase2_started: bool = false

# Single accumulator — timeline + physics tick atomically to stay in sync
var tick_accumulator: float = 0.0

# First-update flag to prevent large delta jumps on init/reset
var _first_update_after_init: bool = true

# Anchors (set by caller)
var anchor_world: Vector3 = Vector3.ZERO
var anchor_cursor: Vector3 = Vector3.ZERO
var anchor_origin: Vector3 = Vector3.ZERO
var anchor_target: Vector3 = Vector3.ZERO

# Debug: empty = show all emitters, otherwise per-emitter toggle (true = enabled)
var debug_emitter_mask: Array[bool] = []

# Signal for action flags (Phase 6 battle integration)
signal action_flags_triggered(flags: int, channel_index: int, frame: int)


func initialize(data: VisualEffectData) -> void:
	vfx_data = data

	active_emitters.clear()
	tick_accumulator = 0.0
	effect_frame = 0
	phase1_finished = false
	phase2_started = false
	_first_update_after_init = true

	# Phase timing from parsed TIMELINES header
	phase1_duration = data.phase1_duration
	phase2_start = phase1_duration + data.phase2_offset

	# Create timeline controllers from pre-parsed timeline arrays
	phase1_controller = _create_controller(data.phase1_emitter_timelines)
	animate_tick_controller = _create_controller(data.child_emitter_timelines)
	phase2_controller = _create_controller(data.phase2_emitter_timelines)

	timeline_enabled = false


func _create_controller(timelines: Array[VisualEffectData.EmitterTimeline]) -> VfxTimelineController:
	# Check if any channel has keyframes
	var has_data: bool = false
	for tl: VisualEffectData.EmitterTimeline in timelines:
		if tl.num_keyframes >= 1:
			has_data = true
			break

	if not has_data:
		return null

	var ctrl := VfxTimelineController.new()
	ctrl.initialize(timelines)
	ctrl.action_flags_triggered.connect(_on_action_flags)
	return ctrl


func _on_action_flags(flags: int, channel_index: int, frame: int) -> void:
	action_flags_triggered.emit(flags, channel_index, frame)


func enable_timeline() -> void:
	if animate_tick_controller or phase1_controller:
		timeline_enabled = true


func start_emitter(emitter_index: int, duration: int = 120) -> VfxActiveEmitter:
	if emitter_index < 0 or emitter_index >= vfx_data.emitters.size():
		push_error("VfxEffectManager: Invalid emitter index: " + str(emitter_index))
		return null

	var emitter_config: VfxEmitter = vfx_data.emitters[emitter_index]
	var emitter := VfxActiveEmitter.new()
	emitter.initialize(emitter_config, emitter_index, vfx_data, duration)
	_apply_anchors(emitter)
	active_emitters.append(emitter)
	return emitter


func update(delta: float) -> void:
	# Clamp first delta after init/reset to prevent large frame jumps
	if _first_update_after_init:
		delta = minf(delta, PHYSICS_TIMESTEP)
		_first_update_after_init = false

	tick_accumulator += delta
	while tick_accumulator >= PHYSICS_TIMESTEP:
		tick_accumulator -= PHYSICS_TIMESTEP

		# Timeline spawns + physics in the same tick so particles are
		# always positioned correctly before the next render.
		if timeline_enabled and (animate_tick_controller or phase1_controller):
			_process_timeline_frame()
		else:
			for emitter: VfxActiveEmitter in active_emitters:
				emitter.update(PHYSICS_TIMESTEP)

		_physics_step()

	# Cleanup dead particles and finished emitters
	_cleanup()


func _process_timeline_frame() -> void:
	var spawn_requests: Array[Dictionary] = []

	# Phase 1: runs from frame 0 to phase1_duration
	if effect_frame < phase1_duration:
		if phase1_controller:
			spawn_requests.append_array(phase1_controller.advance_frame())
	else:
		if not phase1_finished:
			phase1_finished = true

		# animate_tick: runs from phase1_duration onwards
		if animate_tick_controller:
			spawn_requests.append_array(animate_tick_controller.advance_frame())

	# Phase 2: runs from phase2_start onwards (PARALLEL with animate_tick)
	if effect_frame >= phase2_start:
		if not phase2_started:
			phase2_started = true
		if phase2_controller:
			spawn_requests.append_array(phase2_controller.advance_frame())

	# Process all spawn requests
	for request: Dictionary in spawn_requests:
		_process_spawn_request(request)

	effect_frame += 1


func _process_spawn_request(request: Dictionary) -> void:
	var emitter_idx: int = request.emitter_index
	if not debug_emitter_mask.is_empty() and emitter_idx < debug_emitter_mask.size():
		if not debug_emitter_mask[emitter_idx]:
			return
	var spawn_counter: int = request.spawn_counter
	var channel_idx: int = request.get("channel_index", 0)

	var emitter: VfxActiveEmitter = _get_or_create_emitter(emitter_idx, channel_idx)
	if emitter:
		emitter.spawn_particles_for_timeline(spawn_counter)


func _get_or_create_emitter(emitter_index: int, channel_idx: int = 0) -> VfxActiveEmitter:
	# Check if emitter already exists
	for emitter: VfxActiveEmitter in active_emitters:
		if emitter.emitter_index == emitter_index:
			return emitter

	if emitter_index < 0 or emitter_index >= vfx_data.emitters.size():
		push_error("VfxEffectManager: Invalid emitter index: " + str(emitter_index))
		return null

	var emitter_config: VfxEmitter = vfx_data.emitters[emitter_index]
	var emitter := VfxActiveEmitter.new()
	# Timeline emitters use duration_frames=10000 (matching godot-learning).
	# The spawn_counter passed to spawn_particles_for_timeline() drives curve
	# sampling via frame index, not via normalized time t.
	emitter.initialize(emitter_config, emitter_index, vfx_data, VfxConstants.TIMELINE_EMITTER_DURATION)
	emitter.channel_index = channel_idx
	_apply_anchors(emitter)
	active_emitters.append(emitter)
	return emitter


func get_all_particles() -> Array[VfxParticleData]:
	var all: Array[VfxParticleData] = []
	for emitter: VfxActiveEmitter in active_emitters:
		all.append_array(emitter.particles)
	return all


func _physics_step() -> void:
	for emitter: VfxActiveEmitter in active_emitters:
		emitter.tick_particles()


func _cleanup() -> void:
	# Each emitter cleans its own dead particles and returns child spawn requests
	var child_spawn_requests: Array[Dictionary] = []
	for emitter: VfxActiveEmitter in active_emitters:
		child_spawn_requests.append_array(emitter.cleanup_dead_particles())

	# Spawn child emitters using saved info
	for request: Dictionary in child_spawn_requests:
		_spawn_child_emitter(
			request.child_index,
			request.position,
			request.age,
			request.get("channel_index", 0)
		)

	# Remove finished emitters (only if no particles remain)
	# In timeline mode, also remove emitters whose particles are all dead
	# even if the emitter itself hasn't hit its duration limit — the timeline
	# controller drives when spawning stops, not the emitter's own timer.
	var all_timelines_done: bool = timeline_enabled and _all_controllers_done()
	var still_active: Array[VfxActiveEmitter] = []
	for emitter: VfxActiveEmitter in active_emitters:
		if emitter.particles.is_empty() and (emitter.is_done() or all_timelines_done):
			continue
		still_active.append(emitter)
	active_emitters = still_active


func _spawn_child_emitter(child_emitter_index: int, parent_pos: Vector3, frame_counter: int, channel_idx: int = 0) -> void:
	if child_emitter_index < 0 or child_emitter_index >= vfx_data.emitters.size():
		return
	if not debug_emitter_mask.is_empty() and child_emitter_index < debug_emitter_mask.size():
		if not debug_emitter_mask[child_emitter_index]:
			return

	var config: VfxEmitter = vfx_data.emitters[child_emitter_index]

	# Check spawn interval
	var interval: int = config.spawn_interval_start
	if interval > 0 and frame_counter % interval != 0:
		return

	var child_emitter: VfxActiveEmitter = _get_or_create_emitter(child_emitter_index, channel_idx)
	if not child_emitter:
		return

	# Resolve target anchor for child emitter (PARENT mode → use target)
	var child_target_anchor: Vector3 = VfxConstants.resolve_anchor(
		config.target_anchor_mode, anchor_world, anchor_cursor,
		anchor_origin, anchor_target, anchor_target)

	var count: int = config.particle_count_start
	for i in range(count):
		var particle := VfxParticleData.new()
		VfxActiveEmitter.initialize_particle_from_config(
			particle, config, child_emitter_index, vfx_data,
			parent_pos, child_target_anchor, frame_counter, channel_idx)
		child_emitter.particles.append(particle)


# === Public API ===

func set_anchors(world: Vector3, cursor: Vector3, origin: Vector3, target: Vector3) -> void:
	anchor_world = world
	anchor_cursor = cursor
	anchor_origin = origin
	anchor_target = target

	for emitter: VfxActiveEmitter in active_emitters:
		_apply_anchors(emitter)


func _apply_anchors(emitter: VfxActiveEmitter) -> void:
	emitter.anchor_world = anchor_world
	emitter.anchor_cursor = anchor_cursor
	emitter.anchor_origin = anchor_origin
	emitter.anchor_target = anchor_target


func get_particle_data() -> Array:
	var data: Array = []
	for active_emitter: VfxActiveEmitter in active_emitters:
		var emitter_config: VfxEmitter = active_emitter.emitter
		var align_to_vel: bool = emitter_config.align_to_velocity if emitter_config else false
		for p: VfxParticleData in active_emitter.particles:
			data.append({
				"position": p.position,
				"velocity": p.velocity,
				"align_to_velocity": align_to_vel,
				"emitter_index": p.emitter_index,
				"channel_index": p.channel_index,
				"age": p.age,
				"lifetime": p.lifetime,
				"anim_index": p.anim_index,
				"anim_frame": p.anim_frame,
				"anim_time": p.anim_time,
				"anim_offset": p.anim_offset,
				"current_frameset": p.current_frameset,
				"current_depth_mode": p.current_depth_mode,
			})
	return data


func is_done() -> bool:
	if timeline_enabled:
		# Not done until all timeline controllers have finished their channels
		if not _all_controllers_done():
			return false
		# All timelines finished — done when emitters are cleared and particles dead
		return active_emitters.is_empty()
	# Manual mode: done when emitters are finished and all particles are dead
	return active_emitters.is_empty()


func _all_controllers_done() -> bool:
	## A controller is "done" if:
	## - Its phase time window has expired (controller no longer advances), OR
	## - It's finished (all channels past last keyframe), OR
	## - All remaining keyframes are idle (emitter_id=0)
	## Phase1 stops advancing at phase1_duration, so once phase1_finished it's done.
	if phase1_controller and not phase1_finished and not _controller_is_done(phase1_controller):
		return false
	if animate_tick_controller and not _controller_is_done(animate_tick_controller):
		return false
	if phase2_controller and not _controller_is_done(phase2_controller):
		return false
	return true


func _controller_is_done(controller: VfxTimelineController) -> bool:
	if controller.is_finished():
		return true
	# Not finished yet — but are there any future emitters to spawn?
	for state in controller.channel_states:
		if state.finished:
			continue
		# Check current and all future keyframes for any non-zero emitter_id
		for kf_idx in range(state.current_keyframe, mini(state.timeline.num_keyframes + 1, state.timeline.keyframes.size())):
			if state.timeline.keyframes[kf_idx].emitter_id != 0:
				return false
	return true


func reset() -> void:
	active_emitters.clear()

	tick_accumulator = 0.0
	effect_frame = 0
	phase1_finished = false
	phase2_started = false
	_first_update_after_init = true

	# Reinitialize timeline controllers
	if phase1_controller:
		phase1_controller.initialize(vfx_data.phase1_emitter_timelines)
	if animate_tick_controller:
		animate_tick_controller.initialize(vfx_data.child_emitter_timelines)
	if phase2_controller:
		phase2_controller.initialize(vfx_data.phase2_emitter_timelines)
