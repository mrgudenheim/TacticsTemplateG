extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB11 - Warped grid mesh callback (PSX FUN_801c3c7c, offset 0x177C).
## Screen-space 2D overlay: 9x9 vertex grid (8x8 = 64 quads) with two
## independent sinusoidal deformations (Y-wave and X-wave). Creates an
## undulating mesh that fills the screen with a brightness gradient
## (bright at edges, dark in center) to frame the map.
##
## Y-wave: offsets each vertex's Y position via sin(h) * cos(v) * radius
## X-wave: offsets each vertex's X position (transposed grid strides)
## Both waves accumulate angle each frame from spread/vel_spread fields.
##
## CRITICAL: X grid uses transposed strides relative to Y grid.
## See memory note: callback-scratchpad-transposition.md
## Vault: [[Effect Callback Mesh]]
## Vault: [[Embedded MIPS Effect Code]]

const GRID_SIZE: int = 9    # 9x9 vertices
const QUAD_COUNT: int = 8   # 8x8 quads
const ROW_STEP: float = 48.0  # PSX pixels between grid rows

# Wave angle accumulators (updated each physics frame)
var _y_wave_h: int = 0   # piVar27[0x681]
var _y_wave_v: int = 0   # piVar27[0x685]
var _x_wave_h: int = 0   # piVar27[0x689]
var _x_wave_v: int = 0   # piVar27[0x68d]

# UV scrolling accumulators
var _uv_counter_x: int = 0  # piVar27[0x691]
var _uv_counter_y: int = 0  # piVar27[0x692]
var _uv_base_x: int = 0     # from emitter+0x14 (position_start[0])
var _uv_base_y: int = 0     # from emitter+0x16 (position_start[1])
var _half_wrap_x: int = 0   # from param_A8
var _half_wrap_y: int = 0   # from param_AA

# Brightness
var _brightness_row_idx: int = 0
var _brightness_table: Array = []

func _ready() -> void:
	_create_cb_mesh()
	_mesh_instance.top_level = true

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_active = false

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	_active = true
	_frame_counter = 0
	_y_wave_h = 0
	_y_wave_v = 0
	_x_wave_h = 0
	_x_wave_v = 0
	_uv_counter_x = 0
	_uv_counter_y = 0
	_brightness_table = []

	if emitter_config:
		var raw: Dictionary = emitter_config.raw_data

		# UV base from emitter+0x14/0x16 (position_start in parser)
		_uv_base_x = _ri(raw, "position_start", 0)
		_uv_base_y = _ri(raw, "position_start", 1)

		# Half-wrap from param_A8/AA
		var a8: int = int(emitter_config.callback_params.get("param_A8", 0))
		var aa: int = int(emitter_config.callback_params.get("param_AA", 0))
		_half_wrap_x = (a8 + 1) >> 1 if a8 > 0 else 0
		_half_wrap_y = (aa + 1) >> 1 if aa > 0 else 0

		# Brightness row from param_4E
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
	if emitter_config == null or effect_data == null:
		return

	var raw: Dictionary = emitter_config.raw_data

	# --- Y-wave accumulator update (PSX func_0x801a8c8c, line 1049-1051) ---
	# Uses spread fields: lerp(spread_start, spread_end, curve_t)
	# Curve index from emitter+0x08 nibbles (position curve bits 4-7)
	var y_incr_t: float = _curve_t_nibble(0, 4)  # (emitter+0x08 >> 4) & 0xF
	_y_wave_h += int(lerpf(float(_ri(raw, "spread_start", 0)), float(_ri(raw, "spread_end", 0)), y_incr_t))
	_y_wave_v += int(lerpf(float(_ri(raw, "spread_start", 1)), float(_ri(raw, "spread_end", 1)), y_incr_t))

	# --- X-wave accumulator update (PSX lines 1059-1062) ---
	# Uses vel_spread fields: lerp(vel_spread_start, vel_spread_end, curve_t)
	# Curve index from emitter+0x08 nibbles (bits 12-15 of second word)
	var x_incr_t: float = _curve_t_nibble(1, 4)  # (emitter+0x0C >> 12) & 0xF? Actually (emitter+8 >> 0xc & 0xf)
	_x_wave_h += int(lerpf(float(_ri(raw, "vel_spread_start", 0)), float(_ri(raw, "vel_spread_end", 0)), x_incr_t))
	_x_wave_v += int(lerpf(float(_ri(raw, "vel_spread_start", 1)), float(_ri(raw, "vel_spread_end", 1)), x_incr_t))

	# --- UV scroll (PSX lines 924-960) ---
	# Magnitude: lerp(emitter+0x5C, emitter+0x60) = inertia_min_end → weight_min_start
	# Direction: lerp(emitter+0x2E, emitter+0x34) = angle_start[1] → angle_end[1]
	var uv_mag_t: float = _curve_t_nibble(0, 0)  # (emitter+8 >> 0x1c) → top nibble
	var uv_mag: int = int(lerpf(float(emitter_config.inertia_min_end), float(emitter_config.weight_min_start), uv_mag_t))

	var uv_dir_t: float = _curve_t_nibble(0, 2)  # (emitter+8 >> 8 & 0xf)
	var uv_dir: int = int(lerpf(float(_ri(raw, "angle_start", 1)), float(_ri(raw, "angle_end", 1)), uv_dir_t))
	var dir_rad: float = float(uv_dir) * ANGLE_SCALE

	# PSX: rcos(dir) * mag * 0x10 >> 0xc → cos cancels the 4096 scale
	_uv_counter_x += int(cos(dir_rad) * float(uv_mag) * 16.0)
	_uv_counter_y += int(sin(dir_rad) * float(uv_mag) * 16.0)

	# Wrap UV counters
	_uv_counter_x = _wrap_counter(_uv_counter_x, _half_wrap_x)
	_uv_counter_y = _wrap_counter(_uv_counter_y, _half_wrap_y)

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

	# UV rect
	if _material and effect_data.texture:
		var ts: Vector2 = effect_data.texture.get_size()
		if ts.x > 0 and ts.y > 0:
			var u0: int = ((_uv_counter_x >> 12) + _uv_base_x) & 0xFF
			var v0: int = ((_uv_counter_y >> 12) + _uv_base_y) & 0xFF
			_material.set_shader_parameter("uv_rect", Vector4(
				float(u0) / ts.x, float(v0) / ts.y,
				float(_half_wrap_x) / ts.x, float(_half_wrap_y) / ts.y))

	# Color curves (PSX lines 961-974)
	var curve_color: Color = _sample_colors()
	var r_val: float = curve_color.r
	var g_val: float = curve_color.g
	var b_val: float = curve_color.b

	if maxf(r_val, maxf(g_val, b_val)) < 0.001 and _frame_counter > 1:
		return

	var raw: Dictionary = emitter_config.raw_data

	# --- Y-wave grid (PSX lines 984-1012) ---
	# Y vertex values: sin(h) * cos(v) * radius + base_y
	# h_step = 0x20000 / lerp(accel_min_start[0], accel_min_end[0])
	# v_step = 0x20000 / lerp(accel_min_start[1], accel_min_end[1])
	# radius = lerp(accel_min_start[2], accel_min_end[2])
	# v_accel (row offset to h) = lerp(accel_max_start[0], accel_max_end[0]) -- offset 0x6C/0x78
	var grid_curve_t: float = _curve_t_nibble(0, 6)  # (emitter+0xC & 0xF)
	var y_h_step_val: int = int(lerpf(float(_ri(raw, "accel_min_start", 0)), float(_ri(raw, "accel_min_end", 0)), grid_curve_t))
	var y_h_step: int = 0x20000 / maxi(y_h_step_val, 1) if y_h_step_val != 0 else 0
	var y_v_step_val: int = int(lerpf(float(_ri(raw, "accel_max_start", 0)), float(_ri(raw, "accel_max_end", 0)), grid_curve_t))
	var y_v_step: int = 0x20000 / maxi(y_v_step_val, 1) if y_v_step_val != 0 else 0
	# radius from offset 0x68/0x74 = accel_min_start[1] / accel_min_end[1]
	var y_radius: float = lerpf(float(_ri(raw, "accel_min_start", 1)), float(_ri(raw, "accel_min_end", 1)), grid_curve_t)
	# row h_offset from offset 0x6C/0x78 = accel_min_start[2] / accel_min_end[2]
	var y_row_h_offset: float = lerpf(float(_ri(raw, "accel_min_start", 2)), float(_ri(raw, "accel_min_end", 2)), grid_curve_t)

	var grid_y: Array = []
	var y_h: int = _y_wave_h
	var y_v: int = _y_wave_v
	var base_y: float = -64.0
	for row in GRID_SIZE:
		var cos_v: float = cos(float(y_v) * ANGLE_SCALE)
		var offsets: Array[float] = []
		var h: int = y_h
		for col in GRID_SIZE:
			var sin_h: float = sin(float(h) * ANGLE_SCALE)
			offsets.append(sin_h * cos_v * y_radius + base_y)
			h += y_h_step
		grid_y.append(offsets)
		y_h += int(y_row_h_offset)
		y_v += y_v_step
		base_y += ROW_STEP

	# --- X-wave grid (PSX lines 1013-1041, TRANSPOSED strides) ---
	# Same formula but from drag fields, and strides are swapped
	var x_h_step_val: int = int(lerpf(float(_ri(raw, "drag_min_start", 0)), float(_ri(raw, "drag_min_end", 0)), grid_curve_t))
	var x_h_step: int = 0x20000 / maxi(x_h_step_val, 1) if x_h_step_val != 0 else 0
	var x_v_step_val: int = int(lerpf(float(_ri(raw, "drag_max_start", 0)), float(_ri(raw, "drag_max_end", 0)), grid_curve_t))
	var x_v_step: int = 0x20000 / maxi(x_v_step_val, 1) if x_v_step_val != 0 else 0
	var x_radius: float = lerpf(float(_ri(raw, "drag_min_start", 1)), float(_ri(raw, "drag_min_end", 1)), grid_curve_t)
	# row h_offset from offset 0x84/0x90 = drag_min_start[2] / drag_min_end[2]
	var x_row_h_offset: float = lerpf(float(_ri(raw, "drag_min_start", 2)), float(_ri(raw, "drag_min_end", 2)), grid_curve_t)

	var grid_x: Array = []
	var x_h: int = _x_wave_h
	var x_v: int = _x_wave_v
	var base_x: float = 56.0
	for row in GRID_SIZE:
		var cos_v_x: float = cos(float(x_v) * ANGLE_SCALE)
		var offsets: Array[float] = []
		var hx: int = x_h
		for col in GRID_SIZE:
			var sin_hx: float = sin(float(hx) * ANGLE_SCALE)
			offsets.append(sin_hx * cos_v_x * x_radius + base_x)
			hx += x_h_step
		grid_x.append(offsets)
		x_h += int(x_row_h_offset)
		x_v += x_v_step
		base_x += ROW_STEP

	# Brightness table row
	var bright_row: Array = []
	if _brightness_row_idx >= 0 and _brightness_row_idx < _brightness_table.size():
		bright_row = _brightness_table[_brightness_row_idx]

	# Build mesh — in front of map (CB11 overlays on top)
	var base_pos: Vector3 = camera.global_position + cam_fwd * 5.0
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	for qrow in QUAD_COUNT:
		for qcol in QUAD_COUNT:
			# X grid is TRANSPOSED: grid_x[col][row] not grid_x[row][col]
			var sx00: float = grid_x[qcol][qrow]
			var sy00: float = grid_y[qrow][qcol]
			var sx01: float = grid_x[qcol + 1][qrow]
			var sy01: float = grid_y[qrow][qcol + 1]
			var sx10: float = grid_x[qcol][qrow + 1]
			var sy10: float = grid_y[qrow + 1][qcol]
			var sx11: float = grid_x[qcol + 1][qrow + 1]
			var sy11: float = grid_y[qrow + 1][qcol + 1]

			# Screen-space → camera plane
			# PSX screen center = (256, 120) in primitive coords (DRAWENV.x=0, DISPENV.x=128)
			var v00: Vector3 = base_pos + cam_right * (sx00 - 256.0) * psx_scale_x + cam_up * (-(sy00 - 120.0)) * psx_scale_y
			var v01: Vector3 = base_pos + cam_right * (sx01 - 256.0) * psx_scale_x + cam_up * (-(sy01 - 120.0)) * psx_scale_y
			var v10: Vector3 = base_pos + cam_right * (sx10 - 256.0) * psx_scale_x + cam_up * (-(sy10 - 120.0)) * psx_scale_y
			var v11: Vector3 = base_pos + cam_right * (sx11 - 256.0) * psx_scale_x + cam_up * (-(sy11 - 120.0)) * psx_scale_y

			# Brightness: dual-write Gouraud (inner=row N, outer=row N+1)
			var b_inner: float = float(bright_row[qrow]) / BRIGHTNESS_SCALE if qrow < bright_row.size() else 1.0
			var b_outer: float = float(bright_row[qrow + 1]) / BRIGHTNESS_SCALE if qrow + 1 < bright_row.size() else 1.0
			var ci := Color(r_val * b_inner, g_val * b_inner, b_val * b_inner, 1.0)
			var co := Color(r_val * b_outer, g_val * b_outer, b_val * b_outer, 1.0)

			_quad(positions, colors, uvs, custom0, v00, v01, v10, v11, ci, co)

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)
