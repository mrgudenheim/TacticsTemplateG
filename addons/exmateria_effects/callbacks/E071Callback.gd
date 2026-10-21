extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB26/CB27 - Hemisphere/dome mesh callback (PSX FUN_801c2cec): procedural dome, 9 vertex
## rows equator→pole × 16 segments = 128 quads (8 row-gaps × 16 columns). Both callbacks
## point at this function with different emitter configs on different timeline slots.
## Widest ring at equator, tapering to the pole; y_factor=0 (Bahamut emitters) degenerates
## the dome to a flat disk with radial brightness.

const ROWS: int = 9       # Vertex rows from equator to pole
const COLS: int = 16       # Segments around each ring (full circle)

var _brightness_row: Array = []   # 9 values: per-ring brightness (PSX 0-4096)

var _angular_position: int = 0        # 12-bit rotation (0-4095 PSX angle units)
var _accumulated_angle: int = 0       # UV scroll accumulator
var _radius_velocity_accum: float = 0.0
var _radius_accum: float = 0.0
# CB33 snapshots geometry BEFORE integrating the next invocation (0x801C41E4).
var _cb33_radius: int = 0

var _uv_u_step: float = 0.0            # spread_start[0]
var _angle_wrap_range: int = 0          # spread_start[1]
var _uv_base_start: Array = [0.0, 0.0] # vel_spread_start[0..1]
var _angle_increment: int = 0           # vel_spread_start[2]
var _uv_base_end: Array = [0.0, 0.0]   # vel_spread_end[0..1]
var _rotation_speed_start: float = 0.0  # inertia_min_end
var _rotation_speed_end: float = 0.0    # weight_min_start
var _accel_x_start: float = 0.0        # accel_min_start[0] - radius growth
var _accel_z_start: float = 0.0        # accel_min_start[2] - Y height factor
var _accel_x_end: float = 0.0
var _accel_z_end: float = 0.0
var _drag_x_start: float = 0.0         # drag_min_start[0] - radius vel accum
var _drag_y_start: float = 0.0         # drag_min_start[1] - Y delta per row
var _drag_x_end: float = 0.0
var _drag_y_end: float = 0.0
var _base_radius_start: float = 0.0    # param_A8
var _base_radius_end: float = 0.0      # spread_start_w (from callback data)

# Curve indices (1-based: 0 = no curve, 1 = curve 0, etc.)
var _pos_curve_idx: int = 0
var _uv_curve_idx: int = 0
var _rot_speed_curve_idx: int = 0
var _radius_curve_idx: int = 0
var _vel_accel_curve_idx: int = 0
var _param_a8_curve_idx: int = 0

var _current_accel_x: float = 0.0
var _current_accel_z: float = 0.0
var _current_drag_x: float = 0.0
var _current_drag_y: float = 0.0
var _current_base_radius: float = 0.0
var _current_rotation_speed: float = 0.0
var _current_uv_base: Array = [0.0, 0.0]
var _r_val: float = 0.5
var _g_val: float = 0.5
var _b_val: float = 0.5

func _ready() -> void:
	_create_cb_mesh(true)

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_angular_position = 0
	_accumulated_angle = 0
	_radius_velocity_accum = 0.0
	_radius_accum = 0.0
	_cb33_radius = 0
	_active = false
	_brightness_row = []
	_pos_curve_idx = 0
	_uv_curve_idx = 0
	_rot_speed_curve_idx = 0
	_radius_curve_idx = 0
	_vel_accel_curve_idx = 0
	_param_a8_curve_idx = 0

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	"""INIT -> ANIMATE: read emitter params and callback data."""
	if EffectsDebug.particle():
		print("[E071Callback] _on_init emitter=%d spawn=%d channel=%d" % [emitter_index, spawn_counter, channel_index])
	_active = true
	_frame_counter = 0
	_angular_position = 0
	_accumulated_angle = 0
	_radius_velocity_accum = 0.0
	_radius_accum = 0.0
	_cb33_radius = 0

	if emitter_config:
		var raw: Dictionary = emitter_config.raw_data

		# UV params from spread_start and vel_spread_start/end
		var spread_s: Array = raw.get("spread_start", [0, 0, 0])
		_uv_u_step = float(spread_s[0]) if spread_s.size() > 0 else 0.0
		_angle_wrap_range = int(spread_s[1]) if spread_s.size() > 1 else 0

		var vs_start: Array = raw.get("vel_spread_start", [0, 0, 0])
		_uv_base_start = [float(vs_start[0]), float(vs_start[1])] if vs_start.size() >= 2 else [0.0, 0.0]
		_angle_increment = int(vs_start[2]) if vs_start.size() > 2 else 0

		var vs_end: Array = raw.get("vel_spread_end", [0, 0, 0])
		_uv_base_end = [float(vs_end[0]), float(vs_end[1])] if vs_end.size() >= 2 else [0.0, 0.0]

		# Rotation speed (from inertia_min_end / weight_min_start)
		_rotation_speed_start = emitter_config.inertia_min_end
		_rotation_speed_end = emitter_config.weight_min_start

		var accel_s: Array = raw.get("accel_min_start", [0, 0, 0])
		_accel_x_start = float(accel_s[0]) if accel_s.size() > 0 else 0.0
		_accel_z_start = float(accel_s[2]) if accel_s.size() > 2 else 0.0

		var accel_e: Array = raw.get("accel_min_end", [0, 0, 0])
		_accel_x_end = float(accel_e[0]) if accel_e.size() > 0 else 0.0
		_accel_z_end = float(accel_e[2]) if accel_e.size() > 2 else 0.0

		var drag_s: Array = raw.get("drag_min_start", [0, 0, 0])
		_drag_x_start = float(drag_s[0]) if drag_s.size() > 0 else 0.0
		_drag_y_start = float(drag_s[1]) if drag_s.size() > 1 else 0.0

		var drag_e: Array = raw.get("drag_min_end", [0, 0, 0])
		_drag_x_end = float(drag_e[0]) if drag_e.size() > 0 else 0.0
		_drag_y_end = float(drag_e[1]) if drag_e.size() > 1 else 0.0

		_base_radius_start = float(emitter_config.callback_params.get("param_A8", 0))
		_base_radius_end = _base_radius_start  # overridden by callback data below

	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			var overrides: Dictionary = cb_data.get("emitter_overrides", {})
			var em_key: String = str(emitter_config.index) if emitter_config else ""
			var em_override: Dictionary = overrides.get(em_key, {})

			if not em_override.is_empty():
				var brightness_idx: int = int(em_override.get("brightness_row_index", 0))
				var all_rows: Array = cb_data.get("brightness_table", [])
				if brightness_idx >= 0 and brightness_idx < all_rows.size():
					_brightness_row = all_rows[brightness_idx]

				_base_radius_end = float(em_override.get("spread_start_w", _base_radius_start))

				var curve_raw: Array = em_override.get("curve_indices_raw", [])
				if curve_raw.size() >= 5:
					_pos_curve_idx = int(curve_raw[0]) & 0xF
					_uv_curve_idx = int(curve_raw[1]) & 0xF
					_rot_speed_curve_idx = int(curve_raw[3]) >> 4
					_radius_curve_idx = int(curve_raw[4]) & 0xF
					_vel_accel_curve_idx = int(curve_raw[4]) >> 4

				# param_A8 radius curve from position_end[0] low nibble
				var raw_pe_x: int = int(em_override.get("raw_position_end_x", 0))
				_param_a8_curve_idx = raw_pe_x & 0xF
			else:
				# Salamander cb33 is the same 9×16 dome topology but uses the common
				# direct table contract: row index from emitter+0x3C
				# (raw vel_spread_start[2]), with no per-emitter override payload.
				var direct_rows: Array = cb_data.get("brightness_table", [])
				var direct_idx: int = _ri(emitter_config.raw_data, "vel_spread_start", 2) if emitter_config else 0
				if direct_idx >= 0 and direct_idx < direct_rows.size():
					_brightness_row = direct_rows[direct_idx]

		if effect_data.texture and _material:
			_material.set_shader_parameter("effect_texture", effect_data.texture)
			_material.set_shader_parameter("use_texture", true)

	if EffectsDebug.particle():
		print("[E071Callback] Init complete: base_radius=%.1f->%.1f brightness=%d vals, active=%s" % [
			_base_radius_start, _base_radius_end, _brightness_row.size(), _active])

	state = State.ANIMATE
	# Salamander INIT only allocates the two banks; frame 1 is the first draw.
	if callback_id != 33:
		_on_animate(emitter_index, spawn_counter, channel_index)

func _on_animate(_emitter_index: int, spawn_counter: int, _channel_index: int) -> void:
	"""Called each timeline frame. Sample curves, lerp params, update accumulators."""
	_frame_counter = spawn_counter
	if callback_id == 33:
		_animate_cb33()
		return

	# Sample curves to get interpolation factors (0..255 -> 0.0..1.0)
	var t_pos: float = _sample_curve_t(_pos_curve_idx, spawn_counter)
	var t_uv: float = _sample_curve_t(_uv_curve_idx, spawn_counter)
	var t_rot: float = _sample_curve_t(_rot_speed_curve_idx, spawn_counter)
	var t_radius: float = _sample_curve_t(_radius_curve_idx, spawn_counter)
	var t_vel_accel: float = _sample_curve_t(_vel_accel_curve_idx, spawn_counter)
	var t_param_a8: float = _sample_curve_t(_param_a8_curve_idx, spawn_counter)

	_current_accel_x = lerpf(_accel_x_start, _accel_x_end, t_radius)
	_current_accel_z = lerpf(_accel_z_start, _accel_z_end, t_radius)
	_current_drag_x = lerpf(_drag_x_start, _drag_x_end, t_vel_accel)
	_current_drag_y = lerpf(_drag_y_start, _drag_y_end, t_vel_accel)
	_current_base_radius = lerpf(_base_radius_start, _base_radius_end, t_param_a8)
	_current_rotation_speed = lerpf(_rotation_speed_start, _rotation_speed_end, t_rot)
	_current_uv_base = [
		lerpf(_uv_base_start[0], _uv_base_end[0], t_uv),
		lerpf(_uv_base_start[1], _uv_base_end[1], t_uv),
	]

	# Update rotation accumulator (12-bit angle, wraps at 4096)
	_angular_position = (_angular_position + int(_current_rotation_speed)) % 4096

	_accumulated_angle += _angle_increment
	if _angle_wrap_range > 0:
		var wrap_val: int = _angle_wrap_range * 0x100
		if wrap_val > 0:
			_accumulated_angle = _accumulated_angle % wrap_val

	# Update radius via double-integration (PSX pattern)
	_radius_velocity_accum += _current_drag_x
	_radius_accum += _current_accel_x + _radius_velocity_accum

	if emitter_config and emitter_config.flags.get("color_curve_enabled", false):
		var r_idx: int = emitter_config.color_curves.get("r", -1)
		var g_idx: int = emitter_config.color_curves.get("g", -1)
		var b_idx: int = emitter_config.color_curves.get("b", -1)
		_r_val = _sample_color_curve(r_idx, spawn_counter)
		_g_val = _sample_color_curve(g_idx, spawn_counter)
		_b_val = _sample_color_curve(b_idx, spawn_counter)
	else:
		_r_val = 0.5  # 128/256 neutral
		_g_val = 0.5
		_b_val = 0.5

	# Keep the callback alive through black colour-curve frames. The ROM routine
	# still rebuilds and OT-inserts the primitive bank when RGB is zero; lifetime is
	# controlled by the callback state byte, not by colour. Salamander's shell starts
	# on a dark colour sample and brightens later, so killing it here made the mesh
	# invisible for the rest of the spawn.

# CB33 has the same grid dimensions as Bahamut, but its field and timing
# contract is derived independently from FUN_801c41e4. Live salamander.sstate,
# slot2 emitter12 frame10: angle=720, radius=170, UV=(8,97)..(48,121),
# row1 RGB=37. Do not normalize EffectCurve samples a second time.
func _animate_cb33() -> void:
	var raw: Dictionary = emitter_config.raw_data
	var shape_t: float = _curve_t_for_slot("acceleration", 1, 0)
	var drag_t: float = _curve_t_for_slot("drag", 1, 1)
	var uv_t: float = _curve_t_for_slot("velocity_base_angle", 0, 2)
	var rot_t: float = _curve_t_for_slot("radial_velocity", 0, 7)
	_current_base_radius = _cb33_lerp(int(emitter_config.callback_params.get("param_A8", 0)),
		int(emitter_config.callback_params.get("param_AC", 0)), _curve_t_nibble(1, 4))
	_current_accel_x = _cb33_lerp(_ri(raw, "accel_min_start", 0), _ri(raw, "accel_min_end", 0), shape_t)
	_current_accel_z = _cb33_lerp(_ri(raw, "accel_min_start", 1), _ri(raw, "accel_min_end", 1), shape_t)
	_current_drag_x = _cb33_lerp(_ri(raw, "drag_min_start", 0), _ri(raw, "drag_min_end", 0), drag_t)
	_current_drag_y = _cb33_lerp(_ri(raw, "drag_min_start", 1), _ri(raw, "drag_min_end", 1), drag_t)
	_angular_position = (_angular_position + _cb33_lerp(_ri(raw, "radial_min_start"),
		_ri(raw, "radial_min_end"), rot_t)) & 0xfff
	_current_uv_base = [
		_cb33_lerp(_ri(raw, "angle_start", 0), _ri(raw, "angle_end", 0), uv_t),
		_cb33_lerp(_ri(raw, "angle_start", 1), _ri(raw, "angle_end", 1), uv_t)]
	_accumulated_angle += _ri(raw, "angle_start", 2)
	if _angle_wrap_range > 0:
		_accumulated_angle = posmod(_accumulated_angle, _angle_wrap_range * 256)
	_cb33_radius = int(_current_base_radius) + (int(_radius_accum) >> 8)
	_radius_velocity_accum += _current_drag_x
	_radius_accum += _current_accel_x + _radius_velocity_accum
	var rgb := Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0)
	if emitter_config.flags.get("color_curve_enabled", false):
		rgb = _sample_colors()
	_r_val = rgb.r
	_g_val = rgb.g
	_b_val = rgb.b


static func _cb33_lerp(a: int, b: int, t: float) -> int:
	# 0x801A8BE0: arithmetic shift of the delta, not a floating /255 lerp.
	return a + (((b - a) * roundi(t * 255.0)) >> 8)


func physics_step() -> void:
	"""Not used — PSX dome animation driven by invoke, not physics_step."""
	pass

func update_render() -> void:
	"""Rebuild dome mesh: hemisphere from equator to pole."""
	if _array_mesh == null:
		return

	_array_mesh.clear_surfaces()

	if not _active or state != State.ANIMATE:
		return

	if emitter_config == null or effect_data == null:
		return

	# Effective radius: base + accumulated growth >> 8 (PSX shift)
	var effective_radius: float = float(_cb33_radius) if callback_id == 33 else _current_base_radius + _radius_accum / 256.0
	if effective_radius < 0.5:
		return

	if EffectsDebug.particle() and _frame_counter <= 1:
		var outer_r: float = effective_radius * PSX_SCALE
		print("[E071Callback] update_render: eff_radius=%.1f outer_ring=%.2f godot_units center=%s rgb=(%.2f,%.2f,%.2f)" % [
			effective_radius, outer_r, anchor_target, _r_val, _g_val, _b_val])

	var ring_radii: Array[float] = []   # XZ radius per row
	var ring_y_vals: Array[float] = []  # Y displacement per row

	var y_height_factor: float = _current_accel_z
	for r in range(ROWS):
		var row_angle_rad: float = float(r) * 128.0 * ANGLE_SCALE
		if callback_id == 33:
			# ROM truncates twice before scaling height; PSX negative Y is UP.
			ring_radii.append(float((_cb33_radius * roundi(cos(row_angle_rad) * 4096.0)) >> 12) * PSX_SCALE)
			var row_sin: int = (_cb33_radius * roundi(sin(row_angle_rad) * 4096.0)) >> 12
			ring_y_vals.append(float((row_sin * int(y_height_factor)) >> 8) * PSX_SCALE)
		else:
			ring_radii.append(effective_radius * cos(row_angle_rad) * PSX_SCALE)
			ring_y_vals.append(-effective_radius * sin(row_angle_rad) * y_height_factor / 256.0 * PSX_SCALE)
		y_height_factor += _current_drag_y

	var col_cos: Array[float] = []
	var col_sin: Array[float] = []
	for c in range(COLS + 1):
		var col_rad: float = float(_angular_position + c * 256) * ANGLE_SCALE
		col_cos.append(float(roundi(cos(col_rad) * 4096.0)) / 4096.0 if callback_id == 33 else cos(col_rad))
		col_sin.append(float(roundi(sin(col_rad) * 4096.0)) / 4096.0 if callback_id == 33 else sin(col_rad))

	var tex_w: float = 256.0
	var tex_h: float = 256.0
	if effect_data.texture:
		var tex_size: Vector2 = effect_data.texture.get_size()
		if tex_size.x > 0:
			tex_w = tex_size.x
		if tex_size.y > 0:
			tex_h = tex_size.y

	var accumulated_angle_high: float = float(_accumulated_angle >> 8)
	var uv_u0: float = _current_uv_base[0] / tex_w
	var uv_v0: float = (_current_uv_base[1] + accumulated_angle_high) / tex_h
	var uv_u1: float = (_current_uv_base[0] + _uv_u_step) / tex_w
	var uv_v1: float = (_current_uv_base[1] + float(_angle_wrap_range) + accumulated_angle_high) / tex_h

	var center: Vector3 = anchor_target
	if callback_id == 33:
		match emitter_config.get_emitter_anchor_mode():
			EffectEmitter.AnchorMode.ORIGIN: center = anchor_origin
			EffectEmitter.AnchorMode.CURSOR: center = anchor_cursor
			EffectEmitter.AnchorMode.WORLD, EffectEmitter.AnchorMode.CAMERA: center = anchor_world
		var t: float = _curve_t_for_slot("position", 0, 0)
		var start: Vector3 = emitter_config.position_start * 28.0
		var end: Vector3 = emitter_config.position_end * 28.0
		# Positions are already converted to Y-up / Z-mirrored by the parser.
		# Lerp in PSX signed space so negative deltas keep the ROM's rounding.
		center += Vector3(_cb33_lerp(roundi(start.x), roundi(end.x), t),
			-_cb33_lerp(-roundi(start.y), -roundi(end.y), t),
			-_cb33_lerp(-roundi(start.z), -roundi(end.z), t)) * PSX_SCALE

	var has_brightness: bool = _brightness_row.size() >= ROWS

	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	for r in range(ROWS - 1):
		var rad0: float = ring_radii[r]
		var rad1: float = ring_radii[r + 1]
		var y0: float = ring_y_vals[r]
		var y1: float = ring_y_vals[r + 1]

		var bright0: float = float(_brightness_row[r]) / BRIGHTNESS_SCALE if has_brightness else 1.0
		var bright1: float = float(_brightness_row[r + 1]) / BRIGHTNESS_SCALE if has_brightness else 1.0

		var col0 := Color(_r_val * bright0, _g_val * bright0, _b_val * bright0, 1.0)
		var col1 := Color(_r_val * bright1, _g_val * bright1, _b_val * bright1, 1.0)
		if callback_id == 33:
			for component in 3:
				col0[component] = floorf(col0[component] * 255.0 + 0.00001) / 255.0
				col1[component] = floorf(col1[component] * 255.0 + 0.00001) / 255.0

		for c in range(COLS):
			var cc0: float = col_cos[c]
			var sc0: float = col_sin[c]
			var cc1: float = col_cos[c + 1]
			var sc1: float = col_sin[c + 1]

			var v00: Vector3 = center + Vector3(cc0 * rad0, y0, sc0 * rad0)
			var v01: Vector3 = center + Vector3(cc1 * rad0, y0, sc1 * rad0)
			var v10: Vector3 = center + Vector3(cc0 * rad1, y1, sc0 * rad1)
			var v11: Vector3 = center + Vector3(cc1 * rad1, y1, sc1 * rad1)

			if callback_id == 33:
				# Quantize local X/Z before conversion, and preserve the packet's
				# row1,row0 corner order: UV v increases toward the equator.
				v00 = center + Vector3(floorf(cc0 * rad0 * 28.0), y0 * 28.0, -floorf(sc0 * rad0 * 28.0)) * PSX_SCALE
				v01 = center + Vector3(floorf(cc1 * rad0 * 28.0), y0 * 28.0, -floorf(sc1 * rad0 * 28.0)) * PSX_SCALE
				v10 = center + Vector3(floorf(cc0 * rad1 * 28.0), y1 * 28.0, -floorf(sc0 * rad1 * 28.0)) * PSX_SCALE
				v11 = center + Vector3(floorf(cc1 * rad1 * 28.0), y1 * 28.0, -floorf(sc1 * rad1 * 28.0)) * PSX_SCALE
				_quad(positions, colors, uvs, custom0,
					v10, v11, v00, v01, col1, col0,
					Vector2(uv_u0, uv_v0), Vector2(uv_u1, uv_v0),
					Vector2(uv_u0, uv_v1), Vector2(uv_u1, uv_v1))
				continue
			_quad(positions, colors, uvs, custom0,
				v00, v01, v10, v11, col0, col1,
				Vector2(uv_u0, uv_v0), Vector2(uv_u1, uv_v0),
				Vector2(uv_u0, uv_v1), Vector2(uv_u1, uv_v1))

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func _sample_curve_t(curve_idx: int, frame: int) -> float:
	"""Sample an effect curve and return normalized 0.0..1.0 value.
	Curve indices are 1-based: 0 = no curve (returns 0.0), 1 = curve 0, etc."""
	if curve_idx <= 0 or effect_data == null:
		return 0.0
	var actual_idx: int = curve_idx - 1
	var curve = effect_data.get_curve(actual_idx)
	if curve == null:
		return 0.0
	return curve.sample_by_frame(frame) / 255.0

func _sample_color_curve(curve_idx: int, frame: int) -> float:
	"""Sample a color curve (0-based index), returning 0.0..1.0."""
	if curve_idx < 0 or effect_data == null:
		return 0.5
	var curve = effect_data.get_curve(curve_idx)
	if curve == null:
		return 0.5
	return curve.sample_by_frame(frame) / 255.0

func cleanup() -> void:
	_frame_counter = 0
	_angular_position = 0
	_accumulated_angle = 0
	_radius_velocity_accum = 0.0
	_radius_accum = 0.0
	_cb33_radius = 0
	_active = false
	_brightness_row = []
	_r_val = 0.5
	_g_val = 0.5
	_b_val = 0.5
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
