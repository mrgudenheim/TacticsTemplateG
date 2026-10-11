extends RefCounted
## FRAMES / FRAMESET reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_frames_section` + `parse_frame`, the read mirror of
## `writers/EffectWriteFrames.gd`.
## Vault: [[Effect File Format]]
##
## WHAT A FRAME IS. 24 bytes describing one textured quad: two flag bytes, a packed texture-page
## word, four UV bytes into the effect's own sheet, and four signed-s16 screen corners. Frames
## are grouped into FRAMESETS (a 4-byte header then N frames) and framesets into GROUPS, so the
## section is three levels of table before the first byte of payload.
##
## 🔴 THE SECTION IS SELF-DESCRIBING AND THAT IS WHY IT NEEDS A NON-WRITER REFEREE. Every frame
## is located by walking a group table, then a per-group u16 offset table, then a frameset
## header — all read out of the same bytes. A reader that mis-walks and a writer that re-derives
## its own offsets from the SAME mis-walk round-trip byte-perfectly, so `BIN -> parse ->
## serialize -> BIN` cannot see it. The oracle that can is `frames.json`: `parse_effect.py`
## walked these tables independently and its answer is committed, so referee A scores the WALK,
## not just the fields. MEASURED, and the shape of B's blindness is sharper than "it cannot see
## mis-walks": eight seeds here red referee A while B stays at exactly 0 byte mismatches,
## because a reader that ends the walk EARLY hands `patch_all` a SHORT array, and a short array
## is a no-op patch. The one seed B did catch (`MAX_FRAMES_PER_SET` 100 -> 4, 45 byte
## mismatches) drops a frameset from the MIDDLE, which shifts every later index and makes the
## writer stamp frameset N's fields into frameset N+1's bytes. So B sees DESYNC, never
## TRUNCATION. The `# seeded-break:` line in `EffectBinReadWriteCorpusTest` carries all fourteen.
##
## SECTION SIZE IS `animation_ptr - frames_ptr`, NOT `EOF - frames_ptr`. The Python is handed
## `calculate_sections()`'s size and its `max_frame_sets` arithmetic and its offset-table walk
## are both bounded by it. `EffectWriteFrames.frame_offsets` uses the looser file-size bound
## instead; that is safe for a v1 in-place patch (a looser bound can only find MORE frames to
## rewrite in place with their own values) but it is not the same question, so this reader
## follows the Python.
##
## ABSENT IS `null`; A DEGENERATE SECTION IS `[]`. `frames_ptr` out of bounds is the only way
## this section is absent — unlike `time_scale` there is no 0 sentinel. But the Python returns
## an EMPTY list for a section that is present and too small to walk (`section_size < 8`, a
## group table that overruns, an implausible `max_frame_sets`), and `frames.json` then holds
## `[]`, so those must read as `[]` here or referee A reds on the difference.
##
## 🔴 THREE CLAIMS HERE ARE UNGUARDED, AND SAYING SO IS THE POINT. Each was seeded, RUN, and
## left the whole test at 55 passed / 0 failed, so do not read the corpus arm as covering them:
##   1. `max_frame_sets` is a LOOSE upper bound. `first_offset + 4` -> `+ 5` changes nothing,
##      because the offset-table walk terminates on the first entry below `first_offset` long
##      before the bound bites. Tightening it to `/ 8` DOES red 10+ effects, so the line is
##      live — it just carries slack no corpus effect reaches.
##   2. `section_size()` vs `EOF - frames_ptr`. Substituting the writer's file-size bound is
##      green across all 400, so the two readings are indistinguishable on this corpus. The
##      Python's reading is followed because referee A's oracle IS the Python.
##   3. `index` is the offset-table SLOT, not the array position, and the two differ only when
##      a frameset is skipped mid-table. Seeding `framesets.size()` is green, which measures
##      that no corpus effect has a surviving frameset after a skipped one. (E509/E510 have
##      all fifteen skipped — see `EffectBinReadWriteCorpusTest.DEPTH_ARM_BLIND`.)
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

## `semi_trans_mode` -> the name `parse_effect.parse_frame` puts in `blend_mode`. A DERIVED
## field: the writer never writes it, so referee B is blind to it and only referee A scores it.
const BLEND_MODES: Array = ["BLEND_50", "ADD", "SUB", "ADD_25"]

## `max_frame_sets` above this is taken as a mis-walk rather than a real table, and the whole
## section reads as `[]` (`parse_frames_section`'s own guard).
const MAX_FRAME_SETS: int = 500

## A frameset header claiming more frames than this is skipped, not trusted
## (`parse_frames_section`'s second guard). Note it CONTINUES rather than breaking, so a bad
## frameset drops out of the array and every later one keeps its own `index`.
const MAX_FRAMES_PER_SET: int = 100


## One 24-byte frame at `offset`, in `frames.json`'s shape.
##
## `uv.width`/`uv.height` are sign-corrected by byte1's own `width_signed`/`height_signed` bits
## — those two bits are reported nowhere in the output, so the sign correction is the ONLY
## trace of them and a reader that skipped it would report 200 where the extract says -56.
static func parse_frame(buf: PackedByteArray, offset: int, frame_index: int) -> Dictionary:
	var flags_byte0: int = buf[offset]
	var flags_byte1: int = buf[offset + 1]
	var texture_page: int = buf.decode_u16(offset + 2)

	var semi_trans_mode: int = (flags_byte0 >> 5) & 0x03
	var width_signed: bool = (flags_byte1 & 0x10) != 0
	var height_signed: bool = (flags_byte1 & 0x20) != 0

	var uv_width: int = buf[offset + 6]
	var uv_height: int = buf[offset + 7]
	if width_signed and uv_width > 127:
		uv_width -= 256
	if height_signed and uv_height > 127:
		uv_height -= 256

	return {
		"index": frame_index,
		"palette_id": flags_byte0 & 0x0F,
		# Bit 4 selects the CLUT LINE (clear = palette 1 at VRAM 0x7B00, set = palette 2 at
		# 0x7B40) — a static per-sprite choice, verified in the sprite renderer at 0x801a5664.
		"uses_palette_2": (flags_byte0 & 0x10) != 0,
		"semi_trans_mode": semi_trans_mode,
		"semi_trans_on": (flags_byte1 & 0x02) != 0,
		"is_8bpp": (flags_byte0 & 0x80) != 0,
		"blend_mode": BLEND_MODES[semi_trans_mode],
		"uv": {
			"x": buf[offset + 4],
			"y": buf[offset + 5],
			"width": uv_width,
			"height": uv_height,
		},
		"vertices": {
			"top_left": [buf.decode_s16(offset + 8), buf.decode_s16(offset + 10)],
			"top_right": [buf.decode_s16(offset + 12), buf.decode_s16(offset + 14)],
			"bottom_left": [buf.decode_s16(offset + 16), buf.decode_s16(offset + 18)],
			"bottom_right": [buf.decode_s16(offset + 20), buf.decode_s16(offset + 22)],
		},
		"texture_page": {
			"x_base": texture_page & 0x0F,
			"y_base": (texture_page >> 4) & 0x01,
			"blend": (texture_page >> 5) & 0x03,
			"color_depth": (texture_page >> 7) & 0x03,
		},
	}


## The frames section's own size, per `EffectBinHeader.calculate_sections` — Frames runs from
## its pointer to `animation_ptr`. Negative or missing reads as 0, which every caller below
## treats as a degenerate section.
static func section_size(header: Dictionary) -> int:
	var start: int = int(header.get("frames_ptr", 0))
	var end: int = int(header.get("animation_ptr", 0))
	return maxi(0, end - start)


## The flat frameset array — `frames.json`'s shape — or `null` when the section is out of
## bounds. This is the registry block: the unit `EffectWriteFrames.patch_into` consumes.
static func parse(buf: PackedByteArray, header: Dictionary):
	var frames_ptr: int = int(header.get("frames_ptr", 0))
	if frames_ptr <= 0 or frames_ptr >= buf.size():
		return null
	return _walk(buf, frames_ptr, section_size(header))["framesets"]


## The per-group frameset COUNTS — `frameset_groups.json`'s shape — or `null` when the section
## is out of bounds.
##
## A DERIVED VIEW, DELIBERATELY NOT REGISTERED. The group table is the structure `parse()`
## walks, and `EffectWriteFrames` refuses to touch it in v1 precisely because rewriting it
## would desync every offset below it. Registering it would make `EffectBinWriter.patch_all`
## refuse the section outright (no serializer), so it is exposed by name and scored by referee
## A the same way `EffectReadTexture.meta()` is.
static func group_sizes(buf: PackedByteArray, header: Dictionary):
	var frames_ptr: int = int(header.get("frames_ptr", 0))
	if frames_ptr <= 0 or frames_ptr >= buf.size():
		return null
	return _walk(buf, frames_ptr, section_size(header))["group_sizes"]


## `{"framesets": Array, "group_sizes": Array}` — one walk, both answers, so the two views can
## never disagree about how many framesets there are.
static func _walk(buf: PackedByteArray, frames_ptr: int, section_bytes: int) -> Dictionary:
	var empty := {"framesets": [], "group_sizes": []}
	# The Python trusts `animation_ptr` and would raise on a header that points past EOF; here
	# an out-of-range `decode_u16` returns 0 silently after printing, which would turn a
	# malformed header into a plausible-looking empty walk. Clamping keeps every read inside
	# the file. Measured no-op on the corpus: all 401 headers have
	# `frames_ptr <= animation_ptr <= file_size`.
	var size: int = mini(section_bytes, buf.size() - frames_ptr)
	if size < 8:
		return empty

	var group_count: int = buf[frames_ptr]
	var group_entries_end: int = 4 + group_count * 2
	if group_entries_end >= size:
		return empty

	var group_entry_offsets: Array = []
	for g in range(group_count):
		group_entry_offsets.append(buf.decode_u16(frames_ptr + 4 + g * 2))

	var first_offset: int = buf.decode_u16(frames_ptr + group_entries_end)
	var frame_sets_data_start: int = first_offset + 4
	@warning_ignore("integer_division")
	var max_frame_sets: int = (frame_sets_data_start - group_entries_end) / 2
	if max_frame_sets <= 0 or max_frame_sets > MAX_FRAME_SETS:
		return empty

	# Each group's offset table runs from its own entry to the NEXT group's entry; the last
	# group's runs to where frameset data begins. Two bytes per entry.
	var group_sizes_out: Array = []
	for g in range(group_count):
		var start: int = int(group_entry_offsets[g])
		var end: int = int(group_entry_offsets[g + 1]) if g + 1 < group_count else first_offset
		@warning_ignore("integer_division")
		var count: int = (end - start) / 2
		group_sizes_out.append(count)

	# The offset table has no count of its own: it ends at the first entry that points BELOW
	# the first frameset, which is where the frameset payload has already begun.
	var num_frame_sets: int = 0
	for i in range(max_frame_sets):
		var offset_pos: int = frames_ptr + group_entries_end + i * 2
		if offset_pos + 2 > frames_ptr + size:
			break
		if buf.decode_u16(offset_pos) < first_offset:
			break
		num_frame_sets += 1

	var framesets: Array = []
	for fs_idx in range(num_frame_sets):
		var raw_offset: int = buf.decode_u16(frames_ptr + group_entries_end + fs_idx * 2)
		var fs_offset: int = frames_ptr + raw_offset + 4
		if fs_offset + Layout.FRAMESET_HEADER_SIZE > buf.size():
			break
		var header_flags: int = buf.decode_u16(fs_offset)
		var frame_count: int = buf.decode_u16(fs_offset + 2)
		if frame_count <= 0 or frame_count > MAX_FRAMES_PER_SET:
			continue
		var frames: Array = []
		for frame_idx in range(frame_count):
			var frame_offset: int = (fs_offset + Layout.FRAMESET_HEADER_SIZE
				+ frame_idx * Layout.FRAME_SIZE)
			if frame_offset + Layout.FRAME_SIZE > buf.size():
				break
			frames.append(parse_frame(buf, frame_offset, frame_idx))
		framesets.append({
			"index": fs_idx,
			"header_flags": header_flags,
			"frames": frames,
		})

	return {"framesets": framesets, "group_sizes": group_sizes_out}
