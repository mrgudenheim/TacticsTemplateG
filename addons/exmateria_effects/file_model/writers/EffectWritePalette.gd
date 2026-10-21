extends RefCounted
## Byte-exact PALETTE / field-tint writer for `E###.BIN` (#266) — GDScript port of
## `tools/write_effect_palette.py`.
##
## The inverse of `parse_effect.parse_all_palette_keyframes`: nine channels — `for_each` /
## `phase1` / `phase2` × `affected_units` / `caster` / `target` — based at
## `timeline_section_ptr`, `for_each` biased `+8`. Only the known palette fields are
## overwritten; absent contexts/channels and every other byte, padding keyframes
## included, stay verbatim.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## Write one palette channel's raw bytes into `buf` at `base_offset` — the byte-exact inverse
## of `parse_palette_channel`.
static func serialize_channel(buf: PackedByteArray, base_offset: int,
		channel: Dictionary) -> void:
	var keyframes: Array = channel["keyframes"]
	for i in range(Layout.MAX_PALETTE_KEYFRAMES):
		var kf: Dictionary = keyframes[i]
		var rgb: Array = kf["rgb"]
		buf.encode_u16(base_offset + Layout.PALETTE_OFF_TIME + i * 2,
			int(kf["time_value"]) & 0xFFFF)
		var r: int = base_offset + Layout.PALETTE_OFF_RGB + i * 3
		buf[r + 0] = int(rgb[0]) & 0xFF
		buf[r + 1] = int(rgb[1]) & 0xFF
		buf[r + 2] = int(rgb[2]) & 0xFF
		buf[base_offset + Layout.PALETTE_OFF_CTRL + i] = int(kf["ctrl"]) & 0xFF
	buf.encode_u16(base_offset + Layout.PALETTE_TRACK_SIZE,
		int(channel["max_keyframe"]) & 0xFFFF)


## Partial-patch the palette channels of `buf` IN PLACE from `block` (the parsed, possibly
## edited palette block).
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var timeline_ptr: int = int(header["timeline_section_ptr"])
	for context in Layout.PALETTE_TRACK_OFFSETS:
		if not block.has(context):
			continue
		var base: int = timeline_ptr + 8 if context == "for_each" else timeline_ptr
		var ctx_channels = block[context]
		if not (ctx_channels is Dictionary):
			continue
		var offsets: Dictionary = Layout.PALETTE_TRACK_OFFSETS[context]
		for channel_name in offsets:
			if not ctx_channels.has(channel_name):
				continue
			serialize_channel(buf, base + int(offsets[channel_name]),
				ctx_channels[channel_name])
	return ""
