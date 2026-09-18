@tool
extends RefCounted
## The gameplay-event PORT SIGNATURE — what an addon may name instead of the
## `EventBus` autoload.
##
## `src/core/EventBus.gd` is registered by the HOST's `project.godot [autoload]`
## block, so naming it from inside an addon is the same standalone-parse break
## `TunePort` and `DisplayPort` exist to fix: every stranger rig declares an EMPTY
## `[autoload]` block, and an addon cannot ship `project.godot` entries (ADR-0262
## dec. 6). Same shape as its two siblings — a `class_name` an installed addon
## carries, soft-bound to the singleton by node path at call time (ADR-0175 dec. 2).
##
## Two verbs, both SUBSCRIBE, added because `UIRosterBar` and `UIVitalsRoster`
## reached for exactly these two signals and nothing else (#1274, ADR-0308).
##
## 🔴 **THIS PORT HALF IS SUBSCRIBE-ONLY, AND THAT IS A STATED ASYMMETRY RATHER
## THAN A COMPLETE SURFACE.** `EventBus` also publishes `emit_unit_hp_changed`,
## `emit_unit_mp_changed`, `emit_unit_died` and the `unit_died` signal; none of
## them is reached by any addon today, so none is here. `DisplayPort`'s own
## docstring records what that costs when it goes unsaid — #590 shipped
## `set_camera_angle` without its read, and the missing half *"reads as complete
## for exactly as long as nobody outside the host wants the value back"* (ADR-0234).
## So: the emit direction is ABSENT, not unnecessary. The first addon that wants to
## RAISE a unit event adds `emit_*` here and does not go back to the identifier.
##
## 🔴 **THE ABSENT BRANCH IS SILENCE, AND THAT IS THE RIGHT IDENTITY FOR A
## SUBSCRIPTION.** A consumer installing this addon into a project with no event
## bus gets a roster that never receives a live HP change — it still builds, still
## draws, still shows the values it was handed. A `null` propagated into `.connect`
## would instead take down `_ready()` on a UI element whose whole job is to render
## whether or not anything is changing. The verbs return `false` so a caller that
## cares can tell "not connected" from "connected"; both call sites today ignore
## it, which is correct for them and is why the return exists rather than a `void`.

## Resolved singleton, or `null`. Same cache discipline as `TunePort` and
## `DisplayPort`: never caches a negative, and `has_signal` rejects any node that
## answers to the name while carrying none of the channel.
static var _port: Node = null


static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"EventBus")
	if n == null or not n.has_signal(&"unit_hp_changed"):
		return null
	_port = n
	return n


## Test seam — see `TunePort._forget_port` for why `is_instance_valid` is not the
## same question as "does the lookup still succeed".
static func _forget_port() -> void:
	_port = null


## Subscribe `c` to the host's `unit_hp_changed(unit, old_hp, new_hp)`.
##
## Returns `true` when the subscription is live. Idempotent: a second call with the
## same `Callable` is a no-op that still reports `true`, because `Signal.connect`
## raises on a duplicate and a UI element that is removed and re-added to the tree
## runs `_ready()` again.
static func connect_unit_hp_changed(c: Callable) -> bool:
	return _connect(&"unit_hp_changed", c)


## Subscribe `c` to the host's `unit_mp_changed(unit, old_mp, new_mp)`.
static func connect_unit_mp_changed(c: Callable) -> bool:
	return _connect(&"unit_mp_changed", c)


static func _connect(sig: StringName, c: Callable) -> bool:
	var p := _resolve()
	if p == null or not p.has_signal(sig):
		return false
	if p.is_connected(sig, c):
		return true
	return p.connect(sig, c) == OK
