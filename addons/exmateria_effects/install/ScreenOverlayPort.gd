@tool
extends RefCounted

## PORT SIGNATURE - the four verbs a member may name instead of the
## `ScreenEffectOverlay` autoload identifier; the same ruling as
## TintedSurfacesPort (ADR-0308 dec. 1) - the host registers THIS addon's
## script, so the node-path bind is free on arm 2b's stated grounds.
## The two reads are the only verbs in either port whose absent answer is NOT
## the identity: they feed ScreenSubsystem.initialize's baselines, so a wrong
## value makes the WYSIWYG solver (#255) return wrong numbers rather than
## absent. Absent answer = the shipped script's own corner fallbacks, derived
## from it, not copied (ADR-0154).
## vault: .vaults/comments/exmateria_effects/port-contracts.md


## The shipped script - `_absent_pair()` instances it; this file records which
## script the autoload identifier it replaces pointed at.
const ScreenEffectOverlayScript = preload("res://addons/exmateria_effects/overlay/ScreenEffectOverlay.gd")

## `[top, bottom]` read off a detached overlay on first need; the node is
## built AND freed inside `_absent_pair()`, so only the two Colors outlive it.
static var _absent_baselines: Array = []

## Resolved singleton, or `null`. Never caches a negative -
## `TintedSurfacesPort._port`.
static var _port: Node = null


## The two baselines the shipped script declares for its own corners. The
## instance never enters the tree (_ready cannot fire); only the two pure
## corner averages are called on it.
static func _absent_pair() -> Array:
	if _absent_baselines.is_empty():
		var o: Node = ScreenEffectOverlayScript.new()
		_absent_baselines = [o.get_default_top(), o.get_default_bottom()]
		o.free()
	return _absent_baselines


## The live overlay node, or `null` where the consumer registered no autoload.
## 🔴 has_method IS load-bearing here, unlike in the tinted port:
## ScreenEffectOverlay.gd is NOT @tool, so the editor instantiates the autoload
## as a PLACEHOLDER that answers to the name with none of its methods.
static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"ScreenEffectOverlay")
	if n == null or not n.has_method(&"update_layer_gradient"):
		return null
	_port = n
	return n


## Test seam - `TintedSurfacesPort._forget_port`.
static func _forget_port() -> void:
	_port = null


## Fold `owner_id`'s top/bottom deltas into the backdrop; `true` when delivered.
static func update_layer_gradient(owner_id: int, top_delta: Color, bottom_delta: Color,
		tint: Color = Color.BLACK) -> bool:
	var p := _resolve()
	if p == null:
		return false
	p.update_layer_gradient(owner_id, top_delta, bottom_delta, tint)
	return true


## Drop `owner_id`'s layer from the backdrop; `true` when delivered.
static func remove_layer(owner_id: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	p.remove_layer(owner_id)
	return true


## The map's default gradient TOP baseline; with no overlay registered, the
## fallback the shipped script declares for its own top corners.
static func get_default_top() -> Color:
	var p := _resolve()
	if p == null:
		return _absent_pair()[0]
	return p.get_default_top()


## The map's default gradient BOTTOM baseline; the same for the bottom corners.
static func get_default_bottom() -> Color:
	var p := _resolve()
	if p == null:
		return _absent_pair()[1]
	return p.get_default_bottom()
