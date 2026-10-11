extends RefCounted
## The studio's RGBA TGA codec (#280, ADR-0199 decision 6).
##
## #280's round-trip format is "an RGBA .tga matching
## `godot-learning/tools/extract_effect_texture.lua` exactly". Godot READS TGA
## (`Image.load_tga_from_buffer`) but cannot WRITE one, and the studio owns both
## directions of the artist loop, so the 18-byte layout is written by hand here:
##
##   0      ID length (0)          9..10  Y origin (0)
##   1      colour-map type (0)    11..12 width  (u16 LE)
##   2      image type (2)         13..14 height (u16 LE)
##   3..7   colour-map spec (0)    16     bits per pixel (32)
##   8..9   X origin (0)           17     descriptor (0x28)
##
## Descriptor 0x28 = top-left origin (0x20) + 8 alpha bits (0x08), so rows run
## top-to-bottom and need no flip. Texel bytes are BGRA in the file; this module
## hands callers RGBA.
##
## Alpha is the STP bit, never opacity (ADR-0096) — this codec only carries it;
## the meaning lives in the quantizer.
##
## No `class_name` (ADR-0004).

const HEADER_SIZE := 18
const IMAGE_TYPE_TRUECOLOR := 2
const IMAGE_TYPE_TRUECOLOR_RLE := 10
const DESCRIPTOR_TOP_LEFT_ALPHA8 := 0x28


## Decode a TGA into `{ok, width, height, pixels, error}` where `pixels` is RGBA,
## four bytes per texel, in top-left-origin row order.
static func decode(raw: PackedByteArray) -> Dictionary:
	if raw.size() < HEADER_SIZE:
		return _bad("file is %d bytes — too short to hold a TGA header" % raw.size())
	var image_type: int = raw[2]
	if image_type != IMAGE_TYPE_TRUECOLOR and image_type != IMAGE_TYPE_TRUECOLOR_RLE:
		return _bad(("image type %d is neither 2 (uncompressed true-colour) nor 10 " % image_type)
			+ "(RLE true-colour) — re-save as a 32-bit true-colour .tga")
	var bpp: int = raw[16]
	if bpp != 32:
		return _bad(("%d bits per pixel — the studio's format is 32-bit RGBA; " % bpp)
			+ "re-save with an alpha channel (it carries the STP bit, not opacity)")

	var width: int = raw[12] | (raw[13] << 8)
	var height: int = raw[14] | (raw[15] << 8)
	var start: int = HEADER_SIZE + raw[0]        # skip the optional image-ID field
	var need: int = width * height * 4

	# RLE (image type 10) is the DEFAULT in several editors' TGA export, so an artist's
	# re-save routinely arrives compressed — refusing it would reject ordinary saves of a
	# file the studio itself exported. It is lossless, so expand it up front and let every
	# line below (origin flip, channel swizzle, bounds) run on one uniform texel plane.
	var body: PackedByteArray = raw
	if image_type == IMAGE_TYPE_TRUECOLOR_RLE:
		var expanded: Dictionary = _expand_rle(raw, start, need)
		if not expanded.get("ok", false):
			return _bad(str(expanded.get("error", "")))
		body = expanded["bytes"]
		start = 0
	elif raw.size() - start < need:
		return _bad("%dx%d needs %d texel bytes, file holds %d"
			% [width, height, need, raw.size() - start])

	# Descriptor bit 5 = origin. The studio writes top-left (0x28), but
	# bottom-left is the TGA default in Photoshop/GIMP/Aseprite, so an artist's
	# save routinely arrives that way and must be flipped rather than read
	# upside down.
	var bottom_up: bool = (raw[17] & 0x20) == 0
	var row_bytes: int = width * 4

	var pixels := PackedByteArray()
	pixels.resize(need)
	for y in range(height):
		var src_row: int = (height - 1 - y) if bottom_up else y
		var src: int = start + src_row * row_bytes
		var dst: int = y * row_bytes
		for i in range(0, row_bytes, 4):
			pixels[dst + i] = body[src + i + 2]          # R <- file's third byte
			pixels[dst + i + 1] = body[src + i + 1]      # G
			pixels[dst + i + 2] = body[src + i]          # B <- file's first byte
			pixels[dst + i + 3] = body[src + i + 3]      # A
	return {"ok": true, "width": width, "height": height, "pixels": pixels, "error": ""}


## Encode RGBA `pixels` (four bytes per texel, top-left-origin rows) into TGA bytes
## laid out exactly as the Lua extractor writes them.
static func encode(width: int, height: int, pixels: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEADER_SIZE + width * height * 4)
	for i in range(HEADER_SIZE):
		out[i] = 0
	out[2] = IMAGE_TYPE_TRUECOLOR
	out[12] = width & 0xFF
	out[13] = (width >> 8) & 0xFF
	out[14] = height & 0xFF
	out[15] = (height >> 8) & 0xFF
	out[16] = 32
	out[17] = DESCRIPTOR_TOP_LEFT_ALPHA8

	var n: int = min(pixels.size(), width * height * 4)
	for i in range(0, n, 4):
		out[HEADER_SIZE + i] = pixels[i + 2]     # B
		out[HEADER_SIZE + i + 1] = pixels[i + 1] # G
		out[HEADER_SIZE + i + 2] = pixels[i]     # R
		out[HEADER_SIZE + i + 3] = pixels[i + 3] # A
	return out


## Expand `need` bytes of RLE true-colour texel data starting at `from`.
##
## TGA RLE is packet-framed: one header byte, then bit 7 decides the kind. Bit set = a RUN
## packet — `(n & 0x7F) + 1` copies of the ONE texel that follows. Bit clear = a RAW packet —
## that many literal texels. Two properties measured on a real editor's save drive the shape
## here: packets do NOT respect scanline boundaries (a 128x128 sheet came back with runs a
## full row wide, unaligned to rows), so this fills a FLAT plane rather than working row by
## row; and the file carried a 26-byte TGA 2.0 footer ("TRUEVISION-XFILE."), so it stops at
## `need` rather than reading to EOF. Returns `{ok, bytes, error}`.
static func _expand_rle(raw: PackedByteArray, from: int, need: int) -> Dictionary:
	var out := PackedByteArray()
	out.resize(need)
	var written: int = 0
	var pos: int = from
	while written < need:
		if pos >= raw.size():
			return {"ok": false, "bytes": PackedByteArray(), "error":
				"RLE data ends after %d of %d texel bytes — the file is truncated"
				% [written, need]}
		var header: int = raw[pos]
		pos += 1
		var count: int = (header & 0x7F) + 1
		if (header & 0x80) != 0:
			if pos + 4 > raw.size():
				return {"ok": false, "bytes": PackedByteArray(), "error":
					"RLE run packet is cut off %d bytes into the file" % pos}
			for _i in range(count):
				if written + 4 > need:
					break        # a final packet may overrun the last row; clip it
				for b in range(4):
					out[written + b] = raw[pos + b]
				written += 4
			pos += 4
		else:
			var span: int = count * 4
			if pos + span > raw.size():
				return {"ok": false, "bytes": PackedByteArray(), "error":
					"RLE raw packet is cut off %d bytes into the file" % pos}
			for b in range(span):
				if written >= need:
					break
				out[written] = raw[pos + b]
				written += 1
			pos += span
	return {"ok": true, "bytes": out, "error": ""}


static func _bad(msg: String) -> Dictionary:
	return {"ok": false, "width": 0, "height": 0,
			"pixels": PackedByteArray(), "error": msg}
