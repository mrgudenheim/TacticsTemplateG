extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## CB92 - Bicone mesh callback (PSX FUN_801c44a0).
## Renders an expanding diamond/bicone shape at the target position.
## 5 cross-sections from equator to tips, mirrored above and below center.
## 8 sides per cross-section (octagonal, spinning like a top around Y axis).
##
## PSX geometry: widest ring at center (Y=0), tapering to points at ±Y.
## Both radius and height grow proportionally with effective_radius.
## Radius profile [1.0, 0.968, 0.866, 0.661, 0.0] tapers equator→tip.
## Height per section = (section * eff_radius/4) * accel_y / 256.
## 64 GPU quads = 8 sides × 4 section-gaps × 2 halves (upper/lower).
## Vault: [[Effect Callback Mesh]]

const SECTIONS: int = 5
const SIDES: int = 8

# Fallback radius profile if callback data not loaded
const DEFAULT_RADIUS_PROFILE: Array[float] = [1.0, 0.968, 0.866, 0.661, 0.0]

# Parsed callback data (loaded from JSON)
var _brightness_table: Array = []   # 8 values: per-gap bell curve (PSX 0-4096)
var _radius_profile: Array[float] = [1.0, 0.968, 0.866, 0.661, 0.0]  # Normalized

# Bicone state
var _rotation_angle_raw: int = 0  # PSX 0-4095 angle units
var _radius_accum: float = 0.0    # PSX piVar35[0x682]
var _radius_velocity: float = 0.0 # PSX piVar35[0x683]

# Raw emitter values (read once at init)
var _raw_accel_x: float = 0.0   # Radius growth per frame
var _raw_accel_y: float = 0.0   # Y height factor
var _raw_drag_x: float = 0.0    # Radius velocity accumulation
var _raw_drag_y: float = 0.0    # Y factor change per section
var _raw_radial_vel: int = 0    # Rotation speed (PSX angle units/frame)
var _base_radius_raw: float = 0.0  # param_A8

func _ready() -> void:
	_create_cb_mesh(true)

func initialize(data: EffectData, slot: int) -> void:
	super.initialize(data, slot)
	_frame_counter = 0
	_rotation_angle_raw = 0
	_radius_accum = 0.0
	_radius_velocity = 0.0
	_active = false
	_raw_accel_x = 0.0
	_raw_accel_y = 0.0
	_raw_drag_x = 0.0
	_raw_drag_y = 0.0
	_raw_radial_vel = 0
	_base_radius_raw = 0.0
	_brightness_table = []
	_radius_profile = DEFAULT_RADIUS_PROFILE.duplicate()

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	"""INIT -> ANIMATE: read emitter params and start."""
	_active = true
	_frame_counter = 0
	_radius_accum = 0.0
	_radius_velocity = 0.0
	_rotation_angle_raw = 0

	if emitter_config:
		# Read raw acceleration for radius growth and Y height
		var raw_accel = emitter_config.raw_data.get("accel_min_start", [0, 0, 0])
		if raw_accel is Array and raw_accel.size() >= 2:
			_raw_accel_x = float(raw_accel[0])
			_raw_accel_y = float(raw_accel[1])

		# Read raw drag for velocity accumulation
		var raw_drag = emitter_config.raw_data.get("drag_min_start", [0, 0, 0])
		if raw_drag is Array and raw_drag.size() >= 2:
			_raw_drag_x = float(raw_drag[0])
			_raw_drag_y = float(raw_drag[1])

		# Rotation speed from raw radial velocity (PSX angle units per frame)
		_raw_radial_vel = int(emitter_config.raw_data.get("radial_min_start", 0))

		# Base radius from param_A8
		_base_radius_raw = float(emitter_config.callback_params.get("param_A8", 2))

	# Load parsed callback data (brightness table, radius profile)
	if effect_data:
		var cb_data = _load_cb_data()
		if cb_data:
			_brightness_table = cb_data.get("brightness_table", [])
			var raw_profile = cb_data.get("radius_profile", [])
			if not raw_profile.is_empty():
				_radius_profile.clear()
				for v in raw_profile:
					_radius_profile.append(float(v) / BRIGHTNESS_SCALE)

		# Set texture + UV rect on material
		if effect_data.texture and _material:
			_material.set_shader_parameter("effect_texture", effect_data.texture)
			_material.set_shader_parameter("use_texture", true)
			var tex_size = effect_data.texture.get_size()
			if emitter_config and tex_size.x > 0 and tex_size.y > 0:
				var raw_angle = emitter_config.raw_data.get("angle_start", [0, 0, 0])
				var raw_spread = emitter_config.raw_data.get("spread_start", [0, 0, 0])
				if raw_angle is Array and raw_angle.size() >= 2 and raw_spread is Array and raw_spread.size() >= 2:
					_material.set_shader_parameter("uv_rect", Vector4(
						float(raw_angle[0]) / tex_size.x,
						float(raw_angle[1]) / tex_size.y,
						float(raw_spread[0]) / tex_size.x,
						float(raw_spread[1]) / tex_size.y))

	state = State.ANIMATE
	_on_animate(emitter_index, spawn_counter, channel_index)

func _on_animate(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	"""Called each timeline invocation frame."""
	pass

func physics_step() -> void:
	"""Update rotation, radius growth via double-integration."""
	if not _active:
		return

	_frame_counter += 1

	# PSX double-integration: velocity += drag, accum += accel + velocity
	_radius_velocity += _raw_drag_x
	_radius_accum += _raw_accel_x + _radius_velocity

	# PSX rotation: angle += radial_vel, wrapped to 0-4095
	_rotation_angle_raw = (_rotation_angle_raw + _raw_radial_vel) % 4096

	# Auto-deactivation: check if lifetime exceeded
	if emitter_config:
		var max_life: int = emitter_config.lifetime_max_start
		if max_life > 0 and _frame_counter >= max_life:
			_active = false
			state = State.INACTIVE

func update_render() -> void:
	"""Rebuild bicone mesh: diamond shape expanding from center."""
	if _array_mesh == null:
		return

	_array_mesh.clear_surfaces()

	if not _active or state != State.ANIMATE:
		return

	if emitter_config == null or effect_data == null:
		return

	# Effective radius: base + accumulated growth >> 8 (PSX shift)
	var effective_radius_raw: float = _base_radius_raw + _radius_accum / 256.0
	if effective_radius_raw < 0.5:
		return

	# Sample color curves for this frame
	var r_val: float = 1.0
	var g_val: float = 1.0
	var b_val: float = 1.0

	if emitter_config.flags.get("color_curve_enabled", false):
		var r_idx: int = emitter_config.color_curves.get("r", -1)
		var g_idx: int = emitter_config.color_curves.get("g", -1)
		var b_idx: int = emitter_config.color_curves.get("b", -1)

		if r_idx >= 0:
			var r_curve = effect_data.get_curve(r_idx)
			if r_curve:
				r_val = r_curve.sample_by_frame(_frame_counter)
		if g_idx >= 0:
			var g_curve = effect_data.get_curve(g_idx)
			if g_curve:
				g_val = g_curve.sample_by_frame(_frame_counter)
		if b_idx >= 0:
			var b_curve = effect_data.get_curve(b_idx)
			if b_curve:
				b_val = b_curve.sample_by_frame(_frame_counter)

	# Auto-deactivate when color curves reach zero
	if r_val < 0.001 and g_val < 0.001 and b_val < 0.001:
		_active = false
		state = State.INACTIVE
		return

	# Center position: anchor_target + emitter Y offset
	var center: Vector3 = anchor_target + Vector3(0, emitter_config.position_start.y, 0)

	# 8 direction vectors in XZ plane at 45° intervals from rotation angle
	var angle_rad: float = float(_rotation_angle_raw) * ANGLE_SCALE
	var dirs: Array[Vector3] = []
	for i in range(SIDES):
		var a: float = angle_rad + TAU * float(i) / float(SIDES)
		dirs.append(Vector3(cos(a), 0.0, sin(a)))

	# Pre-compute cross-section data for 5 sections
	# Section 0 = equator (widest), Section 4 = tips (zero width)
	var section_xz_radius: Array[float] = []  # XZ radius per section
	var section_y_disp: Array[float] = []      # Y displacement per section

	var y_accum: float = 0.0
	var y_factor: float = _raw_accel_y
	for s in range(SECTIONS):
		# XZ radius: profile * effective_radius, converted to Godot units
		section_xz_radius.append(_radius_profile[s] * effective_radius_raw * PSX_SCALE)
		# Y displacement: y_accum * y_factor / 256, converted to Godot units
		section_y_disp.append(y_accum * y_factor / 256.0 * PSX_SCALE)
		# Advance accumulators (PSX: y_accum += effective_radius >> 2)
		y_accum += effective_radius_raw / 4.0
		y_factor += _raw_drag_y

	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()

	# Draw quads between adjacent sections, for both upper (+Y) and lower (-Y) halves
	var use_brightness_table: bool = _brightness_table.size() >= 8

	for s in range(SECTIONS - 1):
		var r0: float = section_xz_radius[s]
		var r1: float = section_xz_radius[s + 1]
		var y0: float = section_y_disp[s]
		var y1: float = section_y_disp[s + 1]

		var bright_upper: float
		var bright_lower: float
		if use_brightness_table:
			bright_upper = float(_brightness_table[3 - s]) / BRIGHTNESS_SCALE
			bright_lower = float(_brightness_table[4 + s]) / BRIGHTNESS_SCALE
		else:
			bright_upper = (_radius_profile[s] + _radius_profile[s + 1]) * 0.5
			bright_lower = bright_upper

		var col_upper := Color(r_val * bright_upper, g_val * bright_upper, b_val * bright_upper, 1.0)
		var col_lower := Color(r_val * bright_lower, g_val * bright_lower, b_val * bright_lower, 1.0)

		for side in range(SIDES):
			var d0: Vector3 = dirs[side]
			var d1: Vector3 = dirs[(side + 1) % SIDES]

			# Upper half (+Y)
			var v00u: Vector3 = center + d0 * r0 + Vector3(0, y0, 0)
			var v01u: Vector3 = center + d1 * r0 + Vector3(0, y0, 0)
			var v10u: Vector3 = center + d0 * r1 + Vector3(0, y1, 0)
			var v11u: Vector3 = center + d1 * r1 + Vector3(0, y1, 0)

			_quad(positions, colors, uvs, custom0,
				v00u, v01u, v10u, v11u, col_upper, col_upper)

			# Lower half (-Y)
			var v00d: Vector3 = center + d0 * r0 + Vector3(0, -y0, 0)
			var v01d: Vector3 = center + d1 * r0 + Vector3(0, -y0, 0)
			var v10d: Vector3 = center + d0 * r1 + Vector3(0, -y1, 0)
			var v11d: Vector3 = center + d1 * r1 + Vector3(0, -y1, 0)

			_quad(positions, colors, uvs, custom0,
				v00d, v01d, v10d, v11d, col_lower, col_lower)

	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom0)

func cleanup() -> void:
	_frame_counter = 0
	_rotation_angle_raw = 0
	_radius_accum = 0.0
	_radius_velocity = 0.0
	_active = false
	_raw_accel_x = 0.0
	_raw_accel_y = 0.0
	_raw_drag_x = 0.0
	_raw_drag_y = 0.0
	_raw_radial_vel = 0
	_base_radius_raw = 0.0
	_brightness_table = []
	_radius_profile = DEFAULT_RADIUS_PROFILE.duplicate()
	if _array_mesh:
		_array_mesh.clear_surfaces()
	super.cleanup()
