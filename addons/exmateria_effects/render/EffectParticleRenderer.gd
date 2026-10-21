extends Node3D
## Particle renderer feeding the ordered replacement/blend stream (ADR-0365).
##
## Borrows one pool slot and stages replacement + ABR texel populations together. The
## opaque pool MultiMesh stays empty: an early colour OR depth pass would suppress
## later painter-order operations. Source modulation is normalized locally; other
## pool producers retain their own colour contract.
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

# ADR-0211 dec. 4 — alias the published platform façade; one line keeps every use site's
# spelling and makes a grep for the reach find this file.
const DisplayPort = ExMateriaPlatform.DisplayPort
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

## The divisor this renderer applied to sprite corners until #1507:
## `PsxNum.UNITS_PER_TILE`, the BOARD scale. A frame record's corner offsets are SCREEN
## PIXELS, not world units, so dividing them by 28 was a category error — and it also
## froze one camera zoom into the geometry, since 1/28 equals `ortho_size/240` only at
## `ortho_size = 240/28 = 8.571`. Kept ONLY as the no-orthographic-camera fallback in
## `sprite_corner_scale`, where reproducing the pre-#1507 geometry exactly beats guessing.
##
## Spelled through the seam, not as `1.0 / 28.0` (ADR-0091): the 28 here IS
## `PsxMagnitude.UNITS_PER_TILE`, which is what the paragraph above already calls it.
## `UNITS_PER_TILE` is the int 28, so the value is bit-identical to the literal it
## replaces — this is a re-spelling of the divisor, not a change to the fallback.
const LEGACY_BOARD_SCALE: float = 1.0 / float(PsxMagnitude.UNITS_PER_TILE)

const NUM_CHANNELS: int = 5

# Count index zero is replacement; indices 1..4 count the four ABR populations.
const _RM_REPLACE: int = 0

# Slot index borrowed from EffectMultiMeshPool
var _pool_slot: int = -1

# World units per native PSX pixel for the frame being written (#1507). Set once per
# update_particles from the live camera; the fallback value is the pre-#1507 constant so a
# renderer written to with no camera produces exactly the geometry it used to.
var _frame_px_scale: float = LEGACY_BOARD_SCALE
var _pool: Node = null

# Per-render-mode used-instance count for the current frame
var _used_counts: Array[int] = [0, 0, 0, 0, 0]

# Unified transparent-prim record: 24 floats per instance — [0..19] the MultiMesh-compatible
# ADR-0040 packing (byte-identical to a MultiMesh RD buffer), [20] per-prim level_scale
# (1.0 for modes 0/1/2, 0.25 for mode3/ADD25), [21..23] vec4-alignment padding. The compositor
# reads level from [20] (v_level varying), so a merged add run serves both mode1 and mode3.
const _FLOATS_PER_INSTANCE: int = 24
# #6.2: the submission-order transparent-prim staging (record layout + mode/depth/age keys +
# the order()->upload_unified publish) is single-sourced in UnifiedPrimStager, shared with
# the Category-A producers (and TrapEffect until ADR-0369 retired it). Mode resolution stays here — append() takes an
# already-resolved mode; begin() takes the per-frame world->view (only the VIEW is needed:
# ot_order_z is view-space Z, frustum-independent). Occlusion depth (reversed-Z NDC) is computed
# GPU-side in the compositor, the only place the renderer's reversed-Z projection exists —
# the CPU cannot supply it.
var _stager: UnifiedPrimStager = UnifiedPrimStager.new()

# Shared resources
var effect_data: EffectData
var _has_replacement_texels := true
var texture_size: Vector2 = Vector2(128, 256)

# World origin set by EffectInstance each frame (for global_transform positioning)
var _effect_world_origin: Vector3 = Vector3.ZERO

# Pre-camera-advance Q12 submission scale, forwarded by EffectInstance. Direct
# renderer users keep identity; Camera3D framing still only converts pixels to
# world units (#1507). This does not touch particle centres or callback meshes.
var sprite_zoom_q12: float = 4096.0

# Debug-only emitter mute set, written by EffectViewer via
# EffectInstance.set_debug_emitter_filter. Set-style Dictionary (key=emitter_index)
# for O(1) lookup in the per-particle render loop. Not a runtime control surface —
# see CONTEXT.md "Subsystem" avoid list.
var disabled_emitters: Dictionary = {}

# Cached per-emitter align_to_velocity flags
var _emitter_align_to_velocity: Array[bool] = []
var _emitter_uses_sprite_zoom: Array[bool] = []

# Cached per-emitter color curve references (null if color_curve_enabled is false)
var _emitter_color_curve_r: Array = []  # Array of EffectCurve or null
var _emitter_color_curve_g: Array = []
var _emitter_color_curve_b: Array = []


func initialize(data: EffectData, _particle_count: int = 512) -> void:
	"""Initialize renderer: borrow a slot from the pool, set per-effect texture."""
	effect_data = data

	if effect_data and effect_data.texture:
		texture_size = Vector2(effect_data.texture.get_width(), effect_data.texture.get_height())

	# #227: the renderer always uses the global EffectMultiMeshPool autoload (a project global);
	# a future pool-less scene gains the autoload, not a local fallback path.
	_pool = Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")
	if not _pool:
		push_error("EffectParticleRenderer: EffectMultiMeshPool autoload not found")
		return
	_pool_slot = _pool.borrow_slot()
	_apply_texture_to_slot()

	_setup_emitter_caches()

	if EffectsDebug.iteration():
		print("EffectParticleRenderer: Initialized (slot=%d)" % _pool_slot)


func _apply_texture_to_slot() -> void:
	"""Publish the sheet and refresh its conservative STP0 census."""
	if effect_data and effect_data.texture:
		_pool.set_effect_texture(_pool_slot, effect_data.texture)
		_has_replacement_texels = _texture_has_replacement_texels(effect_data.texture)


static func _texture_has_replacement_texels(texture: Texture2D) -> bool:
	# Atlas-wide conservative census, once per texture refresh, not per frame.
	# ABE-on replacement carriers are provably empty without nonzero STP0 texels.
	# Unknown/compressed images retain the carrier rather than dropping coverage.
	var image := texture.get_image()
	if image == null or image.is_compressed():
		return true
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	for i in range(0, bytes.size(), 4):
		if bytes[i + 3] > 229 and (bytes[i] > 2 or bytes[i + 1] > 2 or bytes[i + 2] > 2):
			return true
	return false


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
	_emitter_uses_sprite_zoom.clear()
	_emitter_color_curve_r.clear()
	_emitter_color_curve_g.clear()
	_emitter_color_curve_b.clear()
	if effect_data:
		for i in range(effect_data.emitters.size()):
			var e = effect_data.get_emitter(i)
			if e:
				_emitter_align_to_velocity.append(e.flags.get("align_to_velocity", false))
				# 0x801A5C3C maps the emitter's raw mode nibble 0/1/2/3 to
				# animation.flags &6 = 0/2/4/6. 0x801AA1F8 passes the scale
				# vector only for 0/2. Animation opcode depth_mode is unrelated.
				var sprite_mode: int = (int(e.raw_data.get("animation_target_flag", 0)) >> 4) & 0xF
				_emitter_uses_sprite_zoom.append(sprite_mode < 2)
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
				_emitter_uses_sprite_zoom.append(false)
				_emitter_color_curve_r.append(null)
				_emitter_color_curve_g.append(null)
				_emitter_color_curve_b.append(null)


# --- Legacy pool mesh stays empty for this producer (ADR-0365). ---

func _get_multimesh() -> MultiMesh:
	return _pool.get_multimesh(_pool_slot)


func update_particles(particles: Array[Particle]) -> void:
	"""Pack frame populations in reverse record order (PSX OT head insertion).
	Depth/age ordering and compatible-run batching happen at publication.
	"""
	for rm in range(5):
		_used_counts[rm] = 0
	# Reset the submission-order transparent-prim staging — the only place transparent prims are
	# written. The per-frame world->view for the CPU fold-order key is captured here too (guard
	# null camera -> identity: depths degenerate to base-z, ties break by submission order).
	var frame_camera: Camera3D = get_viewport().get_camera_3d()
	# #1507: sprite corners are SCREEN PIXELS, so their world length depends on the live
	# camera extent. Derived once per frame here, not cached, so a zoom takes effect on
	# the next frame with no invalidation to forget.
	_frame_px_scale = sprite_corner_scale(
		frame_camera.size if frame_camera else 0.0,
		frame_camera != null and frame_camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	)
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
		# Curves are byte/255 envelopes (also read by Studio); the GPU wants byte/128.
		# No curve already means the neutral RGB128 source, i.e. multiplier one.
		if p.emitter_index < _emitter_color_curve_r.size() and _emitter_color_curve_r[p.emitter_index] != null:
			color_modulate *= 255.0 / 128.0
		if p.color_scale != 1.0:
			if p.color_scale <= 0.0:
				continue
			color_modulate *= p.color_scale

		# PSX links each frame primitive at the OT head: last file record draws
		# first. Silf frameset50 is ADD,SUB in the file but SUB->ADD in live RAM
		# (0x801D75B4 -> 0x801D758C). Ascending order subtracts away the figure's
		# warm colours. Reverse only this stack; particle depth/age sort is unchanged.
		for fi in range(frames.size() - 1, -1, -1):
			if not frames[fi] is Dictionary:
				continue
			var frame_data: Dictionary = frames[fi]
			var semi_trans_on: bool = frame_data.get("semi_trans_on", true)

			if not semi_trans_on or _has_replacement_texels:
				_write_instance(_RM_REPLACE, p, frame_data, depth_mode, color_modulate, semi_trans_on, frame_camera, align)

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
	"""Sample colour for the completed simulation tick; default white.

	ParticleSubsystem advances age before publication, whereas PSX 0x801A5EA4
	renders with the old age and 0x801A2EB4 increments it afterward. Thus a
	stepped particle at age1 displays sample0 (Silf fs50: RGB128,128,128),
	not sample1 (109,134,134). Age0 is an unstepped spawn: also sample0.
	Do not use anim_frame: held/looping animations still advance colour age.
	Repeated render/paused/seek publication must not mutate simulation age.
	"""
	var colour_sample_age: int = maxi(p.age - 1, 0)
	var ei: int = p.emitter_index
	if ei < _emitter_color_curve_r.size() and _emitter_color_curve_r[ei] != null:
		# The shared resolve (EffectCurve.sample_rgb) — the SAME source the studio
		# Colour ribbon reads, so preview and render can't diverge. Alpha stays 0.0
		# here; _write_instance sets it per-frame from the semi_trans_on flag.
		return EffectCurve.sample_rgb(_emitter_color_curve_r[ei], _emitter_color_curve_g[ei],
			_emitter_color_curve_b[ei], colour_sample_age)
	return Color(1.0, 1.0, 1.0, 0.0)


## World units per one native PSX pixel of sprite corner offset, for this frame's camera.
##
## Pure and static so the law can be asserted without a viewport — the direction test in
## `tests/PsxMagnitudeTest.gd` seeds a wrong divisor here and in `DisplayPort`.
##
## ⚠️ THE FALLBACK IS THE OLD BEHAVIOUR, DELIBERATELY. With no orthographic camera there
## is no vertical world extent to convert against, and inventing one would be a silent
## wrong size. Returning `LEGACY_BOARD_SCALE` reproduces the pre-#1507 geometry exactly,
## so the degraded case is the previously-shipped case rather than a new artifact.
static func sprite_corner_scale(ortho_size: float, is_orthogonal: bool) -> float:
	if not is_orthogonal or ortho_size <= 0.0:
		return LEGACY_BOARD_SCALE
	return DisplayPort.native_px_to_world(ortho_size)


func _write_instance(rm: int, p: Particle, frame_data: Dictionary, depth_mode: int,
		color_modulate: Color, semi_trans_on: bool, frame_camera: Camera3D,
		align_to_velocity: bool) -> void:
	"""Pack one particle frame population into the ordered stream.

	Packing (ADR-0040):
	  transform.basis  — 9 floats: 4 corners + depth_mode
	  transform.origin — 3 floats: particle world position
	  custom_data      — vec4: uv_rect (x, y, w, h) normalized
	  instance_color   — vec4: color_modulate.rgb + semi_trans_on (0/1) in alpha
	"""
	var uv = frame_data.get("uv", {})
	var uv_x: float = float(uv.get("x", 0))
	var uv_y: float = float(uv.get("y", 0))
	var uv_w: float = float(uv.get("width", 8))
	var uv_h: float = float(uv.get("height", 8))

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

	# #1507: convert the corner offsets from NATIVE PSX PIXELS to world units here, so the
	# basis ships world units and the shader consumes them unscaled. This used to be a
	# `const PSX_SCALE = 1.0/28.0` multiply in effect_particle_stp.gdshaderinc; it moved
	# because the factor is camera-dependent and because GDScript is where it can be
	# asserted. Uniform scale commutes with the align_to_velocity rotation above, so
	# applying it after that rotation is equivalent to applying it before.
	var s: float = _frame_px_scale
	if p.emitter_index >= 0 and p.emitter_index < _emitter_uses_sprite_zoom.size() \
			and _emitter_uses_sprite_zoom[p.emitter_index]:
		s *= sprite_zoom_q12 / 4096.0
	tl_x *= s; tl_y *= s
	tr_x *= s; tr_y *= s
	bl_x *= s; bl_y *= s
	br_x *= s; br_y *= s

	# Pack corners + depth_mode into the transform basis (ADR-0040)
	var basis := Basis(
		Vector3(tl_x, tl_y, tr_x),
		Vector3(tr_y, bl_x, bl_y),
		Vector3(br_x, br_y, float(depth_mode))
	)

	# World position into the transform origin (#227: always pool-relative to the effect origin).
	var origin: Vector3 = _effect_world_origin + p.position

	# UV rect (normalized) — map to texel centers to avoid seam artifacts on mirrored frames
	var custom_data := Color(
		(uv_x + 0.5) / texture_size.x,
		(uv_y + 0.5) / texture_size.y,
		(uv_w - signf(uv_w)) / texture_size.x,
		(uv_h - signf(uv_h)) / texture_size.y
	)

	# Color: normalized source modulation + ABE flag (replacement selection) in alpha
	var instance_color := Color(
		color_modulate.r,
		color_modulate.g,
		color_modulate.b,
		1.0 if semi_trans_on else 0.0
	)

	# Replacement and blended populations share the same primitive key. They are
	# disjoint in the shader, so adjacency preserves ABE/STP semantics at any age.
	_used_counts[rm] += 1
	var operation: int = UnifiedPrimStager.REPLACE if rm == _RM_REPLACE else rm - 1
	_stager.append(basis, origin, instance_color, custom_data, operation, depth_mode, float(p.age))


func _publish_used_counts() -> void:
	"""Never submit an early scene colour/depth pass; publish the ordered stream."""
	_get_multimesh().visible_instance_count = 0
	_publish_unified()


func _publish_unified() -> void:
	"""#219/#220: OT-depth-order the submission-order transparent-prim staging (far -> near) into one
	unified 24-float buffer with adjacent same-DIRECTION runs collapsed (slice C), and hand it to the pool
	(EffectMultiMeshPool.upload_unified). Slice B replaces slice A's by-mode FOLD_ORDER concat with
	OTDepthPrimOrder.order — runs now interleave by depth. #6.2: the order()->upload_unified ceremony
	(and the "pass the ages or equal-depth ties mis-order" contract) now lives in UnifiedPrimStager."""
	_stager.publish(_pool, _pool_slot, false, RID(), 16, true)


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
