extends RefCounted
## Single-sources the transparent-prim staging every combat display-space compositor producer
## shares (COMPOSITOR_DEPENDENCY_MAP.md §6.2). Before this, EffectParticleRenderer._write_instance
## and TrapEffect._emit_record each hand-rolled the identical 24-float record + parallel
## mode/depth/age keys + the OTDepthPrimOrder.order()->EffectMultiMeshPool.upload_unified publish
## ceremony — a byte layout duplicated across two files that had to change together on every format
## bump (slice C touched both). This is the one place that knows the layout; the Category-A
## producers (tiles / cursor / crystal) become new callers instead of a 3rd/4th copy-paste.
##
## Mode resolution deliberately stays at the CALL SITE — the renderer reads a per-frame int
## `semi_trans_mode`, Trap maps a per-emitter `blend_mode` string; they differ legitimately (§7).
## append() takes an ALREADY-RESOLVED mode int (0 mix / 1 add / 2 sub / 3 add25) so this stays a
## pure layout/order/publish helper, not a policy owner.
##
## Layout (ADR-0040): a 24-float record per prim — the 20-float packing (3x4 ROW-MAJOR transform =
## 4 corners + depth_mode in the basis, world origin in the 4th column; color rgba; custom(uv_rect)
## rgba) + per-prim level_scale at [20] (mode3/ADD25 = 0.25 else 1.0) + vec4 pad [21..23].
## Vault: [[Display Space Blend Fold]]

const OTDepthPrimOrder = preload("res://addons/exmateria_effects/render/OTDepthPrimOrder.gd")

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode

var _records: PackedFloat32Array = PackedFloat32Array()
var _modes: PackedInt32Array = PackedInt32Array()
var _depths: PackedFloat32Array = PackedFloat32Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
# World->view transform for the ot_order_z fold key (camera.get_camera_transform().affine_inverse()).
var _view: Transform3D = Transform3D()


func begin(view: Transform3D) -> void:
	"""Reset the staging for a new frame. `view` is the world->view transform used to derive each
	prim's ot_order_z fold key (identity leaves the key view-independent, e.g. a null camera)."""
	_records.clear()
	_modes.clear()
	_depths.clear()
	_ages.clear()
	_view = view


func append(basis: Basis, origin: Vector3, color: Color, uv_rect: Color,
		mode: int, depth_mode: int, age: float) -> void:
	"""Stage one transparent prim. `basis` packs the 4 corners + depth_mode, `origin` the world
	position, `color`/`uv_rect` the per-instance color + normalized UV rect. `mode` is already
	resolved (0..3). `depth_mode` is the ADR-0009 depth mode used for the ot_order_z fold key. `age`
	is the newest-on-top tie-break key (elapsed frames since spawn)."""
	var s := _records
	# row 0: (col0.x, col1.x, col2.x, origin.x)
	s.push_back(basis.x.x); s.push_back(basis.y.x); s.push_back(basis.z.x); s.push_back(origin.x)
	# row 1: (col0.y, col1.y, col2.y, origin.y)
	s.push_back(basis.x.y); s.push_back(basis.y.y); s.push_back(basis.z.y); s.push_back(origin.y)
	# row 2: (col0.z, col1.z, col2.z, origin.z)
	s.push_back(basis.x.z); s.push_back(basis.y.z); s.push_back(basis.z.z); s.push_back(origin.z)
	# color rgba
	s.push_back(color.r); s.push_back(color.g); s.push_back(color.b); s.push_back(color.a)
	# custom rgba (uv_rect)
	s.push_back(uv_rect.r); s.push_back(uv_rect.g); s.push_back(uv_rect.b); s.push_back(uv_rect.a)
	# [20] per-prim level_scale (mode3/ADD25 = 0.25, else 1.0) + vec4 pad [21..23].
	s.push_back(0.25 if mode == 3 else 1.0)
	s.push_back(0.0); s.push_back(0.0); s.push_back(0.0)
	_modes.push_back(mode)
	_depths.push_back(DepthMode.ot_order_z(origin, _view, depth_mode))
	_ages.push_back(age)


func count() -> int:
	return _modes.size()


func is_empty() -> bool:
	return _modes.is_empty()


func publish(pool, slot: int, use_palette: bool = false, palette_tex: RID = RID(),
		palette_rows: int = 16) -> void:
	"""OT-depth-order the staged prims (far->near, newest-on-top ties) and hand the unified 24-float
	buffer + run descriptors to the pool. Passing the ages is REQUIRED — producer staging is
	emitter/object-grouped, NOT back-to-front, so equal-depth add/sub ties would mis-order without it
	(OTDepthPrimOrder ORDERING CONTRACT). No-op-safe on a null pool / negative slot.

	The remaining pool producers (EffectParticleRenderer, TrapEffect) are MONOMORPHIC — always the
	particle contract (STP-window discard, camera billboard, anchor PAR) — so the fragment/geometry/PAR
	axes are no longer forwarded here (ADR-0074 ⑤). The light producers that varied them (crystal /
	tile_overlay / cursor) left the pool to become direct fold nodes with their own monomorphic
	materials. `use_palette` + the CLUT height are still per-producer (trap's indexed sheet)."""
	if pool == null or slot < 0:
		return
	var result: Dictionary = OTDepthPrimOrder.order(_records, _modes, _depths, _ages)
	var unified: PackedFloat32Array = result["unified"]
	var runs: Array = result["runs"]
	pool.upload_unified(slot, unified.to_byte_array(), _modes.size(), runs, use_palette, palette_tex,
		palette_rows)


# --- Read accessors (test surface + any producer that still needs the raw staging). ---

func records() -> PackedFloat32Array:
	return _records


func modes() -> PackedInt32Array:
	return _modes


func depths() -> PackedFloat32Array:
	return _depths


func ages() -> PackedFloat32Array:
	return _ages
