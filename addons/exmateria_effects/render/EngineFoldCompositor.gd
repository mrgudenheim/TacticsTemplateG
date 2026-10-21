extends Node
## Live effect carrier producer: engine-fold (4.8-dev Forward+) or native in-scene. Each
## OTDepthPrimOrder run -> a per-run MultiMeshInstance3D wearing the REAL particle gdshader
## flagged compositor_layer, stamped render_layer_order = its fold-order key; the ENGINE Pass B
## folds them into its held-out target (Pass A seed / Pass C resolve are FoldSurface's, ADR-0074).
## This file owns ONLY the per-frame carrier rebuild: read EffectMultiMeshPool, materialize the
## carriers, stamp their fold order (the retired raw-GLSL fold re-implemented this shading in GLSL).
## OCCLUSION: depth_draw_never + depth-test ENABLED on the SHARED opaque scene depth (render_forward_
## clustered.cpp LOADed not cleared, GREATER_OR_EQUAL, ot_computed_depth) — occluded by units/map
## per-fragment, yet effects still fold against each other in render_layer_order, not camera depth.
## ONE PUBLISHED VERB: `setup_auto(camera)`. It picks the route and attaches; there is no field to
## set first and no renderer for the caller to identify. `_setup_fold` / `_setup_native` are the two
## arms behind it and are private on purpose (ADR-0349 dec. 4).
## Vault: [[Display Space Blend Fold]]
## vault: .vaults/comments/exmateria_effects/engine-fold-carrier.md

## Aliased back to bare spelling through the addon's one global name — exmateria_render declared
## class_name FoldSurface; it now declares only ExMateriaRender (ADR-0212 dec. 1, ADR-0211 dec. 4).
const FoldSurface = ExMateriaRender.FoldSurface

## Same for exmateria_schema's six generic-English globals, collapsed onto one façade (ADR-0212 dec. 1).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

## Preloaded Shader objects, not String paths — ADR-0191 dec. 11. A load() on a mistyped path returns
## null and a null shader raises nothing: the fold just stops, with no error.
const FOLD_REPLACE := preload("res://addons/exmateria_effects/render/effect_fold_replace.gdshader")
const FOLD_ADD := preload("res://addons/exmateria_effects/render/effect_fold_add.gdshader")
const FOLD_SUB := preload("res://addons/exmateria_effects/render/effect_fold_sub.gdshader")
const FOLD_MIX := preload("res://addons/exmateria_effects/render/effect_fold_mix.gdshader")

# The IN-SCENE set: same shading minus compositor_layer, native Forward+ blend. The NATIVE route is TWO
# things (#1352): the PRODUCTION route wherever the build cannot fold (standing down instead is what made
# transparent particles silently vanish) and the #7916 comparison side on the fork. Since #1451 both
# collapse into one derived answer, `override or not Fold.owns()`, which `setup_auto` reads off the port.
# The in-scene half linearizes its own texel (tonemap = the return leg a fold lacks): pow not shareable, see check_no_pow_in_fold.py.
const NATIVE_REPLACE := preload("res://addons/exmateria_effects/render/effect_native_replace.gdshader")
const NATIVE_ADD := preload("res://addons/exmateria_effects/render/effect_native_add.gdshader")
const NATIVE_SUB := preload("res://addons/exmateria_effects/render/effect_native_sub.gdshader")
const NATIVE_MIX := preload("res://addons/exmateria_effects/render/effect_native_mix.gdshader")

## The route (#1451), through the port rather than a bare autoload identifier. Its absent answer is
## the build fact, so a consumer with the addon and no router still attaches on the right side.
const RoutePort = preload("res://addons/exmateria_effects/install/RoutePort.gd")

## The route this producer attached on: true = NATIVE in-scene carriers (no layer, no FoldSurface).
var _route_native := false

## READ-ONLY since #1452 (ADR-0349 dec. 4). It used to be a public settable field that changed what
## `setup` did, which is an interface a caller had to know a call ORDER to use: set the flag, then
## pick the matching verb. `setup_auto` reads the route itself, so the only thing left to publish is
## the answer. Flipping the comparison route is the ROUTER's `set_native_blend()` — the one place
## that can also re-attach — and it is a BETWEEN-CASTS control (dec. 6).
var native_blend: bool:
	get:
		return _route_native
	set(_v):
		push_error("[engine-fold] native_blend is READ-ONLY since #1452 — call setup_auto(camera), and flip the comparison with the router's set_native_blend()")

# Legacy pool calibration (Trap). Particle records explicitly carry normalized
# source modulation and bypass this gain on BOTH replacement and blend (ADR-0365).
const POOL_GOURAUD_GAIN := 2.2

var _pool: Node
var _fold_root: Node3D
var _quad: QuadMesh
var _mat_replace: ShaderMaterial
var _mat_add: ShaderMaterial
var _mat_sub: ShaderMaterial
var _mat_mix: ShaderMaterial
var _fold_surface: FoldSurface
var _logged := false


## THE ENTRY POINT. Call it ONCE, after adding this node to the scene, with an in-tree Camera3D in
## the world that owns playback. It picks the route, attaches on that side, and returns whether a
## producer is live — `false` means do not start playback.
##
## There is nothing else to get right. The caller does not identify the renderer, does not set a
## field first, and does not choose between two verbs that differ in what they assume about a field.
## Keep one producer per playback scene; freeing it frees its carriers.
func setup_auto(cam: Camera3D) -> bool:
	return _setup_native(cam) if RoutePort.is_native() else _setup_fold(cam)


## The NATIVE arm: in-scene carriers, Godot's linear blend, no FoldSurface bracket. Supports GL
## Compatibility with no RenderingDevice.
##
## ⚠️ IT NO LONGER REFUSES A FOLD-CAPABLE RENDERER, and deleting that guard is the point of ADR-0349
## rather than a relaxation of it. The refusal existed for one reason, stated in the README in the
## addon's own words: *"callbacks independently use that predicate and would join a held-out layer
## with no seed/resolve bracket"*. Since #1451 callbacks are on the PRODUCER's route, so there is no
## held-out layer to strand them in. The workaround is not worked around — it is REMOVED, because its
## cause is gone. That refusal is also why this addon had no standalone recipe on fork+Forward+ at
## all, which is why the router was 142 lines of host code (#1453).
func _setup_native(cam: Camera3D) -> bool:
	_route_native = true
	_build(cam)
	return _fold_root != null


## The FOLD arm: carriers join the shared fold layer and the engine's Pass B folds them into the
## display-space scratch, bracketed by a FoldSurface.
func _setup_fold(cam: Camera3D) -> bool:
	_route_native = false
	_build(cam)
	return _fold_root != null


func _build(cam: Camera3D) -> void:
	if cam == null:
		push_warning("[engine-fold] no camera — engine-fold compositor disabled")
		return
	_pool = Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")
	if _pool == null:
		push_warning("[engine-fold] no EffectMultiMeshPool — disabled")
		return
	_quad = QuadMesh.new()
	if _route_native:
		# In-scene: one twin per blend mode, each linearizes its own texel (tonemap = the return leg).
		# 25%-add (ADD_25) rides NATIVE_ADD — its 0.25 level_scale is baked into COLOR below, as in the fold path.
		_mat_replace = _make_mat(NATIVE_REPLACE)
		_mat_add = _make_mat(NATIVE_ADD)
		_mat_sub = _make_mat(NATIVE_SUB)
		_mat_mix = _make_mat(NATIVE_MIX)
	else:
		_mat_replace = _make_mat(FOLD_REPLACE)
		_mat_add = _make_mat(FOLD_ADD)
		_mat_sub = _make_mat(FOLD_SUB)
		_mat_mix = _make_mat(FOLD_MIX)
	_fold_root = Node3D.new()
	_fold_root.name = "EngineFoldPrims"
	add_child(_fold_root)
	if not _route_native:
		# Pass A/C display-space scratch is FoldSurface's (ADR-0074); this owns only the carrier rebuild.
		# In native-blend mode there is no fold scratch — carriers blend into the scene buffer.
		_fold_surface = FoldSurface.new()
		_fold_surface.setup(cam)
	process_priority = 1000   # after the effect renderers fill their pool buckets
	print("[engine-fold] active on camera '%s' (%s)" % [cam.name,
		"NATIVE in-scene blend, linear — no fold layer" if _route_native else "Forward+ engine Pass B fold"])


func _make_mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	# Prims emit RAW display texels — no sRGB->linear on the texel; the fold twins do it structurally
	# (no srgb_to_linear flag left). The in-scene srgb_gamma keeps its 2.2 shader default: a look knob, not set here.
	m.set_shader_parameter("use_palette", false)
	return m


func _process(_dt: float) -> void:
	if _pool == null or _fold_root == null:
		return
	for c in _fold_root.get_children():
		_fold_root.remove_child(c)
		c.free()
	var buckets: Array = _pool.call("get_active_effect_buckets")
	var fold_idx := 0
	var bucket_ranks := {}
	for e in buckets:
		var bytes: PackedByteArray = e.get("unified_bytes", PackedByteArray())
		if bytes.is_empty():
			continue
		var all: PackedFloat32Array = bytes.to_float32_array()
		var tex: Texture2D = e.get("effect_tex_2d")
		var source_gain: float = 1.0 if e.get("normalized_modulation", false) else POOL_GOURAUD_GAIN
		# Paletted producers (tile cursor, trap) publish an INDEXED sheet + a CLUT; the fold shader samples
		# palette_texture at (idx, per-instance row). palette_rows feeds the row V divisor: RANGETILE 9, TRAP1 16.
		var use_palette: bool = e.get("use_palette", false)
		var palette_tex: Texture2D = e.get("palette_tex_2d")
		var palette_rows: int = int(e.get("palette_rows", 16))
		for run in e["runs"]:
			var mode: int = run["mode"]
			var base: int = run["base"]
			var cnt: int = run["count"]
			var stride: int = run.get("stride", 24)
			if cnt <= 0:
				continue
			var buf := PackedFloat32Array()
			buf.resize(cnt * 20)
			for i in range(cnt):
				var src := (base + i) * stride
				for fl in range(20):
					buf[i * 20 + fl] = all[src + fl]
				# #220 record[20] level_scale (mode3/ADD25 = 0.25): MultiMesh holds only 20 floats, so [20] falls
				# off — bake it into instance COLOR, else the fold ADD path folds ADD_25 at 4x (E065 Shiva overbright).
				if stride > 20:
					var lvl := all[src + 20]
					buf[i * 20 + 12] *= lvl
					buf[i * 20 + 13] *= lvl
					buf[i * 20 + 14] *= lvl
				buf[i * 20 + 12] *= source_gain
				buf[i * 20 + 13] *= source_gain
				buf[i * 20 + 14] *= source_gain
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _quad
			mm.instance_count = cnt
			mm.buffer = buf
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			var mat: ShaderMaterial = (_mat_replace if mode == 4 else (_mat_sub if mode == 2 else (_mat_mix if mode == 0 else _mat_add))).duplicate()
			if tex != null:
				mat.set_shader_parameter("effect_texture", tex)
				mat.set_shader_parameter("texture_size", tex.get_size())
			if use_palette and palette_tex != null:
				mat.set_shader_parameter("use_palette", true)
				mat.set_shader_parameter("palette_texture", palette_tex)
				mat.set_shader_parameter("palette_rows", float(palette_rows))
			inst.material_override = mat
			# Per-instance layer membership: join the SHARED fold layer (Fold.FOLD_LAYER — the partition Fold.add
			# carriers use) and stamp the int32 caller-order key via DepthMode.render_layer_order_for (ADR-0074):
			# primary = OT depth bucket x RANK_STRIDE, secondary = submission-stream rank (< RANK_STRIDE), which
			# preserves within-stream order incl. the DEMI add<->sub age tie-break inside a bucket.
			if not _route_native:
				inst.render_layer = Fold.FOLD_LAYER
				var depth: float = run.get("depth", 0.0)
				var bucket: int = DepthMode.render_layer_order_for(depth)
				var rank: int = bucket_ranks.get(bucket, 0)
				inst.render_layer_order = DepthMode.render_layer_order_for(depth, rank)
				bucket_ranks[bucket] = rank + 1
			inst.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
			_fold_root.add_child(inst)
			fold_idx += 1
	if fold_idx > 0 and not _logged:
		print("[engine-fold] folding %d runs through the engine" % fold_idx)
		_logged = true
