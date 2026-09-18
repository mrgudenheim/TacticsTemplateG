extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB17 - Spiral/helix mesh callback (PSX FUN_801c2c74).
## Renders a procedural spiral strip of textured quads with 4-fold rotational symmetry.
##
## Analysis Checklist:
## 1. Quad count: 80 quads (20 per quadrant, 4 quadrants). Section 2: 16/quadrant, Section 3: 4/quadrant.
## 2. Topology: Spiral ribbon — 6 rings of 5 vertices, connected as a continuous strip.
##    Position advances along a velocity vector between ring groups. 4-fold rotational symmetry.
## 3. Orientation: 2D screen-space on PSX. Godot: flat in XZ plane at interpolated position.
## 4. Blend mode: Additive (emitter+0x4C & 3 = 1 for E065 emitters). effect_callback_additive shader.
## 5. Emitter offsets: see field access comments below.
## 6. Fixed-point: radius << 0xc (4096-scale), velocity/accel << 4 (16-scale), colors >> 0xc.
## 7. Color: brightness table at DAT_801c5974, 6 int32s/row, indexed by emitter+0x4E (callback_params).
##    Optional color curve modulation when flags_lo bit 6 set.
## 8. Brightness: extracted to callback_data.json, 6 values per row.
## 9. Init: state 1 → read params, store UV bases, set state to 2.
## 10. Animation: physics_step increments frame counter, update_render rebuilds geometry.
## 11. Cleanup: two-phase (flag then deallocate).
## 12. callback_data.json: brightness table rows.
## Vault: [[Effect Callback Mesh]]
## Vault: [[PSX GPU Primitives]]
## Vault: [[Particle Emitter Format]]

const RINGS: int = 6
const VERTS_PER_RING: int = 5  # 4 from cos/sin + 1 derived (90deg rotation of first)
const QUADRANTS: int = 4

var _cleanup_pending: bool = false

# Ring generation params (raw PSX values, read at render time via curves)
var _radius_start: int = 0       # emitter+0x20 = raw_data["spread_start"][0]
var _radius_end: int = 0         # emitter+0x26 = raw_data["spread_end"][0]
var _vel_raw_start: int = 0      # emitter+0x5C = raw_data["radial_min_start"]
var _vel_raw_end: int = 0        # emitter+0x60 = raw_data["radial_min_end"]
var _accel_raw_start: int = 0    # emitter+0x64 = raw_data["accel_min_start"][0]
var _accel_raw_end: int = 0      # emitter+0x70 = raw_data["accel_min_end"][0]
var _rot_angle_start: int = 0    # emitter+0x44 = inertia_min_start (bag of bytes)
var _rot_angle_end: int = 0      # emitter+0x48 = inertia_min_end
var _rot_accel_start: int = 0    # emitter+0x9C = raw_data["target_start"][0]
var _rot_accel_end: int = 0      # emitter+0xA2 = raw_data["target_end"][0]
var _timing_start: int = 0       # emitter+0xB4 = spawn_interval_start
var _timing_end: int = 0         # emitter+0xB6 = spawn_interval_end

# Velocity direction (for center position advancement)
var _dir_angle_start: int = 0    # emitter+0x2C = raw_data["angle_start"][0]
var _dir_angle_end: int = 0      # emitter+0x32 = raw_data["angle_end"][0]
var _dir_mag_start: int = 0      # emitter+0x2E = raw_data["angle_start"][1]
var _dir_mag_end: int = 0        # emitter+0x34 = raw_data["angle_end"][1]

# Acceleration direction
var _adir_angle_start: int = 0   # emitter+0x38 = raw_data["vel_spread_start"][0]
var _adir_angle_end: int = 0     # emitter+0x3E = raw_data["vel_spread_end"][0]
var _adir_mag_start: int = 0     # emitter+0x3A = raw_data["vel_spread_start"][1]
var _adir_mag_end: int = 0       # emitter+0x40 = raw_data["vel_spread_end"][1]

# UV scrolling
var _uv_counter_x: int = 0
var _uv_counter_y: int = 0
var _uv_base_x: int = 0         # emitter+0xB8 = raw_data["homing_min_start"]
var _uv_base_y: int = 0         # emitter+0xBA = raw_data["homing_max_start"]
var _half_wrap_x: int = 0       # (param_A8 + 1) >> 1
var _half_wrap_y: int = 0       # (param_AA + 1) >> 1
var _uv_vel_x_start: int = 0    # emitter+0x7C = raw_data["drag_min_start"][0]
var _uv_vel_x_end: int = 0      # emitter+0x88 = raw_data["drag_min_end"][0]
var _uv_vel_y_start: int = 0    # emitter+0x80 = raw_data["drag_min_start"][1]
var _uv_vel_y_end: int = 0      # emitter+0x8C = raw_data["drag_min_end"][1]

# Color
var _brightness_row_idx: int = 0 # emitter+0x4E = callback_params["param_4E"]
var _depth_raw: int = 0          # emitter+0x54 = weight_min_start (bag of bytes)

# Parsed data
var _brightness_table: Array = []

func _ready() -> void:
	_create_cb_mesh(true)
	_mesh_instance.top_level = true  # Render in global space, ignore parent transform

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_active = false
	_cleanup_pending = false
	_uv_counter_x = 0
	_uv_counter_y = 0
	_brightness_table = []

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	"""INIT -> ANIMATE: read emitter params and start."""
	_active = true
	_frame_counter = 0
	_uv_counter_x = 0
	_uv_counter_y = 0
	_cleanup_pending = false

	if emitter_config:
		var raw: Dictionary = emitter_config.raw_data

		# Radius (emitter+0x20/0x26 = spread_start_x/spread_end_x)
		_radius_start = _ri(raw, "spread_start", 0)
		_radius_end = _ri(raw, "spread_end", 0)

		# Velocity for radius growth (emitter+0x5C/0x60 = radial_min_start/end)
		_vel_raw_start = int(raw.get("radial_min_start", 0))
		_vel_raw_end = int(raw.get("radial_min_end", 0))

		# Acceleration for radius (emitter+0x64/0x70 = accel_min_start_x/accel_min_end_x)
		_accel_raw_start = _ri(raw, "accel_min_start", 0)
		_accel_raw_end = _ri(raw, "accel_min_end", 0)

		# Rotation angle (emitter+0x44/0x48 = inertia_min_start/end, bag of bytes)
		_rot_angle_start = int(emitter_config.inertia_min_start)
		_rot_angle_end = int(emitter_config.inertia_min_end)

		# Rotation acceleration (emitter+0x9C/0xA2 = target_start[0]/target_end[0])
		_rot_accel_start = _ri(raw, "target_start", 0)
		_rot_accel_end = _ri(raw, "target_end", 0)

		# Timing (emitter+0xB4/0xB6 = spawn_interval_start/end)
		_timing_start = emitter_config.spawn_interval_start
		_timing_end = emitter_config.spawn_interval_end

		# Velocity direction (emitter+0x2C..0x34 = angle_start/end)
		_dir_angle_start = _ri(raw, "angle_start", 0)
		_dir_angle_end = _ri(raw, "angle_end", 0)
		_dir_mag_start = _ri(raw, "angle_start", 1)
		_dir_mag_end = _ri(raw, "angle_end", 1)

		# Acceleration direction (emitter+0x38..0x42 = vel_spread_start/end)
		_adir_angle_start = _ri(raw, "vel_spread_start", 0)
		_adir_angle_end = _ri(raw, "vel_spread_end", 0)
		_adir_mag_start = _ri(raw, "vel_spread_start", 1)
		_adir_mag_end = _ri(raw, "vel_spread_end", 1)

		# UV parameters
		_uv_base_x = int(raw.get("homing_min_start", 0))  # emitter+0xB8
		_uv_base_y = int(raw.get("homing_max_start", 0))  # emitter+0xBA
		var param_a8: int = int(emitter_config.callback_params.get("param_A8", 4096))
		var param_aa: int = int(emitter_config.callback_params.get("param_AA", 4096))
		# PSX: (u16 << 16 >> 16 - u16 << 16 >> 31) >> 1 = (value + (value < 0 ? 1 : 0)) / 2
		_half_wrap_x = (param_a8 + 1) >> 1 if param_a8 > 0 else 0
		_half_wrap_y = (param_aa + 1) >> 1 if param_aa > 0 else 0

		# UV velocity (emitter+0x7C..0x8C = drag_min_start/end)
		_uv_vel_x_start = _ri(raw, "drag_min_start", 0)
		_uv_vel_x_end = _ri(raw, "drag_min_end", 0)
		_uv_vel_y_start = _ri(raw, "drag_min_start", 1)
		_uv_vel_y_end = _ri(raw, "drag_min_end", 1)

		# Color params
		_brightness_row_idx = int(emitter_config.callback_params.get("param_4E", 0))
		_depth_raw = int(emitter_config.weight_min_start)  # emitter+0x54 (bag of bytes)

	# Load brightness table from callback_data.json
	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			_brightness_table = cb_data.get("brightness_table", [])

		# Enable texture. The PSX uses CLUT 0x7B00 (indexed palette) with scrolling
		# UV window. For now, use the full texture — the shader's STP filter passes
		# through semi-transparent non-black pixels, creating the textured pattern.
		# TODO: implement proper CLUT palette mapping for correct scrolling UV
		if effect_data.texture and _material:
			_material.set_shader_parameter("effect_texture", effect_data.texture)
			_material.set_shader_parameter("use_texture", true)

	state = State.ANIMATE

func _on_animate(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	"""Called each timeline invocation frame."""
	pass

func physics_step() -> void:
	"""Update frame counter and UV scrolling."""
	if not _active:
		return

	# Cap frame counter at curve length - 1 to prevent curve wrapping.
	# Callbacks stay alive until externally cleaned up, but the visual
	# should not replay when curves wrap at 160 samples.
	if _frame_counter < FRAME_MAX:
		_frame_counter += 1

	# Sample UV velocity curves (curves["drag"] for the UV curve)
	var uv_curve_t: float = _sample_curve("drag")
	var uv_vel_x: int = int(lerpf(float(_uv_vel_x_start), float(_uv_vel_x_end), uv_curve_t))
	var uv_vel_y: int = int(lerpf(float(_uv_vel_y_start), float(_uv_vel_y_end), uv_curve_t))

	# Update UV counters with wrapping (PSX: value * 16 + counter, wrap at half_wrap * UV_WRAP_SCALE)
	_uv_counter_x = _wrap_counter(_uv_counter_x + uv_vel_x * 16, _half_wrap_x)
	_uv_counter_y = _wrap_counter(_uv_counter_y + uv_vel_y * 16, _half_wrap_y)

func update_render() -> void:
	"""Rebuild spiral mesh geometry."""
	if _array_mesh == null:
		return

	_array_mesh.clear_surfaces()

	if not _active or state != State.ANIMATE:
		return
	if emitter_config == null or effect_data == null:
		return

	# --- Camera-pinned screen-space rendering ---
	# CB17 is pure 2D on PSX — renders directly to framebuffer in screen pixels.
	# In Godot: pin to camera center, use pixel_scale (not PSX_SCALE) for sizing.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_right: Vector3 = camera.global_basis.x
	var cam_up: Vector3 = camera.global_basis.y
	var cam_fwd: Vector3 = -camera.global_basis.z

	# Convert PSX screen pixels (256×240) to Godot view units.
	# Need separate X/Y scales because PSX pixels aren't square on a 4:3 CRT.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y
	var psx_scale_x: float = camera.size * aspect / 256.0
	var psx_scale_y: float = camera.size / 240.0

	# --- Update scrolling UV rect on material ---
	if _material and effect_data.texture:
		var tex_size: Vector2 = effect_data.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			var u0: int = ((_uv_counter_x >> 12) + _uv_base_x) & 0xFF
			var v0: int = ((_uv_counter_y >> 12) + _uv_base_y) & 0xFF
			_material.set_shader_parameter("uv_rect", Vector4(
				float(u0) / tex_size.x,
				float(v0) / tex_size.y,
				float(_half_wrap_x) / tex_size.x,
				float(_half_wrap_y) / tex_size.y))

	# --- Sample curves for all parameters ---
	var radius_t: float = _sample_curve("spread")
	var vel_t: float = _sample_curve("radial_velocity")
	var accel_t: float = _sample_curve("acceleration")
	var rot_t: float = _sample_curve("inertia")
	var rot_accel_t: float = _sample_curve("target_offset")
	var pos_t: float = _sample_curve("position")
	var dir_t: float = _sample_curve("velocity_base_angle")
	var adir_t: float = _sample_curve("velocity_dir_spread")

	# --- Compute ring parameters ---
	# Radius: lerp(spread_start_x, spread_end_x, curve) << 0xc
	var radius_raw: float = lerpf(float(_radius_start), float(_radius_end), radius_t) * 4096.0
	# Velocity: lerp(radial_min_start, radial_min_end, curve) << 4
	var radius_vel: float = lerpf(float(_vel_raw_start), float(_vel_raw_end), vel_t) * 16.0
	# Acceleration: lerp(accel_min_start_x, accel_min_end_x, curve) << 4
	var radius_accel: float = lerpf(float(_accel_raw_start), float(_accel_raw_end), accel_t) * 16.0
	# Rotation angle: lerp(inertia_min_start, inertia_min_end, curve) << 4
	var rot_angle: float = lerpf(float(_rot_angle_start), float(_rot_angle_end), rot_t) * 16.0
	# Rotation velocity: lerp(target_start[0], target_end[0], curve) — no shift
	var rot_vel: float = lerpf(float(_rot_accel_start), float(_rot_accel_end), rot_accel_t)
	# Rotation acceleration per ring: lerp(spawn_interval_start, spawn_interval_end, curve)
	var rot_accel_per_ring: float = lerpf(float(_timing_start), float(_timing_end),
		_sample_curve("spawn_interval"))

	# --- Generate ring vertices ---
	# 6 rings × 5 vertices each. Each vertex = Vector2 offset from center.
	var ring_verts: Array = []  # Array of Array[Vector2]
	for _ring_idx in RINGS:
		var ring_radius: float = radius_raw / BRIGHTNESS_SCALE  # >> 0xc to get actual PSX units
		var verts: Array = []
		for v in 4:
			var angle_fft: int = v * 0x100 + int(rot_angle / 16.0)
			var a: float = float(angle_fft) * ANGLE_SCALE
			var cx: float = cos(a) * ring_radius
			var sy: float = sin(a) * ring_radius
			# PSX: cos * radius >> 0xc, but radius was already >> 0xc above
			verts.append(Vector2(cx, sy))
		# 5th vertex: 90deg rotation of first vertex (-y, x)
		verts.append(Vector2(-verts[0].y, verts[0].x))
		ring_verts.append(verts)
		# Double integration for next ring
		radius_raw += radius_vel
		radius_vel += radius_accel
		rot_angle += rot_vel
		rot_vel += rot_accel_per_ring

	# --- Compute center position (PSX screen coords → camera-pinned) ---
	# CB17 uses absolute PSX screen coordinates:
	#   screen_x = center_x + 128 (X centered at pixel 128)
	#   screen_y = center_y       (Y=0 is top, Y=120 is center)
	# Map to Godot camera-relative offset from screen center.
	var raw: Dictionary = emitter_config.raw_data
	var pos_sx: float = lerpf(float(_ri(raw, "position_start", 0)),
		float(_ri(raw, "position_end", 0)), pos_t)
	var pos_sy: float = lerpf(float(_ri(raw, "position_start", 1)),
		float(_ri(raw, "position_end", 1)), pos_t)
	# The +0x80 in PSX code is DRAWENV X offset (VRAM), not screen centering.
	# DISPENV cancels it, so effective screen_x = center_x. Screen center = 128.
	# Y: absolute from top (0=top, 120=center).
	var center_offset: Vector3 = (cam_right * (pos_sx - 128.0) * psx_scale_x
		+ cam_up * (-(pos_sy - 120.0)) * psx_scale_y)

	# --- Compute velocity direction ---
	var dir_angle_raw: float = lerpf(float(_dir_angle_start), float(_dir_angle_end), dir_t) * 16.0
	var dir_mag_raw: float = lerpf(float(_dir_mag_start), float(_dir_mag_end), dir_t)
	var dir_a: float = dir_angle_raw / 16.0 * ANGLE_SCALE
	var velocity_x: float = cos(dir_a) * dir_mag_raw * 16.0 / BRIGHTNESS_SCALE
	var velocity_y: float = sin(dir_a) * dir_mag_raw * 16.0 / BRIGHTNESS_SCALE

	# --- Compute acceleration direction ---
	var adir_angle_raw: float = lerpf(float(_adir_angle_start), float(_adir_angle_end), adir_t) * 16.0
	var adir_mag_raw: float = lerpf(float(_adir_mag_start), float(_adir_mag_end), adir_t)
	var adir_a: float = adir_angle_raw / 16.0 * ANGLE_SCALE
	var accel_x: float = cos(adir_a) * adir_mag_raw * 16.0 / BRIGHTNESS_SCALE
	var accel_y: float = sin(adir_a) * adir_mag_raw * 16.0 / BRIGHTNESS_SCALE

	# --- Get brightness row ---
	var brightness_row: Array = []
	if _brightness_row_idx >= 0 and _brightness_row_idx < _brightness_table.size():
		brightness_row = _brightness_table[_brightness_row_idx]

	# --- Get color curves ---
	# Check for valid curve indices directly rather than color_curve_enabled flag
	# (parsed flag may be incorrect). Default without curves = 0x80 (0.5).
	var curve_color: Color = _sample_colors()
	var r_val: float = curve_color.r
	var g_val: float = curve_color.g
	var b_val: float = curve_color.b

	# Skip rendering when color curves are at zero (invisible with additive blend).
	# Stay in ANIMATE state — callbacks are cleaned up externally by the effect system.
	var max_color: float = maxf(r_val, maxf(g_val, b_val))
	if max_color < 0.001 and _frame_counter > 1:
		return

	# --- Pre-compute per-ring center positions ---
	# Each ring has its own center position (PSX advances between rings).
	# Quads must span from ring N at pos_N to ring N+1 at pos_{N+1} so
	# adjacent bands share vertices at their boundary.
	var ring_positions: Array[Vector3] = []
	var pos: Vector3 = camera.global_position + cam_fwd * 15.0 + center_offset
	var vel_x: float = velocity_x
	var vel_y: float = velocity_y
	for _i in RINGS:
		ring_positions.append(pos)
		pos += cam_right * vel_x * psx_scale_x + cam_up * (-vel_y) * psx_scale_y
		vel_x += accel_x
		vel_y += accel_y

	# --- Build mesh ---
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	for ring_group in range(RINGS - 1):
		var ring_a: Array = ring_verts[ring_group]
		var ring_b: Array = ring_verts[ring_group + 1]
		var pos_inner: Vector3 = ring_positions[ring_group]
		var pos_outer: Vector3 = ring_positions[ring_group + 1]

		var bright_inner: float = 0.0
		if ring_group < brightness_row.size():
			bright_inner = float(brightness_row[ring_group]) / BRIGHTNESS_SCALE
		var bright_outer: float = 0.0
		if ring_group + 1 < brightness_row.size():
			bright_outer = float(brightness_row[ring_group + 1]) / BRIGHTNESS_SCALE

		var col_inner := Color(r_val * bright_inner, g_val * bright_inner, b_val * bright_inner, 1.0)
		var col_outer := Color(r_val * bright_outer, g_val * bright_outer, b_val * bright_outer, 1.0)

		for v_idx in range(VERTS_PER_RING - 1):
			for q in QUADRANTS:
				var a0: Vector2 = _rotate_quadrant(ring_a[v_idx], q)
				var a1: Vector2 = _rotate_quadrant(ring_a[v_idx + 1], q)
				var b0: Vector2 = _rotate_quadrant(ring_b[v_idx], q)
				var b1: Vector2 = _rotate_quadrant(ring_b[v_idx + 1], q)

				var v00: Vector3 = pos_inner + _to_cam_plane(a0, cam_right, cam_up, psx_scale_x, psx_scale_y)
				var v01: Vector3 = pos_inner + _to_cam_plane(a1, cam_right, cam_up, psx_scale_x, psx_scale_y)
				var v10: Vector3 = pos_outer + _to_cam_plane(b0, cam_right, cam_up, psx_scale_x, psx_scale_y)
				var v11: Vector3 = pos_outer + _to_cam_plane(b1, cam_right, cam_up, psx_scale_x, psx_scale_y)

				_quad(positions, colors, uvs, custom0,
					v00, v01, v10, v11, col_inner, col_outer)

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func _to_cam_plane(offset: Vector2, cam_right: Vector3, cam_up: Vector3,
					sx: float, sy: float) -> Vector3:
	"""Convert 2D PSX screen-pixel offset to 3D camera-facing offset."""
	# PSX screen X → camera right, PSX screen Y (down) → camera -up
	return cam_right * offset.x * sx + cam_up * (-offset.y) * sy

func _offset_to_uv(offset: Vector2) -> Vector2:
	"""Compute tiling UV from screen-pixel offset. Tiles at half_wrap intervals
	so adjacent faces sharing a vertex get the same UV — no seams."""
	var wrap_x: float = maxf(float(_half_wrap_x), 1.0)
	var wrap_y: float = maxf(float(_half_wrap_y), 1.0)
	return Vector2(
		fmod(fmod(offset.x, wrap_x) + wrap_x, wrap_x) / wrap_x,
		fmod(fmod(offset.y, wrap_y) + wrap_y, wrap_y) / wrap_y
	)

func _rotate_quadrant(v: Vector2, quadrant: int) -> Vector2:
	"""Apply 4-fold rotational symmetry: 0°, 90°, 180°, 270°."""
	match quadrant:
		0: return v                          # (x, y)
		1: return Vector2(-v.y, v.x)         # (-y, x)
		2: return Vector2(-v.x, -v.y)        # (-x, -y)
		3: return Vector2(v.y, -v.x)         # (y, -x)
	return v

func cleanup() -> void:
	_frame_counter = 0
	_active = false
	_cleanup_pending = false
	_uv_counter_x = 0
	_uv_counter_y = 0
	_brightness_table = []
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
