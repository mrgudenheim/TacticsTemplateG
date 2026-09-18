extends Node3D
## Global shared MultiMesh pool for batched effect particle rendering (ADR-0040)
##
## Pre-creates N effect slots at game startup. #227: each slot is now ONE MultiMeshInstance3D —
## RM_OPAQUE (canvas + depth, backs #210), the only in-scene draw. It carries the opaque shader on a
## fixed material; the per-effect sheet rides the slot's plain `_effect_tex` field (set via
## set_effect_texture on borrow). The four RM_MODE0..3 blend-mode carriers were retired — the combat
## carrier builder draws the transparent prims published as CPU records below, so the
## mode MultiMeshes (and their "stash the sheet on a mode material and read it back" indirection) are
## gone.
##
## Per-instance state (corners, depth_mode, uv_rect, color_modulate, semi_trans_on) is packed into
## the MultiMesh's per-instance buffers — see EffectParticleRenderer.gd for the packing and
## effect_particle_stp.gdshaderinc for the shader-side unpack.
##
## Each slot also owns unified 24-float CPU records and depth-ordered runs. Particle and TRAP
## producers publish through upload_unified; EngineFoldCompositor builds MultiMesh carriers from
## these records in BOTH native and fold modes. No RenderingDevice resource is required.
##
## Effect spawn becomes a slot pop + one set_effect_texture. Replaces the per-MeshInstance3D
## EffectMeshPool path that ADR-0040 retired.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Effect MultiMesh Pool]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const WARMUP_TOTAL_SLOTS: int = 64       # Concurrent effects pre-warmed
const WARMUP_SLOTS_PER_FRAME: int = 8
const INITIAL_INSTANCE_COUNT: int = 32   # Per (slot, render_mode) MultiMesh
const GROWTH_INSTANCE_COUNT: int = 32

# #227: only the opaque draw survives per slot. RM_OPAQUE names the one in-scene MultiMesh (canvas +
# depth, backs #210); the RM_MODE0..3 blend-mode carriers were retired — the display-space compositor
# consumes transparent CPU records, and the effect sheet moved to the plain _effect_tex
# slot field. The compositor's mode->pipeline mapping rides the run descriptors, not a pool constant.
const RM_OPAQUE: int = 0

# #227: only the opaque shader — the pool draws only RM_OPAQUE in-scene. The four
# effect_particle_mode0..3 shaders are no longer loaded here (the transparent fold happens in the
# display-space compositor, not a per-mode in-scene material).
const _SHADER_PATHS: Array = [
	"res://addons/exmateria_effects/render/effect_particle_opaque.gdshader",
]

# Each slot is { _opaque_mm: MultiMeshInstance3D, _opaque_mat: ShaderMaterial, _effect_tex: Texture2D,
# _unified_bytes/_runs/_count, _use_palette/_palette_tex_2d } — #227 collapsed the old
# 5-wide mm[]/mat[] carriers to the single opaque draw + the plain sheet/palette fields.
var _all_slots: Array[Dictionary] = []
var _available_indices: Array[int] = []  # Free-list stack (LIFO)

var _shared_quad: QuadMesh
var _shaders: Array[Shader] = []  # parallel to _SHADER_PATHS (opaque only since #227)

var _warmup_created: int = 0
var _warmup_done: bool = false

# #227: only RM_OPAQUE draws in-scene (canvas + depth, backs #210). The display-space compositor
# consumes transparent CPU records (combat AND Studio/viewer, slice D #221)
# — so the RM_MODE0..3 blend-mode carriers, the old `_mode_carriers_visible` gate, and the in-scene
# LINEAR blend fallback were all retired.


func _ready() -> void:
	# Shared quad mesh (1×1 in PSX units, scaled in the vertex shader)
	_shared_quad = QuadMesh.new()
	_shared_quad.size = Vector2(1.0, 1.0)

	# Load the slot shader(s) once (#227: opaque only)
	_shaders.resize(_SHADER_PATHS.size())
	for i in range(_SHADER_PATHS.size()):
		_shaders[i] = load(_SHADER_PATHS[i])


func _process(_delta: float) -> void:
	if _warmup_done:
		set_process(false)
		return
	_warmup_frame()


func _warmup_frame() -> void:
	var to_create: int = mini(WARMUP_SLOTS_PER_FRAME, WARMUP_TOTAL_SLOTS - _warmup_created)
	for i in range(to_create):
		_create_slot()
	_warmup_created += to_create

	if EffectsDebug.particle():
		print("[EffectMultiMeshPool] Warmup: %d / %d slots" % [_warmup_created, WARMUP_TOTAL_SLOTS])

	if _warmup_created >= WARMUP_TOTAL_SLOTS:
		_warmup_done = true
		if EffectsDebug.particle():
			print("[EffectMultiMeshPool] Warmup complete: %d slots ready" % _all_slots.size())


func _create_slot() -> void:
	var slot_idx: int = _all_slots.size()

	# #227: one MultiMesh per slot — RM_OPAQUE (canvas + depth, backs #210). The four RM_MODE0..3
	# blend-mode carriers were retired (the compositor folds transparent prims from the unified SSBO).
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _shared_quad
	multimesh.instance_count = INITIAL_INSTANCE_COUNT
	multimesh.visible_instance_count = 0

	var mat := ShaderMaterial.new()
	mat.shader = _shaders[RM_OPAQUE]

	var mm_inst := MultiMeshInstance3D.new()
	mm_inst.multimesh = multimesh
	mm_inst.material_override = mat
	mm_inst.name = "Slot_%d_RM_OPAQUE" % slot_idx
	# Wide custom AABB — particles travel away from the slot's origin, and the basis stores corner
	# data (not a transform), so per-instance AABB computation would be wrong. The slot is parented
	# under this autoload but global_transform reads the effect's world origin per instance.
	mm_inst.custom_aabb = AABB(Vector3(-128.0, -128.0, -128.0), Vector3(256.0, 256.0, 256.0))
	mm_inst.visible = false
	add_child(mm_inst)

	# CPU records and ordinary textures feed BOTH native and fold MultiMesh carriers.
	# The retired RD buffer is not a prerequisite for publication (ADR-0200 dec. 3).
	_all_slots.append({
		"_opaque_mm": mm_inst, "_opaque_mat": mat,
		"_unified_bytes": PackedByteArray(), "_runs": [], "_count": 0,
		"_effect_tex": null, "_palette_tex_2d": null,
	})
	_available_indices.append(slot_idx)


func borrow_slot() -> int:
	"""Pop one slot index from the free list. Grows on demand."""
	if _available_indices.is_empty():
		_create_slot()
		if EffectsDebug.particle():
			print("[EffectMultiMeshPool] On-demand growth: +1 slot (total %d)" % _all_slots.size())
	var idx: int = _available_indices.pop_back()
	# #227: only RM_OPAQUE draws in-scene (canvas + depth). The compositor folds transparent prims
	# from the unified buffer; nothing else renders in-scene.
	var opaque: MultiMeshInstance3D = _all_slots[idx]["_opaque_mm"]
	opaque.visible = true
	opaque.multimesh.visible_instance_count = 0
	# Clear the CPU submission before reusing the slot.
	_all_slots[idx]["_unified_bytes"] = PackedByteArray()
	_all_slots[idx]["_count"] = 0
	_all_slots[idx]["_runs"] = []
	_all_slots[idx]["_use_palette"] = false
	_all_slots[idx]["_palette_rows"] = 16
	_all_slots[idx]["_effect_tex"] = null  # #227: sheet set by the producer after borrow
	_all_slots[idx]["_palette_tex_2d"] = null  # engine-fold harness: palette as a Texture2D (set by paletted producers)
	return idx


func release_slot(idx: int) -> void:
	"""Hide the slot's opaque MultiMesh, reset its visible count, return to free list."""
	if idx < 0 or idx >= _all_slots.size():
		return
	var opaque: MultiMeshInstance3D = _all_slots[idx]["_opaque_mm"]
	opaque.multimesh.visible_instance_count = 0
	opaque.visible = false
	_all_slots[idx]["_unified_bytes"] = PackedByteArray()
	_all_slots[idx]["_count"] = 0
	_all_slots[idx]["_runs"] = []
	_all_slots[idx]["_effect_tex"] = null  # #227: released slot holds no sheet
	_available_indices.append(idx)


func get_multimesh(idx: int) -> MultiMesh:
	return _all_slots[idx]["_opaque_mm"].multimesh


func get_material(idx: int) -> ShaderMaterial:
	return _all_slots[idx]["_opaque_mat"]


func set_effect_texture(idx: int, tex: Texture2D) -> void:
	"""#227: stash this slot's effect sheet on the plain `_effect_tex` field. The compositor reads it
	back via get_active_effect_buckets (once repointed in commit 3), replacing the sheet's old home
	on a mode ShaderMaterial. Called by every producer (EffectParticleRenderer, TrapEffect) after
	borrow."""
	if idx < 0 or idx >= _all_slots.size():
		return
	_all_slots[idx]["_effect_tex"] = tex


func set_palette_texture(idx: int, tex: Texture2D) -> void:
	"""Store the CLUT for native and fold ShaderMaterials. TrapEffect supplies this after borrow;
	RGBA producers need no palette. Published as palette_tex_2d, never as an RD texture."""
	if idx < 0 or idx >= _all_slots.size():
		return
	_all_slots[idx]["_palette_tex_2d"] = tex


func ensure_instance_capacity(idx: int, needed: int) -> void:
	"""Grow the slot's opaque MultiMesh instance_count if needed."""
	var multimesh: MultiMesh = _all_slots[idx]["_opaque_mm"].multimesh
	if multimesh.instance_count >= needed:
		return
	var new_count: int = maxi(needed, multimesh.instance_count + GROWTH_INSTANCE_COUNT)
	multimesh.instance_count = new_count
	if EffectsDebug.particle():
		print("[EffectMultiMeshPool] Grew slot %d to %d instances" % [idx, new_count])


func get_available_count() -> int:
	return _available_indices.size()


# --- #211/#217/#218: combat display-space compositor integration ---

# Keep the ignored palette_tex argument so existing stager callers need no interface change.
# The actual CLUT comes from set_palette_texture, never an RD handle.
@warning_ignore("unused_parameter")
func upload_unified(idx: int, bytes: PackedByteArray, count: int, runs: Array,
		use_palette: bool = false, palette_tex: RID = RID(), palette_rows: int = 16) -> void:
	"""Publish CPU records and ordered run descriptors for native or fold carriers immediately.
	Records retain the 24-float layout (ADR-0040); runs carry mode/base/count/stride/depth.
	palette_tex is an ignored legacy argument; set_palette_texture supplies the actual CLUT."""
	if idx < 0 or idx >= _all_slots.size():
		return
	var slot: Dictionary = _all_slots[idx]
	slot["_runs"] = runs
	slot["_count"] = count
	slot["_use_palette"] = use_palette
	# Palette texture HEIGHT (trap's TRAP1 palette is 16 rows, the tile cursor's RANGETILE 9). The
	# compositor's fold divides the CLUT row V by this, so effects of different height can coexist.
	slot["_palette_rows"] = palette_rows
	# Immediately available to the carrier builder, including GL Compatibility without an RD.
	slot["_unified_bytes"] = bytes


func get_active_effect_buckets() -> Array:
	"""Enumerate active CPU submissions for native and fold carriers (ADR-0200 dec. 3).
	A batch needs records, runs, a positive count and an ordinary Texture2D, not an RD handle.
	Returns unified_bytes, runs, effect_tex_2d, palette_tex_2d, use_palette and palette_rows."""
	var out: Array = []
	var avail := {}
	for i in _available_indices:
		avail[i] = true
	for idx in range(_all_slots.size()):
		if avail.has(idx):
			continue
		var slot: Dictionary = _all_slots[idx]
		var count: int = slot["_count"]
		var runs: Array = slot["_runs"]
		if count <= 0 or runs.is_empty():
			continue
		var bytes: PackedByteArray = slot["_unified_bytes"]
		if bytes.is_empty():
			continue
		# #227: effect sheet from the slot's plain _effect_tex field (set by the producer via
		# set_effect_texture), NOT read back off a mode ShaderMaterial. The mode-material round-trip is
		# gone; the field is the sole source of truth.
		var tex: Texture2D = slot["_effect_tex"]
		if tex == null:
			continue
		# A paletted producer (TrapEffect's indexed TRAP1 sheet) sets these via upload_unified; the
		# RGBA renderer path leaves them off (default false / null palette).
		var use_palette: bool = slot.get("_use_palette", false)
		out.append({
			"runs": runs,
			"effect_tex_2d": tex,
			"unified_bytes": bytes,
			"palette_tex_2d": slot.get("_palette_tex_2d", null),
			"use_palette": use_palette,
			"palette_rows": slot.get("_palette_rows", 16),
		})
	return out
