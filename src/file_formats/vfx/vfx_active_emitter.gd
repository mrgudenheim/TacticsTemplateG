class_name VfxActiveEmitter
extends RefCounted
## Runtime emitter — spawns particles with interpolated parameters
## Port of godot-learning's ActiveEmitter.gd, adapted to use VfxEmitter conv_* fields

const EFFECT_FPS: float = 30.0
const FRAME_DURATION: float = 1.0 / EFFECT_FPS

## Curve parameter name mapping (VfxEmitter key → interpolation_curve_indicies key)
const CURVE_KEY_MAP: Dictionary = {
	"position": "POSITION",
	"spread": "PARTICLE_SPREAD",
	"velocity_base_angle": "VELOCITY_ANGLE",
	"velocity_dir_spread": "VELOCITY_ANGLE_SPREAD",
	"radial_velocity": "RADIAL_VELOCITY",
	"inertia": "INERTIA",
	"weight": "WEIGHT",
	"acceleration": "ACCELERATION",
	"drag": "DRAG",
	"lifetime": "PARTICLE_LIFETIME",
	"target_offset": "TARGET_OFFSET",
	"particle_count": "PARTICLE_COUNT",
	"spawn_interval": "SPAWN_INTERVAL",
	"homing": "HOMING_STRENGTH",
	"homing_blend": "HOMING_CURVE",
}

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
	var t: float = get_normalized_time()
	var interval: int = roundi(_get_spawn_interval(t))

	if interval > 0 and elapsed_frames % interval == 0:
		_spawn_particles(t)

	elapsed_frames += 1

	if elapsed_frames >= duration_frames:
		active = false


func _spawn_particles(t: float) -> void:
	var count: int = _get_particle_count(t)

	for i in range(count):
		var particle := VfxParticleData.new()
		_initialize_particle(particle, t)
		particles.append(particle)


func _initialize_particle(particle: VfxParticleData, t: float) -> void:
	var anchor_offset: Vector3 = _get_anchor_offset()
	var target_anchor: Vector3 = _get_target_anchor()
	initialize_particle_from_config(
		particle, emitter, emitter_index, vfx_data,
		anchor_offset, target_anchor, t, elapsed_frames, channel_index)


# === Shared Particle Initialization (used by both normal and child spawn paths) ===

static func initialize_particle_from_config(
	particle: VfxParticleData,
	config: VfxEmitter,
	config_index: int,
	effect_data: VisualEffectData,
	base_position: Vector3,
	target_anchor: Vector3,
	t: float,
	frame: int,
	channel_idx: int
) -> void:
	# Position (already Godot units via conv_*)
	var pos_offset: Vector3 = _interpolate_vec3_static("position",
		config.conv_position_start, config.conv_position_end, config, effect_data, t, frame)
	var spread: Vector3 = _interpolate_vec3_static("spread",
		config.conv_spread_start, config.conv_spread_end, config, effect_data, t, frame)

	var base_pos: Vector3 = base_position + pos_offset
	var spread_offset: Vector3 = _apply_spread_static(spread, config)
	var final_pos: Vector3 = base_pos + spread_offset

	# Radial velocity (already Godot units/frame)
	var radial_vel: float = _interpolate_range_static("radial_velocity",
		config.conv_radial_velocity_min_start, config.conv_radial_velocity_max_start,
		config.conv_radial_velocity_min_end, config.conv_radial_velocity_max_end,
		config, effect_data, t, frame)

	# Calculate velocity based on velocity_inward flag
	var velocity: Vector3
	if config.is_velocity_inward:
		var to_center: Vector3 = base_pos - final_pos
		if to_center.length_squared() < 0.0001:
			velocity = Vector3(0, -radial_vel, 0)
		else:
			velocity = to_center.normalized() * radial_vel
	else:
		var vel_angle: Vector3 = _interpolate_vec3_static("velocity_base_angle",
			config.conv_angle_start, config.conv_angle_end, config, effect_data, t, frame)
		var vel_spread: Vector3 = _interpolate_vec3_static("velocity_dir_spread",
			config.conv_angle_spread_start, config.conv_angle_spread_end, config, effect_data, t, frame)
		var base_dir: Vector3 = VfxPhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
		var final_dir: Vector3 = VfxPhysics.random_cone_direction(base_dir, vel_spread)
		velocity = final_dir * radial_vel

	# Lifetime (frames) — -1 means animation-driven
	var lifetime: int = int(_interpolate_range_static("lifetime",
		float(config.particle_lifetime_min_start), float(config.particle_lifetime_max_start),
		float(config.particle_lifetime_min_end), float(config.particle_lifetime_max_end),
		config, effect_data, t, frame))
	if lifetime >= 0:
		lifetime = maxi(1, lifetime)

	# Initialize particle
	particle.initialize(
		final_pos,
		velocity,
		lifetime,
		config_index,
		config.child_emitter_idx_on_death if config.child_death_mode != 0 else -1,
		config.child_emitter_idx_on_interval if config.child_midlife_mode != 0 else -1
	)

	# Physics (inertia/weight are raw values, no unit conversion)
	particle.inertia = _interpolate_range_static("inertia",
		config.conv_inertia_min_start, config.conv_inertia_max_start,
		config.conv_inertia_min_end, config.conv_inertia_max_end,
		config, effect_data, t, frame)

	particle.weight = _interpolate_range_static("weight",
		config.conv_weight_min_start, config.conv_weight_max_start,
		config.conv_weight_min_end, config.conv_weight_max_end,
		config, effect_data, t, frame)

	# Acceleration/drag (already Godot units via conv_*)
	particle.acceleration = _interpolate_vec3_range_static("acceleration",
		config.conv_acceleration_min_start, config.conv_acceleration_max_start,
		config.conv_acceleration_min_end, config.conv_acceleration_max_end,
		config, effect_data, t, frame)

	particle.drag = _interpolate_vec3_range_static("drag",
		config.conv_drag_min_start, config.conv_drag_max_start,
		config.conv_drag_min_end, config.conv_drag_max_end,
		config, effect_data, t, frame)

	# Homing (already Godot units via conv_*)
	particle.homing_strength = _interpolate_range_static("homing",
		config.conv_homing_strength_min_start, config.conv_homing_strength_max_start,
		config.conv_homing_strength_min_end, config.conv_homing_strength_max_end,
		config, effect_data, t, frame)

	particle.homing_curve_index = config.interpolation_curve_indicies.get("HOMING_CURVE", -1)

	if particle.homing_strength > 0:
		var target_offset: Vector3 = _interpolate_vec3_static("target_offset",
			config.conv_target_offset_start, config.conv_target_offset_end,
			config, effect_data, t, frame)
		particle.homing_target = target_anchor + target_offset

	particle.anim_index = config.anim_index
	particle.channel_index = channel_idx


# === Anchor Handling ===

func _get_anchor_offset() -> Vector3:
	match emitter.emitter_anchor_mode:
		1: return anchor_cursor
		2: return anchor_origin
		3: return anchor_target
		4: return anchor_parent
	return anchor_world


func _get_target_anchor() -> Vector3:
	match emitter.target_anchor_mode:
		1: return anchor_cursor
		2: return anchor_origin
		3: return anchor_target
		4: return anchor_parent
	return anchor_world


# === Spread ===

static func _apply_spread_static(spread: Vector3, config: VfxEmitter) -> Vector3:
	if config.spread_mode == 0:  # sphere
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


# === Static Interpolation Helpers ===

static func _get_curve_static(param: String, config: VfxEmitter, effect_data: VisualEffectData) -> VfxCurve:
	if not CURVE_KEY_MAP.has(param):
		return null
	var vfx_key: String = CURVE_KEY_MAP[param]
	var idx: int = config.interpolation_curve_indicies.get(vfx_key, 0)
	if idx <= 0:
		return null
	return effect_data.get_curve(idx - 1)


static func _interpolate_vec3_static(param: String, start: Vector3, end_val: Vector3,
	config: VfxEmitter, effect_data: VisualEffectData, t: float, frame: int) -> Vector3:
	return VfxPhysics.interpolate_vec3(start, end_val, t, _get_curve_static(param, config, effect_data), frame)


static func _interpolate_range_static(param: String, min_s: float, max_s: float,
	min_e: float, max_e: float,
	config: VfxEmitter, effect_data: VisualEffectData, t: float, frame: int) -> float:
	return VfxPhysics.interpolate_range(min_s, max_s, min_e, max_e, t, _get_curve_static(param, config, effect_data), frame)


static func _interpolate_vec3_range_static(param: String, min_s: Vector3, max_s: Vector3,
	min_e: Vector3, max_e: Vector3,
	config: VfxEmitter, effect_data: VisualEffectData, t: float, frame: int) -> Vector3:
	return VfxPhysics.interpolate_vec3_range(min_s, max_s, min_e, max_e, t, _get_curve_static(param, config, effect_data), frame)


# === Instance Interpolation (delegates to static) ===

func _get_spawn_interval(t: float) -> float:
	var curve: VfxCurve = _get_curve_static("spawn_interval", emitter, vfx_data)
	return VfxPhysics.interpolate_simple(
		float(emitter.spawn_interval_start),
		float(emitter.spawn_interval_end),
		t, curve, elapsed_frames
	)


func _get_particle_count(t: float) -> int:
	var curve: VfxCurve = _get_curve_static("particle_count", emitter, vfx_data)
	var count: float = VfxPhysics.interpolate_simple(
		float(emitter.particle_count_start),
		float(emitter.particle_count_end),
		t, curve, elapsed_frames
	)
	return maxi(1, int(count))


func tick_particles() -> void:
	for particle: VfxParticleData in particles:
		physics.update_particle(particle)
	for particle: VfxParticleData in particles:
		animator.tick(particle)


func cleanup_dead_particles() -> Array:
	var child_spawn_requests: Array = []
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

func get_normalized_time() -> float:
	if duration_frames <= 0:
		return 0.0
	return clampf(float(elapsed_frames) / float(duration_frames), 0.0, 1.0)


func is_done() -> bool:
	return not active


func spawn_particles_for_timeline(spawn_counter: int) -> void:
	var saved_elapsed: int = elapsed_frames
	elapsed_frames = spawn_counter

	var t: float = get_normalized_time()

	var interval: int = roundi(_get_spawn_interval(t))
	if interval <= 0 or spawn_counter % interval != 0:
		elapsed_frames = saved_elapsed
		return

	var count: int = _get_particle_count(t)
	for i in range(count):
		var particle := VfxParticleData.new()
		_initialize_particle(particle, t)
		particles.append(particle)

	elapsed_frames = saved_elapsed
