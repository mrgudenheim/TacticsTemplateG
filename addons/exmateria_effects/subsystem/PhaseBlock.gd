extends RefCounted
## One phase's worth of cursor + channel state for a subsystem. The owning
## subsystem (ParticleSubsystem) holds one per phase - phase1, phase2, for_each -
## and advances the one the open phase set selects.
## Keyframe interpretation: kf[0] is SKIPPED; kf[N].emitter_id applies DURING
## frames kf[N-1].time..kf[N].time (duration = kf[N].time - kf[N-1].time);
## emitter_id 0 = skip, N = spawn emitter (N-1).
## Vault: [[Effect Camera System]]
## Vault: [[Effect Execution Model]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")


class ChannelState:
	var channel  # TimelineData.Channel - can't use typed ref due to load order
	var current_keyframe: int = 1  # Start at 1, skip kf[0]
	var duration_remaining: int = 0
	var spawn_counter: int = 0
	var finished: bool = false


var timeline  # TimelineData - can't use typed ref due to load order

var channel_states: Array = []

var current_frame: int = 0

# Last keyframe time (across all channels) that spawns particles (emitter_id != 0)
var last_active_keyframe_time: int = 0

signal emitter_started(emitter_index: int, channel_index: int, frame: int)
signal emitter_stopped(emitter_index: int, channel_index: int, frame: int)

# Bit 4 (0x0010) = HIT_REACTION - triggers damage application and potential death
signal action_flags_triggered(flags: int, channel_index: int, frame: int)

# Context stored for debug logging
var _context: String = ""


func _phase_name(ctx: String) -> String:
	return "for-each" if ctx == EffectPhaseClass.PHASE_FOR_EACH else ctx


func initialize(data, context: String = EffectPhaseClass.PHASE_FOR_EACH) -> void:
	"""Initialize controller with timeline data for a specific context"""
	timeline = data
	channel_states.clear()
	current_frame = 0
	_context = context

	var channels = timeline.get_channels(context)

	for ch in channels:
		var state = ChannelState.new()
		state.channel = ch
		state.current_keyframe = 1  # Start at keyframe 1, skip kf[0]
		state.spawn_counter = 0

		if ch.max_keyframe < 1:
			state.finished = true
			state.duration_remaining = 0
		else:
			state.duration_remaining = ch.keyframes[1].time
			state.finished = false

			if EffectsDebug.timeline():
				print("[KF_DEBUG] START %s, particle subsystem, ch%d, KF1 (emitter=%d, dur=%d) at timeline_frame=0" % [
					_phase_name(context), ch.channel_index, ch.keyframes[1].emitter_id, state.duration_remaining])

			var emitter_id = ch.keyframes[1].emitter_id
			if emitter_id != 0:
				emitter_started.emit(emitter_id - 1, ch.channel_index, 0)

			var action_flags = ch.keyframes[1].action_flags
			if action_flags != 0:
				action_flags_triggered.emit(action_flags, ch.channel_index, 0)

		channel_states.append(state)

	channel_states.sort_custom(func(a, b): return a.channel.channel_index < b.channel.channel_index)

	last_active_keyframe_time = 0
	for ch in channels:
		for i in range(ch.max_keyframe, 0, -1):
			if ch.keyframes[i].emitter_id != 0:
				last_active_keyframe_time = maxi(last_active_keyframe_time, ch.keyframes[i].time)
				break


func advance_frame() -> Array:
	"""Advance timeline by one frame, returns spawn requests for this frame.

	Returns array of dictionaries:
	[{emitter_index: int, spawn_counter: int, channel_index: int}, ...]
	"""
	var spawn_requests: Array = []

	for state in channel_states:
		if state.finished:
			continue

		var request = _process_channel(state)
		if request != null:
			spawn_requests.append(request)

	current_frame += 1
	return spawn_requests


func _process_channel(state: ChannelState):
	"""Process a single channel for one frame.

	Corrected algorithm:
	1. Get emitter_id from current keyframe (what to do during this period)
	2. If emitter_id != 0, spawn and increment counter
	3. Decrement duration_remaining
	4. If duration_remaining == 0, advance to next keyframe

	Returns spawn request dict or null.
	"""
	var channel = state.channel

	var kf = channel.keyframes[state.current_keyframe]
	var emitter_id = kf.emitter_id

	var request = null

	if emitter_id != 0:
		var emitter_index = emitter_id - 1  # Convert to 0-based index
		request = {
			"emitter_index": emitter_index,
			"spawn_counter": state.spawn_counter,
			"channel_index": channel.channel_index,
			"action_flags": kf.action_flags,
			"duration_remaining": state.duration_remaining
		}
		state.spawn_counter += 1

	state.duration_remaining -= 1

	if state.duration_remaining <= 0:
		_advance_keyframe(state, emitter_id)

	return request


func _advance_keyframe(state: ChannelState, prev_emitter_id: int) -> void:
	"""Advance to next keyframe and calculate new duration."""
	var channel = state.channel

	if EffectsDebug.timeline():
		print("[KF_DEBUG] END %s, particle subsystem, ch%d, KF%d (emitter=%d) at timeline_frame=%d" % [
			_phase_name(_context), channel.channel_index, state.current_keyframe, prev_emitter_id, current_frame])

	if prev_emitter_id != 0:
		emitter_stopped.emit(prev_emitter_id - 1, channel.channel_index, current_frame)

	state.current_keyframe += 1

	if state.current_keyframe > channel.max_keyframe:
		state.finished = true
		return

	var current_kf = channel.keyframes[state.current_keyframe]
	var prev_kf = channel.keyframes[state.current_keyframe - 1]
	state.duration_remaining = current_kf.time - prev_kf.time

	if EffectsDebug.timeline():
		print("[KF_DEBUG] START %s, particle subsystem, ch%d, KF%d (emitter=%d, dur=%d) at timeline_frame=%d" % [
			_phase_name(_context), channel.channel_index, state.current_keyframe, current_kf.emitter_id, state.duration_remaining, current_frame])

	state.spawn_counter = 0

	var new_emitter_id = current_kf.emitter_id
	if new_emitter_id != 0:
		emitter_started.emit(new_emitter_id - 1, channel.channel_index, current_frame)

	if current_kf.action_flags != 0:
		action_flags_triggered.emit(current_kf.action_flags, channel.channel_index, current_frame)


func is_finished() -> bool:
	"""Check if all channels have finished processing."""
	for state in channel_states:
		if not state.finished:
			return false
	return true


func get_current_frame() -> int:
	"""Get current frame number."""
	return current_frame
