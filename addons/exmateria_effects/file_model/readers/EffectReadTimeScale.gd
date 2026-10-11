extends RefCounted
## TIME-SCALE reader (#270, ADR-0093) — GDScript port of `parse_effect.parse_time_scale`.
##
## Time scale controls the VBlank wait between game-loop iterations: higher values mean fewer
## fixed steps per real second, so everything slows down. Two 600-frame regions, stored as
## packed nibbles (two values per byte) — even frame in the LOW nibble, odd in the HIGH.
##
## The block also carries the two ENABLE bits, which physically live in the effect_flags byte,
## not in this section — so this reader needs BOTH pointers. They are reported here for display
## and edited through the `effect_flags` channel; the time_scale writer never writes them.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


static func _unpack_region(buf: PackedByteArray, region_start: int) -> Array:
	var values: Array = []
	for frame in range(Layout.TIME_SCALE_REGION_FRAMES):
		var byte_val: int = buf[region_start + (frame >> 1)]
		values.append(byte_val & 0x0F if (frame & 1) == 0 else byte_val >> 4)
	return values


## The time_scale block, or `null` when the section is absent or out of bounds.
## `time_scale_ptr == 0` means ABSENT — it is not an offset (131 of 400 effects have one).
static func parse(buf: PackedByteArray, header: Dictionary):
	var off: int = int(header.get("time_scale_ptr", 0))
	var flags_off: int = int(header.get("effect_flags_ptr", -1))
	if off <= 0 or flags_off < 0 or flags_off >= buf.size():
		return null
	if off + 2 * Layout.TIME_SCALE_REGION_BYTES > buf.size():
		return null
	var flags_byte: int = buf[flags_off]
	return {
		"flags": {
			"time_scale_pattern1": (flags_byte & 0x20) != 0,
			"time_scale_pattern2": (flags_byte & 0x40) != 0,
		},
		"outer_phases": _unpack_region(buf, off + Layout.TIME_SCALE_OFF_OUTER),
		"for_each": _unpack_region(buf, off + Layout.TIME_SCALE_OFF_FOR_EACH),
	}
