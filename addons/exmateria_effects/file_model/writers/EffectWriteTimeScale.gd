extends RefCounted

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

## Byte-exact TIME-SCALE writer (#270, ADR-0093): two 600-value regions (outer @+0x000,
## for_each @+0x12C), 300 bytes each, even LOW / odd HIGH nibble. Every nibble is
## re-emitted from the parsed doc — no original byte rides along. ENABLE bits live in
## effect_flags (EffectWriteFlags), not here.
## vault: .vaults/comments/exmateria_effects/bin-reader-referees.md

## Nibble-pack 600 values into 300 bytes at `region_start` (`& 0x0F` guards a stray high bit).
static func _pack_region_into(buf: PackedByteArray, region_start: int, values: Array) -> void:
	for frame in range(Layout.TIME_SCALE_REGION_FRAMES):
		var v: int = int(values[frame]) & 0x0F
		var byte_offset: int = region_start + (frame >> 1)
		if (frame & 1) == 0:
			buf[byte_offset] = (buf[byte_offset] & 0xF0) | v
		else:
			buf[byte_offset] = (buf[byte_offset] & 0x0F) | (v << 4)


## Partial-patch the two curve regions of `buf` in place from `block`.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var ptr: int = int(header["time_scale_ptr"])
	if block.has("outer_phases"):
		_pack_region_into(buf, ptr + Layout.TIME_SCALE_OFF_OUTER, block["outer_phases"])
	if block.has("for_each"):
		_pack_region_into(buf, ptr + Layout.TIME_SCALE_OFF_FOR_EACH, block["for_each"])
	return ""
