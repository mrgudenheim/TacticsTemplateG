extends RefCounted
## PALETTE / FIELD-TINT reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_all_palette_keyframes` + `parse_palette_channel`, the read mirror of
## `writers/EffectWritePalette.gd`.
## Vault: [[Effect File Format]]
##
## NINE channels, not three: `for_each` / `phase1` / `phase2` × `affected_units` / `caster` /
## `target`. Each is 198 bytes — 33 s16 times at +0x00, 33 RGB triplets at +0x42, 33 ctrl bytes
## at +0xA5 — followed by an s16 `max_keyframe` at +198.
##
## `affected_units` is not "everyone": it is the units the ability actually hit AND the
## map/terrain, which is why it is a separate lane from `caster` and `target` rather than their
## union.
##
## 🔴 SAME `+8` ASYMMETRY AS SCREEN: `for_each` bases at `timeline_ptr + 8`, `phase1` and
## `phase2` at `timeline_ptr`. Unlike screen, every watermark here sits at the channel's own
## tail, so there is only the one asymmetry.
##
## ⚠️ NOT SHARED WITH `EffectReadScreen`, DELIBERATELY — the argument is written out in that
## file's header. Short version: the two records look alike and are not the same record, and
## the shared part is four lines of arithmetic against a field-schema interpreter.
##
## THE RGB BYTES ARE REPORTED TWICE, UNSIGNED AND SIGNED, AND THE SIGNED VIEW IS THE READABLE
## ONE. These are colour DELTAS, so `246` means `-10`; `rgb_signed` exists so a +16/-10/-13
## tint does not read as 16/246/243. Only `rgb` is written back (`EffectWritePalette` ignores
## the signed view), so referee B is blind to `rgb_signed`, `enabled`, `blend_mode` and
## `duration_frames` alike.
##
## ⚠️ THE WATERMARK IS CLAMPED, LIKE CAMERA'S AND UNLIKE SCREEN'S. Out of `[0, 33)` reads as 0.
## Measured: unreachable on this corpus — see the `# seeded-break:` line.
##
## ABSENT IS `null`; a channel that would read past EOF is OMITTED, so the key set is data.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## All nine channels — `palette.json`'s shape, `{context: {channel_name: channel}}` — or `null`
## when the section is out of bounds. A context whose channels all fall past EOF is still
## present as an empty dictionary, exactly as the Python leaves it.
static func parse(buf: PackedByteArray, header: Dictionary):
	var timeline_ptr: int = int(header.get("timeline_section_ptr", 0))
	if timeline_ptr <= 0 or timeline_ptr >= buf.size():
		return null
	var out: Dictionary = {}
	for context in Layout.PALETTE_TRACK_OFFSETS:
		out[context] = {}
		var base: int = timeline_ptr + (Layout.TIMELINE_FOR_EACH_BASE_BIAS \
			if context == "for_each" else 0)
		var offsets: Dictionary = Layout.PALETTE_TRACK_OFFSETS[context]
		for channel_name in offsets:
			var offset: int = base + int(offsets[channel_name])
			if offset + Layout.PALETTE_TRACK_SIZE > buf.size():
				continue
			out[context][channel_name] = parse_channel(buf, offset, str(context),
				str(channel_name))
	return out


## One 198-byte channel at `base_offset`, plus its trailing watermark.
static func parse_channel(buf: PackedByteArray, base_offset: int, context: String,
		channel_name: String) -> Dictionary:
	var max_kf: int = 0
	var max_kf_offset: int = base_offset + Layout.PALETTE_TRACK_SIZE
	if max_kf_offset + 2 <= buf.size():
		max_kf = buf.decode_s16(max_kf_offset)
		if max_kf < 0 or max_kf >= Layout.MAX_PALETTE_KEYFRAMES:
			max_kf = 0

	var keyframes: Array = []
	for i in range(Layout.MAX_PALETTE_KEYFRAMES):
		var time_value: int = buf.decode_s16(base_offset + Layout.PALETTE_OFF_TIME + i * 2)
		var rgb_at: int = base_offset + Layout.PALETTE_OFF_RGB + i * 3
		var r: int = buf[rgb_at]
		var g: int = buf[rgb_at + 1]
		var b: int = buf[rgb_at + 2]
		var ctrl: int = buf[base_offset + Layout.PALETTE_OFF_CTRL + i]
		keyframes.append({
			"index": i,
			"time_value": time_value,
			# `time << 3` per the PSX decompilation; a time of 0 is INSTANT (1), not 0.
			"duration_frames": time_value * 8 if time_value > 0 else 1,
			"rgb": [r, g, b],
			# The same three bytes as two's-complement deltas — see the header.
			"rgb_signed": [_signed(r), _signed(g), _signed(b)],
			"ctrl": ctrl,
			# ctrl bit 7 enables the channel; the low seven bits are the blend mode (0-10).
			"enabled": ctrl >= 128,
			"blend_mode": ctrl & 0x7F,
		})

	return {
		"context": context,
		"channel_name": channel_name,
		"keyframes": keyframes,
		"max_keyframe": max_kf,
	}


static func _signed(value: int) -> int:
	return value if value < 128 else value - 256
