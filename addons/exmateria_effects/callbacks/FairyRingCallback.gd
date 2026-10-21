extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## E077 CB35, 0x801C2500: 80 screen-space GT4s, six rings, four quadrants.
## Kept separate from the approximate RadialRing/SpiralMesh transcriptions:
## integer ring integration, angle <<4, per-ring centers, and INIT/no draw matter.
## Vault: [[Embedded MIPS Effect Code]]

var _rows: Array = []
var _uv_accum := Vector2i.ZERO
var _has_frame := false
var _cleanup_pending := false
var _rings: Array = []
var _centers: Array[Vector2i] = []
var _colors_raw := Vector3i(128, 128, 128)

func _ready() -> void:
	_create_cb_mesh()
	_material.set_shader_parameter("gouraud_scale", 255.0 / 128.0)
	_mesh_instance.top_level = true

func _on_init(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	_uv_accum = Vector2i.ZERO
	_frame_counter = 0
	_has_frame = false
	_cleanup_pending = false
	var data = _load_cb_data()
	_rows = data.get("brightness_table", []) if data else []
	if effect_data.texture:
		_material.set_shader_parameter("effect_texture", effect_data.texture)
		_material.set_shader_parameter("use_texture", true)
	state = State.ANIMATE

static func _sin(a: int) -> int:
	return roundi(sin(float(a & 4095) * TAU / 4096.0) * 4096.0)

static func _cos(a: int) -> int:
	return _sin(a + 1024)

func _value(a: String, b: String, index: int, word: int, nibble: int) -> int:
	var raw: Dictionary = emitter_config.raw_data
	var t := roundi(_curve_t_nibble(word, nibble) * 255.0)
	var start: int = _ri(raw, a, index) if raw.has(a) else int(emitter_config.get(a))
	var end: int = _ri(raw, b, index) if raw.has(b) else int(emitter_config.get(b))
	return start + (((end - start) * t) >> 8)

func _on_animate(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	# CB35 uses its own completed-animation counter, not the timeline age.
	var radius := _value("spread_start", "spread_end", 0, 0, 1) << 12
	var growth := _value("radial_min_start", "radial_min_end", -1, 0, 7) << 4
	var acceleration := _value("accel_min_start", "accel_min_end", 0, 1, 0) << 4
	var angle := _value("inertia_min_start", "inertia_min_end", -1, 0, 4) << 4
	var angular_velocity := _value("target_start", "target_end", 0, 1, 3)
	var angular_acceleration := _value("spawn_interval_start", "spawn_interval_end", -1, 1, 6)
	var center := Vector2i(_value("position_start", "position_end", 0, 0, 0),
		_value("position_start", "position_end", 1, 0, 0))
	var direction := _value("angle_start", "angle_end", 0, 0, 2) << 4
	var magnitude := _value("angle_start", "angle_end", 1, 0, 2)
	var velocity := Vector2i((_cos(direction) * magnitude * 16) >> 12,
		(_sin(direction) * magnitude * 16) >> 12)
	direction = _value("vel_spread_start", "vel_spread_end", 0, 0, 3) << 4
	magnitude = _value("vel_spread_start", "vel_spread_end", 1, 0, 3)
	var accel := Vector2i((_cos(direction) * magnitude * 16) >> 12,
		(_sin(direction) * magnitude * 16) >> 12)
	_rings.clear()
	_centers.clear()
	for ring in 6:
		var vertices: Array[Vector2i] = []
		for v in 4:
			vertices.append(Vector2i((_cos(v * 256 + angle) * (radius >> 12)) >> 12,
				(_sin(v * 256 + angle) * (radius >> 12)) >> 12))
		vertices.append(Vector2i(-vertices[0].y, vertices[0].x))
		_rings.append(vertices)
		_centers.append(center)
		center += Vector2i(velocity.x >> 12, velocity.y >> 12)
		velocity += accel
		radius += growth
		growth += acceleration
		angle += angular_velocity
		angular_velocity += angular_acceleration
	var half := _half_wrap()
	_uv_accum.x = posmod(_uv_accum.x + (_value("drag_min_start", "drag_min_end", 0, 1, 1) << 4), maxi(1, half.x << 12))
	_uv_accum.y = posmod(_uv_accum.y + (_value("drag_min_start", "drag_min_end", 1, 1, 1) << 4), maxi(1, half.y << 12))
	_colors_raw = Vector3i(128, 128, 128)
	if emitter_config.flags.get("color_curve_enabled", false):
		var color := _sample_colors()
		_colors_raw = Vector3i(roundi(color.r * 255), roundi(color.g * 255), roundi(color.b * 255))
	_frame_counter = (_frame_counter + 1) % 160
	_has_frame = true

func _half_wrap() -> Vector2i:
	return Vector2i(int(emitter_config.callback_params.get("param_A8", 0)) / 2,
		int(emitter_config.callback_params.get("param_AA", 0)) / 2)

static func _rotate(v: Vector2i, q: int) -> Vector2i:
	match q:
		1: return Vector2i(-v.y, v.x)
		2: return -v
		3: return Vector2i(v.y, -v.x)
	return v

func update_render() -> void:
	_array_mesh.clear_surfaces()
	if not _has_frame or state != State.ANIMATE:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var row_index := int(emitter_config.callback_params.get("param_4E", 0))
	if row_index < 0 or row_index >= _rows.size():
		return
	var row: Array = _rows[row_index]
	var colors_raw := _colors_raw
	# The centred PSX frame's aspect, never the viewport's (gl-ADR-0382).
	var sx := camera.size * DisplayPort.FRAME_ASPECT / 256.0
	var sy := camera.size / 240.0
	var bucket := clampi(int(emitter_config.weight_min_start), 4, 383)
	var base := camera.global_position - camera.global_basis.z * bucket * DepthMode.UNITS_PER_OT_BUCKET
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	var raw: Dictionary = emitter_config.raw_data
	var half := _half_wrap()
	var u := ((_uv_accum.x >> 12) + _ri(raw, "homing_min_start")) & 255
	var v := ((_uv_accum.y >> 12) + _ri(raw, "homing_max_start")) & 255
	var texture_size := effect_data.texture.get_size() if effect_data.texture else Vector2(128, 256)
	# AddPrim prepends each GT4 to the same OT bucket: traverse in reverse.
	for band in range(4, -1, -1):
		var ci := Color(float((colors_raw.x * int(row[band])) >> 12) / 255.0,
			float((colors_raw.y * int(row[band])) >> 12) / 255.0, float((colors_raw.z * int(row[band])) >> 12) / 255.0)
		var co := Color(float((colors_raw.x * int(row[band + 1])) >> 12) / 255.0,
			float((colors_raw.y * int(row[band + 1])) >> 12) / 255.0, float((colors_raw.z * int(row[band + 1])) >> 12) / 255.0)
		for edge in range(3, -1, -1):
			for quadrant in range(3, -1, -1):
				var points: Array[Vector3] = []
				for corner in [Vector2i(band, edge), Vector2i(band, edge + 1), Vector2i(band + 1, edge), Vector2i(band + 1, edge + 1)]:
					var xy: Vector2i = _centers[corner.x] + _rotate(_rings[corner.x][corner.y], quadrant)
					points.append(base + camera.global_basis.x * (xy.x - 128) * sx - camera.global_basis.y * (xy.y - 120) * sy)
				_quad(positions, colors, uvs, custom, points[0], points[1], points[2], points[3], ci, co,
					Vector2(u, v) / texture_size, Vector2((u + half.x) & 255, v) / texture_size,
					Vector2(u, (v + half.y) & 255) / texture_size, Vector2((u + half.x) & 255, (v + half.y) & 255) / texture_size)
	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom)

func cleanup() -> void:
	_has_frame = false
	if _cleanup_pending:
		force_cleanup()
	else:
		_cleanup_pending = true
	state = State.CLEANUP

func force_cleanup() -> void:
	_has_frame = false
	_cleanup_pending = false
	_rings.clear()
	_centers.clear()
	if _array_mesh:
		_array_mesh.clear_surfaces()
	state = State.INACTIVE
