extends Node
## Branch-wide "compositor is always on" autopilot (compositor-displayspace-blend).
##
## The intent on this branch: EVERY scene you launch folds its effects through the ENGINE-fold
## compositor (EngineFoldCompositor, Godot 4.8-dev Pass B) — no per-scene wiring, no wondering
## whether a given scene's effects went through the compositor or not. This autoload watches the
## live 3D camera and keeps EngineFoldCompositor attached to it across scene changes.
##
## IT ATTACHES ON EVERY BUILD; what the BUILD predicate picks is WHICH SHADER SET (#1352). On a fork
## that reports the `compositor_layer` primitive (Forward+-only) the carriers join the fold layer and
## blend in display space. On stock — or any build predating the primitive — EngineFoldCompositor is
## attached in NATIVE mode instead: same carriers, the `effect_native_*` in-scene twins, Godot's linear
## blend, and the sRGB->linear pow those twins carry so each sprite's own colour survives the trip.
##
## It used to `set_process(false)` off-fork and stand down entirely, and that is the defect this
## replaced. Standing down meant nothing ever materialized the pool's transparent prims: no error, no
## missing-material warning, no shader compile to fail — the opaque particle pass kept drawing and the
## transparent half was simply absent. Silent by construction, which is the failure class this whole
## subsystem exists to stop having. The raw-RD GLSL fallback (CombatDisplaySpaceComposite /
## CombatCompositeDriver) was retired in #228 Phase 3, so the engine-fold is the only display-space
## compositor — but "no display-space compositor" must still mean "drawn in linear", never "not drawn".
##
## ⚠️ THE NATIVE ROUTE IS NOT PARITY. Godot blends it in LINEAR, the PSX blends in DISPLAY space, and
## `(a^g + b^g)^(1/g) != a + b` — overlapping adds read dimmer and blend_sub clamps differently. The
## claim is "visible, and per-sprite colour-correct", nothing stronger. See
## addons/exmateria_effects/render/effect_particle_native.gdshaderinc.
##
## MUST be launched on the fork: bin/godot.linuxbsd.editor.dev.x86_64 --rendering-method forward_plus.

## ADR-0211 dec. 4 — the addon's façade is its whole symbol surface, so the
## compositor arrives as a TYPE rather than as a path this file has to spell.
## It was a `const ENGINE_FOLD` STRING naming the file's old `src/effects/`
## address, `load()`ed at attach time, until extraction #7 (#1225): repointed, that
## string would have been the one PRODUCTION `res://addons/exmateria_effects/…`
## site `check_lattice_scene.py` criterion 4 scored, and a `load()` of a path this
## file also spells is an indirection with no reader.
const EngineFoldCompositor = ExMateriaEffects.EngineFoldCompositor

## True when this build supports the compositor_layer primitive (Forward+). The PUBLIC read of that
## fact is Fold.owns() (ADR-0191) — this is the autopilot's own copy, used only to decide whether to
## run at all, and nothing outside this file reads it.
var active := false

var _cam: Camera3D = null
var _fold: Node = null   # the live EngineFoldCompositor, re-created per camera

## Demo/compare OVERRIDE (#7916): force the native in-scene set on a build that CAN fold, so the muddy
## linear-blend result can be held against the display-space one. Opt-in; flip via set_native_blend()
## (the Effect Studio render-layer button). It is an override ON TOP OF the predicate, not the route
## itself — off-fork there is no fold to switch back to, so clearing it changes nothing.
var native_blend_override := false

## The EFFECTIVE route, mirrored onto every EngineFoldCompositor _attach() builds. Written in exactly
## two places (_ready and set_native_blend) and both go through _route_native().
var native_blend := false


## The route: native in-scene when this build cannot fold, or when the demo override asks for it.
##
## It reads `active` rather than taking its own Fold.owns(), and that is deliberate in BOTH directions.
## `active` is already this file's independent evaluation of the same fact (see _ready) — a third query
## here would be a third spelling, which is how one copy became fourteen. And routing on the SAME local
## the oracle compares means a build whose predicate says "no fold" cannot also be handed fold shaders.
func _route_native() -> bool:
	return native_blend_override or not active


## Set the demo override and re-route if that changes the effective side, rebuilding the
## EngineFoldCompositor so the new shader set + render path take effect immediately.
##
## Returns the EFFECTIVE route so a caller's UI cannot lie: off-fork `set_native_blend(false)` returns
## true, because clearing the override does not conjure a fold into a build that has none. The Effect
## Studio button adopts this return value rather than its own guess.
func set_native_blend(v: bool) -> bool:
	native_blend_override = v
	var want := _route_native()
	if want == native_blend:
		return native_blend
	native_blend = want
	_cam = null   # force _attach to rebuild against the current camera
	_attach(get_viewport().get_camera_3d())
	return native_blend


func _ready() -> void:
	# The feature detect lives in Fold.owns() (ADR-0191 dec. 1) — this autoload used to own it and
	# publish it as owns_compositing(), which fourteen call sites then copied verbatim. The query is a
	# property of the BUILD, so the kernel is its honest home.
	#
	# This local query is NOT owns_compositing() coming back: that method was PUBLISHED and duck-typed
	# by fourteen foreign PRODUCTION callers, and dec. 3 deletes it. `active` has exactly one reader
	# outside this file — tests/FoldTest.gd, which exists to compare it against Fold.owns(). The
	# difference is not privacy, it is that one test reading a value in order to check it is the
	# opposite of fourteen producers reading it in order to route on it.
	# What the local query is, is the SECOND INDEPENDENT EVALUATION that FoldTest asserts against. dec. 1 rests on the claim that a kernel-side owns() is "identical in every
	# reachable state" to the copies it replaced, and the only executable check behind that claim is two
	# code paths computing the answer separately and agreeing. Write `active = Fold.owns()` here and the
	# assertion becomes x == x — measured: seeding owns() to return the WRONG answer left FoldTest's
	# oracle assert GREEN, because both sides moved together. So this duplication is deliberate. It is
	# not a leftover copy; it IS the test. Keep it byte-identical to Fold.owns()'s query.
	#
	# Byte-identical INCLUDES the `call()`. A direct `RenderingServer.is_compositor_layer_supported()`
	# resolves at PARSE time on a native class, so off-fork it is a parse error that takes this whole
	# autoload down and the has_method() guard beside it never runs — the same trap Fold.owns() carries
	# the measurement for. Two independent evaluations are only independent while both of them compile.
	active = (RenderingServer.has_method("is_compositor_layer_supported")
		and RenderingServer.call("is_compositor_layer_supported"))
	native_blend = _route_native()
	if active:
		print("[compositor-autopilot] ACTIVE — engine-fold on for every scene (compositor_layer supported)")
	else:
		# NOT "standing down" any more (#1352): _process keeps running and _attach still builds an
		# EngineFoldCompositor, in native mode. The line says which SHADER SET the effects get, because
		# the thing that used to be invisible here was that they got NONE.
		print("[compositor-autopilot] no compositor_layer here (%s / %s) — effects render IN-SCENE (native blend, linear)"
			% [Engine.get_version_info().get("string", "?"), RenderingServer.get_current_rendering_method()])


func _process(_dt: float) -> void:
	# Keep the engine-fold pinned to the current scene's active 3D camera. When the camera changes
	# (scene switch, camera toggled current), rebuild the fold against the new one.
	var cam := get_viewport().get_camera_3d()
	if cam != null and is_instance_valid(_cam) and cam == _cam and is_instance_valid(_fold):
		return
	_attach(cam)


func _attach(cam: Camera3D) -> void:
	if _fold != null and is_instance_valid(_fold):
		_fold.queue_free()
	_fold = null
	_cam = null
	if cam == null:
		return   # no 3D camera yet (loading / a 2D-only scene) — try again next frame
	_fold = EngineFoldCompositor.new()
	_fold.name = "EngineFoldCompositor"
	add_child(_fold)
	# ONE VERB, and no flag mirrored in first (#1452). The producer reads the route through
	# `RoutePort`, which resolves THIS node and reads `native_blend` below — so the value still comes
	# from here, but it arrives as the port's answer rather than as a field this file reaches in and
	# writes. `native_blend` must therefore be current BEFORE `_attach` runs; `_ready` and
	# `set_native_blend` are the only two writers and both go through `_route_native()`.
	if not _fold.setup_auto(cam):
		push_warning("[compositor-autopilot] producer refused the camera — no transparent carriers this attach")
	_cam = cam
	print("[compositor-autopilot] attached engine-fold to camera '%s' (%s)"
		% [cam.name, "NATIVE in-scene" if native_blend else "display-space fold"])
