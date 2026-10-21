extends RefCounted
## Byte-exact PARTICLE-TIMELINE writer for `E###.BIN` (ADR-0089) — GDScript port of
## `tools/write_effect_particle_timeline.py`.
##
## The 15 particle channels (5 `for_each` + 5 `phase1` + 5 `phase2`) in the timeline section.
## `block` is the whole parsed `timeline` block; this serializer reads only its
## `particle_channels` list, each entry carrying its own `context` + `channel_index`.
##
## WRITE ORDER IS LOAD-BEARING. `time[]` spans bytes 0x00..0x31 and `emitter_id[]` starts at
## 0x31, so byte 0x31 is PHYSICALLY SHARED. `emitter_id[0]` is its semantic owner (the parser
## reads it as such, and `time[24]` is a phantom slot real data never reaches — `max_keyframe`
## never reaches 24). So `time[]` is written FIRST and `emitter_id[]` second, letting
## `emitter_id[0]` win the shared byte. Reversing these two loops silently corrupts 0x31.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## File offset of a particle channel — delegated to `EffectBinLayout` so the reader
## (`EffectReadParticleTimeline`) and this writer share one geometry rather than two copies of
## it. Kept as a named function here because `EffectBinWriterCorpusTest` addresses it.
static func channel_offset(timeline_ptr: int, context: String, channel_index: int) -> int:
	return Layout.particle_channel_offset(timeline_ptr, context, channel_index)


## Write one particle channel's raw SoA arrays into `buf` at file offset `base`. Writes all 25
## slots of each array plus the watermark; the unaddressed bytes (the 0x7C/0x7D gap and the
## tail past 0x7F) stay verbatim.
static func serialize_channel(buf: PackedByteArray, base: int, channel: Dictionary) -> void:
	var keyframes: Array = channel["keyframes"]

	# 1. time[] first — its last slot's high byte lands on the shared byte 0x31 ...
	for i in range(Layout.PARTICLE_SLOTS):
		buf.encode_u16(base + Layout.PARTICLE_OFF_TIME + i * 2,
			int(keyframes[i]["time"]) & 0xFFFF)

	# 2. ... then emitter_id[], so emitter_id[0] wins byte 0x31.
	for i in range(Layout.PARTICLE_SLOTS):
		buf[base + Layout.PARTICLE_OFF_EMITTER_ID + i] = int(keyframes[i]["emitter_id"]) & 0xFF

	# 3. action_flags[]
	for i in range(Layout.PARTICLE_SLOTS):
		buf.encode_u16(base + Layout.PARTICLE_OFF_ACTION_FLAGS + i * 2,
			int(keyframes[i]["action_flags"]) & 0xFFFF)

	# 4. max_keyframe watermark
	buf.encode_u16(base + Layout.PARTICLE_OFF_MAX_KEYFRAME,
		int(channel["max_keyframe"]) & 0xFFFF)


## Partial-patch the particle channels of `buf` IN PLACE from `block` (the parsed, possibly
## edited timeline block). Only the channels present in `particle_channels` are overwritten.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var timeline_ptr: int = int(header["timeline_section_ptr"])
	var channels = block.get("particle_channels", [])
	if not (channels is Array):
		return ""
	for channel in channels:
		if not (channel is Dictionary):
			continue
		var context: String = str(channel.get("context", ""))
		var idx: int = int(channel.get("channel_index", -1))
		var base: int = channel_offset(timeline_ptr, context, idx)
		if base < 0:
			return "unknown particle channel %s[%d]" % [context, idx]
		serialize_channel(buf, base, channel)
	return ""
