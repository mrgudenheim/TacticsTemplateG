extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## World-space tube/ball mesh callback. TWO shapes share this class because two different
## PSX routines share the "tube" role:
##   * callback 18  -> E065 FUN_801c43f0 (file+0x1EF0): 9 cross-sections x 8 sides.
##   * callbacks 3/4/5/6/7/8/30/39/56 -> E015 FUN_801c39f8 (file+0x14F8): 3 rings x 32
##     sides, one 9-vertex quadrant (angle step 0x80) mirrored by the four quadrant
##     helpers 0x801a9884/98c4/9904/9944, Y step scaled <<2. 64 quads per bank, alloc 0x1a1c.
## ROM notes: blend is emitter+0x24 (spread_start[2], NOT +0x4C) — ABE = (v & 4) == 0,
## ABR = v & 3 → ((v & 3) << 5) | 0x86; Holy's emitter 5 has v = 1 → B+F, what the additive
## shader already gives, so nothing reads it yet; other blends would need plumbing.
## Brightness: per-ring ramp indexed by emitter+0x3C — E015 cylinder 3 int32/row (stride
## 0xC) at DAT_801c5814 = file+0x3314, CB18 ball 9 int32/row; 0x1000 = 1.0. Cleanup is
## two-phase at +0x1a18.
## Vault: [[Effect Callback Mesh]]

## CB18 (E065 FUN_801c43f0) shape.
const SECTIONS_BALL: int = 9
const SIDES_BALL: int = 8
## file+0x14F8 (E015 FUN_801c39f8) shape: 3 rings, 32 sides (4 quadrants x 8 steps of 0x80).
const SECTIONS_CYL: int = 3
const SIDES_CYL: int = 32

## Effects whose file+0x14F8 routine is the 3-ring × 32-side cylinder, by the callback ids
## that reach that offset in the global table. Rooted in a decompile per entry — E015 cb8 →
## research/decompiled/E015.c FUN_801c39f8 (3 rings, 9 verts/quadrant, step 0x80, 4
## quadrant mirrors), confirmed live in PCSX on the `holy` savestate (slot 1/emitter 5:
## rings at y 0/-236/-472, radius → 255 at max growth). E015 cb7 is a DIFFERENT routine at
## file offset 0 (124 live hits, slot 0 emitter 4), and E067 cb20 also resolves to 0x14F8
## (a 4x4 loop) — hence an (effect, id) table, not `if callback_id == ...`.
##
## 🔴 E174 cb56 IS THE SAME BYTES AS E015 cb8, so it cannot be a different shape.
## Routine a681bd1e9f35, 5584 bytes, both at file+0x14F8, ZERO differing bytes — not
## merely a matching fingerprint. Until #1499 this table listed E015 alone, so
## `shape_for` returned its BALL default for E174 while a guard asserted that default
## as though it had been derived.
##
## Which of the two is right is settled by the TABLE WIDTH, and that argument does not
## depend on reading a loop bound correctly: the brightness table these two share is
## 3 int32 per row, ONE PER RING, at file+0x3314. CYL is [3, 32, 2] — three sections.
## BALL is [9, 8, 0] — nine. A three-column per-ring table cannot serve a nine-section
## ball, so CYL is right for both. The routine's own loop bounds corroborate it
## ([2, 3, 9, 17, 25, 32, 33, 64] with per-ring shifts [3, 5], against the 9x8 family's
## [2, 7, 8, 9, 64] with [3, 5, 7]), but the width is the stronger evidence.
const CYLINDER_SHAPE_EFFECTS: Dictionary = {
	"E015": [8],
	"E080": [41], # live Zodiac CB41: three rings, 32 sides; integer subclass
	"E174": [56],
}

## Resolved per (effect, callback id) in _on_init.
var _sections: int = SECTIONS_BALL
var _sides: int = SIDES_BALL
## FUN_801c39f8 shifts the Y step and the Y step-increment left by 2 (0x801c3ffc /
## 0x801c409c `sll v0,v0,2`); FUN_801c43f0 does not.
var _y_shift: int = 0

var _rotation_angle_raw: int = 0  # piVar39[0x681], wraps 0xFFF
var _radius_accum: int = 0        # piVar39[0x682]
var _radius_velocity: int = 0     # piVar39[0x683]
var _uv_counter: int = 0          # piVar39+0x1a06

# Emitter params (read at init)
var _base_radius_start: int = 0   # emitter+0xA8 = callback_params["param_A8"]
var _base_radius_end: int = 0     # emitter+0xAC = callback_params["param_AC"]
var _rot_vel_start: int = 0       # emitter+0x5C = raw_data["radial_min_start"]
var _rot_vel_end: int = 0         # emitter+0x60 = raw_data["radial_min_end"]
var _y_scale: int = 0             # emitter+0x20 = raw_data["spread_start"][0]
var _y_wrap_max: int = 0          # emitter+0x22 = raw_data["spread_start"][1]
var _uv_step: int = 0             # emitter+0x30 = raw_data["angle_start"][2] (bag of bytes)

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
var _brightness_row_idx: int = 0  # emitter+0x3C = raw_data["vel_spread_start"][2]
var _brightness_table: Array = []

## [sections, sides, y_shift] for one (effect, callback id). PURE — the test surface.
##
## The id -> file-offset table (0x801B50D0) is global, but the code at that offset is
## compiled per E###.BIN, so the same offset is a DIFFERENT routine per effect — the lookup
## is (effect, id), and anything without a decompile on file keeps the 9x8 ball this class
## was written against (E065 FUN_801c43f0). A new entry in CYLINDER_SHAPE_EFFECTS is the
## only way to move an effect.
## The callback ids `CallbackRegistry` routes to THIS class. Kept here rather than
## imported because the registry preloads this file — importing it back would be a
## cycle. `CallbackFoldRoutingTest` asserts this list equals what the registry actually
## produces, so it cannot drift silently.
##
## 📌 32 (E074 Salamander) joined here with the cb32 move, and it is NOT bookkeeping.
## Since #1517 inverted `shape_for`, an id the registry routes here but that is absent
## from this list gets `[]` rather than a BALL default, and `_on_init` push_errors. The
## drift clause caught exactly that mid-change — registry routing 32 against an
## OWNED_IDS without it — and named both lists in the failure. The two are kept in step
## mechanically, not by memory.
const OWNED_IDS: Array[int] = [2, 4, 5, 6, 7, 8, 18, 22, 29, 32, 34, 36, 38, 41, 55, 56]


## [] when `cb_id` is not one this class owns — NOT a default.
##
## 🔴 THIS USED TO RETURN BALL FOR EVERY UNKNOWN ID, AND THAT MISLED THREE TIMES.
## The old body fell through to `[SECTIONS_BALL, SIDES_BALL, 0]` for any id absent from
## `CYLINDER_SHAPE_EFFECTS`, whatever class owned it — so a guard asserting BALL passed
## for ids that were not WorldTubes at all, and kept passing after they moved away:
##   E004 cb3   asserted BALL while routed here; actually RadialRing, 6-wide, +0x4E
##   E174 cb56  asserted BALL while byte-identical to E015 cb8, which was asserted CYL
##   E073 cb30 / E079 cb39  asserted BALL; measured an OPEN 9x9 sheet and moved to
##              WarpedGrid — and those rows would have stayed GREEN after the move
## An answer produced for a question the function cannot see is worse than no answer,
## so an id this class does not own now gets none.
static func shape_for(effect_name: String, cb_id: int) -> Array:
	if not (cb_id in OWNED_IDS):
		return []
	var ids: Array = CYLINDER_SHAPE_EFFECTS.get(effect_name, [])
	if cb_id in ids:
		return [SECTIONS_CYL, SIDES_CYL, 2]
	return [SECTIONS_BALL, SIDES_BALL, 0]


func _effect_name() -> String:
	return effect_data.name if effect_data else ""


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
	var shape: Array = shape_for(_effect_name(), callback_id)
	if shape.is_empty():
		# Unreachable unless OWNED_IDS and the registry disagree — the test guards that.
		# WARN and carry on rather than crash: this is runtime, and the cost of a hard
		# failure here is the player's battle. The build-time guard is the test.
		push_error("WorldTubeCallback: cb%d is not in OWNED_IDS but was routed here; "
			% callback_id + "shape falling back to BALL. Registry and OWNED_IDS disagree.")
		shape = [SECTIONS_BALL, SIDES_BALL, 0]
	_sections = shape[0]
	_sides = shape[1]
	_y_shift = shape[2]
	_active = true
	_frame_counter = 0
	_rotation_angle_raw = 0
	_radius_accum = 0
	_radius_velocity = 0
	_uv_counter = 0

	if emitter_config:
		var raw: Dictionary = emitter_config.raw_data

		_base_radius_start = int(emitter_config.callback_params.get("param_A8", 0))
		_base_radius_end = int(emitter_config.callback_params.get("param_AC", 0))

		_rot_vel_start = int(raw.get("radial_min_start", 0))
		_rot_vel_end = int(raw.get("radial_min_end", 0))

		_y_scale = _ri(raw, "spread_start", 0)
		_y_wrap_max = _ri(raw, "spread_start", 1)

		# UV scroll step: angle_start[2] (emitter+0x30), NOT vel_spread_start[2] (0x3C, the
		# brightness row) — EffectReadEmitters.gd pins the offsets.
		_uv_step = _ri(raw, "angle_start", 2)

		_accel_x_start = _ri(raw, "accel_min_start", 0)
		_accel_y_start = _ri(raw, "accel_min_start", 1)
		_accel_z_start = _ri(raw, "accel_min_start", 2)
		_accel_x_end = _ri(raw, "accel_min_end", 0)
		_accel_y_end = _ri(raw, "accel_min_end", 1)
		_accel_z_end = _ri(raw, "accel_min_end", 2)

		_drag_x_start = _ri(raw, "drag_min_start", 0)
		_drag_y_start = _ri(raw, "drag_min_start", 1)
		_drag_z_start = _ri(raw, "drag_min_start", 2)
		_drag_x_end = _ri(raw, "drag_min_end", 0)
		_drag_y_end = _ri(raw, "drag_min_end", 1)
		_drag_z_end = _ri(raw, "drag_min_end", 2)

		_uv_angle_start = _ri(raw, "angle_start", 0)
		_uv_angle_end = _ri(raw, "angle_end", 0)
		_uv_mag_start = _ri(raw, "angle_start", 1)
		_uv_mag_end = _ri(raw, "angle_end", 1)

		var anchor_str: String = emitter_config.flags.get("emitter_anchor_mode", "WORLD")
		match anchor_str:
			"ORIGIN": _anchor_mode = 0x200
			"TARGET": _anchor_mode = 0x400
			"CURSOR": _anchor_mode = 0xA00
			_: _anchor_mode = 0x000

		_uv_u_start = _ri(raw, "angle_start", 0)   # emitter+0x2C
		_uv_v_start = _ri(raw, "angle_start", 1)   # emitter+0x2E
		_uv_width = _ri(raw, "spread_start", 0)    # emitter+0x20
		_uv_height = _ri(raw, "spread_start", 1)   # emitter+0x22

		# Brightness row: emitter+0x3C. Holy's cylinder emitter 5 reads 0 → row [0, 0x800,
		# 0x1000]; under the B+F blend a colour of 0 draws nothing, so the ramp IS the fade.
		_brightness_row_idx = _ri(raw, "vel_spread_start", 2)

	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			_brightness_table = cb_data.get("brightness_table", [])

		if effect_data.texture and _material:
			_material.set_shader_parameter("effect_texture", effect_data.texture)
			_material.set_shader_parameter("use_texture", true)

	state = State.ANIMATE

func physics_step() -> void:
	"""Update rotation, radius growth, UV counter."""
	if not _active:
		return

	_frame_counter += 1

	# PSX rotation-curve index: (*(u32*)(emitter+0x08) >> 28) - 1.
	var rot_curve_t: float = _curve_t_for_slot("radial_velocity", 0, 7)
	var rot_vel: int = int(lerpf(float(_rot_vel_start), float(_rot_vel_end), rot_curve_t))
	_rotation_angle_raw = (_rotation_angle_raw + rot_vel) & ANGLE_MASK

	# Radius double-integration, once per tick (PSX runs it after the ring loop):
	#   vel += accel(0x7C..0x88);  accum += vel0(0x64..0x70) + vel
	var drag_x: int = int(lerpf(float(_drag_x_start), float(_drag_x_end), _curve_t_for_slot("drag", 1, 1)))
	_radius_velocity += drag_x
	var accel_x: int = int(lerpf(float(_accel_x_start), float(_accel_x_end), _curve_t_for_slot("acceleration", 1, 0)))
	_radius_accum += accel_x + _radius_velocity

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

	var max_color: float = maxf(r_val, maxf(g_val, b_val))
	if max_color < 0.001 and _frame_counter > 1:
		if EffectsDebug.timeline() and _frame_counter % 30 == 0:
			print("[CBTUBE] cb%d SKIP frame=%d color=%.3f (zero)" % [callback_id, _frame_counter, max_color])
		return

	if EffectsDebug.timeline() and _frame_counter % 10 == 0:
		print("[CBTUBE] cb%d %s frame=%d %dx%d r=%.3f g=%.3f b=%.3f base_r=%d..%d accum=%d vel=%d rot=%d" % [
			callback_id, _effect_name(), _frame_counter, _sections, _sides, r_val, g_val, b_val,
			_base_radius_start, _base_radius_end, _radius_accum, _radius_velocity,
			_rotation_angle_raw])

	# Base radius: lerp(emitter+0xA8, emitter+0xAC) on the emitter+0x0E low nibble.
	var radius_curve_t: float = _curve_t_for_slot("callback_world_tube_base_radius", 1, 4)
	var base_radius: int = int(lerpf(float(_base_radius_start), float(_base_radius_end), radius_curve_t))

	# Per-ring Y step and radial step. PSX shifts ONLY the two Y terms left by 2.
	var vel_curve_t: float = _curve_t_for_slot("acceleration", 1, 0)
	var acc_curve_t: float = _curve_t_for_slot("drag", 1, 1)
	var accel_y: int = int(lerpf(float(_accel_y_start), float(_accel_y_end), vel_curve_t)) << _y_shift
	var accel_z: int = int(lerpf(float(_accel_z_start), float(_accel_z_end), vel_curve_t))
	var drag_y: int = int(lerpf(float(_drag_y_start), float(_drag_y_end), acc_curve_t)) << _y_shift
	var drag_z: int = int(lerpf(float(_drag_z_start), float(_drag_z_end), acc_curve_t))

	# Rotation angle → direction vectors in XZ plane
	var angle_rad: float = float(_rotation_angle_raw) * ANGLE_SCALE
	var dirs: Array[Vector3] = []
	for i in _sides:
		var a: float = angle_rad + TAU * float(i) / float(_sides)
		dirs.append(Vector3(cos(a), 0.0, sin(a)))

	var section_verts: Array = []  # Array of Array[Vector3]
	var y_accum: int = 0
	var y_vel: int = accel_y
	var z_accum: int = 0
	var z_vel: int = accel_z

	for _s in _sections:
		# PSX: cos * (base_radius + (accum >> 8)) >> 12 — cos is 4096-scale, so the
		# float form is cos_float * radius; radius is raw PSX units → PSX_SCALE.
		var eff_radius: float = float(base_radius + (z_accum + _radius_accum >> 8)) * PSX_SCALE
		var height: float = float(y_accum >> 8) * PSX_SCALE
		var verts: Array[Vector3] = []
		for d in dirs:
			verts.append(Vector3(d.x * eff_radius, -height, d.z * eff_radius))
		section_verts.append(verts)

		y_vel += drag_y
		z_vel += drag_z
		y_accum += y_vel
		z_accum += z_vel


	var brightness_row: Array = []
	if _brightness_row_idx >= 0 and _brightness_row_idx < _brightness_table.size():
		brightness_row = _brightness_table[_brightness_row_idx]

	var center: Vector3
	match _anchor_mode:
		0x200: center = anchor_origin   # ORIGIN = caster position
		0x400: center = anchor_target   # TARGET = target position
		0xA00: center = anchor_cursor   # CURSOR = cursor position
		_: center = anchor_target       # Default to target (0x600 coord_transform also targets)

	# PSX calls interp_xyz(emitter, t, &pos) BEFORE the anchor add, so the tube base sits at
	# the anchor plus the emitter position offset lerped on the emitter+0x08 low nibble.
	# (Holy's emitter 5 starts at raw -64 -> 64 world units / 2.29 tiles above the target.)
	center += emitter_config.position_start.lerp(
		emitter_config.position_end, _curve_t_for_slot("position", 0, 0))

	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	for section in range(_sections - 1):
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

		for side in _sides:
			var next_side: int = (side + 1) % _sides

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
