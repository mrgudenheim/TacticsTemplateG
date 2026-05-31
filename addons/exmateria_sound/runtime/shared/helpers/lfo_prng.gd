class_name SharedLfoPrng
## Global LFO PRNG state extracted from dispatcher.gd (refactor Pass 2).
##
## FFT analog: FUN_800178F4 — three-step xorshift on DAT_80032a18, the
## global LFSR consumed by noise pitch-LFO callbacks at wf_idx=6
## (FUN_8001780C) and wf_idx=7 (FUN_80017878).
##
## render_effect_sound.gd seeds `_state` at session start from the PCSX
## savestate so PCSX and Godot draw the same sequence; without seeding
## it stays at 0 and the callbacks degrade to a deterministic but
## desynced sequence.
##
## The `_diag_step_count` counter is owned here (next to the function
## that bumps it) rather than in probes/probe_counters.gd, avoiding a
## back-reference from a leaf module to the counters module.

const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")


# Engine PRNG state — port of FFT DAT_80032a18.
static var _state: int = 0

# diag_lfo_prng_step probe call_index counter — bumped inside step().
static var _diag_step_count: int = 0


static func set_state(state: int) -> void:
	var v: int = state & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	_state = v


static func step() -> int:
	## FUN_800178F4 — three-step xorshift on DAT_80032a18, returns
	## (state & 0x7FFF) post-update. MIPS `sra` (arithmetic right shift)
	## maps to GDScript `>>` on s64 since GDScript ints are signed.
	var pre_state: int = _state
	var v: int = _state
	var v1: int = (v << 17) & 0xFFFFFFFF
	if v1 >= 0x80000000:
		v1 -= 0x100000000
	v = (v ^ v1) & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	v1 = v >> 15
	v = (v ^ v1) & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	_state = v
	_diag_step_count += 1
	_Trace.emit("diag_lfo_prng_step", {
		"call_index": _diag_step_count,
		"pre_state": pre_state & 0xFFFFFFFF,
		"post_state": v & 0xFFFFFFFF,
	})
	return v & 0x7FFF
