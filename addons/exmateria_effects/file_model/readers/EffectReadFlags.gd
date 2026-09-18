extends RefCounted
## EFFECT-FLAGS reader (#272, ADR-0092) — GDScript port of `parse_effect.parse_effect_flags`.
##
## 🔴 THE RAW BYTE IS THE ROUND-TRIP SOURCE OF TRUTH. Bits 0-2 and 7 are loaded but AND-masked
## away by the engine, yet effect files still set them (`E001` = `0x03`) — so `flags_byte` is
## carried whole and the writer reproduces it verbatim rather than re-deriving it from the four
## decoded bools. Only bits 3-6 are engine-read (proven at `0x801A1530` / `0x801A61E0` /
## `0x801A3BF8` / `0x801A4A5C`).

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## The effect_flags block, or `null` when the section is out of bounds.
static func parse(buf: PackedByteArray, header: Dictionary):
	var off: int = int(header.get("effect_flags_ptr", -1))
	if off < 0 or off >= buf.size():
		return null
	var flags_byte: int = buf[off + Layout.FLAGS_OFF]
	return {
		"flags_byte": flags_byte,
		"terrain_height_adjust": (flags_byte & 0x08) != 0,
		"audio_fade": (flags_byte & 0x10) != 0,
		"time_scale_pattern1": (flags_byte & 0x20) != 0,
		"time_scale_pattern2": (flags_byte & 0x40) != 0,
	}
