extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## E080 CB40 @0x801C2500 / CB42 @0x801C463C, measured screen-space GT4 banks.
## CB40 has two transposed integer waves, CB42 a fixed 4x4 grid. Both share
## UV/color clocks, byte RGB and same-bucket reverse AddPrim traversal.
## Vault: [[Embedded MIPS Effect Code]]

var _rows: Array = []
var _grid: Array[Vector2i] = []
var _wave := Vector4i.ZERO
var _uv := Vector2i.ZERO
var _rgb := Vector3i(128, 128, 128)
var _cleanup_pending := false

func _ready() -> void:
	_create_cb_mesh()
	_material.set_shader_parameter("gouraud_scale", 255.0 / 128.0)
	_mesh_instance.top_level = true

func _on_init(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	_grid.clear()
	_wave = Vector4i.ZERO
	_uv = Vector2i.ZERO
	_frame_counter = 0
	_cleanup_pending = false
	var data = _load_cb_data()
	_rows = data.get("brightness_table", []) if data else []
	if effect_data.texture:
		_material.set_shader_parameter("effect_texture", effect_data.texture)
		_material.set_shader_parameter("use_texture", true)
	state = State.ANIMATE

static func _sin(angle: int) -> int:
	return roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)

static func _cos(angle: int) -> int:
	return _sin(angle + 1024)

static func _period_step(period: int) -> int:
	# Actual E080 emitters have zero at +0x66. MIPS DIV positive/zero gives
	# LO=-1 (0x801C2A6C), not zero, a clamped divisor, or a script exception.
	return 0x20000 / period if period != 0 else -1

func _value(a: String, b: String, index: int, word: int, nibble: int) -> int:
	var raw: Dictionary = emitter_config.raw_data
	var t := roundi(_curve_t_nibble(word, nibble) * 255.0)
	var start := _ri(raw, a, index)
	return start + (((_ri(raw, b, index) - start) * t) >> 8)

func _half_wrap() -> Vector2i:
	return Vector2i(int(emitter_config.callback_params.get("param_A8", 0)) / 2,
		int(emitter_config.callback_params.get("param_AA", 0)) / 2)

func _on_animate(_emitter_index: int, spawn_counter: int, _channel_index: int) -> void:
	# UV and color use the private completed-animation counter. CB40's wave
	# shape/increments instead sample the invocation age (a3).
	var magnitude := _value("radial_min_start", "radial_min_end", -1, 0, 7)
	var direction := _value("angle_start", "angle_end", 1, 0, 2)
	var half := _half_wrap()
	_uv.x = posmod(_uv.x + ((_cos(direction) * magnitude * 16) >> 12), maxi(1, half.x << 12))
	_uv.y = posmod(_uv.y + ((_sin(direction) * magnitude * 16) >> 12), maxi(1, half.y << 12))
	_rgb = Vector3i(128, 128, 128)
	if emitter_config.flags.get("color_curve_enabled", false):
		var color := _sample_colors()
		_rgb = Vector3i(roundi(color.r * 255), roundi(color.g * 255), roundi(color.b * 255))
	var completed := _frame_counter + 1
	_frame_counter = spawn_counter
	_grid.clear()
	if callback_id == 40:
		var yh := _period_step(_value("accel_min_start", "accel_min_end", 0, 1, 0))
		var yv := _period_step(_value("accel_max_start", "accel_max_end", 0, 1, 0))
		var yr := _value("accel_min_start", "accel_min_end", 1, 1, 0)
		var yo := _value("accel_min_start", "accel_min_end", 2, 1, 0)
		var xh := _period_step(_value("drag_min_start", "drag_min_end", 0, 1, 0))
		var xv := _period_step(_value("drag_max_start", "drag_max_end", 0, 1, 0))
		var xr := _value("drag_min_start", "drag_min_end", 1, 1, 0)
		var xo := _value("drag_min_start", "drag_min_end", 2, 1, 0)
		for row in 9:
			for col in 9:
				var y := -64 + row * 48 + ((_sin(_wave.x + row * yo + col * yh) * ((yr * _cos(_wave.y + row * yv)) >> 4)) >> 20)
				var x := 56 + col * 48 + ((_sin(_wave.z + col * xo + row * xh) * ((xr * _cos(_wave.w + col * xv)) >> 4)) >> 20)
				_grid.append(Vector2i(x - 128, y))
		_wave.x += _value("spread_start", "spread_end", 0, 0, 1)
		_wave.y += _value("spread_start", "spread_end", 1, 0, 1)
		_wave.z += _value("vel_spread_start", "vel_spread_end", 0, 0, 3)
		_wave.w += _value("vel_spread_start", "vel_spread_end", 1, 0, 3)
	else:
		for row in 5:
			for col in 5:
				_grid.append(Vector2i(col * 64, row * 64))
	_frame_counter = completed

func _color(level: int) -> Color:
	return Color(float((_rgb.x * level >> 12) & 255) / 255.0,
		float((_rgb.y * level >> 12) & 255) / 255.0, float((_rgb.z * level >> 12) & 255) / 255.0)

func update_render() -> void:
	_array_mesh.clear_surfaces()
	if _grid.is_empty() or state != State.ANIMATE:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var row_index := int(emitter_config.callback_params.get("param_4E", 0))
	if row_index < 0 or row_index >= _rows.size():
		return
	var row: Array = _rows[row_index]
	# The centred PSX frame's aspect, never the viewport's (gl-ADR-0382).
	var sx := camera.size * DisplayPort.FRAME_ASPECT / 256.0
	var sy := camera.size / 240.0
	var bucket := clampi(int(emitter_config.weight_min_start), 4 if callback_id == 40 else 1, 383)
	var base := camera.global_position - camera.global_basis.z * bucket * DepthMode.UNITS_PER_OT_BUCKET
	var raw: Dictionary = emitter_config.raw_data
	var half := _half_wrap()
	var u := ((_uv.x >> 12) + _ri(raw, "position_start", 0)) & 255
	var v := ((_uv.y >> 12) + _ri(raw, "position_start", 1)) & 255
	var ts := effect_data.texture.get_size() if effect_data.texture else Vector2(128, 256)
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	var cells := 8 if callback_id == 40 else 4
	for r in range(cells - 1, -1, -1):
		for c in range(cells - 1, -1, -1):
			var points: Array[Vector3] = []
			for corner in [Vector2i(c,r), Vector2i(c+1,r), Vector2i(c,r+1), Vector2i(c+1,r+1)]:
				var xy := _grid[corner.y * (cells + 1) + corner.x]
				points.append(base + camera.global_basis.x * (xy.x - 128) * sx - camera.global_basis.y * (xy.y - 120) * sy)
			_quad(positions, colors, uvs, custom, points[0], points[1], points[2], points[3], _color(int(row[r])), _color(int(row[r+1])),
				Vector2(u,v)/ts, Vector2((u+half.x)&255,v)/ts, Vector2(u,(v+half.y)&255)/ts, Vector2((u+half.x)&255,(v+half.y)&255)/ts)
	_build_mesh(_array_mesh, _material, positions, colors, uvs, custom)

func cleanup() -> void:
	_grid.clear()
	if _cleanup_pending:
		force_cleanup()
	else:
		_cleanup_pending = true
	state = State.CLEANUP

func force_cleanup() -> void:
	_grid.clear()
	_cleanup_pending = false
	if _array_mesh:
		_array_mesh.clear_surfaces()
	state = State.INACTIVE
