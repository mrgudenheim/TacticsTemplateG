class_name SharedOpPanLfoDepth
## FFT analog: smd_op_eb_pan_lfo_depth @ LAB_8001693C
##                (opcode 0xEB)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xEB — PanLFO_Depth at FFT LAB_8001693C (jumptable
	## 0x80028CB8). 1 param. Identical formula to 0xE3 / 0xD7 but targets
	## sub-slot 2 (pan-LFO) at chan+0x138 / 0x13A.
	##   depth = 256 / (param + 1); skip if param == 0xFF (wraps).
	## Affects 3 effects (Cyclops, Ultima, Sleep2). See
	## SMD_OPCODE_COVERAGE_STATUS.md §4.5.
	_ProbeCounters.opcode_eb_pan_lfo_depth += 1
	var raw_eb: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var divisor_eb: int = (raw_eb + 1) & 0xFF
	_Trace.emit("opcode_eb_pan_lfo_depth", {
		"call_index": _ProbeCounters.opcode_eb_pan_lfo_depth,
		"param": raw_eb,
		"channel_idx": channel.channel_idx,
	})
	if divisor_eb == 0:
		return
	var depth_eb: int = 0x100 / divisor_eb
	channel.lfo_sub_depth[2] = depth_eb
