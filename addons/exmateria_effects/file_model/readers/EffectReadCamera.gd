extends RefCounted
## CAMERA-TIMELINE reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_camera_keyframes` + `parse_camera_phase_table`, the read mirror of
## `writers/EffectWriteCamera.gd`.
## Vault: [[Effect File Format]]
##
## Three FIXED-SLOT SoA tables — `phase1` (21 slots), `for_each` (17), `phase2` (21) — each
## holding parallel arrays of `end_frame`, a 3×s16 angle, a 3×s16 position, a 3×s16 zoom and a
## u16 command word, plus one `max_keyframe` watermark.
##
## 🔴 ALL THREE BASE AT `timeline_section_ptr` DIRECTLY — NOT `+8`. The screen and palette
## `for_each` channels DO take the `+8` bias, and the camera's `for_each` table does not. That
## is the single easiest thing to get wrong in this corner of the file, and the tables are
## adjacent enough that an eight-byte slip still decodes into plausible-looking numbers.
##
## THE TABLE IS ALWAYS `count` SLOTS LONG, WATERMARK OR NOT. `max_keyframe` says how many the
## engine walks; the parser returns every native slot regardless, so the keyframes past the
## watermark are real bytes and round-trip. That is also why `EffectWriteCamera` can refuse an
## over-capacity table instead of growing one: there is no slot to grow into.
##
## ⚠️ THE READER CLAMPS WHERE THE WRITER REFUSES. A `max_keyframe` outside `[0, count)` reads
## as 0 here (mirroring the Python), while `EffectWriteCamera.serialize_table` returns a refusal
## for the same value. Both are right for their direction — a reader must produce something for
## bytes that exist, a writer must not stamp a watermark the ROM cannot hold — but it means
## referee B would go quiet on a corpus effect with a bad watermark, because the clamped 0 is
## what gets written back. Measured: no corpus effect has one (seeding the clamp away is green).
##
## ABSENT IS `null`, and a table that would read past EOF is OMITTED rather than zero-filled —
## so `camera.json` can carry one, two or three tables and the key set itself is data.
##
## 🔴 THREE DEFENSIVE PATHS HERE ARE UNGUARDED — each seeded, RUN, and green across all 400:
## the `max_keyframe` clamp, `_vec3`'s out-of-bounds `[0, 0, 0]`, and `_s16_or_zero`'s fallback.
## No corpus effect has a watermark outside its slots or a table that runs off the end of the
## file, so none of the three is exercised. They are ported because the Python has them and a
## reader that crashed on a malformed file would be worse — not because anything checks them.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

## `cmd & 0x01E0` -> the keyframe's source mode. Sparse — 0x0A0, 0x0E0, 0x120, 0x160, 0x1A0 have
## no name, and the Python formats those as `UNKNOWN_0x%03X`.
const SOURCE_MODES: Dictionary = {
	0x000: "TARGET", 0x020: "OFFSET", 0x040: "DIRECT", 0x060: "ORIGIN",
	0x080: "EFFECT_CTR", 0x0C0: "MAP", 0x100: "SLOT_COPY", 0x140: "CASTER",
	0x180: "ALL_TARGETS", 0x1C0: "CURSOR",
}

## `cmd & 0x1E00` -> the interpolation. Also sparse, and note 0x0000 is NOT in it: a command
## word with no interpolation bits formats as `UNKNOWN_0x0000`, which is a real and common
## value rather than an error.
const INTERPOLATIONS: Dictionary = {
	0x0200: "IMMEDIATE", 0x0400: "COSINE_A", 0x0600: "COSINE_B", 0x0800: "LINEAR",
	0x0A00: "COSINE_C", 0x0C00: "ADDITIVE", 0x0E00: "ADDITIVE_B",
	0x1000: "SHAKE_DAMPED", 0x1200: "SHAKE_DIRECT", 0x1400: "SHAKE_DAMPED_B",
}


## The three phase tables — `camera.json`'s shape — or `null` when the section is out of
## bounds. A table whose furthest field would read past EOF is left OUT of the result entirely.
static func parse(buf: PackedByteArray, header: Dictionary):
	var timeline_ptr: int = int(header.get("timeline_section_ptr", 0))
	if timeline_ptr <= 0 or timeline_ptr >= buf.size():
		return null
	var out: Dictionary = {}
	for table_name in Layout.CAMERA_TRACK_TABLES:
		var offsets: Dictionary = Layout.CAMERA_TRACK_TABLES[table_name]
		var furthest: int = 0
		for key in ["end_frame", "angle", "position", "zoom", "command", "max_keyframe"]:
			furthest = maxi(furthest, int(offsets[key]))
		if timeline_ptr + furthest + 2 <= buf.size():
			out[table_name] = parse_table(buf, timeline_ptr, offsets)
	return out


## One phase table at `base` (which is `timeline_section_ptr`, unbiased).
static func parse_table(buf: PackedByteArray, base: int, offsets: Dictionary) -> Dictionary:
	var count: int = int(offsets["count"])

	# A watermark outside the native slots reads as 0 — see the ⚠️ note in the header.
	var max_kf: int = 0
	var max_kf_off: int = base + int(offsets["max_keyframe"])
	if max_kf_off + 2 <= buf.size():
		max_kf = buf.decode_s16(max_kf_off)
		if max_kf < 0 or max_kf >= count:
			max_kf = 0

	var keyframes: Array = []
	for i in range(count):
		keyframes.append({
			"index": i,
			"end_frame": _s16_or_zero(buf, base + int(offsets["end_frame"]) + i * 2),
			"angle": _vec3(buf, base + int(offsets["angle"]) + i * 6),
			"position": _vec3(buf, base + int(offsets["position"]) + i * 6),
			"zoom": _vec3(buf, base + int(offsets["zoom"]) + i * 6),
		})
		var c_off: int = base + int(offsets["command"]) + i * 2
		var cmd: int = buf.decode_u16(c_off) if c_off + 2 <= buf.size() else 0
		var kf: Dictionary = keyframes[i]
		kf["command_raw"] = cmd
		kf["channel_mask"] = cmd & 0x0007
		kf["source_mode"] = SOURCE_MODES.get(cmd & 0x01E0,
			"UNKNOWN_0x%03X" % (cmd & 0x01E0))
		kf["interpolation"] = INTERPOLATIONS.get(cmd & 0x1E00,
			"UNKNOWN_0x%04X" % (cmd & 0x1E00))
		kf["param_index"] = (cmd >> 3) & 0x03
		kf["flags"] = (cmd >> 13) & 0x07

	return {"max_keyframe": max_kf, "keyframes": keyframes}


static func _s16_or_zero(buf: PackedByteArray, offset: int) -> int:
	return buf.decode_s16(offset) if offset + 2 <= buf.size() else 0


## Three s16 from `offset`, or `[0, 0, 0]` when the whole triplet does not fit. All-or-nothing,
## mirroring the Python — a partial triplet is never half-read.
static func _vec3(buf: PackedByteArray, offset: int) -> Array:
	if offset + 6 > buf.size():
		return [0, 0, 0]
	return [buf.decode_s16(offset), buf.decode_s16(offset + 2), buf.decode_s16(offset + 4)]
