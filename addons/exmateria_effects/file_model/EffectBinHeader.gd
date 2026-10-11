extends RefCounted
## The 40-byte `E###.BIN` file header, read in GDScript (#1316).
## Vault: [[Effect File Format]], [[Embedded MIPS Effect Code]]
##
## WHY THIS IS HERE AT ALL. Until now this package parsed NO binary: `EffectData.gd`'s own
## docstring reads *"loads pre-converted JSON from parser"*, and the parser is
## `godot-learning/tools/parse_effect.py` — 2,556 lines of host Python, run offline, whose
## output `assets/effects/E###/*.json` is the de-facto interface between the ROM and 110 files
## downstream. Python owned both directions of the format and GDScript owned neither. This is
## the first slice of the read direction coming back: the 40 bytes that ARE the format
## boundary, so the addon that models an effect can also say where one begins.
##
## 🔴 THE HEADER IS NOT ALWAYS AT 0, AND THAT IS 109 OF THE 400 SHIPPED EFFECTS. A CODE-format
## effect prepends MIPS to the file and the 40-byte header sits after it — measured over the
## corpus, the leading gap runs 856…22,164 bytes (median 7,672), while every one of the 291
## DATA-format effects has a gap of exactly `HEADER_SIZE`. So the split is bimodal and the
## question "where does the header start" is a real lookup, not a constant. (110 of 401 counting
## `E000`, the junk/placeholder dir every scanner skips — #301 carries the census.) Two answers,
## in this order:
##
##   1. `vfx_header_offset()` — BATTLE.BIN's per-effect table, which is what the GAME uses.
##      Authoritative, and right for every effect regardless of layout.
##   2. `find_header_offset()` — scan for the MIPS prologue, then for the first plausible
##      header. The fallback for a caller with no BATTLE.BIN, and it MISSES effects whose file
##      does not START with the prologue. `parse_effect.py` names `E259` as *"e.g."*;
##      `EffectBinHeaderCorpusTest`, seeded to scan only, measures the real set — **E259, E338,
##      E464**. All three then read as DATA-format and produce garbage pointers rather than an
##      error, which is the failure mode this whole ordering exists to avoid.
##
## `header_offset()` composes them in that order. A caller with BATTLE.BIN should pass it.
##
## POINTERS ARE RELATIVE TO THE HEADER, NOT TO THE FILE. `parse_header()` adds `base_offset`
## to each, so what it returns is absolute file offsets and a CODE-format effect's numbers are
## directly comparable to a DATA-format one's. `time_scale_ptr` is the exception in the other
## direction: 0 means ABSENT, so it stays 0 rather than becoming `base_offset`.
##
## TRANSCRIBED, NOT ADAPTED. Every function here mirrors one in `tools/parse_effect.py`
## (`find_header_offset`, `load_vfx_header_offset`, `parse_header`, `calculate_sections`)
## including the scan's exact bounds and its skip of `time_scale_ptr` in the ascending check.
## The Python is a byte-exact reference implementation over a 401-effect corpus, so the port
## has a free referee — `EffectBinHeaderCorpusTest` runs it over all of them.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

## The header itself: ten `u32` section pointers at `0x00`–`0x24`.
const HEADER_SIZE: int = 0x28

## BATTLE.BIN's per-effect header-offset table: one `u32` per effect, holding the PSX RAM
## address of that effect's header. `VFX_LOAD_BASE` is where the file is loaded, so
## `entry - VFX_LOAD_BASE` is the file-relative offset.
const VFX_HEADER_TABLE_OFFSET: int = 0x14D8D0
const VFX_LOAD_BASE: int = 0x801C2500
const NUM_VFX: int = 511

## The MIPS function prologue a CODE-format effect opens with: `addiu sp, sp, -N`.
const MIPS_PROLOGUE_MASK: int = 0xFFFF0000
const MIPS_PROLOGUE: int = 0x27BD0000

## `vfx_header_offset()` when the table cannot answer for this id. Not 0 — 0 is the ANSWER
## for every DATA-format effect, and a caller that cannot tell "at the start" from "no idea"
## silently parses the MIPS of a CODE-format file as a header.
const NO_OFFSET: int = -1


## The numeric id in `E###`/`E###.BIN`, or -1 when the name is not one.
static func vfx_id_from_filename(name: String) -> int:
	var stem: String = name.get_file().get_basename()
	if stem.is_empty() or stem.substr(0, 1).to_upper() != "E":
		return -1
	var digits: String = stem.substr(1)
	if digits.is_empty() or not digits.is_valid_int():
		return -1
	return int(digits)


## This effect's header offset per BATTLE.BIN's table, or `NO_OFFSET` when the table cannot
## answer — id out of range, blob too short, or an entry below the load base.
static func vfx_header_offset(battle_bin: PackedByteArray, vfx_id: int) -> int:
	if vfx_id < 0 or vfx_id >= NUM_VFX:
		return NO_OFFSET
	var entry: int = VFX_HEADER_TABLE_OFFSET + vfx_id * 4
	if entry + 4 > battle_bin.size():
		return NO_OFFSET
	var offset: int = battle_bin.decode_u32(entry) - VFX_LOAD_BASE
	if offset < 0:
		return NO_OFFSET
	return offset


## Where the header starts, by scanning — 0 for DATA format, > 0 for CODE format.
##
## A file whose first word is not the MIPS prologue is DATA format and answers 0 immediately.
## Otherwise walk forward looking for a `frames_ptr` of exactly `HEADER_SIZE` whose ten
## pointers all land inside the file and ascend. `time_scale_ptr` is skipped in the ascending
## check because 0 is its legal "absent" value and would break the ordering.
##
## Returns 0 when a CODE-format file yields no plausible header — the same answer the Python
## gives, with the same consequence: the caller parses from 0 and gets nonsense. Prefer
## `vfx_header_offset()`, which cannot fail this way.
static func find_header_offset(data: PackedByteArray) -> int:
	if data.size() < 40:
		return 0
	if (data.decode_u32(0) & MIPS_PROLOGUE_MASK) != MIPS_PROLOGUE:
		return 0

	var file_size: int = data.size()
	var offset: int = 4
	while offset < file_size - 40:
		if data.decode_u32(offset) == HEADER_SIZE:
			var ptrs: Array[int] = []
			var valid := true
			for i in range(10):
				var ptr: int = data.decode_u32(offset + i * 4)
				if offset + ptr > file_size:
					valid = false
					break
				ptrs.append(ptr)
			if valid:
				# Sections are sequential, so the pointers are non-decreasing — minus
				# `time_scale_ptr` at index 5, whose 0 means absent.
				var check: Array[int] = ptrs.slice(0, 5) + ptrs.slice(6)
				var ascending := true
				for i in range(check.size() - 1):
					if check[i] > check[i + 1]:
						ascending = false
						break
				if ascending:
					return offset
		offset += 4
	return 0


## The header offset to parse from: BATTLE.BIN's table when it can answer, the scan otherwise.
## Pass an empty `battle_bin` to force the scan.
static func header_offset(data: PackedByteArray, battle_bin: PackedByteArray, vfx_id: int) -> int:
	if not battle_bin.is_empty():
		var from_table: int = vfx_header_offset(battle_bin, vfx_id)
		if from_table != NO_OFFSET:
			return from_table
	return find_header_offset(data)


## The ten section pointers plus `file_size`, as ABSOLUTE file offsets.
##
## `base_offset` is where the header sits (`header_offset()`'s answer). Every pointer is
## relative to that, so it is added back in — except `time_scale_ptr`, where 0 means the
## section is absent and must stay 0 rather than becoming `base_offset`.
static func parse_header(data: PackedByteArray, base_offset: int = 0) -> Dictionary:
	var time_scale_raw: int = data.decode_u32(base_offset + 0x14)
	return {
		"frames_ptr": base_offset + data.decode_u32(base_offset + 0x00),
		"animation_ptr": base_offset + data.decode_u32(base_offset + 0x04),
		"script_data_ptr": base_offset + data.decode_u32(base_offset + 0x08),
		"effect_data_ptr": base_offset + data.decode_u32(base_offset + 0x0C),
		"anim_table_ptr": base_offset + data.decode_u32(base_offset + 0x10),
		"time_scale_ptr": (base_offset + time_scale_raw) if time_scale_raw != 0 else 0,
		"effect_flags_ptr": base_offset + data.decode_u32(base_offset + 0x18),
		"timeline_section_ptr": base_offset + data.decode_u32(base_offset + 0x1C),
		"sound_def_ptr": base_offset + data.decode_u32(base_offset + 0x20),
		"texture_ptr": base_offset + data.decode_u32(base_offset + 0x24),
		"file_size": data.size(),
	}


## Section boundaries derived from the header: each section runs from its own pointer to the
## next one, and `Texture` runs to the end of the file. There are ten sections when
## `time_scale_ptr` is set and nine when it is not — `AnimCurves` absorbs the span either way.
static func calculate_sections(header: Dictionary) -> Array:
	var sections: Array = []
	sections.append({"name": "Frames", "offset": header["frames_ptr"],
		"size": header["animation_ptr"] - header["frames_ptr"]})
	sections.append({"name": "Animation", "offset": header["animation_ptr"],
		"size": header["script_data_ptr"] - header["animation_ptr"]})
	sections.append({"name": "Script", "offset": header["script_data_ptr"],
		"size": header["effect_data_ptr"] - header["script_data_ptr"]})
	sections.append({"name": "ParticleSystem", "offset": header["effect_data_ptr"],
		"size": header["anim_table_ptr"] - header["effect_data_ptr"]})

	if header["time_scale_ptr"] != 0:
		sections.append({"name": "AnimCurves", "offset": header["anim_table_ptr"],
			"size": header["time_scale_ptr"] - header["anim_table_ptr"]})
		sections.append({"name": "TimeScales", "offset": header["time_scale_ptr"],
			"size": header["effect_flags_ptr"] - header["time_scale_ptr"]})
	else:
		sections.append({"name": "AnimCurves", "offset": header["anim_table_ptr"],
			"size": header["effect_flags_ptr"] - header["anim_table_ptr"]})

	sections.append({"name": "EffectFlags", "offset": header["effect_flags_ptr"],
		"size": header["timeline_section_ptr"] - header["effect_flags_ptr"]})
	sections.append({"name": "Timeline", "offset": header["timeline_section_ptr"],
		"size": header["sound_def_ptr"] - header["timeline_section_ptr"]})
	sections.append({"name": "SoundDef", "offset": header["sound_def_ptr"],
		"size": header["texture_ptr"] - header["sound_def_ptr"]})
	sections.append({"name": "Texture", "offset": header["texture_ptr"],
		"size": header["file_size"] - header["texture_ptr"]})
	return sections


## `header.json`'s document shape, so a caller can produce the file `parse_effect.py` writes.
## `header_offset` / `is_code_format` are present only for CODE-format effects, matching
## `save_effect()` — a DATA-format document carries neither key.
static func header_document(filename: String, data: PackedByteArray, base_offset: int) -> Dictionary:
	var header: Dictionary = parse_header(data, base_offset)
	var doc: Dictionary = {
		"filename": filename,
		"header": header,
		"sections": calculate_sections(header),
	}
	if base_offset > 0:
		doc["is_code_format"] = true
		doc["header_offset"] = base_offset
	return doc
