extends RefCounted

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

## Byte-exact TEXTURE-PLANE writer (#280, ADR-0199 dec. 4): splice the re-quantized
## plane over [texture_ptr+0x404, EOF); CLUT + VRAM header held fixed. Zero slack in
## the corpus -> same-size only (resize = defrag).
## vault: .vaults/comments/exmateria_effects/texture-reader-referees.md

## Splice `block` (the indexed plane) over [texture_ptr+0x404, EOF) in place.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is PackedByteArray):
		return "texture: plane must be a PackedByteArray, got %s" % type_string(typeof(block))
	var texture_ptr: int = int(header["texture_ptr"])
	var start: int = texture_ptr + Layout.TEXTURE_PLANE_OFFSET
	var end: int = buf.size()
	if texture_ptr <= 0 or start >= end:
		return "texture: no pixel plane (texture_ptr=%d, file is %d bytes)" % [texture_ptr, end]
	if block.size() != end - start:
		return ("texture: plane is %d bytes but the section is %d — same-size replacement "
			+ "only (a resize is the deferred defrag path)") % [block.size(), end - start]
	# Tail IS the section: truncate + re-append, no ~100 KB byte loop.
	buf.resize(start)
	buf.append_array(block)
	return ""
