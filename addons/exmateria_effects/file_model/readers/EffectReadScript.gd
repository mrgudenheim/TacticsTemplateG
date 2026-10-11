extends RefCounted
## EFFECT-SCRIPT reader for `E###.BIN` — GDScript port of `parse_effect.parse_script`.
## Vault: [[Effect File Format]]
##
## The bytecode at `script_data_ptr` that drives the whole effect: a stream of 2/4/6/8-byte
## instructions whose first halfword packs a 9-bit opcode id in bits 0-8 and 7 flag bits in
## 9-15. Arguments are s16 and their COUNT comes from the opcode's size, not from the stream —
## there is no per-instruction length byte.
##
## 🔴 ROOT-ONLY, AND THAT IS THE EXTRACT'S SHAPE, NOT A LIMITATION OF THIS PORT. The walk stops
## at the first `end` (opcode 4), so the for-each child bodies that live past it are not in
## `script.json` at all — `EffectScriptPattern` says so in as many words ("script.json is
## root-only ... the for-each child bytes are not on the Godot side"). A reader that walked to
## the section end would decode MORE than the oracle and red on every effect that has a child
## body. Mirroring the stop is the correct behaviour, and it means this reader does not cover
## every byte between `script_data_ptr` and `effect_data_ptr`.
##
## 🔴 A NAMED VIEW ON THE READ SIDE, AND A REGISTERED SECTION ON THE WRITE SIDE.
## `EffectWriteScript.gd` + `EffectBinWriter.serialize_script` write this section byte-exactly
## in GDScript since #1416 — the 3-phase <-> 1-phase swap, preserving the real prologue and
## regenerating the canonical body, mirroring `tools/write_effect_script.py` (#273, ADR-0094).
## Measured over the corpus, the GDScript swap output is byte-identical to the Python's on all
## 288 swappable effects.
##
## What this READER is not is the writer's input. The writer takes the target PATTERN off the
## block and regenerates from a canonical table, because this walk is root-only and the
## canonical 3-phase body continues past the root. Reading it was still the half that had to
## come first — the gate parses the prologue the swap preserves. `script` stays out of
## `EffectBinReader`'s registry for that reason: `parse_all`'s job is to hand `patch_all` a
## block, and this view is the studio's oracle rather than the writer's source of truth.
##
## ⚠️ THE OPCODE TABLE IS A SECOND COPY AND IT IS GUARDED. Python has exactly ONE table:
## `write_effect_script.py` imports `OPCODES` from `parse_effect`, so its reader and writer
## cannot disagree. This file is a THIRD language's copy, and an unguarded copy is the failure
## mode ADR-0085's amendment named for feds (a param-count drift desyncs a decode mid-stream
## and every later instruction is garbage). So `tools/test_effect_script_opcode_drift.py` pins
## this table against `parse_effect.OPCODES` by parsing THIS file's source — edit the Python
## first, then here.
##
## ⚠️ NOT `src/effects/studio/EffectScriptPattern.gd`'s `_META`. That is a deliberate
## THIRTEEN-entry subset for regenerating canonical roots, not a decoder, and it lives in the
## host rather than the addon. It is not a rival table — but it does supply the STRIDES the
## studio's root offsets are computed from, so since #1416 the drift guard pins it too, as a
## subset of this table. `EffectWriteScript.gd` adds no third stride table at all: it reads
## `OPCODES` from here.
##
## ABSENT IS `null`; a zero-length section reads as `[]`.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

## opcode id -> [name, total instruction size in bytes]. Mirrors `parse_effect.OPCODES`; see
## the drift guard named above.
const OPCODES: Dictionary = {
	0: ["goto_yield", 4], 1: ["goto", 4], 2: ["spawn_child_effect", 4],
	3: ["terminate_child", 2], 4: ["end", 2], 5: ["set_texture_page", 2],
	6: ["load_callback", 4], 7: ["invoke_callback", 4], 8: ["load_position", 8],
	9: ["store_pos_to_origin", 2], 10: ["load_pos_from_origin", 2], 11: ["set_rotation", 8],
	12: ["apply_camera_rotation", 2], 13: ["load_camera_rotation", 2], 14: ["set_sprite_scale", 8],
	15: ["apply_sprite_scale", 2], 16: ["set_script_reg", 4], 17: ["branch_reg_eq", 6],
	18: ["branch_reg_ge", 6], 19: ["branch_reg_gt", 6], 20: ["branch_reg_le", 6],
	21: ["branch_reg_lt", 6], 22: ["branch_count_eq", 6], 23: ["branch_count_gt", 6],
	24: ["branch_count_lt", 6], 25: ["branch_child_count_eq", 6], 26: ["branch_child_active", 4],
	27: ["branch_child_inactive", 4], 28: ["branch_reg_ne", 6], 29: ["branch_anim_done", 4],
	30: ["branch_anim_done_complex", 4], 31: ["branch_target_type", 4], 32: ["inc_script_reg", 2],
	33: ["dec_script_reg", 2], 34: ["add_script_reg", 4], 35: ["sub_script_reg", 4],
	36: ["reset_sprite_scale", 2], 37: ["update_all_particles", 2], 38: ["spawn_emitter", 2],
	39: ["init_physics_params", 2], 40: ["for_each", 2], 41: ["process_timeline_frame", 4],
	42: ["clear_timeline_a", 2], 43: ["clear_timeline_b", 2], 44: ["nop_44", 2],
	45: ["nop_45", 2],
}

## Bits 0-8 of the first halfword are the opcode id; bits 9-15 are flags.
const OPCODE_MASK: int = 0x1FF
const FLAGS_SHIFT: int = 9
const FLAGS_MASK: int = 0x7F

## An unrecognised opcode is assumed 2 bytes and walked past, NOT treated as the end — the
## Python does the same, and stopping would silently truncate a script over one unknown word.
const UNKNOWN_SIZE: int = 2

## Opcode 4 (`end`) terminates the root walk. See the root-only note in the header.
const OP_END: int = 4


## The script's own size, per `EffectBinHeader.calculate_sections` — Script runs from its
## pointer to `effect_data_ptr`.
static func section_size(header: Dictionary) -> int:
	return maxi(0, int(header.get("effect_data_ptr", 0)) - int(header.get("script_data_ptr", 0)))


## The root instruction list — `script.json`'s shape — or `null` when out of bounds.
static func parse(buf: PackedByteArray, header: Dictionary):
	var script_ptr: int = int(header.get("script_data_ptr", 0))
	if script_ptr <= 0 or script_ptr >= buf.size():
		return null
	var end_pos: int = script_ptr + section_size(header)
	var out: Array = []
	var pos: int = script_ptr
	while pos < end_pos:
		if pos + 2 > buf.size():
			break
		var word: int = buf.decode_u16(pos)
		var opcode_id: int = word & OPCODE_MASK
		var name: String = "unknown_%d" % opcode_id
		var size: int = UNKNOWN_SIZE
		if OPCODES.has(opcode_id):
			name = str(OPCODES[opcode_id][0])
			size = int(OPCODES[opcode_id][1])
		var instr: Dictionary = {
			# RELATIVE to the section, not the file — the branch opcodes' targets are
			# section-relative too, so an absolute offset here would not compare to them.
			"offset": pos - script_ptr,
			"opcode": opcode_id,
			"name": name,
			"flags": (word >> FLAGS_SHIFT) & FLAGS_MASK,
			"size": size,
		}
		# Arguments are keyed by ARITY, and a truncated tail simply omits the key rather than
		# reading past EOF — `parse_script` guards each one separately and so does this.
		if size >= 4 and pos + 4 <= buf.size():
			instr["arg1"] = buf.decode_s16(pos + 2)
		if size >= 6 and pos + 6 <= buf.size():
			instr["arg2"] = buf.decode_s16(pos + 4)
		if size >= 8 and pos + 8 <= buf.size():
			instr["arg3"] = buf.decode_s16(pos + 6)
		out.append(instr)
		pos += size
		if opcode_id == OP_END:
			break
	return out
