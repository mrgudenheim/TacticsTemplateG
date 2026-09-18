extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB91 - Trail projectile callback (PSX FUN_801c2500).
## Manages custom sub-projectiles (NOT particles in the pool).
## Each projectile has a 9-entry trail ring buffer for ribbon rendering.
##
## Movement: cosine_ease blend between ballistic position (start + velocity * t)
## and target position. The initial velocity comes from the emitter's
## velocity_base_angle/spread/radial_velocity fields, giving scattered launch
## directions that smoothly converge to the target over the lifetime.
##
## After reaching lifetime, enters convergence phase where trail shortens
## from TRAIL_LENGTH-1 down to 0 over additional frames.
## Vault: [[Embedded MIPS Effect Code]]

const ParticlePhysics = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")

const TRAIL_LENGTH: int = 9
const MAX_PROJECTILES: int = 8

# PSX brightness table (DAT_801c24e0): 0/4096 to 4096/4096 in 9 steps
# Index 0 = tail (dimmest), index 8 = head (brightest)
const BRIGHTNESS_TABLE: Array[float] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]

# Sub-projectile data
var _projectiles: Array = []  # Array of dictionaries
var _total_spawned: int = 0

# Texture UV mapping (read from emitter config in _on_init)
var _base_u: int = 0
var _base_v: int = 0
var _uv_step: int = 3
var _v_height: int = 15
var _tex_size: Vector2 = Vector2(128, 128)

func _ready() -> void:
	_create_cb_mesh(true)

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_projectiles.clear()
	_total_spawned = 0

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	"""INIT -> ANIMATE: read UV params from emitter config, load texture."""
	if emitter_config:
		# CB91 UV mapping from emitter config (PSX offsets 0x64, 0x68)
		var raw_accel = emitter_config.raw_data.get("accel_min_start", [0, 0, 0])
		if raw_accel is Array and raw_accel.size() >= 2:
			_base_u = int(raw_accel[0])
			_base_v = int(raw_accel[1])
		# UV step per segment = param_A8 >> 3 (PSX bit shift)
		_uv_step = int(emitter_config.callback_params.get("param_A8", 24)) >> 3
		# V height from param_AA
		_v_height = int(emitter_config.callback_params.get("param_AA", 15))

	# Load texture onto material
	if effect_data and effect_data.texture and _material:
		_material.set_shader_parameter("effect_texture", effect_data.texture)
		_material.set_shader_parameter("use_texture", true)
		_tex_size = effect_data.texture.get_size()

	state = State.ANIMATE
	_on_animate(emitter_index, spawn_counter, channel_index)

func _on_animate(emitter_index: int, spawn_counter: int, _channel_index: int) -> void:
	"""Each invocation: spawn new sub-projectiles based on emitter config."""
	if emitter_config == null:
		return

	# Spawn interval check
	var interval: int = emitter_config.spawn_interval_start
	if interval > 1 and (spawn_counter % interval) != 0:
		return

	# Spawn new projectiles based on particle_count
	var count: int = emitter_config.particle_count_start
	for i in range(count):
		if _projectiles.size() >= MAX_PROJECTILES:
			break
		_spawn_projectile(emitter_index, spawn_counter)

func _spawn_projectile(emitter_index: int, _spawn_counter: int) -> void:
	"""Create a new sub-projectile with velocity from emitter config fields."""
	# Start position: resolve emitter anchor + position offset
	var start_pos: Vector3 = _resolve_emitter_anchor() + emitter_config.position_start

	# Target position: resolve target anchor + target_offset
	var target_pos: Vector3 = _resolve_target_anchor() + emitter_config.target_offset_start

	# Get ribbon half-width from callback_params
	var half_width_raw: int = emitter_config.callback_params.get("param_AA", 15)
	var half_width: float = float(half_width_raw) * PSX_SCALE * 0.5

	# Get lifetime from emitter config
	var lifetime: int = emitter_config.lifetime_max_start
	if lifetime <= 0:
		lifetime = 25

	# Initial velocity from emitter's velocity_base_angle + direction_spread + radial_velocity
	var vel_angle: Vector3 = emitter_config.velocity_base_angle_start
	var vel_spread: Vector3 = emitter_config.velocity_direction_spread_start
	var base_dir: Vector3 = ParticlePhysics.angle_to_direction(vel_angle.x, vel_angle.y, vel_angle.z)
	var final_dir: Vector3 = ParticlePhysics.random_cone_direction(base_dir, vel_spread)

	var radial_vel: float = randf_range(
		emitter_config.radial_velocity_min_start,
		emitter_config.radial_velocity_max_start)
	if absf(radial_vel) < 0.001:
		radial_vel = 0.3

	var velocity: Vector3 = final_dir * radial_vel

	# Initialize trail ring buffer
	var trail: Array[Vector3] = []
	for _t in range(TRAIL_LENGTH):
		trail.append(start_pos)

	var proj: Dictionary = {
		"position": start_pos,
		"velocity": velocity,
		"target": target_pos,
		"start": start_pos,
		"trail": trail,
		"trail_head": 0,
		"frame": 0,
		"lifetime": lifetime,
		"half_width": half_width,
		"emitter_index": emitter_index,
		"active": true,
		"convergence_age": -1,  # -1 = flying, TRAIL_LENGTH-1 -> 0 = fading
	}
	_projectiles.append(proj)
	_total_spawned += 1

	if EffectsDebug.particle():
		print("[CB91] Spawned projectile %d: pos=%s vel=%s -> %s (life=%d)" % [
			_total_spawned, start_pos, velocity, target_pos, lifetime])

func _resolve_emitter_anchor() -> Vector3:
	"""Resolve emitter anchor position based on emitter config."""
	match emitter_config.get_emitter_anchor_mode():
		EffectEmitter.AnchorMode.CURSOR: return anchor_cursor
		EffectEmitter.AnchorMode.ORIGIN: return anchor_origin
		EffectEmitter.AnchorMode.TARGET: return anchor_target
	return anchor_world

func _resolve_target_anchor() -> Vector3:
	"""Resolve target anchor position based on emitter config."""
	match emitter_config.get_target_anchor_mode():
		EffectEmitter.AnchorMode.CURSOR: return anchor_cursor
		EffectEmitter.AnchorMode.ORIGIN: return anchor_origin
		EffectEmitter.AnchorMode.TARGET: return anchor_target
	return anchor_world

func physics_step() -> void:
	"""Update all active sub-projectiles.

	Movement: cosine_ease blend between ballistic position and target.
	- ballistic_pos = start + velocity * frame (straight-line from launch)
	- position = cosine_ease_vec3(ballistic_pos, target, lifetime, frame)
	Early frames: position near ballistic (scattered outward).
	Late frames: position converges to target.

	After lifetime: convergence phase shortens visible trail.
	"""
	var dead_indices: Array[int] = []

	for i in range(_projectiles.size()):
		var proj: Dictionary = _projectiles[i]
		if not proj["active"]:
			dead_indices.append(i)
			continue

		proj["frame"] += 1
		var t: int = proj["frame"]
		var lifetime: int = proj["lifetime"]

		if proj["convergence_age"] < 0:
			# Flying phase: update position with cosine ease convergence
			var ballistic_pos: Vector3 = proj["start"] + proj["velocity"] * float(t)
			proj["position"] = cosine_ease_vec3(ballistic_pos, proj["target"], lifetime, t)

			# Record in trail ring buffer
			var head: int = proj["trail_head"]
			proj["trail"][head] = proj["position"]
			proj["trail_head"] = (head + 1) % TRAIL_LENGTH

			# Every-frame mid-life child spawning
			if emitter_config and emitter_config.flags.get("child_midlife_enabled", false):
				if emitter_config.child_emitter_mid_life >= 0:
					child_spawn_requested.emit(
						emitter_config.child_emitter_mid_life,
						proj["position"], t)

			# Check if reached lifetime -> enter convergence
			if t >= lifetime:
				proj["convergence_age"] = TRAIL_LENGTH - 1
				if EffectsDebug.particle():
					var dist: float = Vector3(proj["position"]).distance_to(Vector3(proj["target"]))
					print("[CB91] CONVERGE proj#%d frame=%d dist=%.3f" % [i + 1, t, dist])
		else:
			# Convergence phase: trail shortening
			proj["convergence_age"] -= 1
			if proj["convergence_age"] <= 0:
				proj["active"] = false
				dead_indices.append(i)

	# Remove dead projectiles (iterate in reverse)
	dead_indices.reverse()
	for idx in dead_indices:
		_projectiles.remove_at(idx)

	# Transition to INACTIVE when no projectiles remain and we've spawned some
	if _projectiles.is_empty() and _total_spawned > 0 and state == State.ANIMATE:
		state = State.INACTIVE

func update_render() -> void:
	"""Rebuild ArrayMesh with ribbon quads for all active trails."""
	if _array_mesh == null:
		return

	_array_mesh.clear_surfaces()

	if _projectiles.is_empty():
		return

	# Get camera basis for billboard ribbons
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_forward: Vector3 = -camera.global_basis.z

	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	for proj in _projectiles:
		if not proj["active"]:
			continue
		_draw_ribbon(proj, cam_forward, positions, colors, uvs, custom0)

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func _draw_ribbon(proj: Dictionary, cam_forward: Vector3,
				positions: PackedVector3Array, colors: PackedColorArray,
				uvs: PackedVector2Array, custom0: PackedFloat32Array) -> void:
	"""Draw ribbon quads with shared edge vertices and per-segment UV stepping."""
	var trail: Array = proj["trail"]
	var head: int = proj["trail_head"]
	var hw: float = proj["half_width"]

	# Determine how many quads to draw
	var visible_quads: int = TRAIL_LENGTH - 1
	if proj["convergence_age"] >= 0:
		visible_quads = proj["convergence_age"]
	if visible_quads <= 0:
		return

	# Build ordered trail positions (newest first)
	var ordered: Array[Vector3] = []
	for i in range(TRAIL_LENGTH):
		var idx: int = (head - 1 - i + TRAIL_LENGTH) % TRAIL_LENGTH
		ordered.append(trail[idx])

	# Number of positions we need (one more than quads)
	var valid_count: int = mini(visible_quads + 1, TRAIL_LENGTH)
	if valid_count < 2:
		return

	# Pre-compute shared perpendicular at each trail position (angle averaging)
	var perps: Array[Vector3] = []
	perps.resize(valid_count)

	for i in range(valid_count):
		if i == 0:
			var seg: Vector3 = ordered[1] - ordered[0]
			if seg.length_squared() < 0.0001:
				perps[0] = Vector3.ZERO
			else:
				perps[0] = seg.cross(cam_forward).normalized()
		elif i == valid_count - 1:
			var seg: Vector3 = ordered[i] - ordered[i - 1]
			if seg.length_squared() < 0.0001:
				perps[i] = perps[i - 1] if i > 0 else Vector3.ZERO
			else:
				perps[i] = seg.cross(cam_forward).normalized()
		else:
			var seg_prev: Vector3 = ordered[i] - ordered[i - 1]
			var seg_next: Vector3 = ordered[i + 1] - ordered[i]
			var perp_prev: Vector3
			var perp_next: Vector3

			if seg_prev.length_squared() < 0.0001:
				perp_prev = Vector3.ZERO
			else:
				perp_prev = seg_prev.cross(cam_forward).normalized()

			if seg_next.length_squared() < 0.0001:
				perp_next = Vector3.ZERO
			else:
				perp_next = seg_next.cross(cam_forward).normalized()

			if perp_prev == Vector3.ZERO:
				perps[i] = perp_next
			elif perp_next == Vector3.ZERO:
				perps[i] = perp_prev
			else:
				if perp_prev.dot(perp_next) < 0:
					perp_next = -perp_next
				var avg: Vector3 = perp_prev + perp_next
				if avg.length_squared() < 0.0001:
					perps[i] = perp_prev
				else:
					perps[i] = avg.normalized()

	# Draw quads using shared edge vertices with per-segment UV stepping
	var num_quads: int = mini(visible_quads, valid_count - 1)
	for i in range(num_quads):
		var p0: Vector3 = ordered[i]
		var p1: Vector3 = ordered[i + 1]

		if (p1 - p0).length_squared() < 0.0001:
			continue

		var perp0: Vector3 = perps[i]
		var perp1: Vector3 = perps[i + 1]
		if perp0 == Vector3.ZERO or perp1 == Vector3.ZERO:
			continue

		var v0: Vector3 = p0 + perp0 * hw
		var v1: Vector3 = p0 - perp0 * hw
		var v2: Vector3 = p1 + perp1 * hw
		var v3: Vector3 = p1 - perp1 * hw

		var u0: float = float(_base_u + i * _uv_step) / _tex_size.x
		var u1: float = float(_base_u + (i + 1) * _uv_step) / _tex_size.x
		var vt: float = float(_base_v) / _tex_size.y
		var vb: float = float(_base_v + _v_height) / _tex_size.y

		var brightness_idx: int = TRAIL_LENGTH - 1 - i
		var brightness: float = BRIGHTNESS_TABLE[clampi(brightness_idx, 0, TRAIL_LENGTH - 1)]
		var color := Color(brightness, brightness, brightness, 1.0)

		# Quad centroid for GTE-style depth
		var centroid: Vector3 = (v0 + v1 + v2 + v3) * 0.25

		# Triangle 1: v0, v1, v2
		positions.append(v0); colors.append(color); uvs.append(Vector2(u0, vt))
		positions.append(v1); colors.append(color); uvs.append(Vector2(u0, vb))
		positions.append(v2); colors.append(color); uvs.append(Vector2(u1, vt))

		# Triangle 2: v1, v3, v2
		positions.append(v1); colors.append(color); uvs.append(Vector2(u0, vb))
		positions.append(v3); colors.append(color); uvs.append(Vector2(u1, vb))
		positions.append(v2); colors.append(color); uvs.append(Vector2(u1, vt))

		for _j in 6:
			custom0.append(centroid.x)
			custom0.append(centroid.y)
			custom0.append(centroid.z)

func cleanup() -> void:
	_projectiles.clear()
	_total_spawned = 0
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
