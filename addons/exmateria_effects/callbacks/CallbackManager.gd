extends Node3D
## Vault: [[Effect Execution Model]]
## Vault: [[Embedded MIPS Effect Code]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")

const CallbackRegistryClass = preload("res://addons/exmateria_effects/callbacks/CallbackRegistry.gd")

var _slots: Array = [null, null, null, null]  # Up to 4 callback slots
var effect_data: EffectData
var rng: RandomNumberGenerator = null
## The cast's ParticleSubsystem, for callbacks that drive particles themselves
## (EffectCallback.particle_host). Null on a host that never set it.
var particle_host = null

signal child_spawn_requested(emitter_index: int, position: Vector3, frame: int)


func initialize(data: EffectData, callback_slot_data: Array, route_native: bool) -> void:
	"""Initialize callback slots from parsed script data.

	callback_slot_data: [{slot: int, callback_id: int}, ...]
	route_native: THE ROUTE this cast draws on (ADR-0349 dec. 2) — true for Godot's in-scene
	  blend, false for the display-space fold. Read ONCE per cast by EffectInstance and handed
	  straight down; this manager does not resolve it and does not cache it, because a cast that
	  re-read it could end up with two callbacks on two different sides of one frame.

	  It is REQUIRED, not defaulted. A default here would be a route nobody chose, applied to
	  every caller who forgot — and the whole defect this replaces is a producer that picked a
	  side from something that was not the route.
	"""
	effect_data = data

	for entry in callback_slot_data:
		var slot: int = entry["slot"]
		var cb_id: int = entry["callback_id"]

		if slot < 0 or slot >= _slots.size():
			push_warning("CallbackManager: Slot %d out of range" % slot)
			continue

		var callback = CallbackRegistryClass.create(cb_id)
		if callback == null:
			continue

		callback.rng = rng
		callback.particle_host = particle_host
		callback.callback_id = cb_id
		# BEFORE initialize, and before any invoke can reach _create_cb_mesh: the route has to be on
		# the callback by the time it builds its mesh, because the mesh is where the twin is bound.
		callback.set_route_native(route_native)
		callback.initialize(data, slot)
		callback.child_spawn_requested.connect(_on_child_spawn_requested)
		add_child(callback)
		_slots[slot] = callback

		if EffectsDebug.particle():
			print("[CallbackManager] Slot %d = CB%d" % [slot, cb_id])


func callback_in_slot(slot: int):
	"""The callback loaded in `slot`, or null — for a host that reads a callback's own state
	(the TRAP charge's handler ticks, which the Studio measures its drain from)."""
	return _slots[slot] if slot >= 0 and slot < _slots.size() else null


func set_particle_host(host) -> void:
	"""Hand every loaded callback the cast's ParticleSubsystem (see particle_host)."""
	particle_host = host
	for callback in _slots:
		if callback:
			callback.particle_host = host


func invoke(slot: int, emitter_index: int, spawn_counter: int, channel_index: int, duration_remaining: int = -1) -> void:
	"""Invoke callback in the given slot.
	PSX sets callback_state=3 when duration_remaining==2 (2 frames left in channel).
	The callback still gets invoked — its state check triggers cleanup code."""
	if slot < 0 or slot >= _slots.size():
		return
	var callback = _slots[slot]
	if callback:
		# PSX: when 2 invocations remain, set state to CLEANUP before invoke
		if duration_remaining == 2 and callback.state == callback.State.ANIMATE:
			callback.state = callback.State.CLEANUP
			if EffectsDebug.timeline():
				print("[CallbackMgr] state→CLEANUP slot=%d CB%d dur_remaining=2" % [slot, callback.callback_id])
		if EffectsDebug.timeline():
			print("[CallbackMgr] invoke slot=%d CB%d emitter=%d spawn=%d ch=%d state=%d dur=%d" % [
				slot, callback.callback_id, emitter_index, spawn_counter, channel_index, callback.state, duration_remaining])
		callback.invoke(emitter_index, spawn_counter, channel_index)


func physics_step() -> void:
	"""Tick physics for all active callbacks."""
	for callback in _slots:
		if callback and callback.is_active():
			callback.physics_step()


func update_render() -> void:
	"""Update render geometry for all callbacks (inactive ones clear their mesh)."""
	for callback in _slots:
		if callback:
			callback.update_render()
			# Engine-fold path only (no-op on stock/Mobile): re-stamp the mesh's depth-bucket
			# render_layer_order now that this frame's geometry (and thus its world AABB) is current, so
			# the compositor folds it at its true depth relative to the particle prims.
			callback.stamp_fold_order()


func update_anchors(origin: Vector3, target: Vector3, world_pos: Vector3,
					cursor: Vector3, facing: float) -> void:
	"""Push updated anchor positions to all callbacks."""
	for callback in _slots:
		if callback:
			callback.anchor_origin = origin
			callback.anchor_target = target
			callback.anchor_world = world_pos
			callback.anchor_cursor = cursor
			callback.caster_facing_angle = facing


func release_all() -> void:
	"""Put every live callback into its CLEANUP (EffectInstance.release) — the same state
	the timeline sets two frames before a span ends, so each winds down its own way (the
	TRAP charge lines finish contracting, the orbs run their fade)."""
	for callback in _slots:
		if callback and callback.is_active():
			callback.cleanup()


func has_active_callbacks() -> bool:
	"""Check if any callback is still active."""
	for callback in _slots:
		if callback and callback.is_active():
			return true
	return false


func reset() -> void:
	"""Reset all callbacks to inactive state (for effect loop restart)."""
	for callback in _slots:
		if callback:
			if callback.has_method("force_cleanup"):
				callback.force_cleanup()
			else:
				callback.cleanup()
			callback.state = callback.State.INACTIVE  # Force INACTIVE for re-init on next loop


func _on_child_spawn_requested(emitter_index: int, pos: Vector3, frame: int) -> void:
	"""Forward child spawn requests from callbacks to EffectInstance."""
	child_spawn_requested.emit(emitter_index, pos, frame)
