class_name TrapParticleRenderer
extends RefCounted
## Rendering logic for TRAP particle effects — sprite rendering + charge line rendering.

var _pool: TrapMeshPool
var _line_mesh: ImmediateMesh = null
var _line_mesh_instance: MeshInstance3D = null
var _line_material: ShaderMaterial = null
var _charge_line_shader: Shader

const LINE_HALF_WIDTH: float = 0.03


func initialize(pool: TrapMeshPool) -> void:
	_pool = pool
	_charge_line_shader = preload("res://src/file_formats/vfx/shaders/trap_charge_line.gdshader")


func setup_line_mesh(parent: Node3D) -> void:
	_line_mesh = ImmediateMesh.new()
	_line_mesh_instance = MeshInstance3D.new()
	_line_mesh_instance.mesh = _line_mesh
	_line_material = ShaderMaterial.new()
	_line_material.shader = _charge_line_shader
	_line_material.render_priority = 1
	_line_mesh_instance.material_override = _line_material
	parent.add_child(_line_mesh_instance)


func cleanup_line_mesh() -> void:
	if _line_mesh_instance != null:
		_line_mesh_instance.queue_free()
		_line_mesh_instance = null
		_line_mesh = null
		_line_material = null


func render(particles: Array[VfxParticleData],
		spell_charge: TrapSpellChargeHandler,
		summon_charge: TrapSummonChargeHandler,
		emitter_palette: Dictionary[int, int]) -> void:
	if _line_mesh != null:
		_line_mesh.clear_surfaces()
	if spell_charge != null:
		_render_charge_lines_for(spell_charge)
	if summon_charge != null:
		_render_charge_lines_for(summon_charge)

	if particles.is_empty():
		_pool.release_all_meshes()
		return

	var trap_data: TrapEffectData = RomReader.trap_effect_data
	if not _pool.is_initialized:
		return

	var renderable: Dictionary = _collect_renderable(particles, trap_data)
	_release_stale_meshes(renderable)
	_resize_particle_meshes(renderable, particles, trap_data)
	_draw_particles(renderable, particles, trap_data, emitter_palette)


func _collect_renderable(particles: Array[VfxParticleData], trap_data: TrapEffectData) -> Dictionary:
	var result: Dictionary = {} # uid -> particle_index
	for pi in range(particles.size()):
		var p: VfxParticleData = particles[pi]
		if p.age == 0 or not p.active or p.is_dead():
			continue

		var frameset_idx: int = p.current_frameset
		if frameset_idx < 0 or frameset_idx >= trap_data.framesets.size():
			continue

		var frameset: VisualEffectData.VfxFrameSet = trap_data.framesets[frameset_idx]
		if frameset.frameset.is_empty():
			continue

		result[p.uid] = pi
	return result


func _release_stale_meshes(renderable: Dictionary) -> void:
	for uid: int in _pool.particle_mesh_map.keys():
		if not renderable.has(uid):
			var mesh_indices: PackedInt32Array = _pool.particle_mesh_map[uid]
			for mi in mesh_indices:
				_pool.return_mesh(mi)
			_pool.particle_mesh_map.erase(uid)


func _resize_particle_meshes(renderable: Dictionary, particles: Array[VfxParticleData], trap_data: TrapEffectData) -> void:
	for uid: int in renderable:
		var pi: int = renderable[uid]
		var p: VfxParticleData = particles[pi]
		var frameset: VisualEffectData.VfxFrameSet = trap_data.framesets[p.current_frameset]
		var needed: int = frameset.frameset.size() * 2
		var current: PackedInt32Array = _pool.particle_mesh_map.get(uid, PackedInt32Array())
		var have: int = current.size()

		if have < needed:
			for _j in range(needed - have):
				current.append(_pool.borrow_mesh_index())
			_pool.particle_mesh_map[uid] = current
		elif have > needed:
			for i in range(needed, have):
				_pool.return_mesh(current[i])
			current = current.slice(0, needed)
			_pool.particle_mesh_map[uid] = current


func _draw_particles(renderable: Dictionary, particles: Array[VfxParticleData],
		trap_data: TrapEffectData, emitter_palette: Dictionary[int, int]) -> void:
	var draw_order: int = 0
	for uid: int in renderable:
		var pi: int = renderable[uid]
		var p: VfxParticleData = particles[pi]
		var frameset_idx: int = p.current_frameset
		var frameset: VisualEffectData.VfxFrameSet = trap_data.framesets[frameset_idx]
		var mesh_indices: PackedInt32Array = _pool.particle_mesh_map[uid]
		var local_slot: int = 0

		for fi in range(frameset.frameset.size()):
			var vfx_frame: VisualEffectData.VfxFrame = frameset.frameset[fi]
			if vfx_frame == null:
				local_slot += 2
				continue

			var mi_opaque: int = mesh_indices[local_slot]
			_render_frame(_pool.meshes[mi_opaque], _pool.materials[mi_opaque], p, vfx_frame, true, draw_order, emitter_palette)
			draw_order += 1
			local_slot += 1

			var mi_semi: int = mesh_indices[local_slot]
			_render_frame(_pool.meshes[mi_semi], _pool.materials[mi_semi], p, vfx_frame, false, draw_order, emitter_palette)
			draw_order += 1
			local_slot += 1


func _render_frame(mesh_inst: MeshInstance3D, mat: ShaderMaterial, p: VfxParticleData,
		vfx_frame: VisualEffectData.VfxFrame, is_opaque_pass: bool, draw_order: int,
		emitter_palette: Dictionary[int, int]) -> void:
	var t := Transform3D.IDENTITY
	t.origin = p.position
	mesh_inst.transform = t

	var uv_rect_data := Vector4(
		float(vfx_frame.top_left_uv.x) / _pool.texture_size.x,
		float(vfx_frame.top_left_uv.y) / _pool.texture_size.y,
		float(vfx_frame.uv_width) / _pool.texture_size.x,
		float(vfx_frame.uv_height) / _pool.texture_size.y
	)

	if is_opaque_pass:
		mat.shader = _pool.opaque_shader
	else:
		var blend_mode: int = clampi(vfx_frame.semi_transparency_mode, 0, 3)
		mat.shader = _pool.blend_shaders[blend_mode]

	var palette_id: int = emitter_palette.get(p.emitter_index, vfx_frame.palette_id)
	var tex: Texture2D = _pool.get_palette_texture(palette_id)
	mat.set_shader_parameter("effect_texture", tex)

	mat.set_shader_parameter("corner_tl", Vector2(float(vfx_frame.top_left_xy.x), float(vfx_frame.top_left_xy.y)))
	mat.set_shader_parameter("corner_tr", Vector2(float(vfx_frame.top_right_xy.x), float(vfx_frame.top_right_xy.y)))
	mat.set_shader_parameter("corner_bl", Vector2(float(vfx_frame.bottom_left_xy.x), float(vfx_frame.bottom_left_xy.y)))
	mat.set_shader_parameter("corner_br", Vector2(float(vfx_frame.bottom_right_xy.x), float(vfx_frame.bottom_right_xy.y)))
	mat.set_shader_parameter("uv_rect_data", uv_rect_data)

	mat.set_shader_parameter("color_modulate", p.color_modulate)
	mat.render_priority = draw_order + 1
	mesh_inst.visible = true


func _render_charge_lines_for(handler: TrapChargeHandlerBase) -> void:
	if handler.active_line_count == 0:
		return

	var cam: Camera3D = _pool.get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos: Vector3 = cam.global_position

	var elem_color: Color = handler.element_color
	var fade_curve: PackedByteArray = TrapChargeHandlerBase.FADE_CURVE
	var hist_size: int = TrapChargeHandlerBase.HISTORY_SIZE

	_line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	for slot in handler.line_slots:
		if not slot.alive:
			continue

		var brightness_segs: int = handler.get_brightness_index(slot)
		if brightness_segs <= 0:
			continue

		var write_index: int = slot.age % hist_size

		# Walk backwards through history: newest (write_index) to oldest
		for seg in range(brightness_segs):
			var idx_end: int = (write_index - seg + hist_size) % hist_size
			var idx_start: int = (idx_end - 1 + hist_size) % hist_size

			var p_start: Vector3 = slot.history[idx_start]
			var p_end: Vector3 = slot.history[idx_end]

			# Skip degenerate segments
			if p_start.is_equal_approx(p_end):
				continue

			# Color from fade curve (head = bright, tail = dim)
			var head_idx: int = hist_size - 1 - seg
			var tail_idx: int = head_idx - 1
			if tail_idx < 0:
				tail_idx = 0
			if head_idx >= fade_curve.size():
				head_idx = fade_curve.size() - 1

			var alpha_end: float = float(fade_curve[head_idx]) / 255.0
			var alpha_start: float = float(fade_curve[tail_idx]) / 255.0
			var color_end := Color(elem_color.r * alpha_end, elem_color.g * alpha_end, elem_color.b * alpha_end, 1.0)
			var color_start := Color(elem_color.r * alpha_start, elem_color.g * alpha_start, elem_color.b * alpha_start, 1.0)

			# Camera-facing quad (billboard strip)
			var seg_dir: Vector3 = (p_end - p_start).normalized()
			var to_cam: Vector3 = (cam_pos - (p_start + p_end) * 0.5).normalized()
			var right: Vector3 = seg_dir.cross(to_cam).normalized() * LINE_HALF_WIDTH

			# Two triangles: start-left, start-right, end-right, start-left, end-right, end-left
			var s_l: Vector3 = p_start - right
			var s_r: Vector3 = p_start + right
			var e_l: Vector3 = p_end - right
			var e_r: Vector3 = p_end + right

			_line_mesh.surface_set_color(color_start)
			_line_mesh.surface_add_vertex(s_l)
			_line_mesh.surface_set_color(color_start)
			_line_mesh.surface_add_vertex(s_r)
			_line_mesh.surface_set_color(color_end)
			_line_mesh.surface_add_vertex(e_r)

			_line_mesh.surface_set_color(color_start)
			_line_mesh.surface_add_vertex(s_l)
			_line_mesh.surface_set_color(color_end)
			_line_mesh.surface_add_vertex(e_r)
			_line_mesh.surface_set_color(color_end)
			_line_mesh.surface_add_vertex(e_l)

	_line_mesh.surface_end()
