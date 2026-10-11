extends RefCounted
## The ENTIRE display-space fold "module" — THREE statics, no object (ADR-0074, ADR-0191,
## CONTEXT.md "Fold"):
##
##   add(carrier, material, order_z, rank)  the decorator that makes a carrier foldable (no-op off-fork)
##   owns() -> bool                         is the fold available in THIS BUILD
##   shader(folded, fallback) -> Shader     the two-way pick that hangs off owns()
##
## It was one static until 2026-08-27. What it is still NOT is material construction, attach or stamp:
## ADR-0074 made the material producer-owned and the ordering DepthMode's, and ADR-0191 dec. 4 re-refused
## a factory on a measurement 0074 did not have — only 6 of the 16 compositor_layer shaders are
## mechanical, and those six are already deduplicated one layer down, into two .gdshaderinc files,
## by dec. 6 (ADR-0191 dec. 4 carries the corrected numbers). A factory would
## also have to take texture / palette_texture / palette_rows across a seam with no business
## knowing them. There is no registry either (dec. 5): a table here would hold res://
## paths into the host and add a startup ordering whose failure mode is "the effect silently vanished."
##
## Membership in the engine's held-out pass is TWO per-instance properties (compositor_layer primitive),
## not just a material — hence one call that stamps both.
##
## `add` hands any GeometryInstance3D (a single-quad MeshInstance3D, a baked multi-quad ArrayMesh, or a
## batched MultiMeshInstance3D — all GeometryInstance3D) its monomorphic `compositor_layer` material AND
## its per-instance membership: `render_layer` = the shared FOLD_LAYER resource (which held-out target)
## + `render_layer_order` = its int32 caller-order key. The engine collects every instance carrying a
## valid `render_layer` whose shader declares `compositor_layer`, and paints them in ascending
## `render_layer_order` into the engine-owned target for that layer.
##
## Ordering is DepthMode's (render_layer_order_for), not the fold's: the producer supplies its own
## representative OT ordering key (order_z, view-space Z) and its submission-stream `rank` (0 for a lone
## quad). See DepthMode.render_layer_order_for and the "Fold order" glossary entry.

## The single shared held-out layer every fold carrier joins (one resource -> one partition, the engine's
## one-partition fast path). Reached by path so Fold.add and EngineFoldCompositor share the SAME cached
## instance (identical ObjectID = one layer) -- the ResourceLoader cache plus the memo below give that.
##
## LAZY, and that is the load-bearing part. `fold_layer.tres` declares a `CompositorRenderLayer`, a type
## only the fork's compositor_layer primitive registers, so a `const FOLD_LAYER := preload(...)` is a
## PARSE error on a build without it -- measured on stock 4.7.1 in a throwaway project:
##
##     ERROR: Cannot get class 'CompositorRenderLayer'.
##     ERROR: fold_layer.tres:21 - Parse Error: Can't create sub resource of type 'CompositorRenderLayer'.
##     SCRIPT ERROR: Parse Error: Could not resolve external class member "FOLD_LAYER".
##
## A parse error takes the WHOLE FILE with it, so `owns()` becomes "Nonexistent function" and the
## in-scene fallback this kernel exists to publish is unreachable on precisely the builds it is for.
## Deferring the load to first read makes the failure a null instead of a parse error, and the only
## reader is `add()`, behind `owns()`. A `static var` with a getter keeps the NAME identical, so every
## `Fold.FOLD_LAYER` call site is unchanged. See ADR-0191 dec. 14.
const FOLD_LAYER_PATH := "res://addons/exmateria_schema/compositing_key/fold_layer.tres"

## The memo behind FOLD_LAYER's getter. Untyped, not `CompositorRenderLayer` -- naming the fork-only
## type here would reintroduce the parse-time dependency the lazy load exists to remove.
static var _fold_layer = null

static var FOLD_LAYER:
	get:
		if _fold_layer == null:
			_fold_layer = load(FOLD_LAYER_PATH)
		return _fold_layer

## The ordering the fold is GIVEN rather than computes — reached by `preload`
## path, because this addon names its own internals by path and never by a
## global (ADR-0212 dec. 1).
const DepthMode = preload("res://addons/exmateria_schema/compositing_key/DepthMode.gd")


## Cached answer to owns(): -1 unqueried, 0 false, 1 true. A tri-state int rather than a bool plus a
## "queried" flag, so the unqueried state is unrepresentable as an answer. The value is a property of
## the BUILD and cannot change within a process, so one query is the whole lifetime's worth.
static var _owns_cache: int = -1


## Does this build own display-space compositing? True on a fork supporting the `compositor_layer`
## primitive under Forward+; false everywhere else, where a producer must draw its in-scene fallback.
##
## THE fold predicate (ADR-0191 dec. 1). It lived as a verbatim six-line copy at fourteen call sites,
## each reaching the CompositorAutopilot autoload by node-path string and duck-typing owns_compositing()
## on an untyped Node. It belongs to the kernel on three counts: a sibling addon asking it stops being
## a foreign-autoload reach, tests/ can ask without booting an autoload, and it names what the value
## actually is — a capability of the BUILD, not a state of the game.
##
## Feature-detect, never version-sniff: has_method guards builds predating the accessor, and
## is_compositor_layer_supported() is itself Forward+-only, so the two collapse into one honest query.
##
## THE QUERY GOES THROUGH `call()`, AND THAT IS NOT STYLE. GDScript resolves a named method on a native
## class at PARSE time, so spelling `RenderingServer.is_compositor_layer_supported()` makes the
## has_method() guard on the same expression unreachable -- measured on stock 4.7.1:
##
##     Parse Error: Static function "is_compositor_layer_supported()" not found in base
##                  "GDScriptNativeClass".
##     ... then: Invalid call. Nonexistent function 'owns' in base 'GDScript'.
##
## i.e. the feature detect took the predicate down with it. `call()` defers the lookup to run time,
## where has_method() can actually answer first. Both halves are needed and both were measured
## independently: with only the FOLD_LAYER fix in place, stock still failed on this line.
## ADR-0191 dec. 14.
## This is the SAME query CompositorAutopilot._ready takes, and CompositorAutopilot.active is written
## in exactly one place from exactly it — so this is not merely equivalent to the retired
## owns_compositing(), it is identical in every reachable state.
static func owns() -> bool:
	if _owns_cache < 0:
		_owns_cache = 1 if (RenderingServer.has_method("is_compositor_layer_supported")
			and RenderingServer.call("is_compositor_layer_supported")) else 0
	return _owns_cache == 1


## Pick between a producer's two shaders on the build predicate: the `compositor_layer` twin when
## this build folds, the in-scene twin when it does not.
##
## Takes Shader OBJECTS, never paths (ADR-0191 dec. 2). A load() on a mistyped path returns null, and
## a null shader here does not raise — the fold "just stops, with no error" (tests/FoldSurfaceTest.gd
## records that hazard by name). Callers hold preloaded consts, so the same typo is a parse error.
## Keeping paths out also keeps the kernel from naming a host file, which check_addon_portability.py
## forbids outright.
static func shader(folded: Shader, fallback: Shader) -> Shader:
	return folded if owns() else fallback


## Meta flag marking a carrier whose tree_exiting un-enroll hook is already wired (Fold.add may run
## every frame for pooled carriers, so connect at most once).
const _EXIT_HOOK_META := "_fold_exit_unenroll"

## Make `carrier` foldable: wear `material` (as material_override, which wins over any surface material)
## and carry its per-instance layer membership (render_layer = FOLD_LAYER) + the fold-order key for
## (order_z, rank). Idempotent — safe to call every frame as a carrier's depth changes (only order_z
## moves; material_override / render_layer re-assign the same RID cheaply).
##
## NO-OP when this build does not own compositing (`owns()` false) — it decorates nothing at all, not
## even the material_override. ADR-0191 dec. 12; `tests/FoldTest.gd` section 5 pins it.
static func add(carrier: GeometryInstance3D, material: Material, order_z: float, rank: int = 0) -> void:
	if carrier == null:
		return
	# SELF-GATED OFF-FORK (ADR-0191 dec. 12). `render_layer` / `render_layer_order` are
	# FORK-ONLY properties, so the two assignments below do not quietly do nothing on a build without
	# them — they RAISE. Measured on stock 4.7.1 in a throwaway project: `mi.render_layer = null`
	# gives "Invalid assignment of property or key 'render_layer' ... on a base object of type
	# 'MeshInstance3D'" and aborts the caller; the identical script survives on the 4.8 fork, which is
	# the control arm that makes the stock result mean something. Two production paths reached here
	# unguarded — CrystalSprite3D._publish (whose docstring claimed stock "renders nothing meaningful")
	# and the additive tile overlay via Tile.gd, which gates on BLEND MODE, not on the predicate.
	#
	# The gate is here rather than at those two call sites for dec. 3's reason: two spellings of one
	# fact is how one copy became fourteen. This kernel published owns(); a decorator that throws on
	# the build state owns() exists to describe is the kernel leaking that property back to every
	# caller. Off-fork a producer draws its in-scene fallback (dec. 1) and decorates nothing.
	#
	# The five `if folded: Fold.add(...) else: <render_priority>` sites keep their `if` — measured, it
	# is the `else` that needs the predicate, so this deletes no local anywhere. See Amendment 4 §3.
	if not owns():
		return
	carrier.material_override = material
	carrier.render_layer = FOLD_LAYER
	carrier.render_layer_order = DepthMode.render_layer_order_for(order_z, rank)
	# Drop layer membership the instant the carrier leaves the tree, before it is freed. NOTE: this is
	# belt-and-suspenders, NOT the fix for the SpinBox-arrow SIGSEGV it was originally added for
	# (b6400949d). Freeing an enrolled member is safe — rendering is single-threaded and the compositor
	# keeps no persistent per-member list, so a freed member just drops from next frame's rebuilt draw
	# list (EngineFoldCompositor frees enrolled carriers every frame). The real crash was a synchronous
	# free() nested in the SpinBox gui_input callstack (a tunable-write-back hazard); the fix is to defer
	# those rebuilds — see ADR-0068 W1–W3 + CONTEXT "Fold member lifetime". This hook is cheap and
	# harmless, so it stays. Hooked once per carrier.
	if not carrier.has_meta(_EXIT_HOOK_META):
		carrier.set_meta(_EXIT_HOOK_META, true)
		carrier.tree_exiting.connect(_unenroll.bind(carrier))


## Un-enroll a carrier from the fold layer (tree_exiting hook). Clears render_layer while the node is
## still valid. Belt-and-suspenders only (see add() — freeing an enrolled member is safe by itself).
## Guarded — the carrier is mid-teardown.
static func _unenroll(carrier: GeometryInstance3D) -> void:
	if carrier != null and is_instance_valid(carrier):
		carrier.render_layer = null
