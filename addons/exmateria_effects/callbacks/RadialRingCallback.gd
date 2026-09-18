extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB10 - Radial concentric ring callback (PSX FUN_801c2500).
## Screen-space 2D overlay: 6 concentric rings with 5 quarter-ring vertices,
## mirrored 4 ways (90-degree rotational symmetry) = 80 quads total.
## Rings expand outward with rotation. Center point moves with velocity.
##
## Analysis:
## 1. Quad count: 80 (5 bands × 4 quads × 4 quadrants). Alloc 0x20fc.
## 2. Topology: Concentric radial rings with 4-fold symmetry.
## 3. Orientation: 2D screen overlay (no GTE). Camera-pinned.
## 4. Blend mode: (emitter+0x4C & 3), typically additive.
## 5. UV base from emitter offset 0xB8/0xBA (homing_min_start/max_start).
## Vault: [[Effect Callback Mesh]]
## Vault: [[Embedded MIPS Effect Code]]

const RING_COUNT: int = 6       # Number of concentric rings
const VERTS_PER_QUARTER: int = 5 # Vertices per quarter-ring (4 computed + 1 mirrored)
const QUADS_PER_BAND: int = 4   # Quads between adjacent vertices in a quarter
const QUADRANTS: int = 4        # 4-way rotational symmetry

# Center position (PSX screen pixels, updated by velocity)
var _center_x: int = 0
var _center_y: int = 0

# Center velocity (fixed-point, >>12 per frame)
var _center_vel_x: int = 0
var _center_vel_y: int = 0

# Center velocity acceleration (added to velocity each frame)
var _center_accel_x: int = 0
var _center_accel_y: int = 0

# Ring vertices: [ring][vert] = (x, y) offsets from center
var _ring_verts: Array = []  # [ring_idx] = Array of Vector2i

# UV scrolling
var _uv_counter_x: int = 0
var _uv_counter_y: int = 0
var _uv_base_x: int = 0
var _uv_base_y: int = 0
var _half_wrap_x: int = 0
var _half_wrap_y: int = 0

# UV scroll speed (from drag fields)
var _uv_vel_x_start: int = 0
var _uv_vel_x_end: int = 0
var _uv_vel_y_start: int = 0
var _uv_vel_y_end: int = 0

# Ring generation params
var _radius_start: int = 0      # spread_start[0], <<12
var _radius_growth_start: int = 0  # inertia_min_start, <<4
var _radius_accel_start: int = 0   # accel_min_start[0], <<4
var _angle_start: int = 0       # rot_vel_start, <<4
var _angle_vel_start: int = 0   # radial_reserved_1
var _angle_jerk_start: int = 0  # spawn_interval_start

# End values for lerping
var _radius_end: int = 0
var _radius_growth_end: int = 0
var _radius_accel_end: int = 0
var _angle_end: int = 0
var _angle_vel_end: int = 0
var _angle_jerk_end: int = 0

# Center velocity params (from vel_spread fields)
var _cvel_dir_start: int = 0
var _cvel_mag_start: int = 0
var _cvel_dir_end: int = 0
var _cvel_mag_end: int = 0
var _caccel_dir_start: int = 0
var _caccel_mag_start: int = 0
var _caccel_dir_end: int = 0
var _caccel_mag_end: int = 0

# Color / brightness
var _brightness_row_idx: int = 0
var _brightness_table: Array = []

func _ready() -> void:
	_create_cb_mesh()
	_mesh_instance.top_level = true

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_active = false
	_uv_counter_x = 0
	_uv_counter_y = 0
	_center_vel_x = 0
	_center_vel_y = 0
	_center_accel_x = 0
	_center_accel_y = 0
	_brightness_table = []

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	_active = true
	_frame_counter = 0
	_uv_counter_x = 0
	_uv_counter_y = 0
	_center_vel_x = 0
	_center_vel_y = 0
	_center_accel_x = 0
	_center_accel_y = 0

	if emitter_config:
		var raw: Dictionary = emitter_config.raw_data

		# UV base from offset 0xB8/0xBA (homing_min_start / homing_max_start)
		_uv_base_x = int(raw.get("homing_min_start", 0))
		_uv_base_y = int(raw.get("homing_max_start", 0))

		# Half-wrap from param_A8/AA
		var param_a8: int = int(emitter_config.callback_params.get("param_A8", 0))
		var param_aa: int = int(emitter_config.callback_params.get("param_AA", 0))
		_half_wrap_x = (param_a8 + 1) >> 1 if param_a8 > 0 else 0
		_half_wrap_y = (param_aa + 1) >> 1 if param_aa > 0 else 0

		# Ring params — bag of bytes, offsets traced from C code
		# Radius base from spread fields (emitter+0x20/0x26)
		_radius_start = _ri(raw, "spread_start", 0)
		_radius_end = _ri(raw, "spread_end", 0)

		# Radius growth (emitter+0x5C/0x60 = inertia_min_end / weight_min_start)
		_radius_growth_start = int(emitter_config.inertia_min_end)
		_radius_growth_end = int(emitter_config.weight_min_start)

		# Radius acceleration (emitter+0x64/0x70 = accel_min_start[0] / accel_min_end[0])
		_radius_accel_start = _ri(raw, "accel_min_start", 0)
		_radius_accel_end = _ri(raw, "accel_min_end", 0)

		# Starting angle (emitter+0x44/0x48 = lifetime_min_start / lifetime_min_end in parser)
		_angle_start = int(emitter_config.lifetime_min_start)
		_angle_end = int(emitter_config.lifetime_min_end)

		# Angle velocity (emitter+0x9C/0xA2 = target_start[0] / target_end[0] in raw)
		_angle_vel_start = _ri(raw, "target_start", 0)
		_angle_vel_end = _ri(raw, "target_end", 0)

		# Angle jerk (emitter+0xB4/0xB6 = spawn_interval_start / spawn_interval_end)
		_angle_jerk_start = emitter_config.spawn_interval_start
		_angle_jerk_end = emitter_config.spawn_interval_end

		# Center velocity (emitter+0x2C/0x2E = angle_start[0]/[1] in parser naming)
		_cvel_dir_start = _ri(raw, "angle_start", 0)
		_cvel_mag_start = _ri(raw, "angle_start", 1)
		_cvel_dir_end = _ri(raw, "angle_end", 0)
		_cvel_mag_end = _ri(raw, "angle_end", 1)

		# Center acceleration (emitter+0x38/0x3A = vel_spread_start[0]/[1] in parser naming)
		_caccel_dir_start = _ri(raw, "vel_spread_start", 0)
		_caccel_mag_start = _ri(raw, "vel_spread_start", 1)
		_caccel_dir_end = _ri(raw, "vel_spread_end", 0)
		_caccel_mag_end = _ri(raw, "vel_spread_end", 1)

		# UV scroll speed from drag fields (0x7C/0x80)
		_uv_vel_x_start = _ri(raw, "drag_min_start", 0)
		_uv_vel_x_end = _ri(raw, "drag_min_end", 0)
		_uv_vel_y_start = _ri(raw, "drag_min_start", 1)
		_uv_vel_y_end = _ri(raw, "drag_min_end", 1)

		# Brightness row
		_brightness_row_idx = int(emitter_config.callback_params.get("param_4E", 0))

	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			_brightness_table = cb_data.get("brightness_table", [])

		if effect_data.texture and _material:
			_material.set_shader_parameter("effect_texture", effect_data.texture)
			_material.set_shader_parameter("use_texture", true)

	state = State.ANIMATE

func physics_step() -> void:
	if not _active:
		return
	if _frame_counter < FRAME_MAX:
		_frame_counter += 1

	# UV scrolling
	var drag_t: float = _sample_curve("drag")
	var uv_vel_x: int = int(lerpf(float(_uv_vel_x_start), float(_uv_vel_x_end), drag_t)) * 0x10
	var uv_vel_y: int = int(lerpf(float(_uv_vel_y_start), float(_uv_vel_y_end), drag_t)) * 0x10

	_uv_counter_x = _wrap_counter(_uv_counter_x + uv_vel_x, _half_wrap_x)
	_uv_counter_y = _wrap_counter(_uv_counter_y + uv_vel_y, _half_wrap_y)

func update_render() -> void:
	if _array_mesh == null:
		return
	_array_mesh.clear_surfaces()
	if not _active or state != State.ANIMATE:
		return
	if emitter_config == null or effect_data == null:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_right: Vector3 = camera.global_basis.x
	var cam_up: Vector3 = camera.global_basis.y
	var cam_fwd: Vector3 = -camera.global_basis.z

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y
	var psx_scale_x: float = camera.size * aspect / 256.0
	var psx_scale_y: float = camera.size / 240.0

	# Update UV rect on material
	if _material and effect_data.texture:
		var tex_size: Vector2 = effect_data.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			var u0: int = ((_uv_counter_x >> 12) + _uv_base_x) & 0xFF
			var v0: int = ((_uv_counter_y >> 12) + _uv_base_y) & 0xFF
			_material.set_shader_parameter("uv_rect", Vector4(
				float(u0) / tex_size.x, float(v0) / tex_size.y,
				float(_half_wrap_x) / tex_size.x, float(_half_wrap_y) / tex_size.y))

	# Color curves
	var curve_color: Color = _sample_colors()
	var r_val: float = curve_color.r
	var g_val: float = curve_color.g
	var b_val: float = curve_color.b

	var max_color: float = maxf(r_val, maxf(g_val, b_val))
	if max_color < 0.001 and _frame_counter > 1:
		return

	# Sample curve t values for ring params
	var spread_t: float = _sample_curve("velocity_dir_spread")
	var accel_t: float = _sample_curve("acceleration")
	var inertia_t: float = _sample_curve("inertia")
	var position_t: float = _sample_curve("position")

	# Compute ring vertices
	# PSX: radius << 12, growth << 4, accel << 4
	var radius: int = int(lerpf(float(_radius_start), float(_radius_end), spread_t)) << 12
	var growth: int = int(lerpf(float(_radius_growth_start), float(_radius_growth_end), inertia_t)) << 4
	var radius_accel: int = int(lerpf(float(_radius_accel_start), float(_radius_accel_end), accel_t)) << 4
	var angle: int = int(lerpf(float(_angle_start), float(_angle_end), accel_t)) << 4
	var angle_vel: int = int(lerpf(float(_angle_vel_start), float(_angle_vel_end), accel_t))
	var angle_jerk: int = int(lerpf(float(_angle_jerk_start), float(_angle_jerk_end), accel_t))

	# Generate 6 rings × 5 quarter-ring vertices
	_ring_verts.clear()
	for ring in RING_COUNT:
		var ring_radius: float = float(radius >> 12)
		var verts: Array = []
		# 4 computed vertices at 0x100 (=256 FFT angle units = 22.5 degrees) apart
		for v in 4:
			var a: float = float(v * 0x100 + angle) * ANGLE_SCALE
			var vx: float = cos(a) * ring_radius
			var vy: float = sin(a) * ring_radius
			verts.append(Vector2(vx, vy))
		# 5th vertex: mirror of 1st rotated 90 degrees: (x5 = -y0, y5 = x0)
		verts.append(Vector2(-verts[0].y, verts[0].x))
		_ring_verts.append(verts)

		# Advance ring params (PSX: radius += growth; growth += accel; etc.)
		radius += growth
		growth += radius_accel
		angle += angle_vel
		angle_vel += angle_jerk

	# Compute center position via interp_xyz
	var center_x_raw: int = int(lerpf(
		float(_ri(emitter_config.raw_data, "position_start", 0)),
		float(_ri(emitter_config.raw_data, "position_end", 0)),
		position_t))
	var center_y_raw: int = int(lerpf(
		float(_ri(emitter_config.raw_data, "position_start", 1)),
		float(_ri(emitter_config.raw_data, "position_end", 1)),
		position_t))

	# Center velocity (from vel_spread: direction + magnitude → cos/sin)
	var vel_dir_t: float = _sample_curve("velocity_base_angle")
	var vel_dir: int = int(lerpf(float(_cvel_dir_start), float(_cvel_dir_end), vel_dir_t)) << 4
	var vel_mag: int = int(lerpf(float(_cvel_mag_start), float(_cvel_mag_end), vel_dir_t))
	_center_vel_x = int(cos(float(vel_dir) * ANGLE_SCALE) * float(vel_mag) * 16.0) + _center_vel_x
	# Wait, looking at the C code more carefully:
	# _DAT_1f8000a4 = rcos(dir) * mag * 0x10 >> 0xc
	# _DAT_1f8000a8 = rsin(dir) * mag * 0x10 >> 0xc
	# These are computed ONCE, not accumulated. Then center += vel >> 12 each frame.
	# And vel += accel each frame.
	# But this is in update_render which runs each frame... I need to restructure.
	# Actually the PSX does this in the render function too. Let me re-read.

	# PSX code computes vel/accel once per frame in the render loop:
	# _DAT_1f8000a4 = rcos(_DAT_1f80005c) * mag * 0x10 >> 0xc
	# Then: center_x += _DAT_1f8000a4 >> 0xc; _DAT_1f8000a4 += _DAT_1f8000b4
	# So vel is in fixed-point, added to center after >>12.

	# Compute center velocity
	var cvel_dir_rad: float = float(vel_dir) * ANGLE_SCALE
	_center_vel_x = int(cos(cvel_dir_rad) * float(vel_mag) * 16.0)
	_center_vel_y = int(sin(cvel_dir_rad) * float(vel_mag) * 16.0)

	# Compute center acceleration
	var accel_dir_t: float = _sample_curve("drag")
	var accel_dir: int = int(lerpf(float(_caccel_dir_start), float(_caccel_dir_end), accel_dir_t)) << 4
	var accel_mag: int = int(lerpf(float(_caccel_mag_start), float(_caccel_mag_end), accel_dir_t))
	var caccel_dir_rad: float = float(accel_dir) * ANGLE_SCALE
	_center_accel_x = int(cos(caccel_dir_rad) * float(accel_mag) * 16.0)
	_center_accel_y = int(sin(caccel_dir_rad) * float(accel_mag) * 16.0)

	# Brightness table row
	var brightness_row: Array = []
	if _brightness_row_idx >= 0 and _brightness_row_idx < _brightness_table.size():
		brightness_row = _brightness_table[_brightness_row_idx]

	# Build mesh — push far behind map for correct depth ordering (orthographic, distance doesn't affect scale)
	var base_pos: Vector3 = camera.global_position + cam_fwd * 200.0
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	# Current center starts from interpolated position
	var cx: float = float(center_x_raw)
	var cy: float = float(center_y_raw)

	# Phase 1: All 5 bands between 6 rings
	# PSX dual-write pattern: inner vertices get brightness[band], outer get brightness[band+1]
	for band in 5:
		var r0: Array = _ring_verts[band]
		var r1: Array = _ring_verts[band + 1]

		# Inner/outer brightness from adjacent table entries (Gouraud gradient)
		var bright_inner: float = 1.0
		var bright_outer: float = 1.0
		if band < brightness_row.size():
			bright_inner = float(brightness_row[band]) / BRIGHTNESS_SCALE
		if band + 1 < brightness_row.size():
			bright_outer = float(brightness_row[band + 1]) / BRIGHTNESS_SCALE
		var col_inner := Color(r_val * bright_inner, g_val * bright_inner, b_val * bright_inner, 1.0)
		var col_outer := Color(r_val * bright_outer, g_val * bright_outer, b_val * bright_outer, 1.0)

		# 4 quads per band (connecting adjacent vertices in the quarter)
		for vi in QUADS_PER_BAND:
			var v0: Vector2 = r0[vi]
			var v1: Vector2 = r0[vi + 1]
			var v2: Vector2 = r1[vi]
			var v3: Vector2 = r1[vi + 1]

			# Emit 4 quadrant copies
			for q in QUADRANTS:
				var qv0: Vector2 = _rotate_quadrant(v0, q)
				var qv1: Vector2 = _rotate_quadrant(v1, q)
				var qv2: Vector2 = _rotate_quadrant(v2, q)
				var qv3: Vector2 = _rotate_quadrant(v3, q)

				# PSX screen coords: center + ring offset (VRAM +0x80 offset ignored per rules)
				var sx0: float = cx + qv0.x
				var sy0: float = cy + qv0.y
				var sx1: float = cx + qv1.x
				var sy1: float = cy + qv1.y
				var sx2: float = cx + qv2.x
				var sy2: float = cy + qv2.y
				var sx3: float = cx + qv3.x
				var sy3: float = cy + qv3.y

				# Map to camera plane (centered at PSX screen center 128, 120)
				var p0: Vector3 = base_pos + cam_right * (sx0 - 128.0) * psx_scale_x + cam_up * (-(sy0 - 120.0)) * psx_scale_y
				var p1: Vector3 = base_pos + cam_right * (sx1 - 128.0) * psx_scale_x + cam_up * (-(sy1 - 120.0)) * psx_scale_y
				var p2: Vector3 = base_pos + cam_right * (sx2 - 128.0) * psx_scale_x + cam_up * (-(sy2 - 120.0)) * psx_scale_y
				var p3: Vector3 = base_pos + cam_right * (sx3 - 128.0) * psx_scale_x + cam_up * (-(sy3 - 120.0)) * psx_scale_y

				_quad(positions, colors, uvs, custom0, p0, p1, p2, p3, col_inner, col_outer)

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func _rotate_quadrant(v: Vector2, quadrant: int) -> Vector2:
	"""Apply 90-degree rotational symmetry for the 4 quadrants."""
	match quadrant:
		0: return Vector2(v.x, v.y)       # Q0: (+cos, +sin)
		1: return Vector2(-v.y, v.x)      # Q1: (-sin, +cos)
		2: return Vector2(-v.x, -v.y)     # Q2: (-cos, -sin)
		3: return Vector2(v.y, -v.x)      # Q3: (+sin, -cos)
	return v

