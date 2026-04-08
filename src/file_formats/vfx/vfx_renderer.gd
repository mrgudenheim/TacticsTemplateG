class_name VfxRenderer
extends Node3D
## Particle renderer using individual MeshInstance3D nodes with dual-pass STP rendering
## Ported from godot-learning's EffectParticleRenderer, adapted for binary-parsed VfxFrame data
##
## Each particle UID owns its own MeshInstance3D + ShaderMaterial nodes, created on
## first render and freed when the particle dies. No pool, no recycling, no stale data.

var _shared_quad: QuadMesh

var _opaque_shader: Shader
var _blend_shaders: Array[Shader] = []  # [mode0, mode1, mode2, mode3]

var _texture_size: Vector2 = Vector2(128, 256)
var _vfx_data: VisualEffectData

# Per-particle mesh ownership: UID → array of {mesh: MeshInstance3D, mat: ShaderMaterial}
var _particle_meshes: Dictionary = {}  # int (uid) → Array[Dictionary]

# Cached per-emitter align_to_velocity flags
var _emitter_align_flags: Array[bool] = []

# Debug: visualize depth values as heat map colors
var debug_depth_enabled: bool = false
var depth_scale: float = 1.0


func initialize(vfx_data: VisualEffectData) -> void:
	_vfx_data = vfx_data

	_shared_quad = QuadMesh.new()
	_shared_quad.size = Vector2(1.0, 1.0)

	_opaque_shader = preload("res://src/file_formats/vfx/shaders/effect_particle_opaque.gdshader")
	_blend_shaders = [
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode0.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode1.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode2.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode3.gdshader"),
	]

	if vfx_data.texture:
		_texture_size = Vector2(vfx_data.vfx_spr.width, vfx_data.vfx_spr.height)

	_emitter_align_flags.clear()
	for emitter: VfxEmitter in vfx_data.emitters:
		_emitter_align_flags.append(emitter.align_to_velocity)


func render(particles: Array[VfxParticleData], vfx_data: VisualEffectData) -> void:
	if particles.is_empty():
		_free_all_meshes()
		return

	var frame_camera: Camera3D = get_viewport().get_camera_3d()

	var renderable_uids: Dictionary = {}  # uid → particle index
	var uid_mesh_need: Dictionary = {}    # uid → mesh count needed

	for pi in range(particles.size()):
		var p: VfxParticleData = particles[pi]
		if p.age == 0 or not p.active:
			continue

		var frameset_idx: int = p.current_frameset
		if frameset_idx < 0 or frameset_idx >= vfx_data.framesets.size():
			continue

		var frameset: VisualEffectData.VfxFrameSet = vfx_data.framesets[frameset_idx]
		if frameset.frameset.is_empty():
			continue

		renderable_uids[p.uid] = pi
		uid_mesh_need[p.uid] = frameset.frameset.size() * 2

	var stale_uids: Array[int] = []
	for uid: int in _particle_meshes:
		if not renderable_uids.has(uid):
			stale_uids.append(uid)

	for uid: int in stale_uids:
		var entries: Array = _particle_meshes[uid]
		for entry: Dictionary in entries:
			entry.mesh.queue_free()
		_particle_meshes.erase(uid)

	for uid: int in renderable_uids:
		var needed: int = uid_mesh_need[uid]
		var entries: Array = _particle_meshes.get(uid, [])
		var have: int = entries.size()

		if have < needed:
			for _i in range(needed - have):
				var entry: Dictionary = _create_mesh_entry()
				entries.append(entry)
			_particle_meshes[uid] = entries
		elif have > needed:
			# Hide excess (don't free — frameset might grow back)
			for i in range(needed, have):
				entries[i].mesh.visible = false

	for uid: int in renderable_uids:
		var pi: int = renderable_uids[uid]
		var p: VfxParticleData = particles[pi]
		var frameset_idx: int = p.current_frameset
		var frameset: VisualEffectData.VfxFrameSet = vfx_data.framesets[frameset_idx]
		var align: bool = p.emitter_index >= 0 and p.emitter_index < _emitter_align_flags.size() and _emitter_align_flags[p.emitter_index]
		var entries: Array = _particle_meshes[uid]
		var slot: int = 0

		var num_frames: int = frameset.frameset.size()
		for fi in range(num_frames):
			var vfx_frame: VisualEffectData.VfxFrame = frameset.frameset[fi]

			var opaque_entry: Dictionary = entries[slot]
			opaque_entry.mat.render_priority = fi
			_render_frame(opaque_entry.mesh, opaque_entry.mat, p, vfx_frame, true, frame_camera, align, p.current_depth_mode)
			slot += 1

			var semi_entry: Dictionary = entries[slot]
			if vfx_frame.semi_transparency_on:
				semi_entry.mat.render_priority = num_frames + fi
				_render_frame(semi_entry.mesh, semi_entry.mat, p, vfx_frame, false, frame_camera, align, p.current_depth_mode)
			else:
				semi_entry.mesh.visible = false
			slot += 1


func _create_mesh_entry() -> Dictionary:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _shared_quad
	mesh_instance.visible = false

	var mat := ShaderMaterial.new()
	mat.shader = _opaque_shader
	mat.render_priority = 0
	if _vfx_data and _vfx_data.texture:
		mat.set_shader_parameter("effect_texture", _vfx_data.texture)
		mat.set_shader_parameter("texture_size", _texture_size)
	mat.set_shader_parameter("bias_pull_8", VfxConstants.DEPTH_BIAS_PULL_8)
	mat.set_shader_parameter("bias_pull_16", VfxConstants.DEPTH_BIAS_PULL_16)
	mat.set_shader_parameter("bias_fixed_front", VfxConstants.DEPTH_BIAS_FIXED_FRONT)
	mat.set_shader_parameter("bias_fixed_back", VfxConstants.DEPTH_BIAS_FIXED_BACK)
	mat.set_shader_parameter("bias_fixed_16", VfxConstants.DEPTH_BIAS_FIXED_16)
	mesh_instance.material_override = mat

	add_child(mesh_instance)
	return {"mesh": mesh_instance, "mat": mat}


func _render_frame(mesh: MeshInstance3D, mat: ShaderMaterial, p: VfxParticleData,
		vfx_frame: VisualEffectData.VfxFrame, is_opaque_pass: bool,
		frame_camera: Camera3D, align_to_velocity: bool, depth_mode: int) -> void:
	var anim_offset: Vector2 = p.anim_offset
	var tl_x: float = float(vfx_frame.top_left_xy.x) + anim_offset.x
	var tl_y: float = float(vfx_frame.top_left_xy.y) + anim_offset.y
	var tr_x: float = float(vfx_frame.top_right_xy.x) + anim_offset.x
	var tr_y: float = float(vfx_frame.top_right_xy.y) + anim_offset.y
	var bl_x: float = float(vfx_frame.bottom_left_xy.x) + anim_offset.x
	var bl_y: float = float(vfx_frame.bottom_left_xy.y) + anim_offset.y
	var br_x: float = float(vfx_frame.bottom_right_xy.x) + anim_offset.x
	var br_y: float = float(vfx_frame.bottom_right_xy.y) + anim_offset.y

	if align_to_velocity:
		var velocity: Vector3 = p.velocity
		if velocity.length_squared() > 0.0 and frame_camera:
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

	var t := Transform3D.IDENTITY
	t.origin = p.position
	mesh.transform = t

	# Map UVs to texel centers (not edges) for correct filter_nearest sampling.
	# Prevents seam artifacts where mirrored frames meet (e.g., E485 circle).
	var uv_rect_data := Vector4(
		(float(vfx_frame.top_left_uv.x) + 0.5) / _texture_size.x,
		(float(vfx_frame.top_left_uv.y) + 0.5) / _texture_size.y,
		(float(vfx_frame.uv_width) - signf(vfx_frame.uv_width)) / _texture_size.x,
		(float(vfx_frame.uv_height) - signf(vfx_frame.uv_height)) / _texture_size.y
	)

	if is_opaque_pass:
		mat.shader = _opaque_shader
		mat.set_shader_parameter("semi_trans_on", vfx_frame.semi_transparency_on)
	else:
		var blend_mode: int = clampi(vfx_frame.semi_transparency_mode, 0, VfxConstants.SemiTransMode.BACK_PLUS_QUARTER)
		mat.shader = _blend_shaders[blend_mode]

	mat.set_shader_parameter("corner_tl", Vector2(tl_x, tl_y))
	mat.set_shader_parameter("corner_tr", Vector2(tr_x, tr_y))
	mat.set_shader_parameter("corner_bl", Vector2(bl_x, bl_y))
	mat.set_shader_parameter("corner_br", Vector2(br_x, br_y))
	mat.set_shader_parameter("uv_rect_data", uv_rect_data)
	mat.set_shader_parameter("color_modulate", p.color_modulate)
	mat.set_shader_parameter("depth_mode", depth_mode)
	mat.set_shader_parameter("depth_scale", depth_scale)
	if debug_depth_enabled:
		mat.set_shader_parameter("debug_depth", true)

	mesh.visible = true


func _free_all_meshes() -> void:
	for uid: int in _particle_meshes:
		for entry: Dictionary in _particle_meshes[uid]:
			entry.mesh.queue_free()
	_particle_meshes.clear()
