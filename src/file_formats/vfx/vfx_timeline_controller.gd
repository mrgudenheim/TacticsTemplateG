class_name VfxTimelineController
extends RefCounted
## Runtime timeline processor — advances channels and triggers emitter spawning
## Port of godot-learning's TimelineController.gd
##
## Uses TacticsTemplateG's already-parsed EmitterTimeline/EmitterKeyframe directly.
##
## Timeline structure:
## - kf[0] is SKIPPED (not used)
## - kf[N].emitter_id applies DURING frames kf[N-1].time to kf[N].time
## - Duration = kf[N].time - kf[N-1].time
## - emitter_id 0 = skip, N = spawn emitter (N-1)


class ChannelState:
	var timeline: VisualEffectData.EmitterTimeline
	var channel_index: int = 0
	var current_keyframe: int = 1  # Start at 1, skip kf[0]
	var duration_remaining: int = 0
	var spawn_counter: int = 0
	var finished: bool = false


var channel_states: Array = []
var current_frame: int = 0

signal emitter_started(emitter_index: int, channel_index: int, frame: int)
signal emitter_stopped(emitter_index: int, channel_index: int, frame: int)
signal action_flags_triggered(flags: int, channel_index: int, frame: int)


func initialize(timelines: Array[VisualEffectData.EmitterTimeline]) -> void:
	channel_states.clear()
	current_frame = 0

	for ch_idx: int in timelines.size():
		var timeline: VisualEffectData.EmitterTimeline = timelines[ch_idx]
		var state := ChannelState.new()
		state.timeline = timeline
		state.channel_index = ch_idx
		state.current_keyframe = 1
		state.spawn_counter = 0

		if timeline.num_keyframes < 1:
			state.finished = true
			state.duration_remaining = 0
		else:
			# Initial duration = kf[1].time - kf[0].time = kf[1].time - 0
			state.duration_remaining = timeline.keyframes[1].time
			state.finished = false

			# Signal start if first keyframe has emitter
			var emitter_id: int = timeline.keyframes[1].emitter_id
			if emitter_id != 0:
				emitter_started.emit(emitter_id - 1, ch_idx, 0)

			# Check action_flags on first keyframe
			var kf: VisualEffectData.EmitterKeyframe = timeline.keyframes[1]
			var action_flag: int = _get_action_flag_bits(kf)
			if action_flag != 0:
				action_flags_triggered.emit(action_flag, ch_idx, 0)

		channel_states.append(state)


func advance_frame() -> Array:
	var spawn_requests: Array = []

	for state: ChannelState in channel_states:
		if state.finished:
			continue

		var request: Variant = _process_channel(state)
		if request != null:
			spawn_requests.append(request)

	current_frame += 1
	return spawn_requests


func _process_channel(state: ChannelState) -> Variant:
	var timeline: VisualEffectData.EmitterTimeline = state.timeline
	var kf: VisualEffectData.EmitterKeyframe = timeline.keyframes[state.current_keyframe]
	var emitter_id: int = kf.emitter_id

	var request: Variant = null

	if emitter_id != 0:
		var emitter_index: int = emitter_id - 1
		# Keyframe duration = total frames this emitter is active for this keyframe
		var kf_duration: int = state.duration_remaining + state.spawn_counter + 1
		request = {
			"emitter_index": emitter_index,
			"spawn_counter": state.spawn_counter,
			"channel_index": state.channel_index,
			"keyframe_duration": kf_duration
		}
		state.spawn_counter += 1

	state.duration_remaining -= 1

	if state.duration_remaining <= 0:
		_advance_keyframe(state, emitter_id)

	return request


func _advance_keyframe(state: ChannelState, prev_emitter_id: int) -> void:
	var timeline: VisualEffectData.EmitterTimeline = state.timeline

	if prev_emitter_id != 0:
		emitter_stopped.emit(prev_emitter_id - 1, state.channel_index, current_frame)

	state.current_keyframe += 1

	if state.current_keyframe > timeline.num_keyframes:
		state.finished = true
		return

	# Duration = kf[N].time - kf[N-1].time
	var current_kf: VisualEffectData.EmitterKeyframe = timeline.keyframes[state.current_keyframe]
	var prev_kf: VisualEffectData.EmitterKeyframe = timeline.keyframes[state.current_keyframe - 1]
	state.duration_remaining = current_kf.time - prev_kf.time

	state.spawn_counter = 0

	var new_emitter_id: int = current_kf.emitter_id
	if new_emitter_id != 0:
		emitter_started.emit(new_emitter_id - 1, state.channel_index, current_frame)

	var action_flag: int = _get_action_flag_bits(current_kf)
	if action_flag != 0:
		action_flags_triggered.emit(action_flag, state.channel_index, current_frame)


func _get_action_flag_bits(kf: VisualEffectData.EmitterKeyframe) -> int:
	# Reconstruct the 16-bit action_flags from parsed booleans
	var flags: int = 0
	if kf.display_damage:
		flags |= 0x1000
	if kf.status_change:
		flags |= 0x2000
	if kf.target_animation:
		flags |= 0x4000
	if kf.use_global_target:
		flags |= 0x0800
	if kf.callback_slot >= 0:
		flags |= (kf.callback_slot + 1) << 8
	flags |= kf.animation_param & 0x00FF
	if kf.unused_flag_80:
		flags |= 0x8000
	return flags


func is_finished() -> bool:
	for state: ChannelState in channel_states:
		if not state.finished:
			return false
	return true


func get_current_frame() -> int:
	return current_frame


func get_active_emitters() -> Array[int]:
	var active_list: Array[int] = []
	for state: ChannelState in channel_states:
		if not state.finished:
			var kf: VisualEffectData.EmitterKeyframe = state.timeline.keyframes[state.current_keyframe]
			if kf.emitter_id != 0:
				var emitter_idx: int = kf.emitter_id - 1
				if emitter_idx not in active_list:
					active_list.append(emitter_idx)
	return active_list
