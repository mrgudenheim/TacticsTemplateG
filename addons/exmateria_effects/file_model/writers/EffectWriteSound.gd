extends RefCounted
## Byte-exact SOUND-TIMELINE writer for `E###.BIN` (#268) — GDScript port of
## `tools/write_effect_sound.py`.
##
## The TIER-1 SFX-trigger tracks: six outer (30 B) + three for-each (54 B) channels in the
## timeline section. Outer channels (`phase1`/`phase2`) base at `timeline_ptr`; `for_each` at
## `timeline_ptr + 8`.
##
## Only each keyframe's raw `duration_frames` + `sound_id` and the channel watermark are
## written. TIER-2 SoundContainers and TIER-3 FEDS stay untouched — they are separate sections
## with their own serializers. Padding between the sound_id block and the tail stays verbatim.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## Write one sound channel's raw bytes into `buf` at `base_offset`. Returns `""` on success.
##
## The ROM track has a FIXED slot budget (`kf_count`: 9 outer / 17 for-each). A keyframes
## list of any OTHER length is refused — over-cap would silently drop keyframes on disk, and
## under-cap would leave stale slot bytes posing as data.
static func serialize_channel(buf: PackedByteArray, base_offset: int, channel: Dictionary,
		kf_count: int, maxkf_off: int) -> String:
	var keyframes: Array = channel["keyframes"]
	if keyframes.size() != kf_count:
		return ("sound channel expects exactly %d native keyframe slots, got %d — "
			+ "refusing to truncate/underfill") % [kf_count, keyframes.size()]
	var sid_base: int = base_offset + kf_count * 2
	for i in range(kf_count):
		var kf: Dictionary = keyframes[i]
		buf.encode_u16(base_offset + i * 2, int(kf["duration_frames"]) & 0xFFFF)
		buf[sid_base + i] = int(kf["sound_id"]) & 0xFF
	buf.encode_u16(base_offset + maxkf_off, int(channel["max_keyframe"]) & 0xFFFF)
	return ""


## `[phase key, base, channel offsets, kf count, max_kf tail]` per phase.
static func _phase_layouts(timeline_ptr: int) -> Array:
	return [
		["phase1", timeline_ptr, Layout.SOUND_PHASE1_OFFSETS,
			Layout.SOUND_OUTER_KF, Layout.SOUND_OUTER_MAXKF_OFF],
		["phase2", timeline_ptr, Layout.SOUND_PHASE2_OFFSETS,
			Layout.SOUND_OUTER_KF, Layout.SOUND_OUTER_MAXKF_OFF],
		["for_each", timeline_ptr + 8, Layout.SOUND_ANIMATE_OFFSETS,
			Layout.SOUND_FOREACH_KF, Layout.SOUND_FOREACH_MAXKF_OFF],
	]


## Partial-patch the sound channels of `buf` IN PLACE from `block`. Phases absent from `block`,
## or a channel list shorter than 3, are left untouched.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var timeline_ptr: int = int(header["timeline_section_ptr"])
	for layout in _phase_layouts(timeline_ptr):
		var phase: String = layout[0]
		var base: int = layout[1]
		var offsets: Array = layout[2]
		var kf_count: int = layout[3]
		var maxkf_off: int = layout[4]
		var channels = block.get(phase)
		if not (channels is Array):
			continue
		for ci in range(offsets.size()):
			if ci >= channels.size() or not (channels[ci] is Dictionary):
				continue
			var err: String = serialize_channel(buf, base + int(offsets[ci]),
				channels[ci], kf_count, maxkf_off)
			if not err.is_empty():
				return "%s[%d]: %s" % [phase, ci, err]
	return ""
