extends RefCounted
## Byte-exact EFFECT-FLAGS writer for `E###.BIN` (#272, ADR-0092) — GDScript port of
## `tools/write_effect_flags.py`.
##
## The single flags byte at `+0x00` of the effect_flags section. Only bits 3-6 are engine-read,
## but the WHOLE raw byte is written so the engine-ignored bits 0-2/7 ride along untouched.
## The dead `0x04` override and the 16 sound-channel bytes at `+0x08..+0x17` stay verbatim —
## the latter are edited through the `sound_containers` serializer, over disjoint bytes.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## Partial-patch the flags byte of `buf` IN PLACE from `block` (the parsed, possibly
## edited effect_flags sub-tree — it carries `flags_byte`).
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary) or not block.has("flags_byte"):
		return ""
	var ptr: int = int(header["effect_flags_ptr"])
	buf[ptr + Layout.FLAGS_OFF] = int(block["flags_byte"]) & 0xFF
	return ""
