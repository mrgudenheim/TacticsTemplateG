extends RefCounted

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")

const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

# psx-faithful-sim: the integrator's *4096 / weight/4096 IS the ROM per-frame arithmetic (integrate_particle_motion), ADR-0091 §4
## PSX-authentic particle physics - NO CONVERSION CONSTANTS
##
## All input values are pre-converted to Godot units by the parser.
## Physics formulas match FFT exactly, just with pre-scaled values.
## Vault: [[Effect File Format]]
## Vault: [[Homing System]]
## Vault: [[Particle Curve Indices]]
## Vault: [[Sprite Offset vs Vertex Position]]

# Global physics from particle header (pre-converted to Godot units)
var gravity: Vector3 = Vector3(0.0, -0.036, 0.0)
var inertia_threshold: float = 512.0  # Raw value (not normalized)


var effect_data = null  # Set by ParticleSubsystem for curve lookups

# Per-instance RNG (ADR-0070). Threaded down from the owning EffectInstance so
# in-instance replay is deterministic — a scrub back-and-forth reproduces the
# exact same cloud. null = fall back to the global randf (unseeded gameplay
# default, and the safe path for direct-construction callers/tests).
var rng: RandomNumberGenerator = null


func rand() -> float:
	"""Instance-RNG randf() with a global fallback when no RNG is threaded in."""
	return rng.randf() if rng != null else randf()


func rand_range(a: float, b: float) -> float:
	"""Instance-RNG randf_range() with a global fallback."""
	return rng.randf_range(a, b) if rng != null else randf_range(a, b)


static func _srange(a: float, b: float, rng: RandomNumberGenerator) -> float:
	"""Static randf_range that honours a passed-in RNG (or global if null) — for
	the static spawn helpers below, which have no `self` to read `rng` from."""
	return rng.randf_range(a, b) if rng != null else randf_range(a, b)


func update_particle_fixed(particle: Particle) -> void:
	"""Update single particle physics for one 30 FPS frame (FFT rate)

	FFT-authentic physics from integrate_particle_motion:
	1. Velocity = (inertia_factor * old_velocity + accel) / inertia + gravity
	2. Position += OLD velocity (semi-implicit Euler)
	3. Acceleration update: drag or homing blend
	"""
	if not particle.active:
		return

	# Store old velocity (PSX quirk: position uses old velocity)
	var old_velocity: Vector3 = particle.velocity

	# === VELOCITY UPDATE ===
	# FFT formula: v = ((inertia - threshold) * v_old + accel * 4096) / inertia
	# The 4096 constant is FIXED in FFT, not variable with inertia
	var inertia: float = particle.inertia
	var inertia_factor: float = maxf(0.0, inertia - inertia_threshold)

	var new_velocity: Vector3
	if inertia > 0.0:
		# FFT: new_vel = (inertia_factor * old_vel + accel * 4096) / inertia
		# The 4096 is a fixed scaling constant, NOT inertia
		new_velocity = (inertia_factor * old_velocity + particle.acceleration * 4096.0) / inertia
	else:
		new_velocity = particle.acceleration * 4096.0

	# Apply gravity (weight is raw 0-4096, gravity is pre-converted)
	# FFT: gravity * weight >> 12 = gravity * weight / 4096
	new_velocity += gravity * particle.weight / 4096.0

	# === POSITION UPDATE (uses OLD velocity) ===
	# Velocity is already in Godot units/frame, so just add directly
	particle.position += old_velocity

	# Store new velocity
	particle.velocity = new_velocity

	# === ACCELERATION UPDATE ===
	# PSX gate is homing_strength != 0 (HOMING_SYSTEM_ANALYSIS.md §7): the SIGN selects
	# behaviour — positive attracts, NEGATIVE repels (flee/dispersal, e.g. E142 emitter 15).
	# A `<= 0` gate would silently collapse repulsion into "no homing".
	if is_zero_approx(particle.homing_strength):
		# Simple physics: drag accumulates into acceleration
		particle.acceleration += particle.drag
	else:
		_apply_homing_acceleration(particle)



func _apply_homing_acceleration(particle: Particle) -> void:
	"""Apply FFT-authentic homing physics

	Blend between drag and homing based on curve value.
	FFT formula: accel += ((drag - homing) * curve_factor) / 127 + homing

	curve_factor range: -128 to +127 (from curve[index-1][frame] - 128)
	Default -128 means: 2×homing - drag (strong homing)
	Value 0 means: pure homing
	Value +127 means: mostly drag, minimal homing
	"""
	# Get curve value (-128 to +127)
	var curve_value: float = -128.0  # Default: full homing when no curve

	if particle.homing_curve_index > 0 and effect_data:
		# FFT uses 1-based curve indices, curve[index-1]
		var curve = effect_data.get_curve(particle.homing_curve_index - 1)
		if curve:
			# Curve returns 0.0-1.0, convert to 0-255 then subtract 128
			curve_value = curve.sample_by_frame(particle.age) * 255.0 - 128.0

	# Calculate homing direction
	var to_target: Vector3 = particle.homing_target - particle.position
	var dist: float = to_target.length()

	if dist < 0.001:
		particle.acceleration += particle.drag
		return

	var direction: Vector3 = to_target / dist

	# Homing force (pre-converted to Godot units)
	var homing_force: Vector3 = direction * particle.homing_strength

	# FFT blend: accel += ((drag - homing) * curve_value) / 127 + homing
	var blend_factor: float = curve_value / 127.0
	var blended: Vector3 = (particle.drag - homing_force) * blend_factor + homing_force

	particle.acceleration += blended


func update_particles_fixed(particles: Array) -> void:
	"""Update all particles at fixed 30 FPS (FFT rate)"""
	for particle in particles:
		update_particle_fixed(particle)


# === Direction Helpers ===

static func angle_to_direction(angle_x: float, angle_y: float, angle_z: float) -> Vector3:
	"""Convert emission angles (already in radians from the parser) to a launch
	direction, by rotating the launch base vector.

	Axis classification (ADR-0091 / ADR-0057). MAGNITUDE: none here — the angles
	arrive pre-converted to radians (via the PsxMagnitude seam upstream), so no unit
	conversion happens in this function. CHIRALITY: the base vector is game-space
	DOWN (0,-1,0); a zero-angle emission launches straight down and negative radial
	velocity carries the particle upward — the effects' launch convention. This is
	NOT a PSX inverted-Y coordinate leak to purge: making the runtime read a
	`Vector3.UP` base identity-preserving requires adding π (a half-turn) to the emission Z
	angle at the parse seam — empirically the ONLY transform that reproduces this
	exact cloud (a sign flip does not) — which would bake a hidden 180° into
	authored angle data for no behavioural gain. So the base stays DOWN; the cloud
	is locked byte-for-byte by ParticleEmissionDirectionTest.
	"""
	var basis: Basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.FORWARD, angle_z)  # Z first
	basis = basis.rotated(Vector3.UP, angle_y)
	basis = basis.rotated(Vector3.RIGHT, angle_x)

	var direction: Vector3 = basis * Vector3.DOWN
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3.DOWN


static func random_cone_direction(base_direction: Vector3, spread: Vector3, rng: RandomNumberGenerator = null) -> Vector3:
	"""Generate random direction within cone spread (spread in radians). An
	optional per-instance RNG (ADR-0070) pins the draw for deterministic replay."""
	var angle_offset_x: float = _srange(-spread.x, spread.x, rng)
	var angle_offset_y: float = _srange(-spread.y, spread.y, rng)

	var basis: Basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.RIGHT, angle_offset_x)
	basis = basis.rotated(Vector3.UP, angle_offset_y)

	return basis * base_direction


# === Interpolation Helpers ===

static func interpolate_simple(start: float, end_val: float, curve = null, frame: int = 0) -> float:
	"""Interpolate between two values. No curve = no interpolation (use start)."""
	if curve == null:
		return start
	var curve_t: float = curve.sample_by_frame(frame)
	return lerpf(start, end_val, curve_t)


static func interpolate_vec3(start: Vector3, end_val: Vector3, curve = null, frame: int = 0) -> Vector3:
	"""Interpolate between two Vector3 values. No curve = no interpolation (use start)."""
	if curve == null:
		return start
	var curve_t: float = curve.sample_by_frame(frame)
	return start.lerp(end_val, curve_t)


static func interpolate_range(
	min_start: float, max_start: float,
	min_end: float, max_end: float,
	curve = null, frame: int = 0,
	rng: RandomNumberGenerator = null
) -> float:
	"""Interpolate between min/max ranges, return random value in range. No curve = use start range.
	Optional per-instance RNG (ADR-0070) pins the draw for deterministic replay."""
	if curve == null:
		return _srange(min_start, max_start, rng)
	var curve_t: float = curve.sample_by_frame(frame)

	var min_val: float = lerpf(min_start, min_end, curve_t)
	var max_val: float = lerpf(max_start, max_end, curve_t)
	return _srange(min_val, max_val, rng)


static func interpolate_vec3_range(
	min_start: Vector3, max_start: Vector3,
	min_end: Vector3, max_end: Vector3,
	curve = null, frame: int = 0,
	rng: RandomNumberGenerator = null
) -> Vector3:
	"""Interpolate between Vector3 min/max ranges. No curve = use start range.
	Optional per-instance RNG (ADR-0070) pins the draw for deterministic replay."""
	if curve == null:
		return Vector3(
			_srange(min_start.x, max_start.x, rng),
			_srange(min_start.y, max_start.y, rng),
			_srange(min_start.z, max_start.z, rng)
		)
	var curve_t: float = curve.sample_by_frame(frame)

	var min_val: Vector3 = min_start.lerp(min_end, curve_t)
	var max_val: Vector3 = max_start.lerp(max_end, curve_t)

	return Vector3(
		_srange(min_val.x, max_val.x, rng),
		_srange(min_val.y, max_val.y, rng),
		_srange(min_val.z, max_val.z, rng)
	)
