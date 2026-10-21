extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB91 - Trail projectile callback (PSX FUN_801c2500, shared load base): custom
## sub-projectiles (NOT pool particles), each with a 9-entry trail ring buffer for
## ribbon rendering. Movement: cosine_ease blend between ballistic position
## (start + velocity * t) and target — scattered launch from the emitter's
## velocity_base_angle/spread/radial_velocity fields; after lifetime a convergence
## phase shortens the trail from TRAIL_LENGTH-1 to 0.
## Vault: [[Embedded MIPS Effect Code]]

const ParticlePhysics = preload("res://addons/exmateria_effects/particles/ParticlePhysics.gd")

const TRAIL_LENGTH: int = 9
const MAX_PROJECTILES: int = 8

## Per-trail-segment brightness, PSX 0-4096, index 0 = tail, 8 = head. Read from
## `callbacks/CB91/callback_data.json`; EMPTY when no file was found.
##
## 🔴 THIS USED TO BE A HARDCODED CONST, AND THE CONST CITED AN IMPOSSIBLE ADDRESS.
## It read `[0.0, 0.125, ... 1.0]` with the comment "PSX brightness table
## (DAT_801c24e0)". 0x801C24E0 is 32 bytes BELOW the 0x801C2500 load base — file
## offset -32 — so it cannot be in the effect file at all. The real table is at
## file+0x36B0 and the routine picks a ROW from it: `lh r2, 0x4E(r9)` then base
## 0x801C5BB0 with stride 0x24. The const was row 0 of six, and it was right only
## because every E317 emitter's +0x4E happens to be 0, so no other row is reachable.
## Correct by luck of the data, not by derivation — and structurally unable to reveal
## a missing table, which is how the impossible citation went unnoticed.
var _brightness_row: Array = []
var _brightness_row_idx: int = 0

var _projectiles: Array = []  # Array of dictionaries
var _total_spawned: int = 0

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
		# Row index: emitter+0x4E, read by `lh r2, 0x4E(r9)` at E317 file+0x1484.
		_brightness_row_idx = int(emitter_config.callback_params.get("param_4E", 0))

	_brightness_row = []
	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			var rows: Array = cb_data.get("brightness_table", [])
			if _brightness_row_idx >= 0 and _brightness_row_idx < rows.size():
				_brightness_row = rows[_brightness_row_idx]
		# WARN, never raise. `parse_by_routine` raises because it is BUILD time and the
		# cost is a rebuild; this is RUNTIME and the cost is the player's battle. The
		# render falls back to flat 1.0 below.
		if _brightness_row.size() < TRAIL_LENGTH:
			push_warning(
				"TrailProjectileCallback: %s CB%d has no usable brightness row %d "
				% [effect_data.name, callback_id, _brightness_row_idx]
				+ "(need %d values). Trail will render FLAT. " % TRAIL_LENGTH
				+ "Regenerate with tools/parse_effect_callbacks.py.")
			_brightness_row = []

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

	var interval: int = emitter_config.spawn_interval_start
	if interval > 1 and (spawn_counter % interval) != 0:
		return

	var count: int = emitter_config.particle_count_start
	for i in range(count):
		if _projectiles.size() >= MAX_PROJECTILES:
			break
		_spawn_projectile(emitter_index, spawn_counter)

func _spawn_projectile(emitter_index: int, _spawn_counter: int) -> void:
	"""Create a new sub-projectile with velocity from emitter config fields."""
	var start_pos: Vector3 = _resolve_emitter_anchor() + emitter_config.position_start

	var target_pos: Vector3 = _resolve_target_anchor() + emitter_config.target_offset_start

	var half_width_raw: int = emitter_config.callback_params.get("param_AA", 15)
	var half_width: float = float(half_width_raw) * PSX_SCALE * 0.5

	var lifetime: int = emitter_config.lifetime_max_start
	if lifetime <= 0:
		lifetime = 25

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

			var head: int = proj["trail_head"]
			proj["trail"][head] = proj["position"]
			proj["trail_head"] = (head + 1) % TRAIL_LENGTH

			# Every-frame mid-life child spawning
			if emitter_config and emitter_config.flags.get("child_midlife_enabled", false):
				if emitter_config.child_emitter_mid_life >= 0:
					child_spawn_requested.emit(
						emitter_config.child_emitter_mid_life,
						proj["position"], t)

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

	if _projectiles.is_empty() and _total_spawned > 0 and state in [State.ANIMATE, State.CLEANUP]:
		super.cleanup()

func is_active() -> bool:
	"""Stay ticking after callback cleanup so in-flight trails can reach target."""
	return state == State.ANIMATE or not _projectiles.is_empty()

func cleanup() -> void:
	"""Stop accepting timeline invocations, but let existing sub-projectiles finish.

	E070 Carbuncle cb23's phase1 slot ends at f42 while its trails are still in
	flight; the ROM lets those child projectiles converge before disappearing.
	"""
	if _projectiles.is_empty():
		super.cleanup()
		return
	state = State.CLEANUP

func update_render() -> void:
	"""Rebuild ArrayMesh with ribbon quads for all active trails."""
	if _array_mesh == null:
		return

	_array_mesh.clear_surfaces()

	if not is_active() or _projectiles.is_empty():
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
		# Flat 1.0 when no table loaded — the same signature every sibling class
		# produces, so the failure looks like the failure this project recognises on
		# sight. Deliberately NOT row 0's values: those are what a working E317 looks
		# like today, so falling back to them would be indistinguishable from working.
		var brightness: float = 1.0
		if not _brightness_row.is_empty():
			brightness = float(_brightness_row[clampi(brightness_idx, 0, TRAIL_LENGTH - 1)]) \
					/ BRIGHTNESS_SCALE
		var color := Color(brightness, brightness, brightness, 1.0)

		# Quad centroid for GTE-style depth
		var centroid: Vector3 = (v0 + v1 + v2 + v3) * 0.25

		positions.append(v0); colors.append(color); uvs.append(Vector2(u0, vt))
		positions.append(v1); colors.append(color); uvs.append(Vector2(u0, vb))
		positions.append(v2); colors.append(color); uvs.append(Vector2(u1, vt))

		positions.append(v1); colors.append(color); uvs.append(Vector2(u0, vb))
		positions.append(v3); colors.append(color); uvs.append(Vector2(u1, vb))
		positions.append(v2); colors.append(color); uvs.append(Vector2(u1, vt))

		for _j in 6:
			custom0.append(centroid.x)
			custom0.append(centroid.y)
			custom0.append(centroid.z)

func force_cleanup() -> void:
	"""Hard reset path used by CallbackManager.reset()."""
	_projectiles.clear()
	_total_spawned = 0
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
