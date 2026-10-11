extends RefCounted

## Single source of truth for PSX Ordering-Table depth modes + calibration.
##
## FFT sorts the battle scene back-to-front with one Ordering Table: a
## primitive's bucket is the projected Z of a representative point, plus a
## per-primitive bias selected by one of these modes. See
## docs/adr/0009-ordering-table-depth-is-one-model.md and the "Rendering
## depth" cluster in CONTEXT.md.
##
## The shader side lives in addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc; this
## script owns the enum and the calibrated magnitudes, and pushes them onto a
## material via apply(). The shader's uniform defaults mirror these values.

enum Mode {
	STANDARD = 0,        ## No bias — sorts at its natural projected depth.
	PULL_FORWARD_8 = 1,  ## ROM: -8 OT buckets toward front (the ~95% particle case).
	FIXED_FRONT = 2,     ## ROM: absolute bucket 8 — always near the front.
	FIXED_BACK = 3,      ## ROM: absolute bucket 0x17E — always at the back.
	FIXED_16 = 4,        ## ROM: absolute bucket 0x10 — near front, behind FIXED_FRONT.
	PULL_FORWARD_16 = 5, ## ROM: -16 OT buckets toward front.
	UNIT = 6,            ## Project nudge: unit sprite just in front of its tile.
	TILE_OVERLAY = 7,    ## Project nudge: between the tile surface and the unit.
	MAP_SKIRT = 8,       ## Project nudge: border/skirt geometry just BEHIND textured map faces.
	SHADOW = 9,          ## Project nudge: the unit's ground shadow, one hair BEHIND the sprite.
	                     ## Faithful to PSX inserting the shadow at the unit's OWN OT slot
	                     ## (ot_base + unit[0x128]*4): the shadow is projected from the SAME
	                     ## representative point as the sprite (not its own ground origin), so
	                     ## it co-sorts with the unit — front of the terrain it stands on,
	                     ## behind the sprite where they overlap. See UNIT_SHADOW_RENDERING.md.
}

## Godot world-units per PSX OT bucket. Anchored to research (8 buckets
## ~= 1.5 tiles; 1 tile = 1 Godot unit = FFT_UNITS_PER_TILE = 28 FFT units),
## tuned once in DepthDebugScene. NOT closed-form: FFT's near-ortho-perspective
## camera and our true-ortho camera have no exact bucket->world mapping (ADR-0009).
const UNITS_PER_OT_BUCKET := 0.19

## Sub-bucket rank stride for the display-space fold order (ADR-0074). A carrier's
## `render_layer_order` is `round(order_z / UNITS_PER_OT_BUCKET) * RANK_STRIDE` (the OT
## bucket, the primary key, shifted up) plus `rank` (a tie-break inside the bucket). The
## stride bounds per-bucket rank: a frame has at most a few hundred fold runs, so `rank`
## never reaches RANK_STRIDE and the depth bucket always dominates. The int32 order key
## (compositor_layer's `render_layer_order`) replaces the old float `sorting_offset` —
## no float32-ULP cliff, no NaN (an int can't be NaN). Lives here (not in the producers)
## so the fold-order encoding is defined once — see render_layer_order_for().
const RANK_STRIDE := 1 << 10

## Sub-bucket project nudges (world units), tuned in DepthDebugScene. Smaller
## than PULL_FORWARD_8 (~1.5 tiles) because these are hairline "in front of the
## surface under me" offsets, not ROM particle pulls.
## 0.23 (was 0.13, was 0.1), dialed on the live scene and materialized (ADR-0068 dec. 8).
## The ladder is one question asked three times — how far in front of the surface under it
## does a unit have to sit before its outline stops being eaten? 0.1 lost Ovelia's outline
## to the tower wall under the scn6 carry lift; 0.13 cleared her; 0.23 is what clearing it
## everywhere costs, and it is still an order of magnitude under PULL_FORWARD_8 (~1.5
## tiles), so it stays a hairline nudge rather than a ROM particle pull. Applied globally
## by `apply()`, not just the scenario rig.
##
## A `static var` (not `const`) because a `const` is frozen at parse time and could never be
## rewritten. ⚠️ THAT IS NECESSARY AND NOT SUFFICIENT: this home is still out of
## `tools/materialize_tunables.py`'s reach, and this dial was hand-work. See the bind site
## in `Unit.gd` — the follower is ONE hop and the reference from there is three.
## Read-only in practice (apply() + DepthDebugScene read it; nothing assigns it).
static var UNIT_FORWARD := 0.23
const TILE_OVERLAY_FORWARD := 0.05
## Shadow nudge: same magnitude as TILE_OVERLAY but a DISTINCT constant so the
## shadow can be tuned independently of the cursor/tile overlay. Strictly less
## than UNIT_FORWARD so the sprite always wins where it overlaps its own shadow;
## still far in front of the terrain (the shadow shares the sprite's base point,
## which already clears the floor). Tuned headful in ScenarioPlayer, not derived.
const SHADOW_FORWARD := 0.05
## Negative = behind. Breaks depth ties between black skirt and textured map edges.
const MAP_SKIRT_BACK := -0.02

## Fixed-mode absolute reversed-Z slots (Godot Forward+: near/front ~ 1.0). These belong to
## the RASTER path (ot_depth + the .glsl/.gdshaderinc occlusion DEPTH write) — do NOT reuse
## them as the compositor ordering key; see ORDER_Z_FIXED_* and ot_order_z below.
const FIXED_FRONT_DEPTH := 0.9999
const FIXED_16_DEPTH := 0.9990
const FIXED_BACK_DEPTH := 0.0001

## Fixed-mode sentinels for the COMPOSITOR ORDERING KEY (ot_order_z, view-space Z world units).
## Unlike FIXED_*_DEPTH (reversed-Z NDC, the raster/occlusion mirror), these live in the same
## view-space-Z world-unit scale as the relative modes so OTDepthPrimOrder buckets them
## consistently: nearer = LESS negative = LARGER, so FRONT is the largest (nearest / on top), 16
## just behind it, and BACK far behind typical combat content. MODERATE (not ±inf) on purpose so
## a lone fixed prim sorts to its extreme WITHOUT blowing OTDepthPrimOrder's per-frame bucket span
## (a battle effect's transparent prims span only a few world-units of depth). See #212 /
## COMPOSITOR_OT_BUCKET_WIDTH_PARITY.md.
const ORDER_Z_FIXED_FRONT := 3.0
const ORDER_Z_FIXED_16 := 2.0
const ORDER_Z_FIXED_BACK := -50.0

## Push the depth-mode selector + calibrated magnitudes onto a ShaderMaterial.
## Call once at material setup. Keeps GDScript authoritative over the shader
## uniform defaults.
static func apply(material: ShaderMaterial, mode: int) -> void:
	material.set_shader_parameter("depth_mode", mode)
	material.set_shader_parameter("ot_units_per_bucket", UNITS_PER_OT_BUCKET)
	material.set_shader_parameter("ot_unit_forward", UNIT_FORWARD)
	material.set_shader_parameter("ot_tile_overlay_forward", TILE_OVERLAY_FORWARD)
	material.set_shader_parameter("ot_shadow_forward", SHADOW_FORWARD)
	material.set_shader_parameter("ot_map_skirt_back", MAP_SKIRT_BACK)
	material.set_shader_parameter("ot_fixed_front", FIXED_FRONT_DEPTH)
	material.set_shader_parameter("ot_fixed_16", FIXED_16_DEPTH)
	material.set_shader_parameter("ot_fixed_back", FIXED_BACK_DEPTH)


## Representative point for a face's OT depth: the average of its vertices —
## FFT's GTE AVSZ3 (tri) / AVSZ4 (quad). Pure (positions in, point out); operate
## in the mesh's local space and bake the result into CUSTOM0 on EVERY vertex of
## the face, so the whole face shares one flat depth. A quad split into two
## triangles MUST feed both tris the same 4-vertex centroid or they z-fight along
## the split diagonal (the original reason CUSTOM0 exists). The map computes this
## at export time in Python; the GDScript per-face builders (effect callbacks,
## projectile models) share these. See ADR-0009 and the "Rendering depth" cluster.
static func tri_centroid(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (a + b + c) / 3.0


## CPU mirror of ot_depth() in addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc — the
## reversed-Z DEPTH for a WORLD-space representative point under the given camera.
## This is the RASTER key: it mirrors the shaders that write gl_FragDepth for the hardware
## occlusion test against the opaque depth buffer (ot_depth.gdshaderinc, and the engine-fold's
## effect_fold_*.gdshader). Modes 0..9 match the shader exactly.
##
## NOT the compositor FOLD-ORDER key — use ot_order_z() for that. The two were one function
## until #212: this NDC value is ~[-1,1] for the combat ortho camera (standard, NOT reversed-Z
## despite the naming), so bucketing it via a clamp[0,1] collapsed every combat prim into bucket
## 0 and made depth ordering inert. The fold now keys on view-space Z (ot_order_z); this stays
## the raster mirror. See research/working_documents/COMPOSITOR_OT_BUCKET_WIDTH_PARITY.md.
##
## `proj` is the camera's projection (Camera3D.get_camera_projection()); `view` is
## world->view (Camera3D.get_camera_transform().affine_inverse()). proj.z.z ==
## PROJECTION_MATRIX[2][2] in GLSL (column 2, row 2), the ortho toward-camera scale.
static func ot_depth(point: Vector3, proj: Projection, view: Transform3D, mode: int) -> float:
	# Fixed modes: absolute OT slots — ignore the point entirely.
	if mode == 2:
		return FIXED_FRONT_DEPTH
	if mode == 3:
		return FIXED_BACK_DEPTH
	if mode == 4:
		return FIXED_16_DEPTH

	# Base depth: project the representative point (reversed-Z NDC).
	var vp: Vector3 = view * point            # world -> view
	var clip: Vector4 = proj * Vector4(vp.x, vp.y, vp.z, 1.0)
	var base: float = clip.z / clip.w

	# Relative modes: shift toward camera by a world distance, then (for our ortho
	# camera) add distance * proj[2][2]. A toward-camera shift ADDS to reversed-Z DEPTH.
	var world_bias: float = 0.0
	if mode == 1:
		world_bias = 8.0 * UNITS_PER_OT_BUCKET       # PULL_FORWARD_8
	elif mode == 5:
		world_bias = 16.0 * UNITS_PER_OT_BUCKET      # PULL_FORWARD_16
	elif mode == 6:
		world_bias = UNIT_FORWARD                    # UNIT
	elif mode == 7:
		world_bias = TILE_OVERLAY_FORWARD            # TILE_OVERLAY
	elif mode == 8:
		world_bias = MAP_SKIRT_BACK                  # MAP_SKIRT (negative = behind)
	elif mode == 9:
		world_bias = SHADOW_FORWARD                  # SHADOW
	# mode 0 STANDARD: world_bias stays 0.

	return base + world_bias * proj.z.z


## The COMPOSITOR PRIM-ORDERING key: linear VIEW-SPACE Z in world units (PSX's SZ>>2 model),
## decoupled from NDC and the frustum. OTDepthPrimOrder buckets this at a fixed
## UNITS_PER_OT_BUCKET (0.19 world-unit) width — the PSX-calibrated OT bucket — so the per-prim
## depth separation reproduces the machine (COMPOSITOR_OT_BUCKET_WIDTH_PARITY.md, #212).
##
## Distinct from ot_depth(): that returns reversed-Z NDC for the RASTER DEPTH write (hardware
## occlusion vs the opaque buffer) and mirrors the shaders; this returns view-space Z for the CPU
## FOLD ORDER. They are DIFFERENT quantities — sharing one NDC value collapsed every combat prim
## to bucket 0 (the #212 bug), because get_camera_projection() on the ortho combat camera yields
## standard NDC-z ≈ [-1,1] (empirically ≈ -0.77), not the reversed-Z [0,1] the clamp assumed.
##
## `view` is world->view (Camera3D.get_camera_transform().affine_inverse()); `proj` is NOT
## needed (view-space Z is frustum-independent — that is the whole point). Smaller (more
## negative) Z = farther; OTDepthPrimOrder folds far->near so the nearer prim draws on top.
## Fixed modes (2/3/4) are absolute OT slots — they ignore the point and return view-Z sentinels.
static func ot_order_z(point: Vector3, view: Transform3D, mode: int) -> float:
	# Fixed modes: absolute OT slots — ignore the point, return the view-Z sentinel.
	if mode == 2:
		return ORDER_Z_FIXED_FRONT
	if mode == 3:
		return ORDER_Z_FIXED_BACK
	if mode == 4:
		return ORDER_Z_FIXED_16

	# Base: the representative point's view-space Z (linear in depth, frustum-independent).
	var d: float = (view * point).z

	# Relative modes: shift toward/away from the camera by a WORLD distance. Toward camera = less
	# negative view-Z = LARGER (nearer), so a forward pull ADDS; MAP_SKIRT_BACK (negative) pushes
	# back. round(d / UNITS_PER_OT_BUCKET) - 8 then equals PSX's post-shift bucket-8 exactly, so
	# these biases become byte-faithful integer OT-bucket offsets.
	var world_bias: float = 0.0
	if mode == 1:
		world_bias = 8.0 * UNITS_PER_OT_BUCKET       # PULL_FORWARD_8
	elif mode == 5:
		world_bias = 16.0 * UNITS_PER_OT_BUCKET      # PULL_FORWARD_16
	elif mode == 6:
		world_bias = UNIT_FORWARD                    # UNIT
	elif mode == 7:
		world_bias = TILE_OVERLAY_FORWARD            # TILE_OVERLAY
	elif mode == 8:
		world_bias = MAP_SKIRT_BACK                  # MAP_SKIRT (negative = behind)
	elif mode == 9:
		world_bias = SHADOW_FORWARD                  # SHADOW
	# mode 0 STANDARD: world_bias stays 0.

	return d + world_bias


## The display-space FOLD-ORDER encoding (ADR-0074): map an OT ordering key (ot_order_z, view-space
## Z world units) plus a submission-stream `rank` to the int32 a foldable carrier wears as its
## `render_layer_order` (the compositor_layer primitive's caller-order key). The engine's held-out
## pass paints layer members in ascending render_layer_order, so this is the paint/blend order —
## distinct from the depth *test* (occlusion), which is per-fragment.
##
## Primary key = the PSX-calibrated OT bucket `round(order_z / UNITS_PER_OT_BUCKET)` (the same
## bucketing OTDepthPrimOrder._bucket_of uses), shifted up by RANK_STRIDE so carriers interleave by
## TRUE depth regardless of producer. Secondary = `rank` (0..RANK_STRIDE-1), a sub-bucket tie-break
## that preserves a producer's within-stream order (e.g. OTDepthPrimOrder's DEMI add<->sub age
## tie-break) inside one bucket. A lone quad passes rank 0 and sits exactly on `bucket * RANK_STRIDE`.
## This is the ONE home for the encoding the producers (Fold.add, EngineFoldCompositor) share; the
## engine compares these keys with an exact int32 comparator (compositor_layer_order_sort.h).
static func render_layer_order_for(order_z: float, rank: int = 0) -> int:
	# rank must stay inside its sub-bucket: a rank >= RANK_STRIDE would spill into the
	# next depth bucket and silently corrupt fold order. Stripped in release builds.
	assert(rank >= 0 and rank < RANK_STRIDE, "fold rank %d out of [0, %d)" % [rank, RANK_STRIDE])
	return int(round(order_z / UNITS_PER_OT_BUCKET)) * RANK_STRIDE + rank


## The DEPTH-LADDER conversion (ADR-0077): a flat UI scene's rung index -> the world-space Z it
## mounts at. One PSX OT bucket per rung, so rung k lands on fold-order bucket k
## (render_layer_order_for(rung_z(k)) == k * RANK_STRIDE) and the reversed-Z DEPTH write separates
## the rungs with no z-fight. The ui3 cameras look down -Z, so LARGER rung = nearer = drawn on top.
##
## The third derivation from UNITS_PER_OT_BUCKET, alongside ot_order_z() and render_layer_order_for(),
## and the last to get a home: it used to live as a private static in each flat scene that has a
## ladder (DetailScene, FormationScene, UnitInfoCluster, UIUnitNameplate) with the multiply inlined
## at three more sites. CONTEXT.md's "Fold order" _Avoid_ already bans re-deriving the bucket
## per producer; this is where the ban points.
static func rung_z(rung: int) -> float:
	return float(rung) * UNITS_PER_OT_BUCKET


static func quad_centroid(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Vector3:
	return (a + b + c + d) * 0.25
