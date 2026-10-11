extends RefCounted
## `WORLD.BIN`'s game-variable store — [b]Campaign's save data, in the ROM's own
## encoding[/b] (docs/WORLD_MAP_PORT_LIST.md crossing C3).
##
## 684 bytes at `*(0x80153280)`, three regions that tile it exactly
## (WORLD_MAP_SCREEN.md §27, `world_map_captures/travel.py`):
## [codeblock]
##   idx <  128 : a whole u32 at  base + 4*idx                    words   0..127
##   idx <  864 : one BIT     at  base + 512 + 4*((idx-128)>>5)   words 128..150
##                bit idx & 31
##   idx < 1024 : one NIBBLE  at  base + 604 + 4*((idx-864)>>3)   words 151..170
##                shift 4*(idx & 7)
## [/codeblock]
##
## [b]Why the ROM's encoding and not a Dictionary of booleans.[/b] The 182 per-node
## event scripts (§29, decoded and exported already) address these variables BY INDEX,
## and so do the battle side's `event_set_script_variable` and the BC opcodes that read
## gil. A store that spelled the flags as Godot-idiomatic fields would need a
## translation table the moment X1 lands, and the table would be the same layout written
## twice. This is also why the seed carries the words this RE has NOT named: they are
## still Campaign's progression, and dropping them makes the store lossy the first time
## anything else reads one.
##
## Named indices live on [WorldMapProgress], which is the query surface. This class only
## knows the addressing.

const WORDS := 171                       # 684 bytes
const U32_MAX_INDEX := 127
const BIT_MAX_INDEX := 863
const MAX_INDEX := 1023

var _w: PackedInt64Array = _zeroed()


static func _zeroed() -> PackedInt64Array:
	var a := PackedInt64Array()
	a.resize(WORDS)
	return a


## The value of variable [param idx]: a u32, a single bit, or a nibble, by region.
func get_var(idx: int) -> int:
	var slot := _slot(idx)
	if slot.x < 0:
		return 0
	var w: int = _w[slot.x]
	if slot.y < 0:
		return w
	return (w >> slot.y) & (1 if idx <= BIT_MAX_INDEX else 0xF)


func set_var(idx: int, value: int) -> void:
	var slot := _slot(idx)
	if slot.x < 0:
		return
	if slot.y < 0:
		_w[slot.x] = value & 0xFFFFFFFF
		return
	var mask: int = (1 if idx <= BIT_MAX_INDEX else 0xF) << slot.y
	_w[slot.x] = ((_w[slot.x] & ~mask) | ((value << slot.y) & mask)) & 0xFFFFFFFF


## (word index, shift) for [param idx]; shift -1 means "the whole word", x -1 means
## the index is out of range.
func _slot(idx: int) -> Vector2i:
	if idx < 0 or idx > MAX_INDEX:
		push_error("world map: game variable %d is out of range" % idx)
		return Vector2i(-1, -1)
	if idx <= U32_MAX_INDEX:
		return Vector2i(idx, -1)
	if idx <= BIT_MAX_INDEX:
		return Vector2i(128 + ((idx - 128) >> 5), idx & 31)
	return Vector2i(151 + ((idx - 864) >> 3), 4 * (idx & 7))


## Seed from a sparse `[[word_index, value], …]` list — the form
## `tools/wm_progress_dump.py` emits from a savestate.
func load_sparse(pairs: Array) -> void:
	_w = _zeroed()
	for p in pairs:
		_w[int(p[0])] = int(p[1]) & 0xFFFFFFFF


## The non-zero words, in the same sparse form. Round-trips [method load_sparse].
func to_sparse() -> Array:
	var out: Array = []
	for i in WORDS:
		if _w[i] != 0:
			out.append([i, _w[i]])
	return out


## A deep copy. Untyped and `load()`-ed rather than self-named: a kernel member declares
## no `class_name` (ADR-0212 dec. 1), so this file's own name is undeclared INSIDE it, and
## a `preload` of itself is a cycle the parser rejects. `load()` at call time is the
## corpus idiom for a self-reference (ADR-0322 dec. 1 found the same shape in
## `EventInstructionArgs`; `ScreenData.gd:152` is the shipped one).
func duplicate_store():
	var v = load("res://addons/exmateria_schema/campaign_state/WorldMapVariables.gd").new()
	v._w = _w.duplicate()
	return v
