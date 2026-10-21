extends RefCounted
## Byte-exact SCREEN-section writer for `E###.BIN` (#255) — GDScript port of
## `tools/write_effect_screen.py`.
##
## The inverse of `parse_effect.parse_all_screen_keyframes`: three backdrop channels
## re-serialized from their `raw` sub-blocks, the source of truth — the derived fields are
## ignored (#254 decision 2). Every other byte stays verbatim (padding keyframes, absent
## contexts); 16-bit fields go out `& 0xFFFF` — signedness is interpretation, not bytes.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## Write one screen channel's `raw` bytes into `buf` at `base_offset` — the byte-exact inverse
## of `parse_screen_channel`. `max_kf_offset` is an absolute offset, or `Layout.NO_MAX_KF`
## when the watermark lives at the channel's own tail.
static func serialize_channel(buf: PackedByteArray, base_offset: int, channel: Dictionary,
		max_kf_offset: int) -> void:
	var keyframes: Array = channel["keyframes"]
	for i in range(Layout.MAX_SCREEN_KEYFRAMES):
		var raw: Dictionary = keyframes[i]["raw"]
		buf.encode_u16(base_offset + Layout.SCREEN_OFF_TIME + i * 2,
			int(raw["time_value"]) & 0xFFFF)
		var s: int = base_offset + Layout.SCREEN_OFF_START + i * 3
		buf[s + 0] = int(raw["start_r"]) & 0xFF
		buf[s + 1] = int(raw["start_g"]) & 0xFF
		buf[s + 2] = int(raw["start_b"]) & 0xFF
		var e: int = base_offset + Layout.SCREEN_OFF_END + i * 3
		buf[e + 0] = int(raw["end_r"]) & 0xFF
		buf[e + 1] = int(raw["end_g"]) & 0xFF
		buf[e + 2] = int(raw["end_b"]) & 0xFF
		buf[base_offset + Layout.SCREEN_OFF_CTRL + i] = int(raw["ctrl"]) & 0xFF

	var max_kf: int = int(channel["max_keyframe"]) & 0xFFFF
	if max_kf_offset != Layout.NO_MAX_KF:
		buf.encode_u16(max_kf_offset, max_kf)
	else:
		buf.encode_u16(base_offset + Layout.SCREEN_OFF_MAX_KF_TAIL, max_kf)


## Partial-patch the screen colour channels of `buf` IN PLACE from `block` (the parsed,
## possibly edited screen block).
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var timeline_ptr: int = int(header["timeline_section_ptr"])

	if block.has("for_each"):
		var fe_base: int = timeline_ptr + 8
		var off: Dictionary = Layout.SCREEN_TRACK_OFFSETS["for_each"]
		serialize_channel(buf, fe_base + int(off["data"]), block["for_each"],
			fe_base + int(off["max_keyframe"]))

	for context in ["phase1", "phase2"]:
		if block.has(context):
			var poff: Dictionary = Layout.SCREEN_TRACK_OFFSETS[context]
			serialize_channel(buf, timeline_ptr + int(poff["data"]), block[context],
				Layout.NO_MAX_KF)
	return ""
