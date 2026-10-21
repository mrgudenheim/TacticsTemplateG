@tool
extends RefCounted

## PORT SIGNATURE — the render ROUTE, the one verb a member may name instead of the
## `CompositorAutopilot` autoload identifier. Same shape as `ScreenOverlayPort`,
## `TintedSurfacesPort`, `ExMateriaPlatform.SfxPort` and `TunePort`: resolve the
## singleton by NODE PATH, and answer something defined when it is absent.
##
## THE ROUTE IS DERIVED, NOT A BUILD FACT (ADR-0349 dec. 1):
##
##     Fold.owns()   the build fact, the kernel's, unchanged
##     route      =  override or not Fold.owns()      <- every producer reads THIS
##
## `Fold.owns()` answers *can this build fold?*. It cannot answer *is this cast drawing
## native?*, and the gap between those two questions is exactly the comparison override:
## on a fold-capable build with the override on, the producer is native while `owns()` is
## still true. Reading `owns()` as if it were the route is what made the frame MIXED —
## particles on one side, callbacks on the other. See docs/context/26-display-space-fold.md
## → **Route**, and use that word: not "mode", not "path".
##
## ⚠️ ABSENT ANSWER IS `not Fold.owns()`, AND THAT IS THE POINT (dec. 3). A consumer who
## installs this addon but not the router gets the CORRECT route for their build and loses
## only two things: the comparison override, and the camera re-attach across scene changes.
## It is the sensible identity — not a crash, and not a lie. Until #1453 ships the router
## with the addon, that configuration is also every stranger project.
## vault: .vaults/comments/exmateria_effects/port-contracts.md

## Aliased back to the bare spelling through the kernel's one global name (ADR-0212 dec. 1).
const Fold = ExMateriaSchema.Fold

## Resolved singleton, or `null`. Never caches a negative — `TintedSurfacesPort._port`.
static var _port: Node = null


## The live router node, or `null` where the consumer registered no autoload.
##
## Resolved by NODE path, never by file path, and that is what let #1451 land before #1453:
## the host's `project.godot` line provides `/root/CompositorAutopilot` today and the addon's
## `plugin.gd` provides the same NAME after the file moves, so this port is written against
## neither address (ADR-0349 §3).
static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"CompositorAutopilot")
	if n == null:
		return null
	_port = n
	return n


## Test seam — `TintedSurfacesPort._forget_port`.
static func _forget_port() -> void:
	_port = null


## THE ROUTE: `true` when a cast started now draws NATIVE (Godot's in-scene blend, in linear
## space, with the `*_native` / additive twins carrying their own sRGB linearize), `false`
## when it folds into the display-space scratch.
##
## 🔴 The property read is TYPE-CHECKED rather than trusted. A non-`@tool` autoload script is
## instantiated in the editor as a PLACEHOLDER that answers to the name with none of its
## members, so `get()` comes back `null` there — and `bool(null)` is `false`, which would
## silently claim "this cast folds" in exactly the configuration that cannot. An untyped
## answer falls through to the absent answer, which is the build fact.
static func is_native() -> bool:
	var p := _resolve()
	if p == null:
		return not Fold.owns()
	var v: Variant = p.get(&"native_blend")
	if typeof(v) != TYPE_BOOL:
		return not Fold.owns()
	return bool(v)
