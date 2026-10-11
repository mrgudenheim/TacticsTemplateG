extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB14 - Rotating tube/cylinder (PSX FUN_801c2500 in E041).
## World-space 3D: 9 rings × 8 vertices = 64 quads forming a rotating tube.
## Vertices placed in 3D world space; Godot camera handles projection.
##
## PCSX dump validation (E041 frame 36, emitter 8):
##   rot_angle=3136, z_base=0, uv_angle=4352(scroll 17)
##   UVs: U=104→119, V=33→64 (base 104,16 + scroll 17, width 15, height 31)
##   Colors: purple gradient (127,31,163) → (0,0,0)
##   Tube: ~50px screen extent, 8 quads/ring × 8 bands
## Vault: [[Effect Callback Mesh]]
## Vault: [[Embedded MIPS Effect Code]]

const RING_COUNT: int = 9
const VERTS_PER_RING: int = 8

var _rotation_angle: int = 0   # ushort, & ANGLE_MASK
var _z_base: int = 0           # piVar39[0x682]
var _z_accel: int = 0          # piVar39[0x683]
var _uv_angle: int = 0         # ushort at byte 0x1A06

var _brightness_row_idx: int = 0
var _brightness_table: Array = []
var _brightness_table_secondary: Array = []

func _ready() -> void:
	_create_cb_mesh()

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_active = false
	_rotation_angle = 0
	_z_base = 0
	_z_accel = 0
	_uv_angle = 0
	_brightness_table = []
	_brightness_table_secondary = []

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	_active = true
	_frame_counter = 0
	_rotation_angle = 0
	_z_base = 0
	_z_accel = 0
	_uv_angle = 0

	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			_brightness_table = cb_data.get("brightness_table", [])
			_brightness_table_secondary = cb_data.get("brightness_table_secondary", [])
		if effect_data.texture and _material:
			_material.set_shader_parameter("effect_texture", effect_data.texture)
			_material.set_shader_parameter("use_texture", true)
			_material.set_shader_parameter("uv_rect", Vector4(0.0, 0.0, 1.0, 1.0))

	if emitter_config:
		# Brightness row from offset 0x3C = vel_spread_start[2] in parser
		_brightness_row_idx = _ri(emitter_config.raw_data, "vel_spread_start", 2)

	state = State.ANIMATE

func physics_step() -> void:
	if not _active or emitter_config == null or effect_data == null:
		return
	if _frame_counter < FRAME_MAX:
		_frame_counter += 1

	var raw: Dictionary = emitter_config.raw_data

	# Rotation angle increment: lerp(emitter+0x5C, emitter+0x60)
	# = radial_min_start / radial_min_end in parser raw_data
	var rot_curve_t: float = _curve_t_nibble(0, 7)  # (emitter+0x08 >> 0x1C)
	var rot_incr: int = int(lerpf(float(raw.get("radial_min_start", 0)), float(raw.get("radial_min_end", 0)), rot_curve_t))
	_rotation_angle = (_rotation_angle + rot_incr) & ANGLE_MASK

	# UV angle increment: emitter+0x30 = angle_start[2] in parser
	var uv_incr: int = _ri(raw, "angle_start", 2)
	_uv_angle = (_uv_angle + uv_incr) & 0xFFFF
	# Wrap within period: emitter+0x22 = spread_start[1]
	var period: int = _ri(raw, "spread_start", 1)
	if period > 0:
		var limit: int = period * 0x100
		while (_uv_angle & 0xFFFF) > limit:
			_uv_angle -= limit
		while _uv_angle < 0:
			_uv_angle += limit

	# Z accumulation: lerp(emitter+0x7C, emitter+0x88) = drag_min_start[0] / drag_min_end[0]
	var z_curve_t: float = _curve_t_nibble(1, 1)  # (emitter+0x0C >> 4 & 0xF)
	var z_accel_incr: int = int(lerpf(float(_ri(raw, "drag_min_start", 0)), float(_ri(raw, "drag_min_end", 0)), z_curve_t))
	_z_accel += z_accel_incr
	# z_base update: lerp(emitter+0x64, emitter+0x70) + accel + z_base
	var z_base_val: int = int(lerpf(float(_ri(raw, "accel_min_start", 0)), float(_ri(raw, "accel_min_end", 0)), z_curve_t))
	_z_base = z_base_val + _z_accel + _z_base

func update_render() -> void:
	if _array_mesh == null:
		return
	_array_mesh.clear_surfaces()
	if not _active or state != State.ANIMATE:
		return
	if emitter_config == null or effect_data == null:
		return

	var raw: Dictionary = emitter_config.raw_data

	# Base position from interp_xyz (emitter position fields)
	var pos_curve_t: float = _curve_t_nibble(0, 0)  # (emitter+0x08 & 0xF)
	var base_psx := Vector3(
		lerpf(float(_ri(raw, "position_start", 0)), float(_ri(raw, "position_end", 0)), pos_curve_t),
		lerpf(float(_ri(raw, "position_start", 1)), float(_ri(raw, "position_end", 1)), pos_curve_t),
		lerpf(float(_ri(raw, "position_start", 2)), float(_ri(raw, "position_end", 2)), pos_curve_t))

	# Convert PSX position to Godot world (Y negated, scaled by 1/28)
	var base_pos: Vector3 = anchor_target + Vector3(base_psx.x, -base_psx.y, base_psx.z) * PSX_SCALE

	# Base radius: lerp(emitter+0xA8, emitter+0xAC) = param_A8 → param_AC
	# C code: (*(ushort*)(iVar38 + 0x0E) & 0xF) = low nibble of byte 6 in curve_indices
	# Byte 6 in word1 = nibble 4 (shift 16), NOT nibble 3 (shift 12)
	var radius_curve_t: float = _curve_t_nibble(1, 4)
	var base_radius: int = int(lerpf(
		float(emitter_config.callback_params.get("param_A8", 0)),
		float(emitter_config.callback_params.get("param_AC", 0)),
		radius_curve_t))

	# Ring params from accel fields (C lines 256-258):
	# local_650 = lerp(0x64, 0x70) = accel_min_start[0] / accel_min_end[0] — z_base for physics_step
	# local_64c = lerp(0x68, 0x74) = accel_min_start[1] / accel_min_end[1] — HEIGHT velocity per ring
	# local_648 = lerp(0x6C, 0x78) = accel_min_start[2] / accel_min_end[2] — RADIUS velocity per ring
	var ring_curve_t: float = _curve_t_nibble(1, 0)  # (emitter+0x0C & 0xF)
	var height_vel_initial: int = int(lerpf(float(_ri(raw, "accel_min_start", 1)), float(_ri(raw, "accel_min_end", 1)), ring_curve_t))
	var radius_vel_initial: int = int(lerpf(float(_ri(raw, "accel_min_start", 2)), float(_ri(raw, "accel_min_end", 2)), ring_curve_t))

	# Drag fields for per-ring acceleration (C lines 266-268):
	# local_63c = lerp(0x80, 0x8C) = drag_min_start[1] / drag_min_end[1] — height acceleration
	# local_638 = lerp(0x84, 0x90) = drag_min_start[2] / drag_min_end[2] — radius acceleration
	var drag_curve_t: float = _curve_t_nibble(1, 1)  # (emitter+0x0C >> 4 & 0xF)
	var height_accel: int = int(lerpf(float(_ri(raw, "drag_min_start", 1)), float(_ri(raw, "drag_min_end", 1)), drag_curve_t))
	var radius_accel: int = int(lerpf(float(_ri(raw, "drag_min_start", 2)), float(_ri(raw, "drag_min_end", 2)), drag_curve_t))

	# Rotation: 4 sin/cos values for the octagonal cross-section
	var angle_rad: float = float(_rotation_angle) * ANGLE_SCALE
	var angle2_rad: float = angle_rad + TAU * 512.0 / BRIGHTNESS_SCALE  # +0x200 = 45 degrees
	var sin_a: float = sin(angle_rad)
	var sin_a2: float = sin(angle2_rad)
	var cos_a: float = cos(angle_rad)
	var cos_a2: float = cos(angle2_rad)

	# Generate 9 rings of 8 vertices
	# PSX (lines 285-322): two accumulators per ring step
	#   iVar27 (radius offset): += local_648 (radius_vel), local_648 += local_638 (radius_accel)
	#   iVar30 (height):        += local_64c (height_vel), local_64c += local_63c (height_accel)
	var rings: Array = []
	var height_vel: int = height_vel_initial
	var radius_vel: int = radius_vel_initial
	var radius_accum: int = 0   # iVar27
	var height_accum: int = 0   # iVar30

	for ring in RING_COUNT:
		var r_raw: int = base_radius + ((radius_accum + _z_base) >> 8)
		var r: float = float(r_raw) * PSX_SCALE
		var h: float = float(height_accum >> 8) * PSX_SCALE

		# 8 vertices: octagon using cos/sin at 0° and 45° with sign flips
		# Matches PSX pattern: (cos*r, h, sin*r), (cos2*r, h, sin2*r), etc.
		var verts: Array = []
		verts.append(Vector3(cos_a * r, -h, sin_a * r))        # 0: (+cos, +sin)
		verts.append(Vector3(cos_a2 * r, -h, sin_a2 * r))      # 1: (+cos2, +sin2)
		verts.append(Vector3(-sin_a * r, -h, cos_a * r))        # 2: (-sin, +cos) — 90° rotated
		verts.append(Vector3(-sin_a2 * r, -h, cos_a2 * r))      # 3: (-sin2, +cos2)
		verts.append(Vector3(-cos_a * r, -h, -sin_a * r))       # 4: (-cos, -sin) — 180°
		verts.append(Vector3(-cos_a2 * r, -h, -sin_a2 * r))     # 5: (-cos2, -sin2)
		verts.append(Vector3(sin_a * r, -h, -cos_a * r))        # 6: (+sin, -cos) — 270°
		verts.append(Vector3(sin_a2 * r, -h, -cos_a2 * r))      # 7: (+sin2, -cos2)
		rings.append(verts)

		# Advance per-ring accumulators (PSX lines 317-320)
		height_vel += height_accel    # local_64c += local_63c
		radius_vel += radius_accel    # local_648 += local_638
		radius_accum += radius_vel    # iVar27 += local_648
		height_accum += height_vel    # iVar30 += local_64c

	# UV computation (all quads share same UVs)
	# U: lerp(angle_start[0], angle_end[0]) to U + spread_start[0]
	# V: lerp(angle_start[1], angle_end[1]) + scroll to V + spread_start[1] + scroll
	var uv_curve_t: float = _curve_t_nibble(0, 2)  # (emitter+0x08 >> 8 & 0xF)
	var u_base: int = int(lerpf(float(_ri(raw, "angle_start", 0)), float(_ri(raw, "angle_end", 0)), uv_curve_t))
	var v_base: int = int(lerpf(float(_ri(raw, "angle_start", 1)), float(_ri(raw, "angle_end", 1)), uv_curve_t))
	var u_width: int = _ri(raw, "spread_start", 0)
	var v_height: int = _ri(raw, "spread_start", 1)
	var v_scroll: int = (_uv_angle >> 8) & 0xFF

	var tex_w: float = 256.0
	var tex_h: float = 256.0
	if effect_data.texture:
		tex_w = float(effect_data.texture.get_width())
		tex_h = float(effect_data.texture.get_height())
	var uv_u0: float = float(u_base & 0xFF) / tex_w
	var uv_u1: float = float((u_base + u_width) & 0xFF) / tex_w
	var uv_v0: float = float((v_base + v_scroll) & 0xFF) / tex_h
	var uv_v1: float = float((v_base + v_height + v_scroll) & 0xFF) / tex_h

	# Color curves
	var curve_color: Color = _sample_colors()
	var r_val: float = curve_color.r
	var g_val: float = curve_color.g
	var b_val: float = curve_color.b

	if maxf(r_val, maxf(g_val, b_val)) < 0.001 and _frame_counter > 1:
		return

	# Brightness
	var bright_row: Array = []
	if _brightness_row_idx >= 0 and _brightness_row_idx < _brightness_table.size():
		bright_row = _brightness_table[_brightness_row_idx]

	# Build mesh: 8 ring bands × 8 quads = 64 quads
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	for ring in 8:
		var r0: Array = rings[ring]
		var r1: Array = rings[ring + 1]
		var b_inner: float = float(bright_row[ring]) / BRIGHTNESS_SCALE if ring < bright_row.size() else 1.0
		var b_outer: float = float(bright_row[ring + 1]) / BRIGHTNESS_SCALE if ring + 1 < bright_row.size() else 1.0

		for vi in VERTS_PER_RING:
			var vi_next: int = (vi + 1) % VERTS_PER_RING
			var v00: Vector3 = base_pos + r0[vi]
			var v01: Vector3 = base_pos + r0[vi_next]
			var v10: Vector3 = base_pos + r1[vi]
			var v11: Vector3 = base_pos + r1[vi_next]

			var ci := Color(r_val * b_inner, g_val * b_inner, b_val * b_inner, 1.0)
			var co := Color(r_val * b_outer, g_val * b_outer, b_val * b_outer, 1.0)

			_quad(positions, colors, uvs, custom0,
				v00, v01, v10, v11, ci, co,
				Vector2(uv_u0, uv_v0), Vector2(uv_u1, uv_v0),
				Vector2(uv_u0, uv_v1), Vector2(uv_u1, uv_v1))

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func cleanup() -> void:
	_active = false
	_frame_counter = 0
	_rotation_angle = 0
	_z_base = 0
	_z_accel = 0
	_uv_angle = 0
	_brightness_table = []
	_brightness_table_secondary = []
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
