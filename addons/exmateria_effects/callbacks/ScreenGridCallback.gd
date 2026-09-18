extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB16 - Full-screen textured grid callback (PSX FUN_801c2500).
## Renders a 4×4 grid of quads covering the entire screen as a 2D overlay.
## Vertex positions are FIXED at init (never change). Only UV scrolling and
## per-quad Gouraud-shaded brightness update each frame.
##
## Analysis Checklist:
## 1. Quad count: 16 (4×4 grid). Alloc 0x6e4 bytes, double-buffered.
## 2. Topology: Flat screen-filling grid. Each quad = 64×64 PSX pixels.
## 3. Orientation: 2D screen overlay. Absolute PSX screen pixels. Fixed at init.
## 4. Blend mode: (emitter+0x4C & 3) << 5 | 0x86. Emitter 10: additive.
## 5. Emitter offsets: UV base from position_start (bag of bytes). Brightness from param_4E.
## 6. Fixed-point: UV counters >> 0xc, colors >> 0xc.
## 7. Color: Brightness table at DAT_801c58e8, 5 int32s/row, indexed by param_4E.
##    Gouraud: inner/outer vertex brightness from adjacent table entries.
## 8. Color curves: emitter 10 has r=4, g=4, b=4.
## 9. Init: set up 16 fixed-position quads, store UV bases.
## 10. Animation: UV scrolling + color updates only. No geometry changes.
## 11. Cleanup: two-phase (flag at +0x6e0).
## 12. callback_data.json: brightness table.
## Vault: [[Effect Callback Mesh]]

const GRID_COLS: int = 4
const GRID_ROWS: int = 4
const CELL_SIZE: float = 64.0  # PSX pixels per grid cell

# UV scrolling (same mechanism as CB17)
var _uv_counter_x: int = 0
var _uv_counter_y: int = 0
var _uv_base_x: int = 0         # emitter+0x14 = raw_data["position_start"][0] (bag of bytes)
var _uv_base_y: int = 0         # emitter+0x16 = raw_data["position_start"][1]
var _half_wrap_x: int = 0       # (param_A8 + 1) >> 1
var _half_wrap_y: int = 0       # (param_AA + 1) >> 1

# UV velocity fields
var _uv_vel_start: int = 0      # emitter+0x5C = raw_data["radial_min_start"]
var _uv_vel_end: int = 0        # emitter+0x60 = raw_data["radial_min_end"]
var _uv_dir_start: int = 0      # emitter+0x2E = raw_data["angle_start"][1] (direction angle)
var _uv_dir_end: int = 0        # emitter+0x34 = raw_data["angle_end"][1]

# Color
var _brightness_row_idx: int = 0 # emitter+0x4E = callback_params["param_4E"]

# Parsed data
var _brightness_table: Array = []

func _ready() -> void:
	_create_cb_mesh()
	_mesh_instance.top_level = true  # Render in global space, ignore parent transform

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_active = false
	_uv_counter_x = 0
	_uv_counter_y = 0
	_brightness_table = []

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	"""INIT -> ANIMATE: read emitter params."""
	_active = true
	_frame_counter = 0
	_uv_counter_x = 0
	_uv_counter_y = 0

	if emitter_config:
		var raw: Dictionary = emitter_config.raw_data

		# UV base from position_start (bag of bytes: emitter+0x14, +0x16)
		_uv_base_x = _ri(raw, "position_start", 0)
		_uv_base_y = _ri(raw, "position_start", 1)

		# Half-wrap from param_A8/AA
		var param_a8: int = int(emitter_config.callback_params.get("param_A8", 4096))
		var param_aa: int = int(emitter_config.callback_params.get("param_AA", 4096))
		_half_wrap_x = (param_a8 + 1) >> 1 if param_a8 > 0 else 0
		_half_wrap_y = (param_aa + 1) >> 1 if param_aa > 0 else 0

		# UV velocity (emitter+0x5C/0x60 = radial_min_start/end)
		_uv_vel_start = int(raw.get("radial_min_start", 0))
		_uv_vel_end = int(raw.get("radial_min_end", 0))

		# UV direction angle (emitter+0x2E/0x34 = angle_start[1]/angle_end[1])
		_uv_dir_start = _ri(raw, "angle_start", 1)
		_uv_dir_end = _ri(raw, "angle_end", 1)

		# Brightness row index
		_brightness_row_idx = int(emitter_config.callback_params.get("param_4E", 0))

	# Load brightness table
	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			_brightness_table = cb_data.get("brightness_table", [])

		# Enable texture
		if effect_data.texture and _material:
			_material.set_shader_parameter("effect_texture", effect_data.texture)
			_material.set_shader_parameter("use_texture", true)

	state = State.ANIMATE

func _on_animate(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	pass

func physics_step() -> void:
	"""Update frame counter and UV scrolling."""
	if not _active:
		return

	if _frame_counter < FRAME_MAX:
		_frame_counter += 1

	# UV velocity: lerp(radial_min_start, radial_min_end, curve) with direction
	var vel_curve_t: float = _sample_curve("radial_velocity")
	var vel_mag: int = int(lerpf(float(_uv_vel_start), float(_uv_vel_end), vel_curve_t))

	var dir_curve_t: float = _sample_curve("velocity_base_angle")
	var dir_angle: int = int(lerpf(float(_uv_dir_start), float(_uv_dir_end), dir_curve_t))

	# rcos/rsin for UV velocity direction
	var dir_rad: float = float(dir_angle) * ANGLE_SCALE
	var uv_vel_x: int = int(cos(dir_rad) * BRIGHTNESS_SCALE) * vel_mag * 16 >> 12
	var uv_vel_y: int = int(sin(dir_rad) * BRIGHTNESS_SCALE) * vel_mag * 16 >> 12

	# Update UV counters with wrapping
	_uv_counter_x = _wrap_counter(_uv_counter_x + uv_vel_x, _half_wrap_x)
	_uv_counter_y = _wrap_counter(_uv_counter_y + uv_vel_y, _half_wrap_y)

func update_render() -> void:
	"""Rebuild screen grid mesh."""
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

	# PSX screen (256×240) → Godot view units
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y
	var psx_scale_x: float = camera.size * aspect / 256.0
	var psx_scale_y: float = camera.size / 240.0

	# Update scrolling UV rect on material
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

	# Color curves — check for valid curve indices directly rather than the
	# color_curve_enabled flag, which may be incorrect in parsed JSON.
	# PSX: flags_lo & 0x40 enables curves. Default without curves = 0x80 (0.5).
	var curve_color: Color = _sample_colors()
	var r_val: float = curve_color.r
	var g_val: float = curve_color.g
	var b_val: float = curve_color.b

	# Get brightness row
	var brightness_row: Array = []
	if _brightness_row_idx >= 0 and _brightness_row_idx < _brightness_table.size():
		brightness_row = _brightness_table[_brightness_row_idx]

	if EffectsDebug.timeline():
		if _frame_counter % 30 == 0:
			var bright0: float = float(brightness_row[0]) / BRIGHTNESS_SCALE if brightness_row.size() > 0 else -1.0
			var r_idx: int = emitter_config.color_curves.get("r", -1)
			print("[CB16] frame=%d r=%.3f g=%.3f b=%.3f bright[0]=%.3f curve_r_idx=%d" % [
				_frame_counter, r_val, g_val, b_val, bright0, r_idx])

	# Skip rendering entirely when color is effectively zero
	var max_color: float = maxf(r_val, maxf(g_val, b_val))
	if max_color < 0.001:
		return

	# Build mesh arrays: 4×4 grid of screen-filling quads
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	# Camera-pinned base position
	var base_pos: Vector3 = camera.global_position + cam_fwd * 15.0

	for row in GRID_ROWS:
		for col in GRID_COLS:
			var x0: float = float(col) * CELL_SIZE
			var x1: float = float(col + 1) * CELL_SIZE
			var y0: float = float(row) * CELL_SIZE
			var y1: float = float(row + 1) * CELL_SIZE

			var v00: Vector3 = base_pos + cam_right * (x0 - 128.0) * psx_scale_x + cam_up * (-(y0 - 120.0)) * psx_scale_y
			var v01: Vector3 = base_pos + cam_right * (x1 - 128.0) * psx_scale_x + cam_up * (-(y0 - 120.0)) * psx_scale_y
			var v10: Vector3 = base_pos + cam_right * (x0 - 128.0) * psx_scale_x + cam_up * (-(y1 - 120.0)) * psx_scale_y
			var v11: Vector3 = base_pos + cam_right * (x1 - 128.0) * psx_scale_x + cam_up * (-(y1 - 120.0)) * psx_scale_y

			var bright_inner: float = 0.0
			if row < brightness_row.size():
				bright_inner = float(brightness_row[row]) / BRIGHTNESS_SCALE
			var bright_outer: float = 0.0
			if row + 1 < brightness_row.size():
				bright_outer = float(brightness_row[row + 1]) / BRIGHTNESS_SCALE

			var col_inner := Color(r_val * bright_inner, g_val * bright_inner, b_val * bright_inner, 1.0)
			var col_outer := Color(r_val * bright_outer, g_val * bright_outer, b_val * bright_outer, 1.0)

			_quad(positions, colors, uvs, custom0,
				v00, v01, v10, v11, col_inner, col_outer)

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func cleanup() -> void:
	_frame_counter = 0
	_active = false
	_uv_counter_x = 0
	_uv_counter_y = 0
	_brightness_table = []
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
