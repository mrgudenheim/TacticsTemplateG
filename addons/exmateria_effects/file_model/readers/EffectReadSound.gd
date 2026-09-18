extends RefCounted
## SOUND-TIMELINE reader, TIER-1 (#268) — GDScript port of
## `parse_effect.parse_sound_keyframes` and its two channel helpers.
##
## Three `phase1` + three `phase2` OUTER channels (30 bytes, 9 keyframes) based at
## `timeline_section_ptr`, plus three `for_each` channels (54 bytes, 17 keyframes) based at
## `timeline_section_ptr + 8`.
##
## All three channels are ALWAYS emitted per phase, even when empty, so the controller's
## `three_phase` detection (phase1 non-empty) matches the parity harness — and so the writer,
## which refuses a keyframe list of any length other than the native slot count, always gets
## exactly what it expects.
##
## `duration_frames` and `max_keyframe` are read SIGNED (`decode_s16`), mirroring the Python's
## `read_s16`. The writer masks back to the same two bytes either way.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


static func _channel(buf: PackedByteArray, off: int, channel_index: int,
		kf_count: int, maxkf_off: int) -> Dictionary:
	var keyframes: Array = []
	var sid_base: int = off + kf_count * 2
	for i in range(kf_count):
		keyframes.append({
			"duration_frames": buf.decode_s16(off + i * 2),
			"sound_id": buf[sid_base + i],
		})
	return {
		"channel_index": channel_index,
		"max_keyframe": buf.decode_s16(off + maxkf_off),
		"keyframes": keyframes,
	}


## The sound block, or `null` when any channel would run past the end of the file.
static func parse(buf: PackedByteArray, header: Dictionary):
	var timeline_ptr: int = int(header.get("timeline_section_ptr", -1))
	if timeline_ptr < 0:
		return null
	var channel_base: int = timeline_ptr + 8
	var last_outer: int = (timeline_ptr
		+ int(Layout.SOUND_PHASE2_OFFSETS[Layout.SOUND_PHASE2_OFFSETS.size() - 1])
		+ Layout.SOUND_OUTER_SIZE)
	var last_foreach: int = (channel_base
		+ int(Layout.SOUND_ANIMATE_OFFSETS[Layout.SOUND_ANIMATE_OFFSETS.size() - 1])
		+ Layout.SOUND_FOREACH_SIZE)
	if maxi(last_outer, last_foreach) > buf.size():
		return null

	var phase1: Array = []
	var phase2: Array = []
	var animate: Array = []
	for i in range(3):
		phase1.append(_channel(buf, timeline_ptr + int(Layout.SOUND_PHASE1_OFFSETS[i]), i,
			Layout.SOUND_OUTER_KF, Layout.SOUND_OUTER_MAXKF_OFF))
		phase2.append(_channel(buf, timeline_ptr + int(Layout.SOUND_PHASE2_OFFSETS[i]), i,
			Layout.SOUND_OUTER_KF, Layout.SOUND_OUTER_MAXKF_OFF))
		animate.append(_channel(buf, channel_base + int(Layout.SOUND_ANIMATE_OFFSETS[i]), i,
			Layout.SOUND_FOREACH_KF, Layout.SOUND_FOREACH_MAXKF_OFF))
	return {"phase1": phase1, "phase2": phase2, "for_each": animate}
