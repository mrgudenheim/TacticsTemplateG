extends RefCounted
## Byte-exact ANIMATION / SEQUENCE writer for `E###.BIN` (#275) — GDScript port of
## `tools/write_effect_animation.py`.
##
## TWO PATHS, AND THE CALLER PICKS BY WHICH FUNCTION IT CALLS. `patch_into` is #275's v1
## IN-PLACE PARAMETER EDIT — a FRAME's frameset/duration/depth_mode, SET_OFFSET's x/y,
## ADD_OFFSET's dx/dy — and it never touches the sequence count or the offset table, because it
## WALKS that structure to locate each opcode. An opcode whose model TYPE disagrees with the
## base bytes is SKIPPED there, not written: v1 cannot change a type, so a disagreement means a
## stale or foreign block and writing it would corrupt the stream.
##
## `build_section` is the STRUCTURAL path (#449's animation half): it EMITS every opcode from
## the block and re-derives the count word and the whole offset table, so insert, delete,
## reorder and opcode-TYPE change all become expressible and the 40 bytes of `seq_count` +
## `offset_table` + `opcode_type` finally have a writer. The splice and the header repoint live
## in `EffectBinWriter.serialize_animation`, for the same preload reason the frames splice does.
##
## THE OPCODE STREAM IS FULLY MODELLED AND THE BYTES AROUND IT ARE NOT. All four opcodes
## re-emit exactly, so unlike the frames section nothing inside a sequence has to be carried.
## What DOES have to be carried is the RESIDUE — the bytes between where the reader's walk
## stopped and where the next sequence begins. Measured over the corpus that is 49 stray `0x81`
## LOOP bytes, in 29 effects, sitting after a sequence the walk ended on an all-zero FRAME.
## They are unreachable by the engine and invisible to the block, and dropping them re-lays out
## 29 effects wrongly, so they are carried rather than tidied away.
##
## THE SECTION IS 4-BYTE ALIGNED — all 401 of them — and the tail padding is recomputed, not
## carried. It is what absorbs a small edit: adding a 3-byte ADD_OFFSET grows 304 corpus
## effects by 4 bytes and 97 of them by NOTHING AT ALL, because their existing pad had the room.
##
## This is the only serializer needing an explicit section SIZE, because a sequence's extent is
## defined by its neighbours rather than by a record count — the registry passes
## `script_data_ptr - animation_ptr`.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

const LOOP: int = 0x81
const SET_OFFSET: int = 0x82
const ADD_OFFSET: int = 0x83
const FRAME_OPCODE_SIZE: int = 3

## opcode byte -> [type name, size in bytes]
const SIZED_OPCODES: Dictionary = {
	LOOP: ["LOOP", 1],
	SET_OFFSET: ["SET_OFFSET", 5],
	ADD_OFFSET: ["ADD_OFFSET", 3],
}


## The section's 4-byte alignment. Measured: `script_data_ptr - animation_ptr` is a multiple of
## 4 in all 401 corpus effects, and the tail is zero-padded up to it.
const SECTION_ALIGN: int = 4

## `parse_animation_sequence`'s safety limit, mirrored so the residue walk stops where the
## reader's walk stopped and not one byte later.
const MAX_SEQUENCE_BYTES: int = 1000

## A sequence count above this reads as a mis-walk (`EffectReadAnimation.MAX_SEQUENCES`).
const MAX_SEQUENCES: int = 256


## `[absolute_start, bytes_the_reader_consumed]` for every sequence the BASE holds, plus the
## section's own bounds. `{}` when the section is degenerate.
static func geometry(buf: PackedByteArray, animation_ptr: int, section_size: int) -> Dictionary:
	if animation_ptr <= 0 or animation_ptr + 4 > buf.size() or section_size < 4:
		return {}
	var seq_count: int = buf.decode_u32(animation_ptr)
	if seq_count == 0 or seq_count > MAX_SEQUENCES:
		return {}
	var section_end: int = mini(animation_ptr + section_size, buf.size())
	var starts: Array = []
	var lengths: Array = []
	for i in range(seq_count):
		var table_pos: int = animation_ptr + 4 + i * 2
		if table_pos + 2 > section_end:
			break
		# THE OFFSET IS RELATIVE TO THE TABLE, NOT THE SECTION: `animation_ptr + 4 + offset`.
		var start: int = animation_ptr + 4 + buf.decode_u16(table_pos)
		if start >= buf.size():
			break
		starts.append(start)
		lengths.append(walked_length(buf, start, section_end))
	return {
		"animation_ptr": animation_ptr,
		"section_end": section_end,
		"seq_count": starts.size(),
		"starts": starts,
		"lengths": lengths,
	}


## How many bytes `EffectReadAnimation.parse_sequence` consumes from `offset`. The four stops
## are its stops — LOOP, an all-THREE-zero FRAME, an unrecognised byte, and the safety limit —
## because the residue is defined as exactly what that walk did not reach.
static func walked_length(buf: PackedByteArray, offset: int, cap: int) -> int:
	var max_pos: int = mini(offset + MAX_SEQUENCE_BYTES, mini(cap, buf.size()))
	var pos: int = offset
	while pos < max_pos:
		var opcode: int = buf[pos]
		if opcode <= 0x7F:
			if pos + FRAME_OPCODE_SIZE > max_pos:
				break
			var duration: int = buf[pos + 1]
			var depth_mode: int = buf[pos + 2]
			pos += FRAME_OPCODE_SIZE
			if opcode == 0 and duration == 0 and depth_mode == 0:
				break
		elif SIZED_OPCODES.has(opcode):
			var size: int = int(SIZED_OPCODES[opcode][1])
			if pos + size > max_pos:
				break
			pos += size
			if opcode == LOOP:
				break
		else:
			break
	return pos - offset


## One sequence's opcode stream, emitted from the block alone. Every opcode is fully modelled,
## so this needs no base bytes — which is the whole reason a TYPE change is expressible here
## and not in `patch_into`. An unknown `type` is skipped rather than guessed at: emitting a
## wrong-length opcode would desync every sequence after it.
static func emit_sequence(opcodes: Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for op in opcodes:
		if not (op is Dictionary):
			continue
		match str(op.get("type", "")):
			"FRAME":
				out.append(int(op.get("frameset", 0)) & 0x7F)
				out.append(int(op.get("duration", 0)) & 0xFF)
				out.append(int(op.get("depth_mode", 0)) & 0xFF)
			"LOOP":
				out.append(LOOP)
			"SET_OFFSET":
				var xy: PackedByteArray = PackedByteArray()
				xy.resize(4)
				xy.encode_u16(0, int(op.get("x", 0)) & 0xFFFF)
				xy.encode_u16(2, int(op.get("y", 0)) & 0xFFFF)
				out.append(SET_OFFSET)
				out.append_array(xy)
			"ADD_OFFSET":
				out.append(ADD_OFFSET)
				out.append(int(op.get("dx", 0)) & 0xFF)
				out.append(int(op.get("dy", 0)) & 0xFF)
	return out


## The whole animation section, re-laid out from `block` plus the base's residue bytes.
## Returns `{ok: bool, bytes: PackedByteArray, error: String}`.
##
## `block` is the sequence array — `EffectReadAnimation.parse`'s own output. Its LENGTH is the
## count word, so appending a sequence is expressible; a sequence with no base counterpart
## simply carries no residue.
static func build_section(buf: PackedByteArray, animation_ptr: int, section_size: int,
		block) -> Dictionary:
	if not (block is Array):
		return {"ok": false, "bytes": PackedByteArray(),
			"error": "animation: the block must be the parsed sequence array, got %s"
				% type_string(typeof(block))}
	var geo: Dictionary = geometry(buf, animation_ptr, section_size)
	if geo.is_empty():
		return {"ok": false, "bytes": PackedByteArray(),
			"error": "animation: the section is degenerate, so there is no layout to rebuild"}
	if block.size() == 0 or block.size() > MAX_SEQUENCES:
		return {"ok": false, "bytes": PackedByteArray(),
			"error": ("animation: %d sequences is outside the 1..%d a count word can describe"
				% [block.size(), MAX_SEQUENCES])}

	var residues: Array = _residues(buf, geo)
	var bodies: Array = []
	for i in range(block.size()):
		var opcodes = block[i].get("opcodes", []) if block[i] is Dictionary else []
		var body: PackedByteArray = emit_sequence(opcodes if opcodes is Array else [])
		if i < residues.size():
			body.append_array(residues[i])
		# A ZERO-LENGTH SEQUENCE IS REFUSED, because it does not stay zero-length on read.
		# Its stored offset would equal the NEXT sequence's, so the reader walks the neighbour's
		# opcodes and hands them back as this sequence's — an edit that silently duplicates a
		# stream instead of emptying one. Measured: no two corpus sequences share a start in any
		# of the 401 effects, so nothing existing relies on the other reading.
		if body.is_empty():
			return {"ok": false, "bytes": PackedByteArray(),
				"error": ("animation: sequence %d would be zero bytes, and its offset would "
					+ "then address the next sequence's stream rather than its own") % i}
		bodies.append(body)

	var out: PackedByteArray = PackedByteArray()
	out.resize(4)
	out.encode_u32(0, block.size())
	var at: int = 4 + block.size() * 2
	for body in bodies:
		var slot: PackedByteArray = PackedByteArray()
		slot.resize(2)
		slot.encode_u16(0, at - 4)
		out.append_array(slot)
		at += (body as PackedByteArray).size()
	for body in bodies:
		out.append_array(body)
	var pad: int = (SECTION_ALIGN - (out.size() % SECTION_ALIGN)) % SECTION_ALIGN
	if pad > 0:
		var tail: PackedByteArray = PackedByteArray()
		tail.resize(pad)
		out.append_array(tail)
	return {"ok": true, "bytes": out, "error": ""}


## The bytes of each base sequence the reader's walk never reached.
##
## A sequence's PHYSICAL extent runs to wherever the next one begins IN OFFSET ORDER, which is
## not necessarily the next index — though measured over the corpus the table ascends in all
## 401, and no two sequences ever share a start. The LAST sequence runs to the section end with
## its trailing zeros stripped, because those are the 4-byte alignment pad and `build_section`
## recomputes them; a non-zero byte in that tail is residue and survives.
static func _residues(buf: PackedByteArray, geo: Dictionary) -> Array:
	var starts: Array = geo["starts"]
	var lengths: Array = geo["lengths"]
	var n: int = starts.size()
	var out: Array = []
	out.resize(n)
	var order: Array = range(n)
	order.sort_custom(func(a, b): return int(starts[a]) < int(starts[b]))
	for k in range(n):
		var i: int = int(order[k])
		var end: int = int(geo["section_end"])
		if k + 1 < n:
			end = int(starts[int(order[k + 1])])
		var from: int = mini(int(starts[i]) + int(lengths[i]), end)
		var raw: PackedByteArray = buf.slice(from, maxi(from, end))
		if k + 1 >= n:
			while raw.size() > 0 and raw[raw.size() - 1] == 0:
				raw = raw.slice(0, raw.size() - 1)
		out[i] = raw
	return out
