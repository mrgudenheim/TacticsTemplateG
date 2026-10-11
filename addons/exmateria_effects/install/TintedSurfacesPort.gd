@tool
extends RefCounted

## PORT SIGNATURE - the six verbs a member may name instead of the
## `TintedSurfaces` autoload identifier. A member may reach NO autoload
## identifier at all (ADR-0308 dec. 1); the host registers THIS addon's
## script, so the node-path bind below is free on arm 2b's stated grounds -
## the script travels with the addon, the registration does not
## (ADR-0308 dec. 6; the trade ADR-0175 dec. 2 made for `Tune`).
## Absent answers: every write is a no-op, every read says "nothing is
## registered" - the true answer, not a fallback.
## tests/TunePortTest.gd drives both the bound and the absent path.
## vault: .vaults/comments/exmateria_effects/port-contracts.md


## The shipped script. 🔴 SURFACE_MAP CANNOT GO THROUGH THE NODE: a GDScript
## const is not a property, so node.SURFACE_MAP on the resolved autoload fails
## at runtime - the reach lands on the SCRIPT. One 0: overlay/TintedSurfaces.gd:70.
const TintedSurfacesScript = preload("res://addons/exmateria_effects/overlay/TintedSurfaces.gd")

## The reserved MAP-surface token, re-exported off the shipped script above.
const SURFACE_MAP: int = TintedSurfacesScript.SURFACE_MAP

## Resolved singleton, or `null`. Never caches a negative: the autoload can
## appear after first touch (plugin.gd registers at enable; a test can add it).
static var _port: Node = null


## The live registry node, or `null` where the consumer registered no autoload.
## has_method is the second rejection: it keeps a consumer's unrelated
## `TintedSurfaces` node - the name alone would match it - out of the reach.
static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"TintedSurfaces")
	if n == null or not n.has_method(&"update_stack"):
		return null
	_port = n
	return n


## Test seam - drop the cache so the next call re-resolves: removing the
## autoload without freeing it leaves a valid instance behind.
static func _forget_port() -> void:
	_port = null


## Fold `stack` onto `surface_id` on behalf of `owner_id` at frame `now`;
## `true` when the registry took it.
static func update_stack(surface_id: int, owner_id: int, stack, now: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	p.update_stack(surface_id, owner_id, stack, now)
	return true


## Write `owner_id`'s flat `tint` layer on `surface_id`; `true` when delivered.
static func update_layer(surface_id: int, owner_id: int, tint: Color) -> bool:
	var p := _resolve()
	if p == null:
		return false
	p.update_layer(surface_id, owner_id, tint)
	return true


## Drop `owner_id`'s layer from `surface_id`; `true` when delivered.
static func remove_layer(surface_id: int, owner_id: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	p.remove_layer(surface_id, owner_id)
	return true


## Drop every layer `owner_id` holds; `true` when delivered.
static func remove_all_layers_for_owner(owner_id: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	p.remove_all_layers_for_owner(owner_id)
	return true


## Whether `surface_id` has a registered material. `false` with no registry is
## the TRUE answer, not a fallback; both call sites guard a write with it.
static func is_surface_registered(surface_id: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	return p.is_surface_registered(surface_id)
