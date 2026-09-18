extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB18 - 3D tube/ball mesh callback (PSX FUN_801c43f0).
## Renders a 3D tube/ball in world space at the caster position using GTE projection.
## 9 cross-sections × 8 sides (octagonal), with double-integration radius growth.
##
## Analysis Checklist:
## 1. Quad count: 64 per bank (0x40). 2 banks double-buffered. Alloc = 0x1a1c.
## 2. Topology: 3D tube/ball — 9 octagonal cross-sections connected by quads.
## 3. Orientation: WORLD SPACE 3D. GTE perspective projection on PSX. Godot: native 3D mesh.
## 4. Blend mode: from emitter+0x24 (NOT +0x4C). Emitter 6: additive.
## 5. Anchor mode: ORIGIN (emitter+2 & 0xE00 = 0x200). Positioned at caster tile.
## 6. Fixed-point: radius >> 8 (256-scale), vertices >> 0xc (4096-scale from sin/cos).
## 7. Color: brightness table at DAT_801c5a1c, 9 int32s/row, indexed by emitter+0x3C.
##    Gouraud shading with per-channel RGB from color curves r=8, g=8, b=9.
## 8. State: [0x681]=rotation angle, [0x682]=radius accum, [0x683]=radius velocity.
## 9. Cleanup: two-phase at +0x1a18.
## 10. callback_data.json: brightness table (6 rows × 9 values).
## Vault: [[Effect Callback Mesh]]

const SECTIONS: int = 9
const SIDES: int = 8

var _rotation_angle_raw: int = 0  # piVar39[0x681], wraps 0xFFF
var _radius_accum: int = 0        # piVar39[0x682]
var _radius_velocity: int = 0     # piVar39[0x683]
var _uv_counter: int = 0          # piVar39+0x1a06

# Emitter params (read at init)
var _base_radius_start: int = 0   # emitter+0xA8 = callback_params["param_A8"]
var _base_radius_end: int = 0     # emitter+0xAC = callback_params["param_AA"] (bag of bytes: +0xAC)
var _rot_vel_start: int = 0       # emitter+0x5C = raw_data["radial_min_start"]
var _rot_vel_end: int = 0         # emitter+0x60 = raw_data["radial_min_end"]
var _y_scale: int = 0             # emitter+0x20 = raw_data["spread_start"][0]
var _y_wrap_max: int = 0          # emitter+0x22 = raw_data["spread_start"][1]
var _uv_step: int = 0             # emitter+0x30 = raw_data["vel_spread_start"][2] (bag of bytes)

# Accel fields (3-axis, from emitter accel/drag)
var _accel_x_start: int = 0       # emitter+0x64 = raw_data["accel_min_start"][0]
var _accel_y_start: int = 0       # emitter+0x68 = raw_data["accel_min_start"][1]
var _accel_z_start: int = 0       # emitter+0x6C = raw_data["accel_min_start"][2]
var _accel_x_end: int = 0         # emitter+0x70 = raw_data["accel_min_end"][0]
var _accel_y_end: int = 0         # emitter+0x74 = raw_data["accel_min_end"][1]
var _accel_z_end: int = 0         # emitter+0x78 = raw_data["accel_min_end"][2]
var _drag_x_start: int = 0        # emitter+0x7C = raw_data["drag_min_start"][0]
var _drag_y_start: int = 0        # emitter+0x80 = raw_data["drag_min_start"][1]
var _drag_z_start: int = 0        # emitter+0x84 = raw_data["drag_min_start"][2]
var _drag_x_end: int = 0          # emitter+0x88 = raw_data["drag_min_end"][0]
var _drag_y_end: int = 0          # emitter+0x8C = raw_data["drag_min_end"][1]
var _drag_z_end: int = 0          # emitter+0x90 = raw_data["drag_min_end"][2]

# UV direction
var _uv_angle_start: int = 0      # emitter+0x2C = raw_data["angle_start"][0]
var _uv_angle_end: int = 0        # emitter+0x32 = raw_data["angle_end"][0]
var _uv_mag_start: int = 0        # emitter+0x2E = raw_data["angle_start"][1]
var _uv_mag_end: int = 0          # emitter+0x34 = raw_data["angle_end"][1]

# UV texture rect (bag of bytes: spread_start = UV size, angle_start = UV origin)
var _uv_u_start: int = 0         # (char)lerp(angle_start[0], angle_end[0], curve)
var _uv_v_start: int = 0         # (char)lerp(angle_start[1], angle_end[1], curve)
var _uv_width: int = 0           # spread_start[0] = emitter+0x20
var _uv_height: int = 0          # spread_start[1] = emitter+0x22

# Anchor mode from emitter+0x02/0x03: *(ushort*)(emitter+2) & 0xE00
# 0x200=ORIGIN (caster), 0x400=TARGET, 0x600/0x800=coord_transform, 0xA00=CURSOR
var _anchor_mode: int = 0

# Brightness
var _brightness_row_idx: int = 0  # emitter+0x3C — bag of bytes: size_spread_start
var _brightness_table: Array = []

func _ready() -> void:
	_create_cb_mesh(true)

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_active = false
	_rotation_angle_raw = 0
	_radius_accum = 0
	_radius_velocity = 0
	_uv_counter = 0
	_brightness_table = []

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	"""INIT -> ANIMATE: read emitter params."""
	_active = true
	_frame_counter = 0
	_rotation_angle_raw = 0
	_radius_accum = 0
	_radius_velocity = 0
	_uv_counter = 0

	if emitter_config:
		var raw: Dictionary = emitter_config.raw_data

		# Base radius: emitter+0xA8, +0xAC
		_base_radius_start = int(emitter_config.callback_params.get("param_A8", 0))
		_base_radius_end = int(emitter_config.callback_params.get("param_AA", 0))

		# Rotation velocity: emitter+0x5C, +0x60
		_rot_vel_start = int(raw.get("radial_min_start", 0))
		_rot_vel_end = int(raw.get("radial_min_end", 0))

		# Y scale/wrap: emitter+0x20, +0x22
		_y_scale = _ri(raw, "spread_start", 0)
		_y_wrap_max = _ri(raw, "spread_start", 1)

		# UV step: emitter+0x30
		_uv_step = _ri(raw, "vel_spread_start", 2)

		# Accel (3-axis): emitter+0x64..0x78
		_accel_x_start = _ri(raw, "accel_min_start", 0)
		_accel_y_start = _ri(raw, "accel_min_start", 1)
		_accel_z_start = _ri(raw, "accel_min_start", 2)
		_accel_x_end = _ri(raw, "accel_min_end", 0)
		_accel_y_end = _ri(raw, "accel_min_end", 1)
		_accel_z_end = _ri(raw, "accel_min_end", 2)

		# Drag (3-axis): emitter+0x7C..0x90
		_drag_x_start = _ri(raw, "drag_min_start", 0)
		_drag_y_start = _ri(raw, "drag_min_start", 1)
		_drag_z_start = _ri(raw, "drag_min_start", 2)
		_drag_x_end = _ri(raw, "drag_min_end", 0)
		_drag_y_end = _ri(raw, "drag_min_end", 1)
		_drag_z_end = _ri(raw, "drag_min_end", 2)

		# UV direction: emitter+0x2C..0x34
		_uv_angle_start = _ri(raw, "angle_start", 0)
		_uv_angle_end = _ri(raw, "angle_end", 0)
		_uv_mag_start = _ri(raw, "angle_start", 1)
		_uv_mag_end = _ri(raw, "angle_end", 1)

		# Anchor mode from parsed emitter flags.
		# PSX dispatches on *(ushort*)(emitter+2) & 0xE00:
		# 0x200=ORIGIN, 0x400/0x600=TARGET (via coord_transform), 0xA00=CURSOR
		var anchor_str: String = emitter_config.flags.get("emitter_anchor_mode", "WORLD")
		match anchor_str:
			"ORIGIN": _anchor_mode = 0x200
			"TARGET": _anchor_mode = 0x400
			"CURSOR": _anchor_mode = 0xA00
			_: _anchor_mode = 0x000

		# UV texture rect: u_start/v_start from angle fields, width/height from spread
		_uv_u_start = _ri(raw, "angle_start", 0)   # emitter+0x2C
		_uv_v_start = _ri(raw, "angle_start", 1)   # emitter+0x2E
		_uv_width = _ri(raw, "spread_start", 0)    # emitter+0x20
		_uv_height = _ri(raw, "spread_start", 1)   # emitter+0x22

		# Brightness row from emitter+0x3C (size_spread_start, bag of bytes)
		_brightness_row_idx = 0  # Default; overridden from callback_data if available

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

func physics_step() -> void:
	"""Update rotation, radius growth, UV counter."""
	if not _active:
		return

	_frame_counter += 1

	# Rotation: angle += lerp(rot_vel_start, rot_vel_end, curve), wrap at 0xFFF
	var rot_curve_t: float = _sample_curve("radial_velocity")
	var rot_vel: int = int(lerpf(float(_rot_vel_start), float(_rot_vel_end), rot_curve_t))
	_rotation_angle_raw = (_rotation_angle_raw + rot_vel) & ANGLE_MASK

	# Radius double-integration:
	# velocity += drag, accum += accel + velocity
	var drag_curve_t: float = _sample_curve("drag")
	var drag_x: int = int(lerpf(float(_drag_x_start), float(_drag_x_end), drag_curve_t))
	_radius_velocity += drag_x
	var accel_curve_t: float = _sample_curve("acceleration")
	var accel_x: int = int(lerpf(float(_accel_x_start), float(_accel_x_end), accel_curve_t))
	_radius_accum += accel_x + _radius_velocity

	# UV wrapping
	_uv_counter = (_uv_counter + _uv_step) & 0xFFFF
	if _y_wrap_max > 0:
		var wrap_limit: int = _y_wrap_max * 0x100
		while _uv_counter >= wrap_limit:
			_uv_counter -= wrap_limit
		while _uv_counter < 0:
			_uv_counter += wrap_limit

func update_render() -> void:
	"""Rebuild 3D tube mesh."""
	if _array_mesh == null:
		return

	_array_mesh.clear_surfaces()

	if not _active or state != State.ANIMATE:
		return
	if emitter_config == null or effect_data == null:
		return

	# Update UV rect: u from angle lerp, v scrolls via _uv_counter
	if _material and effect_data.texture:
		var tex_size: Vector2 = effect_data.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			var u0: int = _uv_u_start & 0xFF
			var v_scroll: int = (_uv_counter >> 8) & 0xFF
			var v0: int = (_uv_v_start + v_scroll) & 0xFF
			_material.set_shader_parameter("uv_rect", Vector4(
				float(u0) / tex_size.x,
				float(v0) / tex_size.y,
				float(_uv_width) / tex_size.x,
				float(_uv_height) / tex_size.y))

	# Color curves — check indices directly (not flag)
	var curve_color: Color = _sample_colors()
	var r_val: float = curve_color.r
	var g_val: float = curve_color.g
	var b_val: float = curve_color.b

	# Skip rendering when invisible
	var max_color: float = maxf(r_val, maxf(g_val, b_val))
	if max_color < 0.001 and _frame_counter > 1:
		if EffectsDebug.timeline() and _frame_counter % 30 == 0:
			print("[CB18] SKIP frame=%d color=%.3f (zero)" % [_frame_counter, max_color])
		return

	if EffectsDebug.timeline() and _frame_counter % 10 == 0:
		print("[CB18] RENDER frame=%d r=%.3f g=%.3f b=%.3f base_r=%d accum=%d vel=%d rot=%d anchor=%s" % [
			_frame_counter, r_val, g_val, b_val, _base_radius_start, _radius_accum,
			_radius_velocity, _rotation_angle_raw, str(anchor_origin)])

	# Sample base radius curve
	var radius_curve_t: float = _sample_curve("weight")  # from emitter+0x0E nibble
	var base_radius: int = int(lerpf(float(_base_radius_start), float(_base_radius_end), radius_curve_t))

	# Sample accel curves for Y/Z height
	var accel_curve_t: float = _sample_curve("acceleration")
	var accel_y: int = int(lerpf(float(_accel_y_start), float(_accel_y_end), accel_curve_t))
	var accel_z: int = int(lerpf(float(_accel_z_start), float(_accel_z_end), accel_curve_t))
	var drag_curve_t: float = _sample_curve("drag")
	var drag_y: int = int(lerpf(float(_drag_y_start), float(_drag_y_end), drag_curve_t))
	var drag_z: int = int(lerpf(float(_drag_z_start), float(_drag_z_end), drag_curve_t))

	# Rotation angle → 8 direction vectors in XZ plane
	var angle_rad: float = float(_rotation_angle_raw) * ANGLE_SCALE
	var dirs: Array[Vector3] = []
	for i in SIDES:
		var a: float = angle_rad + TAU * float(i) / float(SIDES)
		dirs.append(Vector3(cos(a), 0.0, sin(a)))

	# Compute 9 cross-section vertex rings
	var section_verts: Array = []  # Array of Array[Vector3]
	var y_accum: int = 0
	var y_vel: int = accel_y
	var z_accum: int = 0
	var z_vel: int = accel_z

	for _s in SECTIONS:
		# PSX: cos * (base_radius + (accum >> 8)) >> 12
		# cos returns 4096-scale, >> 12 cancels. So vertex = cos_float * radius.
		# radius is in RAW PSX world units. Apply PSX_SCALE for Godot.
		var eff_radius: float = float(base_radius + (z_accum + _radius_accum >> 8)) * PSX_SCALE
		var height: float = float(y_accum >> 8) * PSX_SCALE
		var verts: Array[Vector3] = []
		for d in dirs:
			verts.append(Vector3(d.x * eff_radius, -height, d.z * eff_radius))
		section_verts.append(verts)

		# Double-integration for Y height and Z radius offset
		y_vel += drag_y
		z_vel += drag_z
		y_accum += y_vel
		z_accum += z_vel

	# Get brightness row
	var brightness_row: Array = []
	if _brightness_row_idx >= 0 and _brightness_row_idx < _brightness_table.size():
		brightness_row = _brightness_table[_brightness_row_idx]

	# Center position: select anchor based on emitter anchor mode
	var center: Vector3
	match _anchor_mode:
		0x200: center = anchor_origin   # ORIGIN = caster position
		0x400: center = anchor_target   # TARGET = target position
		0xA00: center = anchor_cursor   # CURSOR = cursor position
		_: center = anchor_target       # Default to target (0x600 coord_transform also targets)

	# Build mesh
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	for section in range(SECTIONS - 1):
		var ring_a: Array = section_verts[section]
		var ring_b: Array = section_verts[section + 1]

		var bright_inner: float = 1.0
		if section < brightness_row.size():
			bright_inner = float(brightness_row[section]) / BRIGHTNESS_SCALE
		var bright_outer: float = 1.0
		if section + 1 < brightness_row.size():
			bright_outer = float(brightness_row[section + 1]) / BRIGHTNESS_SCALE

		var col_inner := Color(r_val * bright_inner, g_val * bright_inner, b_val * bright_inner, 1.0)
		var col_outer := Color(r_val * bright_outer, g_val * bright_outer, b_val * bright_outer, 1.0)

		for side in SIDES:
			var next_side: int = (side + 1) % SIDES

			var v00: Vector3 = center + ring_a[side]
			var v01: Vector3 = center + ring_a[next_side]
			var v10: Vector3 = center + ring_b[side]
			var v11: Vector3 = center + ring_b[next_side]

			_quad(positions, colors, uvs, custom0,
				v00, v01, v10, v11, col_inner, col_outer)

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func cleanup() -> void:
	_frame_counter = 0
	_active = false
	_rotation_angle_raw = 0
	_radius_accum = 0
	_radius_velocity = 0
	_uv_counter = 0
	_brightness_table = []
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
