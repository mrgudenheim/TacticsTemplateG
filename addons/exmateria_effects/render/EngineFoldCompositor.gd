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
## FOLD requires 4.8-dev + Forward+; native/GL uses setup_native().
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
const FOLD_ADD := preload("res://addons/exmateria_effects/render/effect_fold_add.gdshader")
const FOLD_SUB := preload("res://addons/exmateria_effects/render/effect_fold_sub.gdshader")
const FOLD_MIX := preload("res://addons/exmateria_effects/render/effect_fold_mix.gdshader")

# The IN-SCENE set: same shading minus compositor_layer, native Forward+ blend. native_blend is now TWO
# things (#1352): the PRODUCTION ROUTE off-fork (standing down instead is what made transparent particles
# silently vanish) and the #7916 comparison side on the fork — CompositorAutopilot decides, this obeys.
# The in-scene half linearizes its own texel (tonemap = the return leg a fold lacks): pow not shareable, see check_no_pow_in_fold.py.
const NATIVE_ADD := preload("res://addons/exmateria_effects/render/effect_native_add.gdshader")
const NATIVE_SUB := preload("res://addons/exmateria_effects/render/effect_native_sub.gdshader")
const NATIVE_MIX := preload("res://addons/exmateria_effects/render/effect_native_mix.gdshader")

## When true, materialise carriers with the NATIVE in-scene set (no layer, no FoldSurface); set by CompositorAutopilot.
var native_blend := false

# Pool-envelope -> display-gouraud gain (retired psx_brightness global, ADR-0074 endgame): the POOL decodes
# its curve to /255, so color_modulate is only the pool's envelope; this bakes the ÷255->÷128 lift into the
# fold COLOR — the single choke point every pooled run (particles + trap) finalizes through, so the global
# can be deleted. Exact retired 2.2 = net-neutral: do NOT "fix" to /128 (DEMI2 audit: FAITHFUL). See check_no_psx_brightness_in_fold.py.
const POOL_GOURAUD_GAIN := 2.2

var _pool: Node
var _fold_root: Node3D
var _quad: QuadMesh
var _mat_add: ShaderMaterial
var _mat_sub: ShaderMaterial
var _mat_mix: ShaderMaterial
var _fold_surface: FoldSurface
var _logged := false


## Standalone native entry, ONLY when the renderer cannot fold (e.g. GL). ONCE after adding to the scene.
## Returns false on a fold-capable renderer without setup: callbacks still select Fold.owns() and would be
## stranded. Keep one producer for the active playback scene; freeing it frees its carriers.
func setup_native(cam: Camera3D) -> bool:
	if Fold.owns():
		push_warning("[engine-fold] setup_native requires a non-fold-capable renderer; use setup(camera) for folded callbacks")
		return false
	native_blend = true
	setup(cam)
	return _fold_root != null


func setup(cam: Camera3D) -> void:
	if cam == null:
		push_warning("[engine-fold] no camera — engine-fold compositor disabled")
		return
	_pool = Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")
	if _pool == null:
		push_warning("[engine-fold] no EffectMultiMeshPool — disabled")
		return
	_quad = QuadMesh.new()
	if native_blend:
		# In-scene: one twin per blend mode, each linearizes its own texel (tonemap = the return leg).
		# 25%-add (ADD_25) rides NATIVE_ADD — its 0.25 level_scale is baked into COLOR below, as in the fold path.
		_mat_add = _make_mat(NATIVE_ADD)
		_mat_sub = _make_mat(NATIVE_SUB)
		_mat_mix = _make_mat(NATIVE_MIX)
	else:
		_mat_add = _make_mat(FOLD_ADD)
		_mat_sub = _make_mat(FOLD_SUB)
		_mat_mix = _make_mat(FOLD_MIX)
	_fold_root = Node3D.new()
	_fold_root.name = "EngineFoldPrims"
	add_child(_fold_root)
	if not native_blend:
		# Pass A/C display-space scratch is FoldSurface's (ADR-0074); this owns only the carrier rebuild.
		# In native-blend mode there is no fold scratch — carriers blend into the scene buffer.
		_fold_surface = FoldSurface.new()
		_fold_surface.setup(cam)
	process_priority = 1000   # after the effect renderers fill their pool buckets
	print("[engine-fold] active on camera '%s' (%s)" % [cam.name,
		"NATIVE in-scene blend, linear — no fold layer" if native_blend else "Forward+ engine Pass B fold"])


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
	for e in buckets:
		var bytes: PackedByteArray = e.get("unified_bytes", PackedByteArray())
		if bytes.is_empty():
			continue
		var all: PackedFloat32Array = bytes.to_float32_array()
		var tex: Texture2D = e.get("effect_tex_2d")
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
				# ADR-0074 endgame: bake the pool-envelope gain (retired psx_brightness) into COLOR — net-neutral relocation.
				buf[i * 20 + 12] *= POOL_GOURAUD_GAIN
				buf[i * 20 + 13] *= POOL_GOURAUD_GAIN
				buf[i * 20 + 14] *= POOL_GOURAUD_GAIN
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _quad
			mm.instance_count = cnt
			mm.buffer = buf
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			var mat: ShaderMaterial = (_mat_sub if mode == 2 else (_mat_mix if mode == 0 else _mat_add)).duplicate()
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
			if not native_blend:
				inst.render_layer = Fold.FOLD_LAYER
				inst.render_layer_order = DepthMode.render_layer_order_for(float(run.get("depth", 0.0)), fold_idx)
			inst.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
			_fold_root.add_child(inst)
			fold_idx += 1
	if fold_idx > 0 and not _logged:
		print("[engine-fold] folding %d runs through the engine" % fold_idx)
		_logged = true
