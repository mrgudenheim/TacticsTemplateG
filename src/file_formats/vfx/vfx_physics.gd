class_name VfxPhysics
extends RefCounted
## PSX-authentic particle physics
## All input values are pre-converted to Godot units by VfxEmitter.conv_* fields

var gravity: Vector3 = Vector3(0.0, -0.036, 0.0)
var inertia_threshold: float = 512.0

var vfx_data: VisualEffectData  # For curve lookups


func initialize(effect: VisualEffectData) -> void:
	vfx_data = effect
	gravity = effect.gravity
	inertia_threshold = float(effect.inertia_threshold)


func update_particle(particle: VfxParticleData) -> void:
	if not particle.active:
		return

	# Store old velocity (PSX: position uses old velocity)
	var old_velocity: Vector3 = particle.velocity

	# Velocity update: v = ((inertia - threshold) * v_old + accel * 4096) / inertia
	var inertia: float = particle.inertia
	var inertia_factor: float = maxf(0.0, inertia - inertia_threshold)

	var new_velocity: Vector3
	if inertia > 0.0:
		new_velocity = (inertia_factor * old_velocity + particle.acceleration * 4096.0) / inertia
	else:
		new_velocity = particle.acceleration * 4096.0

	# Gravity: gravity * weight / 4096
	new_velocity += gravity * particle.weight / 4096.0

	# Position update (uses OLD velocity)
	particle.position += old_velocity

	particle.velocity = new_velocity

	# Acceleration update: drag or homing
	if particle.homing_strength <= 0.0:
		particle.acceleration += particle.drag
	else:
		_apply_homing_acceleration(particle)

	particle.age += 1


func _apply_homing_acceleration(particle: VfxParticleData) -> void:
	# Get curve value (-128 to +127)
	var curve_value: float = -128.0

	if particle.homing_curve_index > 0 and vfx_data:
		var curve: VfxCurve = vfx_data.get_curve(particle.homing_curve_index - 1)
		if curve:
			curve_value = curve.sample_by_frame(particle.age) * 255.0 - 128.0

	var to_target: Vector3 = particle.homing_target - particle.position
	var dist: float = to_target.length()

	if dist < 0.001:
		particle.acceleration += particle.drag
		return

	var direction: Vector3 = to_target / dist
	var homing_force: Vector3 = direction * particle.homing_strength

	# FFT blend: accel += ((drag - homing) * curve_value) / 127 + homing
	var blend_factor: float = curve_value / 127.0
	var blended: Vector3 = (particle.drag - homing_force) * blend_factor + homing_force

	particle.acceleration += blended


# === Direction Helpers ===

static func angle_to_direction(angle_x: float, angle_y: float, angle_z: float) -> Vector3:
	var basis: Basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.FORWARD, angle_z)
	basis = basis.rotated(Vector3.UP, angle_y)
	basis = basis.rotated(Vector3.RIGHT, angle_x)

	var direction: Vector3 = basis * Vector3.DOWN
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3.DOWN


static func random_cone_direction(base_direction: Vector3, spread: Vector3) -> Vector3:
	var angle_offset_x: float = randf_range(-spread.x, spread.x)
	var angle_offset_y: float = randf_range(-spread.y, spread.y)

	var basis: Basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.RIGHT, angle_offset_x)
	basis = basis.rotated(Vector3.UP, angle_offset_y)

	return basis * base_direction


# === Interpolation Helpers ===

static func interpolate_simple(start: float, end_val: float, t: float, curve: VfxCurve = null, frame: int = 0) -> float:
	if curve == null:
		return start
	var curve_t: float = curve.sample_by_frame(frame)
	return lerpf(start, end_val, curve_t)


static func interpolate_vec3(start: Vector3, end_val: Vector3, t: float, curve: VfxCurve = null, frame: int = 0) -> Vector3:
	if curve == null:
		return start
	var curve_t: float = curve.sample_by_frame(frame)
	return start.lerp(end_val, curve_t)


static func interpolate_range(
	min_start: float, max_start: float,
	min_end: float, max_end: float,
	t: float, curve: VfxCurve = null, frame: int = 0
) -> float:
	if curve == null:
		return randf_range(min_start, max_start)
	var curve_t: float = curve.sample_by_frame(frame)

	var min_val: float = lerpf(min_start, min_end, curve_t)
	var max_val: float = lerpf(max_start, max_end, curve_t)
	return randf_range(min_val, max_val)


static func interpolate_vec3_range(
	min_start: Vector3, max_start: Vector3,
	min_end: Vector3, max_end: Vector3,
	t: float, curve: VfxCurve = null, frame: int = 0
) -> Vector3:
	if curve == null:
		return Vector3(
			randf_range(min_start.x, max_start.x),
			randf_range(min_start.y, max_start.y),
			randf_range(min_start.z, max_start.z)
		)
	var curve_t: float = curve.sample_by_frame(frame)

	var min_val: Vector3 = min_start.lerp(min_end, curve_t)
	var max_val: Vector3 = max_start.lerp(max_end, curve_t)

	return Vector3(
		randf_range(min_val.x, max_val.x),
		randf_range(min_val.y, max_val.y),
		randf_range(min_val.z, max_val.z)
	)
