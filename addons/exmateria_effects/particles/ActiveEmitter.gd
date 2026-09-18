extends RefCounted
## Runtime emitter - spawns particles with pre-converted values (NO scaling constants)
## Vault: [[Effect Execution Model]]
## Vault: [[Effect Frame Pacing]]
## Vault: [[Emitter Anchor Modes]]
## Vault: [[Frameset Header Flags]]
## Vault: [[Homing System]]
## Vault: [[Particle Curve Indices]]
## Vault: [[Particle Emitter Format]]
## Vault: [[Particle Runtime State]]
## Vault: [[Sprite Offset vs Vertex Position]]

const EffectCurve = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const EffectEmitter = preload("res://addons/exmateria_effects/file_model/EffectEmitter.gd")
const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")
const ParticlePhysics = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")
const ParticlePool = preload("res://addons/exmateria_effects/particles/ParticlePool.gd")

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


const EFFECT_FPS: float = 30.0
const FRAME_DURATION: float = 1.0 / EFFECT_FPS

# References
var config: EffectEmitter
var effect_data: EffectData
var particle_pool: ParticlePool
var physics: ParticlePhysics

# Timing
var elapsed_frames: int = 0
var duration_frames: int = 120
var spawn_accumulator: float = 0.0

# State
var active: bool = false
var emitter_index: int = -1
var channel_index: int = 0  # Timeline lane that spawned this emitter; NOT a Z-order key (see ADR-0015)

# Anchors (Godot world positions)
var anchor_world: Vector3 = Vector3.ZERO
var anchor_cursor: Vector3 = Vector3.ZERO
var anchor_origin: Vector3 = Vector3.ZERO
var anchor_target: Vector3 = Vector3.ZERO
var anchor_parent: Vector3 = Vector3.ZERO
var anchor_camera: Vector3 = Vector3.ZERO  # PSX CAMERA anchor: (tile*14/28, 0, tile*14/28) relative to effect
var caster_facing_angle: float = 0.0  # Radians, Y-axis rotation for OUTWARD_UNIT_ORIENTED

# Spawned particles (for child emitter tracking)
var spawned_particles: Array[Particle] = []


func initialize(
	emitter_config: EffectEmitter,
	data: EffectData,
	pool: ParticlePool,
	phys: ParticlePhysics,
	duration: int = 120
) -> void:
	config = emitter_config
	effect_data = data
	particle_pool = pool
	physics = phys
	duration_frames = duration
	emitter_index = config.index

	elapsed_frames = 0
	spawn_accumulator = 0.0
	active = true
	spawned_particles.clear()


func update(delta: float) -> void:
	"""Update emitter at 30 FPS fixed timestep"""
	if not active:
		return

	spawn_accumulator += delta
	while spawn_accumulator >= FRAME_DURATION:
		spawn_accumulator -= FRAME_DURATION
		_process_frame()


func _process_frame() -> void:
	"""Process one 30 FPS effect frame"""
	var interval = roundi(_get_spawn_interval())

	if interval > 0 and elapsed_frames % interval == 0:
		_spawn_particles()

	elapsed_frames += 1

	if elapsed_frames >= duration_frames:
		active = false


func _spawn_particles() -> void:
	"""Spawn particles for current frame"""
	var count = _get_particle_count()

	for i in range(count):
		var particle = particle_pool.acquire()
		if particle == null:
			break
		_initialize_particle(particle)
		spawned_particles.append(particle)


func _initialize_particle(particle: Particle) -> void:
	"""Initialize particle with interpolated parameters (all pre-converted)"""
	var velocity_inward_flag = config.flags.get("velocity_inward", false)
	var align_to_facing_flag = config.flags.get("align_to_facing", false)
	var is_unit_oriented = velocity_inward_flag and align_to_facing_flag

	# Position (already Godot units)
	var base_pos = _interpolate_vec3("position", config.position_start, config.position_end)
	var spread = _interpolate_vec3("spread", config.spread_start, config.spread_end)

	# OUTWARD_UNIT_ORIENTED: rotate position offset and spread by facing
	if is_unit_oriented:
		base_pos = _rotate_y(base_pos, caster_facing_angle)
		spread = _rotate_y(spread, caster_facing_angle)

	base_pos += _get_anchor_offset()
	var final_pos = base_pos + _apply_spread(spread)

	# Radial velocity (already Godot units/frame)
	var radial_vel = _interpolate_range("radial_velocity",
		config.radial_velocity_min_start, config.radial_velocity_max_start,
		config.radial_velocity_min_end, config.radial_velocity_max_end)

	# 4-mode velocity dispatch based on velocity_inward + align_to_facing flags
	var velocity: Vector3
	if is_unit_oriented:
		# OUTWARD_UNIT_ORIENTED: outward (angle-based) + rotated by caster facing
		var vel_angle = _interpolate_vec3("velocity_base_angle",
			config.velocity_base_angle_start, config.velocity_base_angle_end)
		var vel_spread = _interpolate_vec3("velocity_dir_spread",
			config.velocity_direction_spread_start, config.velocity_direction_spread_end)
		var base_dir = ParticlePhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
		var final_dir = ParticlePhysics.random_cone_direction(base_dir, vel_spread, physics.rng)
		velocity = _rotate_y(final_dir * radial_vel, caster_facing_angle)
	elif velocity_inward_flag:
		# INWARD: direction from particle toward emitter center (base_pos)
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
		var vel_angle = _interpolate_vec3("velocity_base_angle",
			config.velocity_base_angle_start, config.velocity_base_angle_end)
		var vel_spread = _interpolate_vec3("velocity_dir_spread",
			config.velocity_direction_spread_start, config.velocity_direction_spread_end)
		var base_dir = ParticlePhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
		var final_dir = ParticlePhysics.random_cone_direction(base_dir, vel_spread, physics.rng)
		velocity = final_dir * radial_vel

	# Lifetime (frames) - -1 means animation-driven (dies when animation completes)
	var lifetime: int = int(_interpolate_range("lifetime",
		float(config.lifetime_min_start), float(config.lifetime_max_start),
		float(config.lifetime_min_end), float(config.lifetime_max_end)))
	# Ensure positive lifetimes are at least 1, but preserve -1 for animation-driven
	if lifetime >= 0:
		lifetime = maxi(1, lifetime)

	# Initialize particle
	particle.initialize(
		final_pos,
		velocity,
		lifetime,
		emitter_index,
		config.child_emitter_on_death,
		config.child_emitter_mid_life
	)

	# Physics (inertia/weight are raw values)
	particle.inertia = _interpolate_range("inertia",
		config.inertia_min_start, config.inertia_max_start,
		config.inertia_min_end, config.inertia_max_end)

	particle.weight = _interpolate_range("weight",
		config.weight_min_start, config.weight_max_start,
		config.weight_min_end, config.weight_max_end)

	# Acceleration/drag (already Godot units)
	particle.acceleration = _interpolate_vec3_range("acceleration",
		config.acceleration_min_start, config.acceleration_max_start,
		config.acceleration_min_end, config.acceleration_max_end)

	particle.drag = _interpolate_vec3_range("drag",
		config.drag_min_start, config.drag_max_start,
		config.drag_min_end, config.drag_max_end)

	# Homing (already Godot units)
	particle.homing_strength = _interpolate_range("homing",
		config.homing_strength_min_start, config.homing_strength_max_start,
		config.homing_strength_min_end, config.homing_strength_max_end)

	particle.homing_curve_index = config.curves.get("homing_blend", -1)

	var arrival_raw: int = config.flags.get("homing_arrival_threshold", 0)
	particle.homing_arrival_threshold = PsxMagnitude.tile_to_game(arrival_raw * 16.0) if arrival_raw > 0 else 0.0

	# Any NON-ZERO strength homes (negative = repel); a `> 0` guard would strand the
	# target for repulsion effects. See HOMING_SYSTEM_ANALYSIS.md §7.
	if not is_zero_approx(particle.homing_strength):
		var target_offset = _interpolate_vec3("target_offset",
			config.target_offset_start, config.target_offset_end)
		particle.homing_target = _get_target_anchor() + target_offset

	particle.anim_index = config.anim_index
	particle.channel_index = channel_index  # Propagate lane id (used by callbacks/debug, not draw order)
	particle.frameset_group_offset = _get_group_offset(config.anim_param)


# === Anchor Handling ===

func _get_anchor_offset() -> Vector3:
	match config.get_emitter_anchor_mode():
		EffectEmitter.AnchorMode.CURSOR: return anchor_cursor
		EffectEmitter.AnchorMode.ORIGIN: return anchor_origin
		EffectEmitter.AnchorMode.TARGET: return anchor_target
		EffectEmitter.AnchorMode.PARENT: return anchor_parent
		EffectEmitter.AnchorMode.CAMERA: return anchor_camera
	return anchor_world


func _get_target_anchor() -> Vector3:
	match config.get_target_anchor_mode():
		EffectEmitter.AnchorMode.CURSOR: return anchor_cursor
		EffectEmitter.AnchorMode.ORIGIN: return anchor_origin
		EffectEmitter.AnchorMode.TARGET: return anchor_target
		EffectEmitter.AnchorMode.PARENT: return anchor_parent
		EffectEmitter.AnchorMode.CAMERA: return anchor_camera
	return anchor_world


# === Spread ===

func _apply_spread(spread: Vector3) -> Vector3:
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


# === Interpolation ===

func _get_spawn_interval() -> float:
	var curve = _get_curve("spawn_interval")
	return ParticlePhysics.interpolate_simple(
		float(config.spawn_interval_start),
		float(config.spawn_interval_end),
		curve, elapsed_frames
	)


func _get_particle_count() -> int:
	var curve = _get_curve("particle_count")
	var count = ParticlePhysics.interpolate_simple(
		float(config.particle_count_start),
		float(config.particle_count_end),
		curve, elapsed_frames
	)
	return maxi(1, int(count))


func _interpolate_vec3(param: String, start: Vector3, end: Vector3) -> Vector3:
	return ParticlePhysics.interpolate_vec3(start, end, _get_curve(param), elapsed_frames)


func _interpolate_range(param: String, min_s: float, max_s: float, min_e: float, max_e: float) -> float:
	return ParticlePhysics.interpolate_range(min_s, max_s, min_e, max_e, _get_curve(param), elapsed_frames, physics.rng)


func _interpolate_vec3_range(param: String, min_s: Vector3, max_s: Vector3, min_e: Vector3, max_e: Vector3) -> Vector3:
	return ParticlePhysics.interpolate_vec3_range(min_s, max_s, min_e, max_e, _get_curve(param), elapsed_frames, physics.rng)


func _get_curve(param: String) -> EffectCurve:
	if not config.curves.has(param):
		return null
	var idx = config.curves[param]
	if idx < 0:
		return null
	return effect_data.get_curve(idx)


# === Utility ===

static func _rotate_y(v: Vector3, angle: float) -> Vector3:
	"""Rotate vector around Y axis. Matches PSX build_rotation_matrix with X=0,Z=0."""
	if absf(angle) < 0.001:
		return v
	var c = cos(angle)
	var s = sin(angle)
	return Vector3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)


func _get_group_offset(anim_param: int) -> int:
	"""Get cumulative frameset offset for the given frameset group.

	Delegates to EffectData.frameset_group_offset — the one derivation (see its
	docstring). Kept as a named method because the sim reads it on a hot path.
	"""
	return effect_data.frameset_group_offset(anim_param)


func is_done() -> bool:
	return not active


func spawn_particles_for_timeline(spawn_counter: int) -> void:
	"""Spawn particles based on timeline spawn_counter.

	Called by ParticleSubsystem when timeline says this emitter should spawn.
	Uses spawn_counter for curve lookups instead of elapsed_frames.
	"""
	# Use spawn_counter as elapsed_frames for curve lookups
	var saved_elapsed = elapsed_frames
	elapsed_frames = spawn_counter

	# Check spawn interval
	var interval = roundi(_get_spawn_interval())
	if interval <= 0 or spawn_counter % interval != 0:
		elapsed_frames = saved_elapsed
		return

	# Get particle count and spawn
	var count = _get_particle_count()
	for i in range(count):
		var particle = particle_pool.acquire()
		if particle == null:
			break
		_initialize_particle(particle)
		spawned_particles.append(particle)

	elapsed_frames = saved_elapsed
