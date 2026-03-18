class_name VfxRenderer
extends Node3D
## Particle renderer using individual MeshInstance3D nodes with dual-pass STP rendering
## Ported from godot-learning's EffectParticleRenderer, adapted for binary-parsed VfxFrame data
##
## Uses stable mesh assignment: each particle UID keeps the same mesh indices across frames,
## preventing cross-particle material flicker when sort order changes.

const Z_EPSILON: float = 0.001
const GROWTH_BATCH_SIZE: int = 128
const OFFSCREEN_POSITION := Vector3(0, -10000, 0)

const DEPTH_MODE_Z_OFFSETS: Array[float] = [
	0.0,    # Mode 0: STANDARD
	-0.05,  # Mode 1: PULL_FORWARD_8
	-0.15,  # Mode 2: FIXED_FRONT
	0.5,    # Mode 3: FIXED_BACK
	-0.1,   # Mode 4: FIXED_16
	-0.1,   # Mode 5: PULL_FORWARD_16
]

var _shared_quad: QuadMesh
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _pool_size: int = 0

var _opaque_shader: Shader
var _blend_shaders: Array[Shader] = []  # [mode0, mode1, mode2, mode3]

var _texture_size: Vector2 = Vector2(128, 256)
var _vfx_data: VisualEffectData

# Stable mesh assignment: particle UID → assigned mesh indices
var _particle_mesh_map: Dictionary = {}  # int (uid) → PackedInt32Array (mesh indices)
var _free_mesh_indices: Array[int] = []

# Pre-allocated sort buffers
var _sort_keys: PackedFloat64Array = []
var _sort_particle_idx: PackedInt32Array = []
var _sort_frame_idx: PackedInt32Array = []
var _sort_frameset_idx: PackedInt32Array = []
var _sort_opaque: Array[bool] = []
var _sort_indices: Array[int] = []
var _sort_capacity: int = 0
var _sort_count: int = 0
var _sort_comparator: Callable

# Cached per-emitter align_to_velocity flags
var _emitter_align_flags: Array[bool] = []


func initialize(vfx_data: VisualEffectData, initial_pool_size: int = 4096) -> void:
	_vfx_data = vfx_data

	_shared_quad = QuadMesh.new()
	_shared_quad.size = Vector2(1.0, 1.0)

	# Load shaders
	_opaque_shader = preload("res://src/file_formats/vfx/shaders/effect_particle_opaque.gdshader")
	_blend_shaders = [
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode0.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode1.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode2.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode3.gdshader"),
	]

	if vfx_data.texture:
		_texture_size = Vector2(vfx_data.vfx_spr.width, vfx_data.vfx_spr.height)

	# Create initial mesh pool — all start as free
	_grow_pool(initial_pool_size)
	_free_mesh_indices.clear()
	for i in range(_pool_size):
		_free_mesh_indices.append(i)

	# Setup sort buffers
	_sort_capacity = initial_pool_size * 2
	_sort_keys.resize(_sort_capacity)
	_sort_particle_idx.resize(_sort_capacity)
	_sort_frame_idx.resize(_sort_capacity)
	_sort_frameset_idx.resize(_sort_capacity)
	_sort_opaque.resize(_sort_capacity)
	_sort_indices.resize(_sort_capacity)
	_sort_comparator = func(a: int, b: int) -> bool: return _sort_keys[a] < _sort_keys[b]

	# Cache align_to_velocity flags
	_emitter_align_flags.clear()
	for emitter: VfxEmitter in vfx_data.emitters:
		_emitter_align_flags.append(emitter.align_to_velocity)


func render(particles: Array[VfxParticleData], vfx_data: VisualEffectData) -> void:
	if particles.is_empty():
		_release_all_meshes()
		return

	var frame_camera: Camera3D = get_viewport().get_camera_3d()

	# Step 1: Determine which particles are renderable and how many meshes each needs
	# Each frameset frame generates 2 sort entries (opaque + semi-trans), so needs 2 mesh slots
	var renderable_uids: Dictionary = {}  # uid → particle index
	var uid_mesh_need: Dictionary = {}    # uid → number of mesh slots needed

	for pi in range(particles.size()):
		var p: VfxParticleData = particles[pi]
		if p.age == 0 or not p.active or p.is_dead():
			continue

		var frameset_idx: int = p.current_frameset
		if frameset_idx < 0 or frameset_idx >= vfx_data.framesets.size():
			continue

		var frameset: VisualEffectData.VfxFrameSet = vfx_data.framesets[frameset_idx]
		if frameset.frameset.is_empty():
			continue

		renderable_uids[p.uid] = pi
		uid_mesh_need[p.uid] = frameset.frameset.size() * 2  # opaque + semi-trans per frame

	# Step 2: Release meshes for particles no longer present
	var stale_uids: Array[int] = []
	for uid: int in _particle_mesh_map:
		if not renderable_uids.has(uid):
			stale_uids.append(uid)

	for uid: int in stale_uids:
		var mesh_indices: PackedInt32Array = _particle_mesh_map[uid]
		for mi in mesh_indices:
			_meshes[mi].visible = false
			_meshes[mi].position = OFFSCREEN_POSITION
			_free_mesh_indices.append(mi)
		_particle_mesh_map.erase(uid)

	# Step 3: Adjust mesh count per particle (grow/shrink as frameset changes)
	for uid: int in renderable_uids:
		var needed: int = uid_mesh_need[uid]
		var current: PackedInt32Array = _particle_mesh_map.get(uid, PackedInt32Array())
		var have: int = current.size()

		if have < needed:
			# Borrow more meshes
			var to_borrow: int = needed - have
			for _i in range(to_borrow):
				var mi: int = _borrow_mesh_index()
				current.append(mi)
			_particle_mesh_map[uid] = current
		elif have > needed:
			# Return excess meshes
			for i in range(needed, have):
				_meshes[current[i]].visible = false
				_meshes[current[i]].position = OFFSCREEN_POSITION
				_free_mesh_indices.append(current[i])
			current = current.slice(0, needed)
			_particle_mesh_map[uid] = current
		# else: have == needed, no change

	# Step 4: Build sort entries (same logic as before, but track which particle owns each entry)
	const OPAQUE_PASS_OFFSET: float = 0.0
	const SEMI_TRANS_PASS_OFFSET: float = 100000.0

	_sort_count = 0

	# Also track per-particle sort entry indices so we can map sorted entries back to mesh slots
	# _sort_uid[i] = particle uid for sort entry i
	# _sort_local_idx[i] = which mesh slot within that particle's allocation (0, 1, 2, ...)
	var _sort_uid: PackedInt64Array = []
	var _sort_local_idx: PackedInt32Array = []
	_sort_uid.resize(_sort_capacity)
	_sort_local_idx.resize(_sort_capacity)

	for uid: int in renderable_uids:
		var pi: int = renderable_uids[uid]
		var p: VfxParticleData = particles[pi]
		var frameset_idx: int = p.current_frameset
		var frameset: VisualEffectData.VfxFrameSet = vfx_data.framesets[frameset_idx]

		var depth_mode: int = clampi(p.current_depth_mode, 0, DEPTH_MODE_Z_OFFSETS.size() - 1)
		var depth_z_offset: float = DEPTH_MODE_Z_OFFSETS[depth_mode]
		var local_slot: int = 0

		for fi in range(frameset.frameset.size()):
			var frame_z_offset: float = -fi * Z_EPSILON
			var total_z_offset: float = frame_z_offset + depth_z_offset
			var base_sort_key: float = p.channel_index * VfxConstants.CHANNEL_SORT_SPACING + (-total_z_offset)

			# Ensure sort buffers have room
			var needed_cap: int = _sort_count + 2
			if needed_cap > _sort_capacity:
				_ensure_sort_capacity(needed_cap)
				_sort_uid.resize(_sort_capacity)
				_sort_local_idx.resize(_sort_capacity)

			# Opaque pass entry
			_sort_keys[_sort_count] = OPAQUE_PASS_OFFSET + base_sort_key
			_sort_particle_idx[_sort_count] = pi
			_sort_frame_idx[_sort_count] = fi
			_sort_frameset_idx[_sort_count] = frameset_idx
			_sort_opaque[_sort_count] = true
			_sort_uid[_sort_count] = uid
			_sort_local_idx[_sort_count] = local_slot
			local_slot += 1
			_sort_count += 1

			# Semi-trans pass entry
			_sort_keys[_sort_count] = SEMI_TRANS_PASS_OFFSET + base_sort_key
			_sort_particle_idx[_sort_count] = pi
			_sort_frame_idx[_sort_count] = fi
			_sort_frameset_idx[_sort_count] = frameset_idx
			_sort_opaque[_sort_count] = false
			_sort_uid[_sort_count] = uid
			_sort_local_idx[_sort_count] = local_slot
			local_slot += 1
			_sort_count += 1

	# Step 5: Sort by key to determine draw order
	_sort_indices.resize(_sort_count)
	for i in range(_sort_count):
		_sort_indices[i] = i
	_sort_indices.sort_custom(_sort_comparator)

	# Step 6: Render using stable mesh assignment
	# Sort determines draw ORDER (render_priority), but each entry uses its particle's own mesh slot
	for draw_order in range(_sort_count):
		var idx: int = _sort_indices[draw_order]
		var uid: int = _sort_uid[idx]
		var local_idx: int = _sort_local_idx[idx]
		var p: VfxParticleData = particles[_sort_particle_idx[idx]]
		var fs: VisualEffectData.VfxFrameSet = vfx_data.framesets[_sort_frameset_idx[idx]]
		var vfx_frame: VisualEffectData.VfxFrame = fs.frameset[_sort_frame_idx[idx]]
		var align: bool = p.emitter_index >= 0 and p.emitter_index < _emitter_align_flags.size() and _emitter_align_flags[p.emitter_index]

		var mesh_indices: PackedInt32Array = _particle_mesh_map[uid]
		var mi: int = mesh_indices[local_idx]
		var mesh: MeshInstance3D = _meshes[mi]
		var mat: ShaderMaterial = _materials[mi]

		# Set render priority based on draw order so GPU draws in correct sequence
		mat.render_priority = draw_order + 1

		_render_frame(mesh, mat, p, vfx_frame, _sort_opaque[idx], frame_camera, align)



func _render_frame(mesh: MeshInstance3D, mat: ShaderMaterial, p: VfxParticleData,
		vfx_frame: VisualEffectData.VfxFrame, is_opaque_pass: bool,
		frame_camera: Camera3D, align_to_velocity: bool) -> void:
	# Corner positions from VfxFrame (s16 PSX units) + animation offset
	var anim_offset: Vector2 = p.anim_offset
	var tl_x: float = float(vfx_frame.top_left_xy.x) + anim_offset.x
	var tl_y: float = float(vfx_frame.top_left_xy.y) + anim_offset.y
	var tr_x: float = float(vfx_frame.top_right_xy.x) + anim_offset.x
	var tr_y: float = float(vfx_frame.top_right_xy.y) + anim_offset.y
	var bl_x: float = float(vfx_frame.bottom_left_xy.x) + anim_offset.x
	var bl_y: float = float(vfx_frame.bottom_left_xy.y) + anim_offset.y
	var br_x: float = float(vfx_frame.bottom_right_xy.x) + anim_offset.x
	var br_y: float = float(vfx_frame.bottom_right_xy.y) + anim_offset.y

	# Velocity-based rotation
	if align_to_velocity:
		var velocity: Vector3 = p.velocity
		if velocity.length_squared() > 0.0001 and frame_camera:
			var cam_basis: Basis = frame_camera.global_transform.basis
			var screen_vel: Vector3 = cam_basis.inverse() * velocity
			var angle: float = atan2(-screen_vel.y, screen_vel.x)

			var cos_a: float = cos(angle)
			var sin_a: float = sin(angle)

			var new_tl_x: float = tl_x * cos_a - tl_y * sin_a
			var new_tl_y: float = tl_x * sin_a + tl_y * cos_a
			var new_tr_x: float = tr_x * cos_a - tr_y * sin_a
			var new_tr_y: float = tr_x * sin_a + tr_y * cos_a
			var new_bl_x: float = bl_x * cos_a - bl_y * sin_a
			var new_bl_y: float = bl_x * sin_a + bl_y * cos_a
			var new_br_x: float = br_x * cos_a - br_y * sin_a
			var new_br_y: float = br_x * sin_a + br_y * cos_a

			tl_x = new_tl_x; tl_y = new_tl_y
			tr_x = new_tr_x; tr_y = new_tr_y
			bl_x = new_bl_x; bl_y = new_bl_y
			br_x = new_br_x; br_y = new_br_y

	# Position mesh at particle world position
	var t := Transform3D.IDENTITY
	t.origin = p.position
	mesh.transform = t

	# UV rect (normalized) from VfxFrame
	var uv_rect_data := Vector4(
		float(vfx_frame.top_left_uv.x) / _texture_size.x,
		float(vfx_frame.top_left_uv.y) / _texture_size.y,
		float(vfx_frame.uv_width) / _texture_size.x,
		float(vfx_frame.uv_height) / _texture_size.y
	)

	# Swap shader for opaque vs semi-trans pass
	if is_opaque_pass:
		mat.shader = _opaque_shader
	else:
		var blend_mode: int = clampi(vfx_frame.semi_transparency_mode, 0, 3)
		mat.shader = _blend_shaders[blend_mode]

	# Set per-frame shader parameters
	mat.set_shader_parameter("corner_tl", Vector2(tl_x, tl_y))
	mat.set_shader_parameter("corner_tr", Vector2(tr_x, tr_y))
	mat.set_shader_parameter("corner_bl", Vector2(bl_x, bl_y))
	mat.set_shader_parameter("corner_br", Vector2(br_x, br_y))
	mat.set_shader_parameter("uv_rect_data", uv_rect_data)

	mesh.visible = true


func set_z_bias(value: float) -> void:
	for mat: ShaderMaterial in _materials:
		mat.set_shader_parameter("z_bias", value)


func _borrow_mesh_index() -> int:
	if _free_mesh_indices.is_empty():
		# Grow pool and add new indices to free list
		var old_size: int = _pool_size
		_grow_pool(_pool_size + GROWTH_BATCH_SIZE)
		for i in range(old_size, _pool_size):
			_free_mesh_indices.append(i)
	return _free_mesh_indices.pop_back()


func _release_all_meshes() -> void:
	for uid: int in _particle_mesh_map:
		var mesh_indices: PackedInt32Array = _particle_mesh_map[uid]
		for mi in mesh_indices:
			_meshes[mi].visible = false
			_meshes[mi].position = OFFSCREEN_POSITION
			_free_mesh_indices.append(mi)
	_particle_mesh_map.clear()


func _grow_pool(new_size: int) -> void:
	if new_size <= _pool_size:
		return

	for i in range(new_size - _pool_size):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _shared_quad
		mesh_instance.visible = false
		mesh_instance.position = OFFSCREEN_POSITION

		var mat := ShaderMaterial.new()
		mat.shader = _opaque_shader
		mat.render_priority = 1  # Render after terrain (priority 0)
		if _vfx_data and _vfx_data.texture:
			mat.set_shader_parameter("effect_texture", _vfx_data.texture)
			mat.set_shader_parameter("texture_size", _texture_size)
		mesh_instance.material_override = mat
		_materials.append(mat)

		add_child(mesh_instance)
		_meshes.append(mesh_instance)

	_pool_size = new_size


func _ensure_sort_capacity(needed: int) -> void:
	if needed <= _sort_capacity:
		return
	_sort_capacity = int(needed * 1.5)
	_sort_keys.resize(_sort_capacity)
	_sort_particle_idx.resize(_sort_capacity)
	_sort_frame_idx.resize(_sort_capacity)
	_sort_frameset_idx.resize(_sort_capacity)
	_sort_opaque.resize(_sort_capacity)
	_sort_indices.resize(_sort_capacity)
