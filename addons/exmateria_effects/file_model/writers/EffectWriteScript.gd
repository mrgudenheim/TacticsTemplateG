extends RefCounted
## Byte-exact EFFECT-SCRIPT writer for `E###.BIN` (#1416) — GDScript port of
## `tools/write_effect_script.py` (#273, ADR-0094), the fifteenth and last of Python's sections.
## Vault: [[Effect File Format]]
##
## The authorable content is the PATTERN, not the instructions: an effect is `3-phase` (an
## outer `process_timeline_frame` loop plus a for-each child) or `1-phase` (the for-each loop
## alone), and the one edit the studio offers is the SWAP. This does not assemble an arbitrary
## op-list: it regenerates the canonical section for a pattern, preserving the effect's own
## prologue (`set_texture_page` + 0-4 `load_callback` + `init_physics_params`) verbatim.
##
## A swap RESIZES, which is why the splice is not here: the patterns' bodies differ in length,
## so every section after the script moves and the header is repointed
## (`EffectBinWriter.relocate`, ADR-0337). `EffectBinWriter` preloads this file, so this file
## cannot preload it back; the splice lives in `EffectBinWriter.serialize_script`, beside
## `serialize_sound_def` (the other resizing section, same reason). This file owns the model —
## canonical bodies, regenerate, gate — the registry owns the one write that moves bytes.
##
## The bodies are FULL SECTIONS, including the for-each child. `EffectReadScript.parse` is
## ROOT-ONLY (stops at the first `end`); a writer re-encoding the parsed root would TRUNCATE
## every effect whose canonical body continues past it. Measured over the corpus: re-encoding
## the parsed root fills the section exactly for 161 effects and is a strict PREFIX for 240
## more — so the canonical bodies are a table, not a re-encode, and `BODY_3PHASE` carries the
## child the reader cannot see.
##
## That table's third copy is guarded: Python has one (`write_effect_script._BODY_*`, shared by
## its own reader and writer); this is the second; `src/effects/studio/EffectScriptPattern.gd`'s
## root-only view is the third. `tools/test_effect_script_opcode_drift.py` pins all three
## against the Python by parsing their sources, pinning the host's as a PREFIX of this one
## (the relation that actually has to hold). The alternative — the host preloading this file
## instead of carrying a view — removes a copy but adds a `src/` -> addon resource reach to
## `check_lattice_scene`'s criterion 4 (ENFORCING register at target 0; currently 56, `src`
## holds exactly 1). A measured table is cheaper than a graded reach.
##
## OPCODE SIZES ARE NOT COPIED: `EffectReadScript.OPCODES` is the one GDScript decoder table and
## is already drift-guarded, so this file reads its strides from there.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")
const ReadScript = preload("res://addons/exmateria_effects/file_model/readers/EffectReadScript.gd")

const P_3PHASE: String = "3-phase"
const P_1PHASE: String = "1-phase"
const P_CUSTOM: String = "Custom"

## The opcodes the prologue and the canonical bodies are built from. Ids only — every SIZE
## comes from `ReadScript.OPCODES`, so there is no second stride table to drift.
const OP_GOTO_YIELD: int = 0
const OP_END: int = 4
const OP_SET_TEXTURE_PAGE: int = 5
const OP_LOAD_CALLBACK: int = 6
const OP_BRANCH_COUNT_EQ: int = 22
const OP_BRANCH_ANIM_DONE: int = 29
const OP_BRANCH_ANIM_DONE_COMPLEX: int = 30
const OP_BRANCH_TARGET_TYPE: int = 31
const OP_UPDATE_ALL_PARTICLES: int = 37
const OP_INIT_PHYSICS_PARAMS: int = 39
const OP_FOR_EACH: int = 40
const OP_PROCESS_TIMELINE_FRAME: int = 41
const OP_CLEAR_TIMELINE_A: int = 42

## Sections are padded up to this multiple, which keeps the section AFTER the script aligned.
const SECTION_ALIGN: int = 4

## The label the 3-phase ROOT ends on. Everything after it in `BODY_3PHASE` is the for-each
## child, which `EffectReadScript` never decodes — see `root_body()`.
const ROOT_END_LABEL: String = "endroot"

## Canonical bodies (everything after the prologue), as `[label, opcode, [args]]` where an arg
## is either a literal int or a label `String` resolved to its absolute-within-section offset.
## Derived from the real E043 (1-phase) and E001 (3-phase root + child) byte layouts, and
## mirroring `write_effect_script._BODY_1PHASE` / `_BODY_3PHASE` entry for entry.
const BODY_1PHASE: Array = [
	["btt", OP_BRANCH_TARGET_TYPE, ["end"]],
	["bad", OP_BRANCH_ANIM_DONE, ["wait"]],
	["fe", OP_FOR_EACH, []],
	["up1", OP_UPDATE_ALL_PARTICLES, []],
	["gy1", OP_GOTO_YIELD, ["bad"]],
	["wait", OP_UPDATE_ALL_PARTICLES, []],
	["bce", OP_BRANCH_COUNT_EQ, [0, "end"]],
	["gy2", OP_GOTO_YIELD, ["wait"]],
	["end", OP_END, []],
]

const BODY_3PHASE: Array = [
	# ROOT — what `EffectReadScript.parse` can see, ending at `endroot`.
	["btt", OP_BRANCH_TARGET_TYPE, ["endroot"]],
	["bad", OP_BRANCH_ANIM_DONE_COMPLEX, ["wait"]],
	["ptf", OP_PROCESS_TIMELINE_FRAME, ["child"]],
	["up1", OP_UPDATE_ALL_PARTICLES, []],
	["gy1", OP_GOTO_YIELD, ["bad"]],
	["wait", OP_UPDATE_ALL_PARTICLES, []],
	["bce", OP_BRANCH_COUNT_EQ, [0, "endroot"]],
	["gy2", OP_GOTO_YIELD, ["wait"]],
	["endroot", OP_END, []],
	# FOR-EACH CHILD — past the root's `end`, structurally the 1-phase loop. Invisible to the
	# reader, which is why re-encoding a parsed root would drop it.
	["child", OP_BRANCH_ANIM_DONE, ["cwait"]],
	["cfe", OP_FOR_EACH, []],
	["cup1", OP_UPDATE_ALL_PARTICLES, []],
	["cgy1", OP_GOTO_YIELD, ["child"]],
	["cwait", OP_UPDATE_ALL_PARTICLES, []],
	["cbce", OP_BRANCH_COUNT_EQ, [0, "cend"]],
	["cgy2", OP_GOTO_YIELD, ["cwait"]],
	["cend", OP_END, []],
]


## The canonical body for `pattern`, or `[]` for a non-canonical one.
static func body(pattern: String) -> Array:
	if pattern == P_1PHASE:
		return BODY_1PHASE
	if pattern == P_3PHASE:
		return BODY_3PHASE
	return []


## The ROOT-ONLY prefix of that body — through `endroot` for 3-phase, the whole thing for
## 1-phase, which has no child. This is what a decoder that stops at the first `end` can see,
## and the shape `src/effects/studio/EffectScriptPattern.gd` regenerates op-dicts from.
static func root_body(pattern: String) -> Array:
	var full: Array = body(pattern)
	if pattern != P_3PHASE:
		return full
	for i in range(full.size()):
		if str((full[i] as Array)[0]) == ROOT_END_LABEL:
			return full.slice(0, i + 1)
	return full


## `3-phase` (opcode 41 outer + opcode 31 `branch_target_type`), `1-phase` (opcode 40 for-each,
## no opcode 41), else `Custom`. Ports `write_effect_script.detect_pattern`, and runs on the
## ROOT — both sides stop at the first `end`, so a decoded root and a byte walk agree.
static func detect(script_ops: Array) -> String:
	var has_outer := false
	var has_for_each := false
	var has_target_type := false
	for op in script_ops:
		if not (op is Dictionary):
			continue
		match int((op as Dictionary).get("opcode", -1)):
			OP_PROCESS_TIMELINE_FRAME:
				has_outer = true
			OP_FOR_EACH:
				has_for_each = true
			OP_BRANCH_TARGET_TYPE:
				has_target_type = true
	if has_outer and has_target_type:
		return P_3PHASE
	if has_for_each and not has_outer:
		return P_1PHASE
	return P_CUSTOM


## `{texture_page, callbacks: [[slot, id], …]}` read from the prologue, or `{}` when it is not
## the canonical shape (`set_texture_page`, 0-4 `load_callback`, optional `clear_timeline_a`,
## `init_physics_params`). Ports `write_effect_script.parse_prologue`, op-side.
static func extract_prologue(script_ops: Array) -> Dictionary:
	if script_ops.size() < 2:
		return {}
	var first: Dictionary = script_ops[0]
	if int(first.get("opcode", -1)) != OP_SET_TEXTURE_PAGE:
		return {}
	var texture_page := int(first.get("flags", 0))
	var i := 1
	var callbacks: Array = []
	while i < script_ops.size() \
			and int((script_ops[i] as Dictionary).get("opcode", -1)) == OP_LOAD_CALLBACK:
		var cb: Dictionary = script_ops[i]
		callbacks.append([int(cb.get("flags", 0)), int(cb.get("arg1", 0))])
		i += 1
	if i < script_ops.size() \
			and int((script_ops[i] as Dictionary).get("opcode", -1)) == OP_CLEAR_TIMELINE_A:
		i += 1
	if i >= script_ops.size() \
			or int((script_ops[i] as Dictionary).get("opcode", -1)) != OP_INIT_PHYSICS_PARAMS:
		return {}
	return {"texture_page": texture_page, "callbacks": callbacks}


## The prologue bytes: `set_texture_page` + `load_callback` × N + (`clear_timeline_a` on 1-phase)
## + `init_physics_params`. Preserved verbatim across a swap — only the body is regenerated.
static func build_prologue(pattern: String, texture_page: int,
		callbacks: Array) -> PackedByteArray:
	var out := PackedByteArray()
	_append_u16(out, _opword(OP_SET_TEXTURE_PAGE, texture_page))
	for cb in callbacks:
		_append_u16(out, _opword(OP_LOAD_CALLBACK, int((cb as Array)[0])))
		_append_u16(out, int((cb as Array)[1]))
	if pattern == P_1PHASE:
		_append_u16(out, _opword(OP_CLEAR_TIMELINE_A))
	_append_u16(out, _opword(OP_INIT_PHYSICS_PARAMS))
	return out


## The WHOLE canonical script section for `pattern` — prologue + body (+ for-each child on
## 3-phase) + alignment pad. Branch arguments are absolute-within-section and therefore shift
## with the callback count, which is why they are resolved here rather than stored.
## Returns an EMPTY array for a non-canonical pattern; callers gate first.
static func regenerate_section(pattern: String, texture_page: int,
		callbacks: Array) -> PackedByteArray:
	var seq: Array = body(pattern)
	if seq.is_empty():
		return PackedByteArray()
	var out: PackedByteArray = build_prologue(pattern, texture_page, callbacks)

	# First pass: every instruction's absolute-within-section offset (the prologue is fixed).
	var labels: Dictionary = {}
	var cursor: int = out.size()
	for entry in seq:
		labels[str((entry as Array)[0])] = cursor
		cursor += _size(int((entry as Array)[1]))

	# Second pass: emit, resolving label arguments to those offsets.
	for entry in seq:
		var opcode: int = int((entry as Array)[1])
		_append_u16(out, _opword(opcode))
		for arg in ((entry as Array)[2] as Array):
			_append_u16(out, int(labels[arg]) if arg is String else int(arg))

	while out.size() % SECTION_ALIGN != 0:
		out.append(0)
	return out


## The script section's current bytes, `[script_data_ptr, effect_data_ptr)`.
static func section_bytes(buf: PackedByteArray, header: Dictionary) -> PackedByteArray:
	var start: int = int(header.get("script_data_ptr", 0))
	var end: int = int(header.get("effect_data_ptr", 0))
	return buf.slice(start, end)


## `{ok: bool, reason: String, pattern: String, texture_page: int, callbacks: Array}` — the
## ADR-0094 dec. 3 gate, byte-side: DATA-format AND the section regenerates ITSELF exactly from
## its own `(pattern, prologue)`. `reason` is empty exactly when `ok`.
##
## 🔴 CODE-FORMAT IS READ OFF THE HEADER BASE, NOT OFF THE FIRST FOUR BYTES, and that is a
## DELIBERATE improvement on the Python this ports. `write_effect_script.is_code_format` tests
## for a leading `addiu sp, sp, -N`, which E259/E338/E464 do not have even though they ARE
## CODE-format — `EffectBinHeader`'s own docstring names those three as the effects the prologue
## scan misses. Python then falls through to reading a header at file offset 0, gets garbage,
## and refuses them as "unreadable script section header". Here the caller has already resolved
## the header through BATTLE.BIN, so `frames_ptr - HEADER_SIZE` names the base exactly and those
## three are refused as what they are. MEASURED: the refused SET is identical to Python's 113
## effects; only the reason census differs, 110/2/1 here against Python's 107/3/2/1.
static func classify_bytes(buf: PackedByteArray, header: Dictionary) -> Dictionary:
	if not header.has("frames_ptr"):
		return _refusal("geometry carries no frames_ptr, so the header base is unknown")
	var base: int = int(header["frames_ptr"]) - Layout.HEADER_SIZE
	if base != 0:
		return _refusal("CODE-format effect (script is MIPS executable, not editable)")

	var start: int = int(header.get("script_data_ptr", 0))
	var end: int = int(header.get("effect_data_ptr", 0))
	if start - base < Layout.HEADER_SIZE or end <= start or end > buf.size():
		return _refusal("unreadable script section header")

	var ops = ReadScript.parse(buf, header)
	if not (ops is Array):
		return _refusal("unreadable script section header")
	var pattern: String = detect(ops)
	if pattern == P_CUSTOM:
		return _refusal("Custom script (not a recognized 1-phase / 3-phase pattern)")
	var pro: Dictionary = extract_prologue(ops)
	if pro.is_empty():
		return _refusal("non-canonical prologue")
	var texture_page: int = int(pro["texture_page"])
	var callbacks: Array = pro["callbacks"]
	if regenerate_section(pattern, texture_page, callbacks) != section_bytes(buf, header):
		return _refusal("non-canonical script body (does not match the canonical %s template)"
			% pattern)
	return {"ok": true, "reason": "", "pattern": pattern, "texture_page": texture_page,
		"callbacks": callbacks}


## The pattern the file's script section CURRENTLY has, or `""` when the section cannot be
## decoded at all. Unlike `classify_bytes` this asks nothing about canonicality — a CODE-format
## effect's MIPS still walks to SOME answer, and the extract's `script.json` walks the same
## bytes the same way, so the two agree. That is what lets a serializer tell "this block asks
## for no change" apart from "this block asks for a change I must refuse".
static func current_pattern(buf: PackedByteArray, header: Dictionary) -> String:
	var ops = ReadScript.parse(buf, header)
	if not (ops is Array):
		return ""
	return detect(ops)


## `classify_bytes(…).ok` — the boolean half, for a caller that only needs the gate.
static func is_swappable(buf: PackedByteArray, header: Dictionary) -> bool:
	return bool(classify_bytes(buf, header)["ok"])


## The target pattern a registry BLOCK asks for. The block is `script.json`'s shape — the parsed
## ROOT op-list — so the pattern is detected from it, exactly as `EffectScriptSaver` does with
## the live ops. A `{"pattern": …}` dictionary is accepted too: that is the minimal shape the
## Python CLI consumes and the one a saver already serializes. Returns `""` for neither.
static func target_pattern(block) -> String:
	if block is Array:
		return detect(block)
	if block is Dictionary and block.has("pattern"):
		return str(block["pattern"])
	return ""



static func _refusal(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "pattern": "", "texture_page": 0, "callbacks": []}


## An instruction word: opcode id in bits 0-8, flags in bits 9-15.
static func _opword(opcode: int, flags: int = 0) -> int:
	return (opcode + (flags << ReadScript.FLAGS_SHIFT)) & 0xFFFF


## The instruction stride, from the ONE guarded GDScript opcode table.
static func _size(opcode: int) -> int:
	return int((ReadScript.OPCODES[opcode] as Array)[1])


static func _append_u16(out: PackedByteArray, value: int) -> void:
	out.append(value & 0xFF)
	out.append((value >> 8) & 0xFF)
