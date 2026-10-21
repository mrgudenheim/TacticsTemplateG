extends RefCounted
## The TRAP particle spawn-init (FUN_801a7f5c, 0x801a7f5c) as our port models it: an
## ellipsoid-SURFACE spawn point around a centre, then one of the TRAP velocity modes.
## A TRAP handler lifted into E### form (ADR-0369) spawns through this: ActiveEmitter takes
## this branch for an emitter whose `flags.spawn_model == "TRAP"`. (It was first
## single-sourced out of the hand-written TrapEffect, since retired.)
##
## This is the PORT's model, not a ROM-parity claim: the SCATTER branch lacks the ROM's
## zero-delta fallback and the DIRECTIONAL basis is the retired TrapEffect's reconstruction.
## RNG draw order is part of the contract — callers seed one stream and replay it.
## Vault: [[TRAP Hit Effect Particle System]]
## Vault: [[TRAP Charge Particle System]]
## No class_name (ADR-0004).

enum VelocityMode { NONE, SCATTER, DIRECTIONAL, SPHERICAL_RANDOM, FACING_DIRECTIONAL, ZERO }


static func parse_velocity_mode(mode_str: String) -> VelocityMode:
	match mode_str:
		"SCATTER": return VelocityMode.SCATTER
		"DIRECTIONAL": return VelocityMode.DIRECTIONAL
		"SPHERICAL_RANDOM": return VelocityMode.SPHERICAL_RANDOM
		"FACING_DIRECTIONAL": return VelocityMode.FACING_DIRECTIONAL
		"ZERO": return VelocityMode.ZERO
	return VelocityMode.NONE


static func is_directional(mode: VelocityMode) -> bool:
	return mode == VelocityMode.DIRECTIONAL or mode == VelocityMode.FACING_DIRECTIONAL


static func _rand(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()


static func _rand_range(rng: RandomNumberGenerator, a: float, b: float) -> float:
	return rng.randf_range(a, b) if rng != null else randf_range(a, b)


static func random_unit_sphere(rng: RandomNumberGenerator) -> Vector3:
	var theta := _rand(rng) * TAU
	var phi := acos(2.0 * _rand(rng) - 1.0)
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))


## `axes` are the config's +0x10..0x14 "velocity" words — misnamed in the ROM, they are the
## spawn ellipsoid's semi-axes. Returns the offset from the spawn centre (zero for a
## degenerate ellipsoid, drawing no randoms).
static func ellipsoid_offset(axes: Vector3, rng: RandomNumberGenerator) -> Vector3:
	if axes.length() <= 0.001:
		return Vector3.ZERO
	var d := random_unit_sphere(rng)
	return Vector3(d.x * axes.x, d.y * axes.y, d.z * axes.z)


## Spawn position relative to the anchor. DIRECTIONAL modes rotate the whole local
## position into the impact direction (local X = up).
static func spawn_position(centre: Vector3, offset: Vector3, mode: VelocityMode,
		impact_direction: Vector3) -> Vector3:
	var pos := centre + offset
	if is_directional(mode) and impact_direction.length_squared() > 0.001:
		pos = rotate_by_direction(pos, impact_direction)
	return pos


## Launch velocity. `speed_min/max` are already Godot units per tick; `base_angle` and
## `half_range` are radians (the ROM halves `half_range`, so this does too).
static func spawn_velocity(mode: VelocityMode, offset: Vector3, speed_min: float,
		speed_max: float, base_angle: Vector3, half_range: Vector3,
		impact_direction: Vector3, rng: RandomNumberGenerator) -> Vector3:
	match mode:
		VelocityMode.SCATTER:
			var speed := _rand_range(rng, speed_min, speed_max)
			if offset.length() > 0.001 and absf(speed) > 0.001:
				return -offset.normalized() * speed
			return Vector3.ZERO
		VelocityMode.DIRECTIONAL, VelocityMode.FACING_DIRECTIONAL:
			var cone := _cone_basis(base_angle, half_range, rng)
			var speed := _rand_range(rng, speed_min, speed_max)
			var vel_local := cone * Vector3(0, speed, 0)
			if impact_direction.length_squared() > 0.001:
				return build_direction_basis(impact_direction) * vel_local
			return vel_local
		VelocityMode.SPHERICAL_RANDOM:
			var cone := _cone_basis(base_angle, half_range, rng)
			var speed := _rand_range(rng, speed_min, speed_max)
			return cone * Vector3(0, -speed, 0)
	return Vector3.ZERO


static func _cone_basis(base_angle: Vector3, half_range: Vector3, rng: RandomNumberGenerator) -> Basis:
	var ax := base_angle.x + _rand_range(rng, -half_range.x * 0.5, half_range.x * 0.5)
	var ay := base_angle.y + _rand_range(rng, -half_range.y * 0.5, half_range.y * 0.5)
	var az := base_angle.z + _rand_range(rng, -half_range.z * 0.5, half_range.z * 0.5)
	return Basis.from_euler(Vector3(ax, ay, az), EULER_ORDER_ZYX)


## Local → world for DIRECTIONAL positions: local X maps to world up (world X = local Y,
## world Y = -local X), then a yaw to the impact direction's XZ heading.
static func rotate_by_direction(local_vec: Vector3, direction: Vector3) -> Vector3:
	var base_rotated := Vector3(local_vec.y, -local_vec.x, local_vec.z)
	var dir_xz := Vector3(direction.x, 0.0, direction.z)
	if dir_xz.length_squared() < 0.001:
		return base_rotated
	dir_xz = dir_xz.normalized()
	var angle := atan2(dir_xz.z, dir_xz.x)
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(base_rotated.x * c - base_rotated.z * s, base_rotated.y,
		base_rotated.x * s + base_rotated.z * c)


## The PSX direction matrix for DIRECTIONAL velocity: yaw = atan2(-dx, dz),
## pitch = atan2(dy, |dxz|) + 90°, roll = 0.
static func build_direction_basis(direction: Vector3) -> Basis:
	var d := direction.normalized()
	var yaw := atan2(-d.x, d.z)
	var pitch := atan2(d.y, sqrt(d.x * d.x + d.z * d.z)) + PI * 0.5
	return Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
