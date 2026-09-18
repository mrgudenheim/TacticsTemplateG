extends RefCounted
## SCREEN-SUBSYSTEM reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_all_screen_keyframes` + `parse_screen_channel`, the read mirror of
## `writers/EffectWriteScreen.gd`.
## Vault: [[Effect File Format]]
##
## The backdrop-colour animation: one 298-byte channel per phase (`for_each`, `phase1`,
## `phase2`), each holding 33 keyframes as four PARALLEL arrays — s16 times at +0x00, start RGB
## triplets at +0x42, end RGB triplets at +0xA5, a ctrl byte at +0x108 — plus a `max_keyframe`
## watermark.
##
## 🔴 `for_each` IS BIASED `+8` AND THE OTHER TWO ARE NOT. That asymmetry is real and is worth
## 400 byte mismatches when you get it wrong. The camera section has the opposite convention:
## nothing is biased there, `for_each` included — see `EffectReadCamera`.
##
## ⚠️ THE SECOND ASYMMETRY IS NOTATIONAL, NOT REAL, AND SAYING SO IS THE POINT.
## `SCREEN_TRACK_OFFSETS` gives `for_each` an explicit `max_keyframe` offset (0x06A8) while
## phase1/phase2 use the `NO_MAX_KF` sentinel and read the watermark from the channel's tail
## (+298). Those are THE SAME ADDRESS: `for_each`'s data begins at 0x057E and
## `0x057E + 298 == 0x06A8`. Seeding the branch away — every watermark read from the tail — is
## green across all 400 effects. The branch is ported because the Python and the Layout table
## both carry it and `EffectWriteScreen` reads the same shape, but it discriminates NOTHING
## here, and a reader who "verifies" it by seeing green is verifying arithmetic, not a decode.
##
## ⚠️ NOT SHARED WITH `EffectReadPalette`, DELIBERATELY. The two look alike — 33 slots, s16
## times at +0x00, an RGB run at +0x42, a ctrl byte whose bit 7 is a mode flag and whose low
## seven are a blend mode, the same `time * 8` duration rule — and they are not the same
## record: screen carries START AND END RGB and a `raw` sub-dict, palette carries one RGB plus
## a signed view and no `raw`, their ctrl offsets differ (0x108 vs 0xA5), their watermarks live
## in different places, and palette nests three named channels per context where screen has
## one. What is genuinely common is four lines of arithmetic; what a shared reader would need
## is a field-schema interpreter. The duplication is cheaper than the abstraction, and the
## nine `# seeded-break:` entries between them show the two are scored independently.
##
## `duration_frames`, `mode` and `blend_mode` are DERIVED — `EffectWriteScreen` serializes from
## `raw` and ignores them (#254 decision 2) — so referee B is blind to all three and only
## `screen.json` scores them.
##
## ABSENT IS `null`; a channel that would read past EOF is OMITTED, so the key set is data.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

## The bytes a channel needs to be present at all: 298 of keyframes + the 2-byte watermark.
const CHANNEL_BYTES: int = 300


## The three screen channels — `screen.json`'s shape — or `null` when the section is out of
## bounds.
static func parse(buf: PackedByteArray, header: Dictionary):
	var timeline_ptr: int = int(header.get("timeline_section_ptr", 0))
	if timeline_ptr <= 0 or timeline_ptr >= buf.size():
		return null
	var out: Dictionary = {}
	for context in Layout.SCREEN_TRACK_OFFSETS:
		var offsets: Dictionary = Layout.SCREEN_TRACK_OFFSETS[context]
		# `for_each` reads from `timeline_ptr + 8`; phase1/phase2 from `timeline_ptr`.
		var base: int = timeline_ptr + (Layout.TIMELINE_FOR_EACH_BASE_BIAS \
			if context == "for_each" else 0)
		var channel_offset: int = base + int(offsets["data"])
		if channel_offset + CHANNEL_BYTES > buf.size():
			continue
		# `for_each`'s watermark has its own offset; the other two sit at the channel tail.
		var max_kf_offset: int = Layout.NO_MAX_KF
		if int(offsets["max_keyframe"]) != Layout.NO_MAX_KF:
			max_kf_offset = base + int(offsets["max_keyframe"])
		out[context] = parse_channel(buf, channel_offset, str(context), max_kf_offset)
	return out


## One 298-byte channel at `base_offset`. `max_kf_offset` is ABSOLUTE, or `Layout.NO_MAX_KF`
## when the watermark lives at the channel's own tail.
static func parse_channel(buf: PackedByteArray, base_offset: int, context: String,
		max_kf_offset: int) -> Dictionary:
	var watermark_at: int = max_kf_offset if max_kf_offset != Layout.NO_MAX_KF \
		else base_offset + Layout.SCREEN_OFF_MAX_KF_TAIL
	var keyframes: Array = []
	for i in range(Layout.MAX_SCREEN_KEYFRAMES):
		var time_value: int = buf.decode_s16(base_offset + Layout.SCREEN_OFF_TIME + i * 2)
		var s: int = base_offset + Layout.SCREEN_OFF_START + i * 3
		var e: int = base_offset + Layout.SCREEN_OFF_END + i * 3
		var ctrl: int = buf[base_offset + Layout.SCREEN_OFF_CTRL + i]
		var raw: Dictionary = {
			"time_value": time_value,
			"start_r": buf[s], "start_g": buf[s + 1], "start_b": buf[s + 2],
			"end_r": buf[e], "end_g": buf[e + 1], "end_b": buf[e + 2],
			"ctrl": ctrl,
		}
		keyframes.append({
			"index": i,
			"time_value": time_value,
			# `time << 3` per the PSX decompilation, and a time of 0 is INSTANT (1), not 0 —
			# a keyframe with no duration still occupies a frame.
			"duration_frames": time_value * 8 if time_value > 0 else 1,
			"start_r": raw["start_r"], "start_g": raw["start_g"], "start_b": raw["start_b"],
			"end_r": raw["end_r"], "end_g": raw["end_g"], "end_b": raw["end_b"],
			"ctrl": ctrl,
			# ctrl bit 7 picks TINT over FADE; the low seven bits are the blend mode.
			"mode": "TINT" if ctrl >= 128 else "FADE",
			"blend_mode": ctrl % 128,
			# The authoritative PSX-domain bytes the writer serializes from (#254 slice 4).
			# The three fields above it are a derived cache of these.
			"raw": raw,
		})
	return {
		"context": context,
		"keyframes": keyframes,
		"max_keyframe": buf.decode_s16(watermark_at),
	}
