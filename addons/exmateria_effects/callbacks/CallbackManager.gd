extends Node3D
## Manages callback slots, dispatches invocations, and forwards child spawn requests.
## Vault: [[Effect Execution Model]]
## Vault: [[Embedded MIPS Effect Code]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")

const CallbackRegistryClass = preload("res://addons/exmateria_effects/callbacks/CallbackRegistry.gd")

var _slots: Array = [null, null, null, null]  # Up to 4 callback slots
var effect_data: EffectData

signal child_spawn_requested(emitter_index: int, position: Vector3, frame: int)


func initialize(data: EffectData, callback_slot_data: Array) -> void:
	"""Initialize callback slots from parsed script data.

	callback_slot_data: [{slot: int, callback_id: int}, ...]
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

		callback.callback_id = cb_id
		callback.initialize(data, slot)
		callback.child_spawn_requested.connect(_on_child_spawn_requested)
		add_child(callback)
		_slots[slot] = callback

		if EffectsDebug.particle():
			print("[CallbackManager] Slot %d = CB%d" % [slot, cb_id])


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
			callback.cleanup()
			callback.state = callback.State.INACTIVE  # Force INACTIVE for re-init on next loop


func _on_child_spawn_requested(emitter_index: int, pos: Vector3, frame: int) -> void:
	"""Forward child spawn requests from callbacks to EffectInstance."""
	child_spawn_requested.emit(emitter_index, pos, frame)
