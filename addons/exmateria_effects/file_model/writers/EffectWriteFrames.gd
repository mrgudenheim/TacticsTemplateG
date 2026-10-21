extends RefCounted
## Byte-exact FRAMES / FRAMESET writer for `E###.BIN` (#278) — GDScript port of
## `tools/write_effect_frames.py`.
##
## ONE PATH: `build_section` RE-LAYS OUT the whole section from the base's own geometry plus
## the block's frame counts (#449 q1) — adding or deleting a frame becomes expressible and
## the group/offset table finally has a writer. Frame fields are written in place, 24 bytes
## at a time, by `serialize_frame`: #278's discipline — write only what a field owns, never
## the offsets. The splice and header repoint live in `EffectBinWriter.serialize_frames`,
## because that file preloads this one and so this one cannot preload it to reach `relocate`.
##
## THE RE-LAYOUT RE-LAYS OUT; IT DOES NOT RE-AUTHOR. Everything the block does not model is
## carried VERBATIM out of the base — `texture_page`'s unmodelled bits 9..15, each frameset's
## `header_flags`, the three bytes after `group_count`, the offset-table slots past the last
## frameset, and any slot the reader SKIPPED (`frame_count` 0 or > 100; E509 and E510 skip all
## fifteen). That is what makes regeneration byte-exact on a block nobody edited.
##
## GROUP MEMBERSHIP IS NOT AUTHORABLE, SO THE FRAMESET COUNT IS FIXED. `group_sizes` is read
## from the BASE, never the block, and the offset table keeps exactly its slots. Adding a
## FRAME is in scope; adding a FRAMESET is not — #449 q1 scopes it that way.
##
## A SLOT MISSING FROM THE BLOCK IS CARRIED, NEVER DROPPED. The reader can end its walk early
## and hand back a SHORT array; a re-layout that believed it would TRUNCATE the file — the
## shape of the seeded break in #1426. Slots are matched by the block's own `index`, so an
## absent one keeps its base bytes.
##
## The two flag bytes are read-modify-written, so every unauthored bit (byte0 bit 4, byte1's
## `width_signed`/`height_signed`) survives untouched.
##
## `uv.width`/`uv.height` and the vertices are sign-corrected ON READ by the frame's own
## sign-flag bits; masking to a byte is two's-complement either way, so no signed/unsigned
## branch is needed.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

const VERTEX_CORNERS: Array = ["top_left", "top_right", "bottom_left", "bottom_right"]

## A frameset header claiming more frames than this is a slot the READER skips, and this
## carries verbatim rather than re-laying out. Mirrors `EffectReadFrames.MAX_FRAMES_PER_SET`,
## which is where the number is argued.
const MAX_FRAMES_PER_SET: int = 100

## Above this the group table is taken as a mis-walk and the section is refused rather than
## re-laid out. Mirrors `EffectReadFrames.MAX_FRAME_SETS`.
const MAX_FRAME_SETS: int = 500


## Write one frame's editable fields into `buf` at `offset` (24 bytes).
static func serialize_frame(buf: PackedByteArray, offset: int, frame: Dictionary) -> void:
	var byte0: int = buf[offset]
	var palette_id: int = int(frame.get("palette_id", 0)) & 0x0F
	var semi_trans_mode: int = int(frame.get("semi_trans_mode", 0)) & 0x03
	var is_8bpp: int = 1 if frame.get("is_8bpp", false) else 0
	buf[offset] = (byte0 & 0x10) | palette_id | (semi_trans_mode << 5) | (is_8bpp << 7)

	var semi_trans_on: int = 1 if frame.get("semi_trans_on", false) else 0
	buf[offset + 1] = (buf[offset + 1] & ~0x02) | (semi_trans_on << 1)

	# +2/+3 (texture_page, packed u16) intentionally untouched — not v1-editable.

	var uv = frame.get("uv", {})
	if uv is Dictionary:
		buf[offset + 4] = int(uv.get("x", 0)) & 0xFF
		buf[offset + 5] = int(uv.get("y", 0)) & 0xFF
		buf[offset + 6] = int(uv.get("width", 0)) & 0xFF
		buf[offset + 7] = int(uv.get("height", 0)) & 0xFF

	var vertices = frame.get("vertices", {})
	if vertices is Dictionary:
		for i in range(VERTEX_CORNERS.size()):
			var pair = vertices.get(VERTEX_CORNERS[i], [0, 0])
			if not (pair is Array) or pair.size() < 2:
				continue
			buf.encode_u16(offset + 8 + i * 4, int(pair[0]) & 0xFFFF)
			buf.encode_u16(offset + 8 + i * 4 + 2, int(pair[1]) & 0xFFFF)


## The BASE's own frames geometry — everything the re-layout needs that the block does not
## carry. `{}` when the section is degenerate, which is the same "do not touch this" the
## reader signals by returning `[]`.
##
## EVERY OFFSET IN THIS SECTION IS RELATIVE TO `frames_ptr + 4`, NOT TO `frames_ptr`: the
## `+ 4` is the group-count word, and a reader or writer that drops it lands four bytes early
## in every frameset in the file.
##
## `phys_slots` is `sum(group_sizes)` and the PHYSICAL length of the offset table — NOT the
## number of framesets: some effects carry a `0000` terminator slot past their last frameset,
## which is how the reader's walk knows to stop. Regenerating it from the frameset count alone
## would shorten those tables by two bytes and move every frameset in them.
static func geometry(buf: PackedByteArray, frames_ptr: int, section_bytes: int) -> Dictionary:
	if frames_ptr <= 0 or frames_ptr >= buf.size():
		return {}
	var size: int = mini(section_bytes, buf.size() - frames_ptr)
	if size < 8:
		return {}

	var group_count: int = buf[frames_ptr]
	var table_off: int = 4 + group_count * 2
	if group_count <= 0 or table_off >= size:
		return {}
	var first_offset: int = buf.decode_u16(frames_ptr + table_off)
	@warning_ignore("integer_division")
	var phys_slots: int = (first_offset + 4 - table_off) / 2
	if phys_slots <= 0 or phys_slots > MAX_FRAME_SETS:
		return {}

	var group_sizes: Array = []
	for g in range(group_count):
		var start: int = buf.decode_u16(frames_ptr + 4 + g * 2)
		var end: int = first_offset
		if g + 1 < group_count:
			end = buf.decode_u16(frames_ptr + 4 + (g + 1) * 2)
		@warning_ignore("integer_division")
		group_sizes.append((end - start) / 2)

	# The offset table has no count of its own: it ends at the first entry pointing BELOW the
	# first frameset, which is where the payload has already begun.
	var live: int = 0
	for i in range(phys_slots):
		var pos: int = frames_ptr + table_off + i * 2
		if pos + 2 > frames_ptr + size:
			break
		if buf.decode_u16(pos) < first_offset:
			break
		live += 1

	var slot_starts: Array = []
	for i in range(live):
		slot_starts.append(frames_ptr + buf.decode_u16(frames_ptr + table_off + i * 2) + 4)

	return {
		"frames_ptr": frames_ptr,
		"size": size,
		"group_count": group_count,
		"group_sizes": group_sizes,
		"table_off": table_off,
		"first_offset": first_offset,
		"phys_slots": phys_slots,
		"live_slots": live,
		"slot_starts": slot_starts,
	}


## The base bytes of slot `i` — its 4-byte header and its frames. A slot the reader SKIPS
## (`frame_count` 0 or above `MAX_FRAMES_PER_SET`) has no length we can read out of it, so its
## extent is the distance to the NEXT slot, and for the last slot the bare header.
static func slot_payload(buf: PackedByteArray, geo: Dictionary, i: int) -> PackedByteArray:
	var starts: Array = geo["slot_starts"]
	var start: int = int(starts[i])
	if start + Layout.FRAMESET_HEADER_SIZE > buf.size():
		return PackedByteArray()
	var frame_count: int = buf.decode_u16(start + 2)
	if frame_count > 0 and frame_count <= MAX_FRAMES_PER_SET:
		var end: int = mini(start + Layout.FRAMESET_HEADER_SIZE
			+ frame_count * Layout.FRAME_SIZE, buf.size())
		return buf.slice(start, end)
	var skipped_end: int = start + Layout.FRAMESET_HEADER_SIZE
	if i + 1 < int(geo["live_slots"]):
		skipped_end = maxi(skipped_end, int(starts[i + 1]))
	return buf.slice(start, mini(skipped_end, buf.size()))


## The whole frames section, re-laid out from `buf`'s geometry and `block`'s frame counts.
## Returns `{ok: bool, bytes: PackedByteArray, error: String}`.
##
## `block` is the flat frameset array — `EffectReadFrames.parse`'s own output. A frameset is
## matched to its slot by `index` (the offset-table SLOT, not the array position); the
## refusal below enforces it.
##
## THE PAYLOAD IS CONTIGUOUS AND IN SLOT ORDER, which is what makes the offsets derivable at
## all; the re-layout reproduces the original offsets exactly when nothing changed size.
##
## A frame added past the base's own is templated from the frameset's FIRST FRAME (see
## `_rebuild_slot`), then patched with the block's fields.
static func build_section(buf: PackedByteArray, frames_ptr: int, section_bytes: int,
		block) -> Dictionary:
	if not (block is Array):
		return {"ok": false, "bytes": PackedByteArray(),
			"error": "frames: the block must be the parsed frameset array, got %s"
				% type_string(typeof(block))}
	var geo: Dictionary = geometry(buf, frames_ptr, section_bytes)
	if geo.is_empty():
		return {"ok": false, "bytes": PackedByteArray(),
			"error": "frames: the section is degenerate, so there is no layout to rebuild"}

	# A FRAMESET IS MATCHED BY ITS `index`, AND A BLOCK WITHOUT ONE IS REFUSED RATHER THAN
	# MATCHED BY POSITION. `index` is the offset-table SLOT; falling back to the array position
	# would stamp frameset N's frames into frameset N+1's bytes when a slot was skipped, and
	# dropping the unindexed entry would silently lose a real edit — the failure #1413 fixed
	# for the emitters. So it is an error: a caller that did not come from the reader finds out.
	var by_index: Dictionary = {}
	for entry in block:
		if not (entry is Dictionary):
			continue
		if not entry.has("index"):
			return {"ok": false, "bytes": PackedByteArray(),
				"error": ("frames: a frameset in the block carries no 'index', so the slot it "
					+ "belongs to cannot be known — the reader always sets one")}
		by_index[int(entry["index"])] = entry

	# A FRAME COUNT THE READER WOULD SKIP IS A ONE-WAY EDIT, SO IT IS REFUSED HERE: the reader
	# drops a frameset with 0 or above `MAX_FRAMES_PER_SET` frames, so a block asking for
	# either writes a section that no longer parses back — the slot vanishes from the next
	# read and the edit cannot be reversed.
	for entry in block:
		if not (entry is Dictionary):
			continue
		var frames = entry.get("frames", null)
		if not (frames is Array):
			continue
		if frames.size() == 0 or frames.size() > MAX_FRAMES_PER_SET:
			return {"ok": false, "bytes": PackedByteArray(),
				"error": ("frames: frameset %d asks for %d frames, and the reader skips a "
					+ "frameset outside 1..%d — the edit would not read back")
					% [int(entry.get("index", -1)), frames.size(), MAX_FRAMES_PER_SET]}

	var live: int = int(geo["live_slots"])
	var payloads: Array = []
	var original_end: int = frames_ptr
	for i in range(live):
		var base_payload: PackedByteArray = slot_payload(buf, geo, i)
		if base_payload.is_empty():
			return {"ok": false, "bytes": PackedByteArray(),
				"error": "frames: slot %d runs past the end of the file" % i}
		original_end = maxi(original_end, int(geo["slot_starts"][i]) + base_payload.size())
		payloads.append(_rebuild_slot(base_payload, by_index.get(i)))

	var group_count: int = int(geo["group_count"])
	var group_sizes: Array = geo["group_sizes"]
	var phys_slots: int = int(geo["phys_slots"])

	var out: PackedByteArray = PackedByteArray()
	out.append(group_count)
	out.append_array(buf.slice(frames_ptr + 1, frames_ptr + 4))
	var cursor: int = group_count * 2
	for g in range(group_count):
		var pair: PackedByteArray = PackedByteArray()
		pair.resize(2)
		pair.encode_u16(0, cursor)
		out.append_array(pair)
		cursor += int(group_sizes[g]) * 2

	# The payload begins immediately after the PHYSICAL table, terminator slots included, and
	# a stored frameset offset is that position minus the four-byte group-count word.
	var data_start: int = 4 + group_count * 2 + phys_slots * 2
	var offsets: Array = []
	var at: int = data_start
	for payload in payloads:
		offsets.append(at - 4)
		at += (payload as PackedByteArray).size()

	for i in range(phys_slots):
		var slot: PackedByteArray = PackedByteArray()
		slot.resize(2)
		if i < offsets.size():
			slot.encode_u16(0, int(offsets[i]))
		else:
			# A terminator slot: zeros, because the rule (anything below `first_offset` stops
			# the walk) is what makes them correct — carrying the base bytes instead would
			# discriminate nothing.
			slot.encode_u16(0, 0)
		out.append_array(slot)
	for payload in payloads:
		out.append_array(payload)

	# Whatever the original section held past its last frameset.
	if original_end < frames_ptr + int(geo["size"]):
		out.append_array(buf.slice(original_end, frames_ptr + int(geo["size"])))
	return {"ok": true, "bytes": out, "error": ""}


## One slot's bytes: the base payload with `frame_count` and every frame's editable fields
## taken from `edited`, or the base payload untouched when the block has no entry for it.
static func _rebuild_slot(base_payload: PackedByteArray, edited) -> PackedByteArray:
	if not (edited is Dictionary):
		return base_payload
	var frames = edited.get("frames", null)
	if not (frames is Array):
		return base_payload

	var out: PackedByteArray = base_payload.duplicate()
	var want: int = frames.size() * Layout.FRAME_SIZE + Layout.FRAMESET_HEADER_SIZE
	if out.size() < Layout.FRAMESET_HEADER_SIZE:
		return base_payload
	while out.size() < want:
		# Template a new frame from the frameset's FIRST frame. When the base slot carries no
		# frame at all there is nothing to copy, so the new record is zeroed and every field
		# the block does model is written over it below.
		if base_payload.size() >= Layout.FRAMESET_HEADER_SIZE + Layout.FRAME_SIZE:
			out.append_array(base_payload.slice(Layout.FRAMESET_HEADER_SIZE,
				Layout.FRAMESET_HEADER_SIZE + Layout.FRAME_SIZE))
		else:
			var blank: PackedByteArray = PackedByteArray()
			blank.resize(Layout.FRAME_SIZE)
			out.append_array(blank)
	if out.size() > want:
		out = out.slice(0, want)
	out.encode_u16(2, frames.size() & 0xFFFF)
	for k in range(frames.size()):
		if frames[k] is Dictionary:
			serialize_frame(out, Layout.FRAMESET_HEADER_SIZE + k * Layout.FRAME_SIZE, frames[k])
	return out
