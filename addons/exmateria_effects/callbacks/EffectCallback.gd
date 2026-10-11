extends Node3D
## Base class for MIPS callback reimplementations.
## Each callback produces custom geometry (ribbons, tubes, etc.) instead of
## normal particle spawning.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Effect Callback Mesh]]
## Vault: [[Effect Execution Model]]
## Vault: [[Embedded MIPS Effect Code]]
## Vault: [[PSX GPU Primitives]]
## Vault: [[Unit Sprite Render Pipeline]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
# Declared on the BASE class only: the ten callback shapes extend this file, and a
# redeclaration in a subclass is `The member "EffectsContent" already exists in parent
# class` — a collision only the stranger rig sees (#1218 paid for that lesson).
const EffectsContent = preload("res://addons/exmateria_effects/install/EffectsContent.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const EffectEmitter = preload("res://addons/exmateria_effects/file_model/EffectEmitter.gd")

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

signal child_spawn_requested(emitter_index: int, position: Vector3, frame: int)

enum State { INACTIVE, INIT, ANIMATE, CLEANUP }
var state: int = State.INACTIVE

# --- Constants ---
const FRAME_MAX: int = 159
const PSX_SCALE: float = 1.0 / 28.0
const BRIGHTNESS_SCALE: float = 4096.0
const ANGLE_SCALE: float = TAU / 4096.0
const UV_WRAP_SCALE: int = 0x1000
const ANGLE_MASK: int = 0xFFF

# Callback blend material. On the engine-fold path (fork >= 4.8 + Forward+, CompositorAutopilot owns
# compositing) the mesh wears the `compositor_layer` variant so the engine folds it into the display
# scratch instead of the transparent color layer — where Pass C would composite the folded result
# OVER it under any folded prim's footprint (the E065 Shiva "spikes pierce the flash" bug). Stock/Mobile and
# the test runner keep the plain additive shader (the fold variant's compositor_layer render_mode is
# Forward+-only).
#
# Both consts are `preload`ed since ADR-0191 dec. 2, which is a change from the String paths that
# were here: the fold shader now resolves on EVERY build, not just the fork. That is safe, and it
# was measured rather than assumed. Under stock 4.7 a minimal project preloading a `compositor_layer`
# shader loads it silently — no error, non-null, `code` intact. The engine only compiles a shader
# when a ShaderMaterial BINDS it, and off-fork `Fold.shader()` hands back the fallback, so the fold
# twin is never bound. (Bind it deliberately off-fork and you do get `SHADER ERROR: Invalid render
# mode: compositor_layer` — from `set_code`, at the bind, not at the load.) The old comment here
# claimed this file was "load()ed lazily and only on the fork"; that rationale is retired, not
# quietly dropped.
const CB_SHADER_NORMAL := preload("res://addons/exmateria_effects/callbacks/effect_callback_additive.gdshader")
const CB_SHADER_FOLD := preload("res://addons/exmateria_effects/callbacks/effect_callback_fold.gdshader")

var callback_id: int = -1
var slot_index: int = -1
var effect_data: EffectData
var emitter_config: EffectEmitter  # The emitter config this callback reads params from

# Anchors (updated by CallbackManager each frame)
var anchor_origin: Vector3 = Vector3.ZERO
var anchor_target: Vector3 = Vector3.ZERO
var anchor_world: Vector3 = Vector3.ZERO
var anchor_cursor: Vector3 = Vector3.ZERO
var caster_facing_angle: float = 0.0

# Common state (subclasses that use these don't need to redeclare)
var _frame_counter: int = 0
var _active: bool = false
var _array_mesh: ArrayMesh
var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _folded: bool = false   # true when the mesh wears the compositor_layer variant (engine-fold path)


func initialize(data: EffectData, slot: int) -> void:
	"""Initialize callback with effect data and slot index."""
	effect_data = data
	slot_index = slot
	state = State.INACTIVE


func invoke(emitter_index: int, spawn_counter: int, channel_index: int) -> void:
	"""Called by CallbackManager when timeline triggers this callback slot."""
	# Store the emitter config for parameter reads
	emitter_config = effect_data.get_emitter(emitter_index)
	if emitter_config == null:
		return

	# PSX process_keyframe_actions writes state=1 only on KEYFRAME HITS
	# (spawn_counter=0). Per-frame for_each calls (spawn_counter>0)
	# just invoke the callback which checks state=2 and runs animate code.
	match state:
		State.INACTIVE:
			state = State.INIT
			_on_init(emitter_index, spawn_counter, channel_index)
		State.INIT:
			_on_init(emitter_index, spawn_counter, channel_index)
		State.ANIMATE:
			if spawn_counter == 0:
				# New keyframe hit → force re-init (PSX writes state=1)
				state = State.INIT
				_on_init(emitter_index, spawn_counter, channel_index)
			else:
				_on_animate(emitter_index, spawn_counter, channel_index)
		State.CLEANUP:
			if spawn_counter == 0:
				# New keyframe hit from different channel/emitter → re-init
				# PSX: timeline sets state=1 on keyframe hits regardless of current state
				state = State.INIT
				_on_init(emitter_index, spawn_counter, channel_index)
			else:
				# Ongoing invocations during cleanup → run cleanup code
				cleanup()


func physics_step() -> void:
	"""Called once per 30 FPS physics frame."""
	pass


func update_render() -> void:
	"""Called each render frame to update ImmediateMesh geometry."""
	pass


func is_active() -> bool:
	"""Returns true if callback has active geometry to render."""
	return state == State.ANIMATE


func cleanup() -> void:
	"""Clean up callback. Stays in CLEANUP state to prevent re-init from
	subsequent timeline invocations (PSX: state=3 → state=0 with null sprite ptr)."""
	state = State.CLEANUP


# --- Virtual methods for subclasses ---

func _on_init(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	"""Handle INIT state. Override in subclass."""
	state = State.ANIMATE


func _on_animate(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	"""Handle ANIMATE state. Override in subclass."""
	pass


# --- Static helpers ---

static func cosine_ease(start_val: float, end_val: float, duration: int, t: int) -> float:
	"""PSX-style cosine ease interpolation (rcos lookup approximation)."""
	if duration <= 0:
		return end_val
	var ratio: float = clampf(float(t) / float(duration), 0.0, 1.0)
	# PSX uses rcos table: (1 - cos(ratio * PI)) / 2
	var ease_factor: float = (1.0 - cos(ratio * PI)) * 0.5
	return start_val + (end_val - start_val) * ease_factor


static func cosine_ease_vec3(start_val: Vector3, end_val: Vector3, duration: int, t: int) -> Vector3:
	"""PSX-style cosine ease for Vector3."""
	return Vector3(
		cosine_ease(start_val.x, end_val.x, duration, t),
		cosine_ease(start_val.y, end_val.y, duration, t),
		cosine_ease(start_val.z, end_val.z, duration, t)
	)


# --- Common helpers for subclasses ---


static func _ri(raw: Dictionary, key: String, index: int = -1) -> int:
	"""Read integer from emitter raw_data. Handles both scalar and array values."""
	var val = raw.get(key, 0)
	if val is Array:
		if index >= 0 and index < val.size():
			return int(val[index])
		return 0
	return int(val)


func _load_cb_data() -> Variant:
	"""Load callback_data.json for this callback's effect and ID."""
	if not effect_data:
		return null
	var path := EffectsContent.callback_data_path(effect_data.name, callback_id)
	if not FileAccess.file_exists(path):
		return null
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	var txt = f.get_as_text()
	f.close()
	var j = JSON.new()
	if j.parse(txt) != OK:
		return null
	return j.data


static func _build_mesh(array_mesh: ArrayMesh, material: ShaderMaterial,
		positions: PackedVector3Array, colors: PackedColorArray,
		uvs: PackedVector2Array, custom0: PackedFloat32Array) -> void:
	"""Build ArrayMesh surface from packed arrays with CUSTOM0 GTE depth."""
	if positions.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	var cf := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, cf)
	array_mesh.surface_set_material(0, material)


static func _quad(pos: PackedVector3Array, col: PackedColorArray,
		uv: PackedVector2Array, c0: PackedFloat32Array,
		v00: Vector3, v01: Vector3, v10: Vector3, v11: Vector3,
		ci: Color, co: Color,
		uv00 := Vector2.ZERO, uv10 := Vector2(1, 0),
		uv01 := Vector2(0, 1), uv11 := Vector2(1, 1)) -> void:
	"""Append a quad (2 triangles) with Gouraud inner/outer colors and CUSTOM0 depth."""
	var centroid: Vector3 = DepthMode.quad_centroid(v00, v01, v10, v11)
	pos.append(v00); col.append(ci); uv.append(uv00)
	pos.append(v01); col.append(ci); uv.append(uv10)
	pos.append(v10); col.append(co); uv.append(uv01)
	pos.append(v01); col.append(ci); uv.append(uv10)
	pos.append(v11); col.append(co); uv.append(uv11)
	pos.append(v10); col.append(co); uv.append(uv01)
	for _i in 6:
		c0.append(centroid.x)
		c0.append(centroid.y)
		c0.append(centroid.z)


func _sample_curve(curve_name: String) -> float:
	"""Sample a named curve at the current frame counter. Returns 0.0-1.0."""
	if emitter_config == null or effect_data == null:
		return 0.0
	var curve_idx: int = emitter_config.curves.get(curve_name, -1)
	if curve_idx < 0:
		return 0.0
	var curve = effect_data.get_curve(curve_idx)
	if curve == null:
		return 0.0
	return curve.sample_by_frame(_frame_counter)


func _sample_colors() -> Color:
	"""Sample R/G/B color curves at current frame. Returns Color(r, g, b, 1)."""
	var r: float = 0.5
	var g: float = 0.5
	var b: float = 0.5
	if emitter_config and effect_data:
		var ri: int = emitter_config.color_curves.get("r", -1)
		var gi: int = emitter_config.color_curves.get("g", -1)
		var bi: int = emitter_config.color_curves.get("b", -1)
		if ri >= 0:
			var c = effect_data.get_curve(ri)
			if c: r = c.sample_by_frame(_frame_counter)
		if gi >= 0:
			var c = effect_data.get_curve(gi)
			if c: g = c.sample_by_frame(_frame_counter)
		if bi >= 0:
			var c = effect_data.get_curve(bi)
			if c: b = c.sample_by_frame(_frame_counter)
	return Color(r, g, b, 1.0)


func _curve_t_nibble(byte_idx: int, bit_shift: int) -> float:
	"""Sample a curve using nibble-packed index from emitter curve_indices_raw.
	byte_idx selects which 4-byte word (0 or 1), bit_shift selects nibble (0-7)."""
	if emitter_config == null or effect_data == null:
		return 0.0
	var raw_bytes: Array = emitter_config.raw_data.get("curve_indices_raw", [])
	if raw_bytes.is_empty():
		return 0.0
	var base: int = byte_idx * 4
	if base + 3 >= raw_bytes.size():
		return 0.0
	var word: int = int(raw_bytes[base]) | (int(raw_bytes[base + 1]) << 8) | (int(raw_bytes[base + 2]) << 16) | (int(raw_bytes[base + 3]) << 24)
	var nibble: int = (word >> (bit_shift * 4)) & 0xF
	var curve_idx: int = nibble - 1
	if curve_idx < 0:
		return 0.0
	var curve = effect_data.get_curve(curve_idx)
	if curve == null:
		return 0.0
	return curve.sample_by_frame(_frame_counter)


func _create_cb_mesh(use_brightness: bool = false) -> void:
	"""Create standard ArrayMesh + MeshInstance3D + ShaderMaterial for callback rendering.
	Set use_brightness=false for callbacks with own brightness tables — that flips the shader's
	use_psx_brightness uniform off, so its brightness stays 1.0 instead of the fold's ÷255→÷128
	display-gouraud gain (PSX_OUTPUT_LEVEL; the old psx_brightness global was retired, ADR-0074)."""
	_array_mesh = ArrayMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _array_mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Route through the compositor when the engine-fold owns compositing (fork + Forward+); otherwise
	# keep the plain additive shader for stock/Mobile. Same uniforms either way, so the per-frame
	# set_shader_parameter calls below and in subclasses are shader-agnostic.
	_folded = Fold.owns()
	var shader := blend_shader()
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("use_texture", false)
	if not use_brightness:
		_material.set_shader_parameter("use_psx_brightness", false)
	add_child(_mesh_instance)
	if _folded and EffectsDebug.particle():
		print("[callback-fold] CB%d slot=%d routed through compositor (compositor_layer)" % [callback_id, slot_index])


static func blend_shader() -> Shader:
	"""This producer's blend shader: the compositor_layer variant when the build folds, else the plain
	additive fallback. The PICK is Fold.shader's (ADR-0191 dec. 2) and is tested on both branches in
	FoldTest; what this pins is which two shaders this producer hands it, and in which order."""
	return Fold.shader(CB_SHADER_FOLD, CB_SHADER_NORMAL)


func stamp_fold_order() -> void:
	"""Self-place this callback in the engine fold via the thin Fold.add decorator (ADR-0074): hand its
	MeshInstance carrier its own compositor_layer material (_material) + its fold-order render_layer_order, so
	the engine interleaves this callback with the particle carriers by TRUE depth (ADR-0009 one-depth
	model). The mesh already computes this depth per-vertex (ot_computed_depth); here we need one
	representative scalar for the whole instance, so we use its world-space AABB center. A lone callback
	quad has no within-stream rank, so rank 0 places it exactly on its OT bucket. No-op unless folded;
	called each frame by CallbackManager after update_render()."""
	if not _folded or _mesh_instance == null or not is_instance_valid(_mesh_instance):
		return
	if not _mesh_instance.is_inside_tree():
		return
	var cam := _mesh_instance.get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := cam.get_camera_transform().affine_inverse()
	var center: Vector3 = _mesh_instance.global_transform * _mesh_instance.get_aabb().get_center()
	# STANDARD (0) matches the callback shader's ot_depth(..., 0).
	var d := DepthMode.ot_order_z(center, view, DepthMode.Mode.STANDARD)
	Fold.add(_mesh_instance, _material, d)


static func _wrap_counter(val: int, half_wrap: int) -> int:
	"""Wrap UV counter within [0, half_wrap * UV_WRAP_SCALE)."""
	if half_wrap <= 0:
		return val
	var limit: int = half_wrap * UV_WRAP_SCALE
	while val >= limit:
		val -= limit
	while val < 0:
		val += limit
	return val
