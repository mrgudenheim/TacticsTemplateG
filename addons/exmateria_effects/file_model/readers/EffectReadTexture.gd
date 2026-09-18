extends RefCounted
## TEXTURE reader (#280/#297, ADR-0199) — the sheet's INDEXED PLANE, its CLUTs, and a decode.
## GDScript port of `tools/write_effect_texture.py`'s read half + `parse_effect`'s meta/palette
## + the Lua extractor's depth/dimension derivation.
## Registry entry = the PLANE alone: the only part of this section that can be written back — ADR-0199
## holds the CLUT fixed and the VRAM header is derived. meta()/swatches()/clut_words()/decode are
## DERIVED VIEWS (named statics, not registry entries; patch_all refuses no-serializer sections).
## Only section load-bearing at render time: a raw .BIN with no extract folder draws NO PIXELS.
## 🔴 `+0x403` IS THE UPLOAD STRIDE, NOT THE DEPTH — they disagree for 282 of the 401 corpus effects;
## depth is the per-frame `flags_byte0 & 0x80`. No class_name (ADR-0004) — path-preloaded.
## Vault: [[Effect File Format]]
## vault: .vaults/comments/exmateria_effects/texture-reader-referees.md

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

## 5-bit -> 8-bit: REPLICATE (`(v<<3)|(v>>2)`) is the correct PSX expansion; TRUNCATE (`v*8`) reproduces
## the committed texture.tga byte for byte — referee C's exact-compare mode.
enum { EXPAND_REPLICATE, EXPAND_TRUNCATE }

## Alpha carries the STP bit, never opacity (ADR-0096).
const STP_ALPHA: int = 128
const OPAQUE_ALPHA: int = 255


# --- the registered section: the indexed pixel plane -------------------------

## The indexed pixel plane — `[texture_ptr + 0x404, EOF)` — or `null` when absent/out of bounds.
## ZERO slack in all 401 corpus effects: EOF is the section's true end (the u24 at `+0x400` is a cross-check only).
static func parse(buf: PackedByteArray, header: Dictionary):
	var start: int = _plane_start(header)
	if start < 0 or start >= buf.size():
		return null
	return buf.slice(start, buf.size())


static func _plane_start(header: Dictionary) -> int:
	var texture_ptr: int = int(header.get("texture_ptr", 0))
	if texture_ptr <= 0:
		return -1
	return texture_ptr + Layout.TEXTURE_PLANE_OFFSET


# --- derived view: the VRAM upload header ------------------------------------

## The 4-byte VRAM upload header at `texture_ptr + 0x400` (texture_meta.json's shape), or `null` out of bounds.
## `vram_y` is `null`: not encoded — the init at 0x801a0e80 uploads at fixed X `vram_x` and derives height from
## size/stride; inventing a y would be fabrication. `palette_1/2_nonzero` report which CLUT block holds data.
## No texel WIDTH in here: a row is `row_bytes` BYTES (one texel at 8bpp, two at 4bpp); `dimensions()` takes depth.
static func meta(buf: PackedByteArray, header: Dictionary):
	var base: int = int(header.get("texture_ptr", 0))
	if base <= 0 or base + Layout.TEXTURE_PLANE_OFFSET > buf.size():
		return null
	var h: int = base + Layout.TEXTURE_VRAM_HEADER_OFFSET
	var size: int = buf[h] | (buf[h + 1] << 8) | (buf[h + 2] << 16)
	var stride_flag: int = buf[base + Layout.TEXTURE_STRIDE_FLAG_OFFSET]
	var row_bytes: int = Layout.TEXTURE_ROW_BYTES_WIDE if stride_flag \
		else Layout.TEXTURE_ROW_BYTES_NARROW
	@warning_ignore("integer_division")
	var rows: int = size / row_bytes if row_bytes else 0
	return {
		"pixel_data_size": size,
		"stride_flag": stride_flag,
		"row_bytes": row_bytes,
		"height": rows,
		"vram_x": Layout.TEXTURE_VRAM_X,
		"vram_y": null,
		"palette_1_nonzero": _any_nonzero(buf, base + Layout.TEXTURE_CLUT_1_OFFSET,
			Layout.TEXTURE_CLUT_BLOCK_BYTES),
		"palette_2_nonzero": _any_nonzero(buf, base + Layout.TEXTURE_CLUT_2_OFFSET,
			Layout.TEXTURE_CLUT_BLOCK_BYTES),
	}


static func _any_nonzero(buf: PackedByteArray, start: int, length: int) -> bool:
	for i in range(start, mini(start + length, buf.size())):
		if buf[i] != 0:
			return true
	return false


# --- derived view: the swatch strip ------------------------------------------

## CLUT line 1 as 256 `[r8, g8, b8, stp]` entries — texture_palette.json's shape (bit-replication included: an EXACT
## match for the committed artifact). Always line 1, always 256: the studio's swatch strip, not what a frame reads.
static func swatches(buf: PackedByteArray, header: Dictionary):
	var base: int = int(header.get("texture_ptr", 0))
	if base <= 0:
		return null
	var out: Array = []
	for i in range(Layout.TEXTURE_CLUT_ENTRIES):
		var off: int = base + Layout.TEXTURE_CLUT_1_OFFSET + i * 2
		if off + 2 > buf.size():
			break
		var word: int = buf[off] | (buf[off + 1] << 8)
		out.append([
			_expand5(word & 0x1F, EXPAND_REPLICATE),
			_expand5((word >> 5) & 0x1F, EXPAND_REPLICATE),
			_expand5((word >> 10) & 0x1F, EXPAND_REPLICATE),
			(word >> 15) & 1,
		])
	return out


# --- the CLUT a FRAME actually reads -----------------------------------------

## The BGR555 words one frame renders through. `uses_palette_2` (the frame's `flags_byte0 & 0x10`) picks the 512-byte
## block; at 4bpp `palette_id` then picks a 16-entry sub-palette inside it. At 8bpp the palette IS the whole block and
## `palette_id` is ignored — measured, all 338 8bpp corpus effects carry it 0 on every frame.
static func clut_words(buf: PackedByteArray, header: Dictionary, is_8bpp: bool,
		uses_palette_2: bool = false, palette_id: int = 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base: int = int(header.get("texture_ptr", 0))
	if base <= 0:
		return out
	base += Layout.TEXTURE_CLUT_2_OFFSET if uses_palette_2 else Layout.TEXTURE_CLUT_1_OFFSET
	var count: int = Layout.TEXTURE_CLUT_ENTRIES if is_8bpp else Layout.TEXTURE_SUB_PALETTE_ENTRIES
	if not is_8bpp:
		base += maxi(palette_id, 0) * Layout.TEXTURE_SUB_PALETTE_ENTRIES * 2
	out.resize(count)
	for i in range(count):
		var off: int = base + i * 2
		out[i] = (buf[off] | (buf[off + 1] << 8)) if off + 2 <= buf.size() else 0
	return out


# --- depth and dimensions ----------------------------------------------------

## The sheet's colour depth from the FIRST frame of the first frameset — `true` 8bpp, `false` 4bpp, `null` when the
## frames section cannot be walked. `extract_effect_texture.lua`'s `detect_is_8bpp` transcribed deliberately: it
## produced every committed texture.tga, so referee C compares like with like. NOT `write_effect_texture.sheet_facts`,
## which unions depth over ALL frames — the right gate for AUTHORING (refuses E040/E509/E510), the wrong one for
## decoding, where something must still be drawn.
static func sheet_depth(buf: PackedByteArray, header: Dictionary):
	var frames_ptr: int = int(header.get("frames_ptr", 0))
	if frames_ptr <= 0 or frames_ptr >= buf.size():
		return null
	var group_count: int = buf[frames_ptr]
	if group_count == 0:
		group_count = 1
	var offset_table: int = frames_ptr + 4 + group_count * 2
	if offset_table + 2 > buf.size():
		return null
	var first: int = buf[offset_table] | (buf[offset_table + 1] << 8)
	# frameset header is 4 bytes (flags + frame count); the first frame follows it.
	var first_frame: int = frames_ptr + first + 4 + Layout.FRAMESET_HEADER_SIZE
	if first_frame < 0 or first_frame >= buf.size():
		return null
	return (buf[first_frame] & 0x80) != 0


## `(width, height)` in TEXELS for the whole sheet, or `Vector2i.ZERO` when it cannot be derived — transcribed from
## the Lua extractor, which sized the committed TGAs. Height = the 16-bit word at `+0x400` shifted by the stride's
## amount; when that reads ZERO the plane LENGTH is used instead — not dead code: 56 of the 401 corpus effects carry
## a pixel-data size of exactly 0x10000 (low 16 bits zero). ⚠️ The fallback's row width is DEPTH-dependent (256 at
## 8bpp, 128 at 4bpp); the Python forces 256 there — a third tool disagreement, followed Lua because the Lua sized the
## referee-C TGAs. 🔴 UNGUARDED: all 56 fallback effects are 8bpp (the two readings agree there), so do NOT read
## referee C as covering a 4bpp 0x10000 sheet.
static func dimensions(buf: PackedByteArray, header: Dictionary, is_8bpp: bool) -> Vector2i:
	var base: int = int(header.get("texture_ptr", 0))
	if base <= 0 or base + Layout.TEXTURE_PLANE_OFFSET > buf.size():
		return Vector2i.ZERO
	var h: int = base + Layout.TEXTURE_VRAM_HEADER_OFFSET
	var combined: int = buf[h] | (buf[h + 1] << 8)
	var stride_flag: int = buf[base + Layout.TEXTURE_STRIDE_FLAG_OFFSET]
	var row_bytes: int = Layout.TEXTURE_ROW_BYTES_WIDE if stride_flag \
		else Layout.TEXTURE_ROW_BYTES_NARROW
	var height: int = combined >> (8 if stride_flag else 7)
	if height == 0:
		var plane: int = buf.size() - (base + Layout.TEXTURE_PLANE_OFFSET)
		row_bytes = Layout.TEXTURE_ROW_BYTES_WIDE if is_8bpp \
			else Layout.TEXTURE_ROW_BYTES_NARROW
		@warning_ignore("integer_division")
		var rows: int = plane / row_bytes if plane > 0 else 0
		height = rows
	return Vector2i(row_bytes if is_8bpp else row_bytes * 2, height)


# --- the decode --------------------------------------------------------------

## The sheet as RGBA bytes, four per texel, top-left-origin row order — the same order/channels `TextureTga.decode`
## hands back, so the two are directly comparable; empty when the section is absent or unsized. REPLICATE = correct +
## default; TRUNCATE reproduces texture.tga byte for byte, keeping referee C exact. ~13M texels via an int32 lookup.
static func decode_rgba(buf: PackedByteArray, header: Dictionary, is_8bpp: bool,
		uses_palette_2: bool = false, palette_id: int = 0,
		expand: int = EXPAND_REPLICATE) -> PackedByteArray:
	var plane = parse(buf, header)
	if plane == null:
		return PackedByteArray()
	var size: Vector2i = dimensions(buf, header, is_8bpp)
	if size.x <= 0 or size.y <= 0:
		return PackedByteArray()
	var texels: int = size.x * size.y
	var words: PackedInt32Array = clut_words(buf, header, is_8bpp, uses_palette_2, palette_id)
	if words.is_empty():
		return PackedByteArray()

	var lut := PackedInt32Array()
	lut.resize(words.size())
	for i in range(words.size()):
		lut[i] = _packed_rgba(words[i], expand)

	var out := PackedInt32Array()
	out.resize(texels)
	var mask: int = words.size() - 1        # 256 and 16 are both powers of two
	if is_8bpp:
		var n: int = mini(texels, plane.size())
		for i in range(n):
			out[i] = lut[plane[i] & mask]
	else:
		# 4bpp packs two texels per byte, LOW nibble first.
		var n: int = mini(texels >> 1, plane.size())
		for i in range(n):
			var b: int = plane[i]
			out[i * 2] = lut[b & 0x0F]
			out[i * 2 + 1] = lut[(b >> 4) & 0x0F]
	return out.to_byte_array()


## The sheet as an RGBA8 `Image` for `ImageTexture.create_from_image`; `null` when the section is absent — an editor
## that cannot tell "no texture" from "a black one" draws black over a sheet it failed to read.
static func decode_image(buf: PackedByteArray, header: Dictionary, is_8bpp: bool,
		uses_palette_2: bool = false, palette_id: int = 0,
		expand: int = EXPAND_REPLICATE):
	var size: Vector2i = dimensions(buf, header, is_8bpp)
	var rgba: PackedByteArray = decode_rgba(buf, header, is_8bpp, uses_palette_2, palette_id,
		expand)
	if size.x <= 0 or size.y <= 0 or rgba.size() != size.x * size.y * 4:
		return null
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, rgba)


## One BGR555 word as `r | g<<8 | b<<16 | a<<24` (alpha = STP bit 128, never opacity), signed to fit an int32 — the
## little-endian bytes `PackedInt32Array.to_byte_array()` emits are R,G,B,A.
static func _packed_rgba(word: int, expand: int) -> int:
	var v: int = _expand5(word & 0x1F, expand) \
		| (_expand5((word >> 5) & 0x1F, expand) << 8) \
		| (_expand5((word >> 10) & 0x1F, expand) << 16) \
		| ((STP_ALPHA if (word & 0x8000) else OPAQUE_ALPHA) << 24)
	return v - 0x100000000 if v >= 0x80000000 else v


static func _expand5(v: int, expand: int) -> int:
	return v * 8 if expand == EXPAND_TRUNCATE else (v << 3) | (v >> 2)
