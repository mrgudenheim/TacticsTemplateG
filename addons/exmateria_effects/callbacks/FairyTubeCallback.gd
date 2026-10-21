extends "res://addons/exmateria_effects/callbacks/WorldTubeCallback.gd"
## E077 CB36 @0x801C3C7C: WorldTube topology, integer per-invocation bank.
## Avoid changing sibling callbacks' clocks/anchors while correcting Fairy's.
## Vault: [[Embedded MIPS Effect Code]]

var _bank_vertices := PackedVector3Array()
var _bank_colors := PackedColorArray()
var _bank_uvs := PackedVector2Array()
var _bank_depth := PackedFloat32Array()
var _cleanup_pending := false

func _ready() -> void:
	super._ready()
	_material.set_shader_parameter("uv_rect", Vector4(0, 0, 1, 1))
	_material.set_shader_parameter("use_psx_brightness", false)
	_material.set_shader_parameter("gouraud_scale", 255.0 / 128.0)

func _on_init(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	super._on_init(emitter_index, spawn_counter, channel_index)
	_clear_bank()
	_cleanup_pending = false

func physics_step() -> void:
	# ROM advances ONLY during the callback invocation, never during rendering.
	pass

func _value(start: int, end: int, word: int, nibble: int) -> int:
	return start + (((end - start) * roundi(_curve_t_nibble(word, nibble) * 255.0)) >> 8)

static func _sin(a: int) -> int:
	return roundi(sin(float(a & 4095) * TAU / 4096.0) * 4096.0)

static func _cos(a: int) -> int:
	return _sin(a + 1024)

func _on_animate(_emitter_index: int, spawn_counter: int, _channel_index: int) -> void:
	_frame_counter = spawn_counter
	_clear_bank()
	var radius := _value(_base_radius_start, _base_radius_end, 1, 4)
	var acceleration := Vector3i(_value(_accel_x_start, _accel_x_end, 1, 0),
		_value(_accel_y_start, _accel_y_end, 1, 0), _value(_accel_z_start, _accel_z_end, 1, 0))
	var drag := Vector3i(_value(_drag_x_start, _drag_x_end, 1, 1),
		_value(_drag_y_start, _drag_y_end, 1, 1), _value(_drag_z_start, _drag_z_end, 1, 1))
	_rotation_angle_raw = (_rotation_angle_raw + _value(_rot_vel_start, _rot_vel_end, 0, 7)) & 4095
	_uv_counter = (_uv_counter + _uv_step) & 65535
	if _uv_counter >= 32768:
		_uv_counter -= 65536
	if _uv_counter > _uv_height * 256:
		_uv_counter -= _uv_height * 256
	if _uv_counter < 0:
		_uv_counter += _uv_height * 256
	var raw: Dictionary = emitter_config.raw_data
	var center_psx := Vector3i.ZERO
	var t := roundi(_curve_t_nibble(0, 0) * 255.0)
	for axis in 3:
		var start := _ri(raw, "position_start", axis)
		# interp_xyz's store helper 0x801A8BF8 also uses arithmetic >>8.
		center_psx[axis] = start + (((_ri(raw, "position_end", axis) - start) * t) >> 8)
	var anchor := Vector3.ZERO
	match int(raw.get("animation_target_flag", 0)) & 14:
		2: anchor = anchor_world
		4: anchor = anchor_origin
		6: anchor = anchor_target
		10: anchor = Vector3(anchor_cursor.x, 0, anchor_cursor.z) # get_cursor_pos adds X/Z only
	var center := anchor + Vector3(center_psx.x, -center_psx.y, -center_psx.z) / 28.0
	var rings: Array = []
	var y := 0
	var z := 0
	var vy := acceleration.y
	var vz := acceleration.z
	for ring in 9:
		var r := radius + ((z + _radius_accum) >> 8)
		var a := Vector2i((_cos(_rotation_angle_raw) * r) >> 12, (_sin(_rotation_angle_raw) * r) >> 12)
		var b := Vector2i((_cos(_rotation_angle_raw + 512) * r) >> 12, (_sin(_rotation_angle_raw + 512) * r) >> 12)
		var points: Array[Vector3] = []
		for p in [a, b, Vector2i(-a.y,a.x), Vector2i(-b.y,b.x), -a, -b, Vector2i(a.y,-a.x), Vector2i(b.y,-b.x)]:
			points.append(center + Vector3(p.x, -(y >> 8), -p.y) / 28.0)
		rings.append(points)
		vy += drag.y
		vz += drag.z
		y += vy
		z += vz
	_radius_velocity += drag.x
	_radius_accum += acceleration.x + _radius_velocity
	var bytes := Vector3i(128,128,128)
	if emitter_config.flags.get("color_curve_enabled", false):
		var color := _sample_colors()
		bytes = Vector3i(roundi(color.r * 255), roundi(color.g * 255), roundi(color.b * 255))
	if _brightness_row_idx < 0 or _brightness_row_idx >= _brightness_table.size():
		return
	var row: Array = _brightness_table[_brightness_row_idx]
	var u := _value(_ri(raw,"angle_start",0), _ri(raw,"angle_end",0), 0, 2) & 255
	var v := (_value(_ri(raw,"angle_start",1), _ri(raw,"angle_end",1), 0, 2) + ((_uv_counter & 65535) >> 8)) & 255
	var texture_size := effect_data.texture.get_size() if effect_data.texture else Vector2(128,256)
	# Preserve packet corner correspondence; the shared mesh path owns depth.
	# Per-face OT traversal/framebuffer ordering is not certified by vertex parity.
	for ring in 8:
		var ci := Color(float((bytes.x * int(row[ring])) >> 12) / 255.0, float((bytes.y * int(row[ring])) >> 12) / 255.0, float((bytes.z * int(row[ring])) >> 12) / 255.0)
		var co := Color(float((bytes.x * int(row[ring + 1])) >> 12) / 255.0, float((bytes.y * int(row[ring + 1])) >> 12) / 255.0, float((bytes.z * int(row[ring + 1])) >> 12) / 255.0)
		for side in 8:
			var next := (side + 1) % 8
			# PSX GT4 v0/v1 are the next ring, v2/v3 the preceding ring.
			_quad(_bank_vertices, _bank_colors, _bank_uvs, _bank_depth,
				rings[ring + 1][side], rings[ring + 1][next], rings[ring][side], rings[ring][next], co, ci,
				Vector2(u,v) / texture_size, Vector2((u + _uv_width) & 255,v) / texture_size,
				Vector2(u,(v + _uv_height) & 255) / texture_size, Vector2((u + _uv_width) & 255,(v + _uv_height) & 255) / texture_size)

func _clear_bank() -> void:
	_bank_vertices.clear()
	_bank_colors.clear()
	_bank_uvs.clear()
	_bank_depth.clear()

func update_render() -> void:
	_array_mesh.clear_surfaces()
	if state == State.ANIMATE:
		_build_mesh(_array_mesh, _material, _bank_vertices, _bank_colors, _bank_uvs, _bank_depth)

func cleanup() -> void:
	_clear_bank()
	if _cleanup_pending:
		super.cleanup()
	_cleanup_pending = true
	state = State.CLEANUP

func force_cleanup() -> void:
	_clear_bank()
	super.cleanup()
	_cleanup_pending = false
	state = State.INACTIVE
