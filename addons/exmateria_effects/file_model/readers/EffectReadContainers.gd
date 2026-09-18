extends RefCounted
## SOUND-CONTAINERS reader (#289) — GDScript port of `parse_effect.parse_sound_containers`.
##
## The 4 per-effect TIER-2 resolver entries, 4 bytes each — `[mode, id_a, id_b, id_c]` at
## `effect_flags_ptr + 8 + ci*4`. Each entry carries its own `index`, which the writer uses for
## addressing, so the shape is position-independent.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## The sound_containers block, or `null` when the 16 bytes do not fit the file.
static func parse(buf: PackedByteArray, header: Dictionary):
	var base: int = int(header.get("effect_flags_ptr", -1)) + Layout.CONTAINERS_OFFSET
	if base < Layout.CONTAINERS_OFFSET or base + Layout.CONTAINER_COUNT * Layout.CONTAINER_STRIDE > buf.size():
		return null
	var containers: Array = []
	for ci in range(Layout.CONTAINER_COUNT):
		var o: int = base + ci * Layout.CONTAINER_STRIDE
		containers.append({
			"mode": buf[o], "id_a": buf[o + 1], "id_b": buf[o + 2], "id_c": buf[o + 3],
			"index": ci,
		})
	return {"containers": containers}
