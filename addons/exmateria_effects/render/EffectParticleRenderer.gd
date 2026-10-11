extends Node3D
## Particle renderer feeding the EffectMultiMeshPool slot + the display-space compositor (ADR-0040)
##
## Borrows one slot from the global EffectMultiMeshPool autoload. #227: a slot is a single
## RM_OPAQUE MultiMesh (canvas + depth) — the opaque pass is written to its per-instance buffers via
## set_instance_transform / set_instance_custom_data / set_instance_color, and the opaque shader
## unpacks from MODEL_MATRIX basis + INSTANCE_CUSTOM + COLOR (see effect_particle_stp.gdshaderinc).
## Transparent-frame prims (corners, depth_mode, uv_rect, color_modulate, semi_trans_on) are NOT
## drawn as MultiMeshes — they are staged into the slot's unified 24-float SSBO (submission order +
## per-prim mode/ot_order_z/age), which the combat display-space compositor OT-depth-orders and folds.
##
## Draw calls per frame: 1 opaque MultiMesh per effect + the compositor's folded transparent passes,
## instead of the per-MeshInstance3D path's ~N_particles × 2 × N_effects (ADR-0040). #227 also retired
## the editor pool-less local fallback: the renderer always uses the (project-global) pool autoload.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Effect MultiMesh Pool]]
## Vault: [[Effect Texture Upload]]
## Vault: [[Frameset Header Flags]]
## Vault: [[PSX Texture Page Register]]
## Vault: [[Particle Coloring System]]
## Vault: [[Sprite Offset vs Vertex Position]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectCurve = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")
const UnifiedPrimStager = preload("res://addons/exmateria_effects/render/UnifiedPrimStager.gd")

const NUM_CHANNELS: int = 5

# The one in-scene draw (canvas + depth), the pool's sole surviving MultiMesh (#227). Transparent
# prims ride the unified staging keyed by blend mode (0..3), not a per-mode MultiMesh slot anymore.
const _RM_OPAQUE: int = 0

# Slot index borrowed from EffectMultiMeshPool
var _pool_slot: int = -1
var _pool: Node = null

# Per-render-mode used-instance count for the current frame
var _used_counts: Array[int] = [0, 0, 0, 0, 0]

# #218/#219: per-frame CPU staging of the transparent-prim 20-float/instance packing, filled
# alongside the mode-MultiMesh writes. Slice A (#218) collected four per-mode stagings and
# concatenated them in FOLD_ORDER. Slice B (#219) instead collects THREE parallel arrays in
# SUBMISSION order — records (the 20 floats), modes (blend mode 0..3), depths (reversed-Z OT
# depth) — and OTDepthPrimOrder.order()s them into a depth-ordered unified buffer (far -> near)
# at publish. Runs become maximal adjacent same-mode spans over the depth-ordered stream. The
# in-scene mode MultiMeshes are NO LONGER written at runtime (slice D) — they survive only as
# per-slot texture-stashes; the unified buffer is the transparent carrier for the particle producers
# (TrapEffect included since #225). See EffectMultiMeshPool.upload_unified.
# Slice C (#220): the unified record grew to 24 floats — [0..19] the MultiMesh-compatible
# ADR-0040 packing (byte-identical to a MultiMesh RD buffer), [20] per-prim level_scale
# (1.0 for modes 0/1/2, 0.25 for mode3/ADD25), [21..23] vec4-alignment padding. The
# compositor reads level from [20] (v_level varying) so a merged add run serves both
# mode1 and mode3. Legacy per-mode probe buffers stay 20-float MultiMesh; every runtime producer
# (the general renderer + TrapEffect since #225) publishes the 24-float unified record.
const _FLOATS_PER_INSTANCE: int = 24
# #6.2: the submission-order transparent-prim staging (24-float record layout + parallel
# mode/ot_order_z-depth/age keys + the order()->upload_unified publish ceremony) is single-sourced
# in UnifiedPrimStager, shared with TrapEffect and the Category-A producers. Mode resolution stays
# here (the per-frame semi_trans_mode int) — append() takes an already-resolved mode. The per-frame
# world->view for the fold-order key is handed to begin(); only the VIEW is needed (ot_order_z is
# view-space Z, frustum-independent). Occlusion depth (reversed-Z NDC) is computed GPU-side in the
# compositor, the ONLY place the renderer's reversed-Z projection exists — the CPU cannot supply it.
var _stager: UnifiedPrimStager = UnifiedPrimStager.new()

# Cached per-render-mode capacity (mirror of MultiMesh.instance_count)
var _capacities: Array[int] = [0, 0, 0, 0, 0]

# Shared resources
var effect_data: EffectData
var texture_size: Vector2 = Vector2(128, 256)

# World origin set by EffectInstance each frame (for global_transform positioning)
var _effect_world_origin: Vector3 = Vector3.ZERO

# Debug-only emitter mute set, written by EffectViewer via
# EffectInstance.set_debug_emitter_filter. Set-style Dictionary (key=emitter_index)
# for O(1) lookup in the per-particle render loop. Not a runtime control surface —
# see CONTEXT.md "Subsystem" avoid list.
var disabled_emitters: Dictionary = {}

# Cached per-emitter align_to_velocity flags
var _emitter_align_to_velocity: Array[bool] = []

# Cached per-emitter color curve references (null if color_curve_enabled is false)
var _emitter_color_curve_r: Array = []  # Array of EffectCurve or null
var _emitter_color_curve_g: Array = []
var _emitter_color_curve_b: Array = []


func initialize(data: EffectData, _particle_count: int = 512) -> void:
	"""Initialize renderer: borrow a slot from the pool, set per-effect texture."""
	effect_data = data

	if effect_data and effect_data.texture:
		texture_size = Vector2(effect_data.texture.get_width(), effect_data.texture.get_height())

	# #227: the renderer always uses the global EffectMultiMeshPool autoload (a project global). The
	# old editor/pool-less _setup_local_slot fallback — the only non-compositor in-scene render path —
	# is retired; a future pool-less scene gains the autoload rather than resurrecting that path.
	_pool = Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")
	if not _pool:
		push_error("EffectParticleRenderer: EffectMultiMeshPool autoload not found")
		return
	_pool_slot = _pool.borrow_slot()
	_apply_texture_to_slot()
	_capacities[_RM_OPAQUE] = _pool.get_multimesh(_pool_slot).instance_count

	_setup_emitter_caches()

	if EffectsDebug.iteration():
		print("EffectParticleRenderer: Initialized (slot=%d)" % _pool_slot)


func _apply_texture_to_slot() -> void:
	"""#227: stash the effect sheet on the slot's plain _effect_tex field (what the compositor folds),
	and set effect_texture + texture_size on the RM_OPAQUE material only — RM_OPAQUE still draws
	in-scene (canvas + depth), so its shader samples the sheet. The RM_MODE0..3 materials no longer
	carry the sheet (nothing has read it there since the reader repointed to _effect_tex in commit 3)."""
	if effect_data and effect_data.texture:
		_pool.set_effect_texture(_pool_slot, effect_data.texture)
		var mat: ShaderMaterial = _pool.get_material(_pool_slot)
		mat.set_shader_parameter("effect_texture", effect_data.texture)
		mat.set_shader_parameter("texture_size", texture_size)


func refresh_texture() -> void:
	"""Re-push the effect sheet after an authoring edit swapped it (#280 texture import,
	ADR-0199). `_apply_texture_to_slot` otherwise runs ONCE at initialize(), so a replaced
	`effect_data.texture` would keep rendering the old sheet until the effect fully
	respawned — the same staleness `refresh_emitter_caches` exists to fix for the emitter
	caches. Re-derives `texture_size` too: it is cached from the old sheet's dimensions and
	feeds the shader's UV normalisation. Cheap (two uniform writes + a slot field)."""
	if effect_data and effect_data.texture:
		texture_size = Vector2(effect_data.texture.get_width(), effect_data.texture.get_height())
	if _pool and _pool_slot >= 0:
		_apply_texture_to_slot()


func refresh_emitter_caches() -> void:
	"""Re-derive the per-emitter caches after an authoring edit (Effect Studio). The colour-curve
	refs + align_to_velocity flags are otherwise cached ONLY at initialize() — a live colour-curve
	enable toggle or curve reassignment updates the model but would keep sampling stale data (the
	E312 idx0 "colour curves do nothing" report) until the effect fully respawned. Cheap: a handful
	of per-emitter array writes. The host calls it on every emitter-channel edit."""
	_setup_emitter_caches()


func _setup_emitter_caches() -> void:
	"""Cache per-emitter flags + color curves once at init."""
	_emitter_align_to_velocity.clear()
	_emitter_color_curve_r.clear()
	_emitter_color_curve_g.clear()
	_emitter_color_curve_b.clear()
	if effect_data:
		for i in range(effect_data.emitters.size()):
			var e = effect_data.get_emitter(i)
			if e:
				_emitter_align_to_velocity.append(e.flags.get("align_to_velocity", false))
				if e.flags.get("color_curve_enabled", false):
					var cc: Dictionary = e.color_curves
					_emitter_color_curve_r.append(effect_data.get_curve(int(cc.get("r", -1))))
					_emitter_color_curve_g.append(effect_data.get_curve(int(cc.get("g", -1))))
					_emitter_color_curve_b.append(effect_data.get_curve(int(cc.get("b", -1))))
				else:
					_emitter_color_curve_r.append(null)
					_emitter_color_curve_g.append(null)
					_emitter_color_curve_b.append(null)
			else:
				_emitter_align_to_velocity.append(false)
				_emitter_color_curve_r.append(null)
				_emitter_color_curve_g.append(null)
				_emitter_color_curve_b.append(null)


# --- MultiMesh access (pool-backed; only RM_OPAQUE draws in-scene, #227) ---

func _get_multimesh() -> MultiMesh:
	return _pool.get_multimesh(_pool_slot)


func _ensure_capacity(needed: int) -> void:
	if _capacities[_RM_OPAQUE] >= needed:
		return
	_pool.ensure_instance_capacity(_pool_slot, needed)
	_capacities[_RM_OPAQUE] = _pool.get_multimesh(_pool_slot).instance_count


func update_particles(particles: Array[Particle]) -> void:
	"""Zero-alloc render path: walk particles, route each frame to the right
	render_mode's MultiMesh, pack per-instance state into transform / custom
	data / color.

	Per ADR-0040 (extends ADR-0015):
	  L1 (inter-particle macro depth) — fragment shader ot_depth, unchanged.
	  L2 (intra-particle frame stack) — instance-buffer write order (this loop's
		  `for fi in range(frames.size())` is the determining order).
	  L3 (opaque vs semi-trans pass split) — per-MultiMesh render_mode.
	"""
	# Reset per-rm used counts
	for rm in range(5):
		_used_counts[rm] = 0
	# #219/Slice-D: reset the submission-order transparent-prim staging (at runtime this is now the
	# ONLY place transparent prims are written — the mode-MM double-write is retired). The per-frame
	# world->view for the CPU fold-order key is captured here too (guard null camera -> identity, so
	# depths degenerate to base-z and ordering still tie-breaks by submission).
	var frame_camera: Camera3D = get_viewport().get_camera_3d()
	var frame_view: Transform3D = frame_camera.get_camera_transform().affine_inverse() if frame_camera else Transform3D()
	_stager.begin(frame_view)

	if not effect_data:
		_publish_used_counts()
		return

	var _perf_enabled: bool = EffectsDebug.particle()
	var _t0: int
	var _t3: int
	if _perf_enabled:
		_t0 = Time.get_ticks_usec()

	for pi in range(particles.size()):
		var p: Particle = particles[pi]

		if disabled_emitters.has(p.emitter_index):
			continue

		var frameset_idx: int = p.frameset_idx
		if frameset_idx < 0 or frameset_idx >= effect_data.framesets.size():
			continue

		var frameset = effect_data.framesets[frameset_idx]
		if not frameset is Dictionary:
			continue

		var frames = frameset.get("frames", [])
		var depth_mode: int = clampi(p.depth_mode, 0, 5)
		var align: bool = p.emitter_index < _emitter_align_to_velocity.size() and _emitter_align_to_velocity[p.emitter_index]

		# Per-particle color modulate (sampled once per particle, not per frame)
		var color_modulate: Color = _compute_color_modulate(p)

		for fi in range(frames.size()):
			if not frames[fi] is Dictionary:
				continue
			var frame_data: Dictionary = frames[fi]
			var semi_trans_on: bool = frame_data.get("semi_trans_on", true)

			# Opaque pass (always written into RM_OPAQUE)
			_write_instance(_RM_OPAQUE, p, frame_data, depth_mode, color_modulate, semi_trans_on, frame_camera, align)

			# Semi-trans pass (conditional, routed by blend mode). The `rm` arg is 1 + blend_mode
			# (1..4): _write_instance stages it to the unified transparent buffer (no MultiMesh, #227).
			if semi_trans_on:
				var blend_mode: int = clampi(int(frame_data.get("semi_trans_mode", 1)), 0, 3)
				_write_instance(1 + blend_mode, p, frame_data, depth_mode, color_modulate, semi_trans_on, frame_camera, align)

	_publish_used_counts()

	if _perf_enabled:
		_t3 = Time.get_ticks_usec()
		var total_ms = (_t3 - _t0) / 1000.0
		if total_ms > 4.0:
			print("[PARTICLE_PERF] %.1fms total | opaque=%d mode0=%d mode1=%d mode2=%d mode3=%d particles=%d" % [
				total_ms, _used_counts[0], _used_counts[1], _used_counts[2], _used_counts[3], _used_counts[4],
				particles.size()])


func _compute_color_modulate(p: Particle) -> Color:
	"""Sample per-emitter color curves for this particle's age; default white."""
	var ei: int = p.emitter_index
	if ei < _emitter_color_curve_r.size() and _emitter_color_curve_r[ei] != null:
		# The shared resolve (EffectCurve.sample_rgb) — the SAME source the studio
		# Colour ribbon reads, so preview and render can't diverge. Alpha stays 0.0
		# here; _write_instance sets it per-frame from the semi_trans_on flag.
		return EffectCurve.sample_rgb(_emitter_color_curve_r[ei], _emitter_color_curve_g[ei],
			_emitter_color_curve_b[ei], p.age)
	return Color(1.0, 1.0, 1.0, 0.0)


func _write_instance(rm: int, p: Particle, frame_data: Dictionary, depth_mode: int,
		color_modulate: Color, semi_trans_on: bool, frame_camera: Camera3D,
		align_to_velocity: bool) -> void:
	"""Pack one particle frame into the (rm) MultiMesh's next free instance slot.

	Packing (ADR-0040):
	  transform.basis  — 9 floats: 4 corners + depth_mode
	  transform.origin — 3 floats: particle world position
	  custom_data      — vec4: uv_rect (x, y, w, h) normalized
	  instance_color   — vec4: color_modulate.rgb + semi_trans_on (0/1) in alpha
	"""
	# Extract UV data
	var uv = frame_data.get("uv", {})
	var uv_x: float = float(uv.get("x", 0))
	var uv_y: float = float(uv.get("y", 0))
	var uv_w: float = float(uv.get("width", 8))
	var uv_h: float = float(uv.get("height", 8))

	# Get vertex corners + apply animation offset
	var vertices = frame_data.get("vertices", {})
	var tl = vertices.get("top_left", [-8, -8])
	var tr = vertices.get("top_right", [8, -8])
	var bl = vertices.get("bottom_left", [-8, 8])
	var br = vertices.get("bottom_right", [8, 8])

	var anim_offset: Vector2 = p.anim_offset
	var tl_x: float = float(tl[0]) + anim_offset.x
	var tl_y: float = float(tl[1]) + anim_offset.y
	var tr_x: float = float(tr[0]) + anim_offset.x
	var tr_y: float = float(tr[1]) + anim_offset.y
	var bl_x: float = float(bl[0]) + anim_offset.x
	var bl_y: float = float(bl[1]) + anim_offset.y
	var br_x: float = float(br[0]) + anim_offset.x
	var br_y: float = float(br[1]) + anim_offset.y

	# Apply velocity-based rotation if enabled
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

	# Pack corners + depth_mode into the transform basis (ADR-0040)
	var basis := Basis(
		Vector3(tl_x, tl_y, tr_x),
		Vector3(tr_y, bl_x, bl_y),
		Vector3(br_x, br_y, float(depth_mode))
	)

	# World position into the transform origin (#227: always pool-relative to the effect origin).
	var origin: Vector3 = _effect_world_origin + p.position

	var transform := Transform3D(basis, origin)

	# UV rect (normalized) — map to texel centers to avoid seam artifacts on mirrored frames
	var custom_data := Color(
		(uv_x + 0.5) / texture_size.x,
		(uv_y + 0.5) / texture_size.y,
		(uv_w - signf(uv_w)) / texture_size.x,
		(uv_h - signf(uv_h)) / texture_size.y
	)

	# Color: modulate.rgb + semi_trans_on (used by opaque shader only) in alpha
	var instance_color := Color(
		color_modulate.r,
		color_modulate.g,
		color_modulate.b,
		1.0 if semi_trans_on else 0.0
	)

	# Slice D (#221): the transparent mode MultiMeshes are NOT written — this renderer's transparent
	# prims fold through the display-space compositor, so writing them was a pure double-write (the
	# ADR-0040 CPU cost). We write a MultiMesh only for RM_OPAQUE (canvas+depth, always in-scene). Transparent prims
	# live ONLY in the unified staging below. (#227: the editor local-fallback preview path is retired.)
	if rm == _RM_OPAQUE:
		var slot: int = _used_counts[rm]
		_used_counts[rm] = slot + 1
		if slot >= _capacities[rm]:
			_ensure_capacity(slot + 1)
		var multimesh: MultiMesh = _get_multimesh()
		multimesh.set_instance_transform(slot, transform)
		multimesh.set_instance_custom_data(slot, custom_data)
		multimesh.set_instance_color(slot, instance_color)

	# #218/#219: stage the transparent-mode instance into the submission-order unified buffer via the
	# shared UnifiedPrimStager (byte-identical to the MultiMesh RD buffer: transform 3x4 ROW-MAJOR,
	# color rgba, custom rgba, level_scale, pad). RM_OPAQUE (rm 0) stays MultiMesh-only. mode index =
	# rm - 1. The per-prim OT ORDER key is the VIEW-SPACE Z of the SAME world_origin (the stager
	# derives ot_order_z from the view handed to begin()), so the CPU fold order matches the billboard
	# the compositor rasterizes. (The shader still writes its OWN reversed-Z ot_depth as gl_FragDepth
	# for occlusion.)
	if rm != _RM_OPAQUE:
		_stager.append(basis, origin, instance_color, custom_data, rm - 1, depth_mode, float(p.age))


func _publish_used_counts() -> void:
	"""#227: only RM_OPAQUE has a pool MultiMesh (canvas + depth) to fill; transparent prims ride the
	unified buffer, so only its visible count is published. Then (#218) publish the unified
	transparent-prim buffer to the pool for the combat compositor."""
	_get_multimesh().visible_instance_count = _used_counts[_RM_OPAQUE]
	_publish_unified()


func _publish_unified() -> void:
	"""#219/#220: OT-depth-order the submission-order transparent-prim staging (far -> near) into one
	unified 24-float buffer with adjacent same-DIRECTION runs collapsed (slice C), and hand it to the pool
	(EffectMultiMeshPool.upload_unified). Slice B replaces slice A's by-mode FOLD_ORDER concat with
	OTDepthPrimOrder.order — runs now interleave by depth. #6.2: the order()->upload_unified ceremony
	(and the "pass the ages or equal-depth ties mis-order" contract) now lives in UnifiedPrimStager."""
	_stager.publish(_pool, _pool_slot)


func release_pool_meshes() -> void:
	"""Return the borrowed slot to the global pool (called on effect cleanup)."""
	if _pool_slot >= 0:
		_pool.release_slot(_pool_slot)
		_pool_slot = -1


func get_active_count() -> int:
	"""Return total active instance count across all 5 render_modes."""
	var total: int = 0
	for rm in range(5):
		total += _used_counts[rm]
	return total
