class_name VfxActiveEmitter
extends RefCounted
## Runtime emitter — spawns particles with interpolated parameters
## Port of godot-learning's ActiveEmitter.gd, adapted to use VfxEmitter conv_* fields

const FRAME_DURATION: float = VfxConstants.TICK_DURATION

const CP := VfxConstants.CurveParam

# References
var emitter: VfxEmitter
var emitter_index: int = -1
var vfx_data: VisualEffectData
var particles: Array[VfxParticleData] = []
var physics: VfxPhysics
var animator: VfxAnimator

# Timing
var elapsed_frames: int = 0
var duration_frames: int = 120
var spawn_accumulator: float = 0.0

# State
var active: bool = false
var channel_index: int = 0

# Anchors (Godot world positions)
var anchor_world: Vector3 = Vector3.ZERO
var anchor_cursor: Vector3 = Vector3.ZERO
var anchor_origin: Vector3 = Vector3.ZERO
var anchor_target: Vector3 = Vector3.ZERO
var anchor_parent: Vector3 = Vector3.ZERO
var caster_facing_angle: float = 0.0  # Radians, Y-axis rotation for OUTWARD_UNIT_ORIENTED


func initialize(
	vfx_emitter: VfxEmitter,
	idx: int,
	data: VisualEffectData,
	duration: int = 120
) -> void:
	emitter = vfx_emitter
	emitter_index = idx
	vfx_data = data
	particles = []
	physics = VfxPhysics.new()
	physics.initialize(data)
	animator = VfxAnimator.new()
	animator.initialize(data)
	duration_frames = duration

	elapsed_frames = 0
	spawn_accumulator = 0.0
	active = true


func update(delta: float) -> void:
	if not active:
		return

	spawn_accumulator += delta
	while spawn_accumulator >= FRAME_DURATION:
		spawn_accumulator -= FRAME_DURATION
		_process_frame()


func _process_frame() -> void:
	var interval: int = roundi(_get_spawn_interval())

	if interval > 0 and elapsed_frames % interval == 0:
		_spawn_particles()

	elapsed_frames += 1

	if elapsed_frames >= duration_frames:
		active = false


func _spawn_particles() -> void:
	var count: int = _get_particle_count()

	for i: int in range(count):
		var particle: VfxParticleData = VfxParticleData.new()
		_initialize_particle(particle)
		particles.append(particle)


func _initialize_particle(particle: VfxParticleData) -> void:
	var anchor_offset: Vector3 = _get_anchor_offset()
	var target_anchor: Vector3 = _get_target_anchor()
	initialize_particle_from_config(
		particle, emitter, emitter_index, vfx_data,
		anchor_offset, target_anchor, elapsed_frames, channel_index, caster_facing_angle)


# === Shared Particle Initialization (used by both normal and child spawn paths) ===

static func initialize_particle_from_config(
	particle: VfxParticleData,
	config: VfxEmitter,
	config_index: int,
	effect_data: VisualEffectData,
	base_position: Vector3,
	target_anchor: Vector3,
	frame: int,
	channel_idx: int,
	facing_angle: float = 0.0
) -> void:
	var is_unit_oriented: bool = config.is_velocity_inward and config.align_to_facing

	# --- Position & Spread ---
	var pos_offset: Vector3 = _interpolate_vec3_static(CP.POSITION,
		config.conv_position_start, config.conv_position_end, config, effect_data, frame)
	var spread: Vector3 = _interpolate_vec3_static(CP.PARTICLE_SPREAD,
		config.conv_spread_start, config.conv_spread_end, config, effect_data, frame)

	# OUTWARD_UNIT_ORIENTED: rotate position offset and spread by facing
	if is_unit_oriented:
		pos_offset = _rotate_y(pos_offset, facing_angle)
		spread = _rotate_y(spread, facing_angle)

	var base_pos: Vector3 = base_position + pos_offset
	var spread_offset: Vector3 = _apply_spread_static(spread, config)
	var final_pos: Vector3 = base_pos + spread_offset

	# --- Velocity ---
	var radial_vel: float = _interpolate_range_static(CP.RADIAL_VELOCITY,
		config.conv_radial_velocity_min_start, config.conv_radial_velocity_max_start,
		config.conv_radial_velocity_min_end, config.conv_radial_velocity_max_end,
		config, effect_data, frame)

	# 4-mode velocity dispatch based on velocity_inward + align_to_facing flags
	var velocity: Vector3
	if is_unit_oriented:
		# OUTWARD_UNIT_ORIENTED: outward (angle-based) + rotated by caster facing
		var vel_angle: Vector3 = _interpolate_vec3_static(CP.VELOCITY_ANGLE,
			config.conv_angle_start, config.conv_angle_end, config, effect_data, frame)
		var vel_spread: Vector3 = _interpolate_vec3_static(CP.VELOCITY_ANGLE_SPREAD,
			config.conv_angle_spread_start, config.conv_angle_spread_end, config, effect_data, frame)
		var base_dir: Vector3 = VfxPhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
		var final_dir: Vector3 = VfxPhysics.random_cone_direction(base_dir, vel_spread)
		velocity = _rotate_y(final_dir * radial_vel, facing_angle)
	elif config.is_velocity_inward:
		# INWARD: direction from particle toward emitter center
		var to_center: Vector3 = base_pos - final_pos
		if to_center.length_squared() < 0.0001:
			velocity = Vector3(0, -radial_vel, 0)
		else:
			velocity = to_center.normalized() * radial_vel
	elif config.align_to_facing:
		# SKIP: zero velocity (unimplemented in PSX, falls through)
		velocity = Vector3.ZERO
	else:
		# OUTWARD: standard angle-based direction
		var vel_angle: Vector3 = _interpolate_vec3_static(CP.VELOCITY_ANGLE,
			config.conv_angle_start, config.conv_angle_end, config, effect_data, frame)
		var vel_spread: Vector3 = _interpolate_vec3_static(CP.VELOCITY_ANGLE_SPREAD,
			config.conv_angle_spread_start, config.conv_angle_spread_end, config, effect_data, frame)
		var base_dir: Vector3 = VfxPhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
		var final_dir: Vector3 = VfxPhysics.random_cone_direction(base_dir, vel_spread)
		velocity = final_dir * radial_vel

	# --- Lifetime ---
	var lifetime: int = int(_interpolate_range_static(CP.PARTICLE_LIFETIME,
		float(config.particle_lifetime_min_start), float(config.particle_lifetime_max_start),
		float(config.particle_lifetime_min_end), float(config.particle_lifetime_max_end),
		config, effect_data, frame))
	if lifetime >= 0:
		lifetime = maxi(1, lifetime)

	# Initialize particle
	particle.initialize(
		final_pos,
		velocity,
		lifetime,
		config_index,
		config.child_emitter_idx_on_death if config.child_death_mode != 0 else VfxConstants.NO_CHILD_EMITTER,
		config.child_emitter_idx_on_interval if config.child_midlife_mode != 0 else VfxConstants.NO_CHILD_EMITTER
	)

	# --- Physics ---
	particle.inertia = _interpolate_range_static(CP.INERTIA,
		config.conv_inertia_min_start, config.conv_inertia_max_start,
		config.conv_inertia_min_end, config.conv_inertia_max_end,
		config, effect_data, frame)

	particle.weight = _interpolate_range_static(CP.WEIGHT,
		config.conv_weight_min_start, config.conv_weight_max_start,
		config.conv_weight_min_end, config.conv_weight_max_end,
		config, effect_data, frame)

	# Acceleration/drag (already Godot units via conv_*)
	particle.acceleration = _interpolate_vec3_range_static(CP.ACCELERATION,
		config.conv_acceleration_min_start, config.conv_acceleration_max_start,
		config.conv_acceleration_min_end, config.conv_acceleration_max_end,
		config, effect_data, frame)

	particle.drag = _interpolate_vec3_range_static(CP.DRAG,
		config.conv_drag_min_start, config.conv_drag_max_start,
		config.conv_drag_min_end, config.conv_drag_max_end,
		config, effect_data, frame)

	# --- Homing ---
	particle.homing_strength = _interpolate_range_static(CP.HOMING_STRENGTH,
		config.conv_homing_strength_min_start, config.conv_homing_strength_max_start,
		config.conv_homing_strength_min_end, config.conv_homing_strength_max_end,
		config, effect_data, frame)

	particle.homing_curve_index = config.interpolation_curve_indicies.get(CP.HOMING_CURVE, -1)

	if particle.homing_strength > 0:
		var target_offset: Vector3 = _interpolate_vec3_static(CP.TARGET_OFFSET,
			config.conv_target_offset_start, config.conv_target_offset_end,
			config, effect_data, frame)
		particle.homing_target = target_anchor + target_offset

	# --- Homing Arrival ---
	var arrival_raw: int = config.homing_arrival_threshold_raw
	particle.homing_arrival_threshold = arrival_raw * 16.0 / 28.0 if arrival_raw > 0 else 0.0

	# --- Animation ---
	particle.anim_index = config.anim_index
	particle.channel_index = channel_idx


# === Anchor Handling ===

func _get_anchor_offset() -> Vector3:
	return VfxConstants.resolve_anchor(emitter.emitter_anchor_mode,
		anchor_world, anchor_cursor, anchor_origin, anchor_target, anchor_parent)


func _get_target_anchor() -> Vector3:
	return VfxConstants.resolve_anchor(emitter.target_anchor_mode,
		anchor_world, anchor_cursor, anchor_origin, anchor_target, anchor_parent)


# === Spread ===

static func _apply_spread_static(spread: Vector3, config: VfxEmitter) -> Vector3:
	if config.spread_mode == VfxConstants.SpreadMode.SPHERE:
		return _random_sphere(spread)
	return _random_box(spread)


static func _random_sphere(spread: Vector3) -> Vector3:
	var theta: float = randf() * TAU
	var phi: float = acos(2.0 * randf() - 1.0)
	var r: float = pow(randf(), 1.0 / 3.0)
	return Vector3(
		r * spread.x * sin(phi) * cos(theta),
		r * spread.y * cos(phi),
		r * spread.z * sin(phi) * sin(theta)
	)


static func _random_box(spread: Vector3) -> Vector3:
	return Vector3(
		randf_range(-spread.x, spread.x),
		randf_range(-spread.y, spread.y),
		randf_range(-spread.z, spread.z)
	)


static func _rotate_y(v: Vector3, angle: float) -> Vector3:
	## Rotate vector around Y axis. Matches PSX build_rotation_matrix with X=0,Z=0.
	if absf(angle) < 0.001:
		return v
	var c: float = cos(angle)
	var s: float = sin(angle)
	return Vector3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)


# === Static Interpolation Helpers ===

static func _get_curve_static(param: int, config: VfxEmitter, effect_data: VisualEffectData) -> VfxCurve:
	var idx: int = config.interpolation_curve_indicies.get(param, 0)
	if idx <= 0:
		return null
	return effect_data.get_curve(idx - 1)


static func _interpolate_vec3_static(param: int, start: Vector3, end_val: Vector3,
	config: VfxEmitter, effect_data: VisualEffectData, frame: int) -> Vector3:
	return VfxPhysics.interpolate_vec3(start, end_val, _get_curve_static(param, config, effect_data), frame)


static func _interpolate_range_static(param: int, min_s: float, max_s: float,
	min_e: float, max_e: float,
	config: VfxEmitter, effect_data: VisualEffectData, frame: int) -> float:
	return VfxPhysics.interpolate_range(min_s, max_s, min_e, max_e, _get_curve_static(param, config, effect_data), frame)


static func _interpolate_vec3_range_static(param: int, min_s: Vector3, max_s: Vector3,
	min_e: Vector3, max_e: Vector3,
	config: VfxEmitter, effect_data: VisualEffectData, frame: int) -> Vector3:
	return VfxPhysics.interpolate_vec3_range(min_s, max_s, min_e, max_e, _get_curve_static(param, config, effect_data), frame)


# === Instance Interpolation (delegates to static) ===

func _get_spawn_interval() -> float:
	var curve: VfxCurve = _get_curve_static(CP.SPAWN_INTERVAL, emitter, vfx_data)
	return VfxPhysics.interpolate_simple(
		float(emitter.spawn_interval_start),
		float(emitter.spawn_interval_end),
		curve, elapsed_frames
	)


func _get_particle_count() -> int:
	var curve: VfxCurve = _get_curve_static(CP.PARTICLE_COUNT, emitter, vfx_data)
	var count: float = VfxPhysics.interpolate_simple(
		float(emitter.particle_count_start),
		float(emitter.particle_count_end),
		curve, elapsed_frames
	)
	return maxi(1, int(count))


func tick_particles() -> void:
	for particle: VfxParticleData in particles:
		physics.update_particle(particle)
	for particle: VfxParticleData in particles:
		animator.tick(particle)


func cleanup_dead_particles() -> Array[Dictionary]:
	var child_spawn_requests: Array[Dictionary] = []
	for particle: VfxParticleData in particles:
		if particle.is_dead() or not particle.active:
			if particle.child_emitter_on_death >= 0:
				var parent_config: VfxEmitter = null
				if particle.emitter_index >= 0 and particle.emitter_index < vfx_data.emitters.size():
					parent_config = vfx_data.emitters[particle.emitter_index]
				if parent_config and parent_config.child_death_mode != 0:
					child_spawn_requests.append({
						"child_index": particle.child_emitter_on_death,
						"position": particle.position,
						"age": particle.age,
						"channel_index": particle.channel_index
					})
	particles = particles.filter(
		func(p: VfxParticleData) -> bool: return p.active and not p.is_dead())
	return child_spawn_requests


# === Utility ===

func is_done() -> bool:
	return not active


func spawn_particles_for_timeline(spawn_counter: int) -> void:
	var saved_elapsed: int = elapsed_frames
	elapsed_frames = spawn_counter

	var interval: int = roundi(_get_spawn_interval())
	if interval <= 0 or spawn_counter % interval != 0:
		elapsed_frames = saved_elapsed
		return

	var count: int = _get_particle_count()
	for i: int in range(count):
		var particle: VfxParticleData = VfxParticleData.new()
		_initialize_particle(particle)
		particles.append(particle)

	elapsed_frames = saved_elapsed
