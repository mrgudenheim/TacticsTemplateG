extends RefCounted
## Byte-exact SOUND-CONTAINERS writer for `E###.BIN` (#289) — GDScript port of
## `tools/write_effect_containers.py`.
##
## The shared, effect-global TIER-2 SoundContainers: 4 entries of 4 bytes
## `[mode, id_a, id_b, id_c]` at `effect_flags_ptr + 8`. These live INSIDE the Effect-Flags
## section, but this serializer owns ONLY the 16 container bytes, so `EffectWriteFlags`
## coexists with it over disjoint bytes.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## Partial-patch the 4 SoundContainers of `buf` IN PLACE from `block` (the parsed, possibly
## edited doc). Only the known container bytes are overwritten.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var containers = block.get("containers")
	if not (containers is Array):
		return ""
	var base: int = int(header["effect_flags_ptr"]) + Layout.CONTAINERS_OFFSET
	var n: int = mini(Layout.CONTAINER_COUNT, containers.size())
	for ci in range(n):
		var entry = containers[ci]
		if not (entry is Dictionary):
			continue
		var cbase: int = base + ci * Layout.CONTAINER_STRIDE
		for k in range(Layout.CONTAINER_FIELDS.size()):
			buf[cbase + k] = int(entry.get(Layout.CONTAINER_FIELDS[k], 0)) & 0xFF
	return ""
