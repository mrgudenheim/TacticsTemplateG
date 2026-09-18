extends RefCounted
## ANIMATION / SEQUENCE reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_animations_section` + `parse_animation_sequence`, the read mirror of
## `writers/EffectWriteAnimation.gd`.
## Vault: [[Effect File Format]]
##
## A u32 sequence count, a u16 offset table, then one VARIABLE-LENGTH opcode stream per
## sequence. Four opcodes: any byte `<= 0x7F` is a 3-byte FRAME (that byte IS the frameset
## index), `0x81` LOOP is 1 byte and ends the sequence, `0x82` SET_OFFSET is 5, `0x83`
## ADD_OFFSET is 3.
##
## 🔴 THE STREAM HAS NO LENGTH — IT HAS FOUR DIFFERENT WAYS TO STOP, and every one of them is a
## claim the reader makes about where a sequence ends:
##   1. LOOP, unconditionally;
##   2. an all-zero FRAME (`opcode == 0 and duration == 0 and depth_mode == 0`) — and ONLY all
##      three together, not `duration == 0` alone, which the Python's own comment misstates as
##      "duration 0 often signals end";
##   3. an unrecognised byte (0x80, or anything above 0x83);
##   4. the `offset + 1000` safety limit.
## Get any of them wrong and the walk runs into the next sequence's bytes or stops short of
## its own. `animations.json` is what says which — see the `# seeded-break:` line in
## `EffectBinReadWriteCorpusTest`.
##
## ⚠️ THE LEAF IS `animations.json`, PLURAL, while the writer's section name is `animation`.
## Three of the thirteen sections disagree with their leaf by name (`particle_timeline` ->
## `timeline.json`, `sound_def` -> `feds.bin` are the others), which is why `SECTION_SOURCES`
## is a map and not a `"%s.json"` format string.
##
## ABSENT IS `null`; A DEGENERATE SECTION IS `[]`. Same split as `frames`: out of bounds reads
## as absent, while a section that is present but reports `section_size < 4`, a zero count or a
## count above 256 reads as the empty list `animations.json` actually holds for it.
##
## 🔴 TWO CLAIMS HERE ARE UNGUARDED, both seeded and RUN against the whole corpus:
##   1. the unrecognised-opcode branch. Making it RESYNCHRONISE (`pos += 1`) instead of ending
##      the sequence is green on all 400, so no corpus sequence contains a byte outside
##      `0x00..0x7F`, `0x81`, `0x82`, `0x83`. That corroborates `EffectWriteAnimation`'s own
##      claim ("the corpus audit found none of these") rather than merely repeating it.
##   2. `MAX_SEQUENCE_BYTES` is a LOOSE bound — 1000 is never reached, though 100 reds 10+
##      effects, so the line is live with slack. Same shape as `EffectReadFrames`'
##      `max_frame_sets`.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const LOOP: int = 0x81
const SET_OFFSET: int = 0x82
const ADD_OFFSET: int = 0x83

const FRAME_OPCODE_SIZE: int = 3
const LOOP_OPCODE_SIZE: int = 1
const SET_OFFSET_OPCODE_SIZE: int = 5
const ADD_OFFSET_OPCODE_SIZE: int = 3

## A sequence count above this is taken as a mis-read and the whole section reads as `[]`
## (`parse_animations_section`'s own guard).
const MAX_SEQUENCES: int = 256

## `parse_animation_sequence`'s safety limit: no sequence is walked more than this many bytes
## past its own start, whatever the stream says.
const MAX_SEQUENCE_BYTES: int = 1000


## The section's own size, per `EffectBinHeader.calculate_sections` — Animation runs from its
## pointer to `script_data_ptr`. This is the one section whose extent cannot be derived from a
## record count, which is why `EffectWriteAnimation` also has to be handed it.
static func section_size(header: Dictionary) -> int:
	return maxi(0, int(header.get("script_data_ptr", 0)) - int(header.get("animation_ptr", 0)))


## The sequence array — `animations.json`'s shape — or `null` when the section is out of
## bounds.
static func parse(buf: PackedByteArray, header: Dictionary):
	var animation_ptr: int = int(header.get("animation_ptr", 0))
	if animation_ptr <= 0 or animation_ptr + 4 > buf.size():
		return null
	var size: int = mini(section_size(header), buf.size() - animation_ptr)
	if size < 4:
		return []

	var seq_count: int = buf.decode_u32(animation_ptr)
	if seq_count == 0 or seq_count > MAX_SEQUENCES:
		return []

	var section_end: int = animation_ptr + size
	var out: Array = []
	for i in range(seq_count):
		var table_pos: int = animation_ptr + 4 + i * 2
		if table_pos + 2 > section_end:
			break
		# 🔴 THE OFFSET IS RELATIVE TO THE TABLE, NOT THE SECTION: `animation_ptr + 4 + offset`.
		# The `+ 4` is the count word, and a reader that drops it lands four bytes early in
		# every sequence in the file.
		var seq_start: int = animation_ptr + 4 + buf.decode_u16(table_pos)
		if seq_start >= buf.size():
			break
		out.append(parse_sequence(buf, seq_start, i))
	return out


## One sequence's opcode stream from `offset`, in `animations.json`'s shape.
static func parse_sequence(buf: PackedByteArray, offset: int, seq_idx: int) -> Dictionary:
	var opcodes: Array = []
	var max_pos: int = mini(offset + MAX_SEQUENCE_BYTES, buf.size())
	var pos: int = offset
	while pos < max_pos:
		var opcode: int = buf[pos]
		if opcode <= 0x7F:
			if pos + FRAME_OPCODE_SIZE > max_pos:
				break
			var duration: int = buf[pos + 1]
			var depth_mode: int = buf[pos + 2]
			opcodes.append({
				"type": "FRAME",
				"frameset": opcode,
				"duration": duration,
				"depth_mode": depth_mode,
			})
			pos += FRAME_OPCODE_SIZE
			# An all-zero FRAME terminates — all THREE bytes, not `duration` alone.
			if duration == 0 and opcode == 0 and depth_mode == 0:
				break
		elif opcode == LOOP:
			opcodes.append({"type": "LOOP"})
			pos += LOOP_OPCODE_SIZE
			break
		elif opcode == SET_OFFSET:
			if pos + SET_OFFSET_OPCODE_SIZE > max_pos:
				break
			opcodes.append({
				"type": "SET_OFFSET",
				"x": buf.decode_s16(pos + 1),
				"y": buf.decode_s16(pos + 3),
			})
			pos += SET_OFFSET_OPCODE_SIZE
		elif opcode == ADD_OFFSET:
			if pos + ADD_OFFSET_OPCODE_SIZE > max_pos:
				break
			# s8 deltas, sign-extended by hand — the bytes are stored unsigned.
			var dx: int = buf[pos + 1]
			var dy: int = buf[pos + 2]
			opcodes.append({
				"type": "ADD_OFFSET",
				"dx": dx - 256 if dx > 127 else dx,
				"dy": dy - 256 if dy > 127 else dy,
			})
			pos += ADD_OFFSET_OPCODE_SIZE
		else:
			# Unrecognised (0x80, or above 0x83): the sequence ends here rather than
			# resynchronising, because there is no way to know this byte's length.
			break
	return {"index": seq_idx, "opcodes": opcodes}
