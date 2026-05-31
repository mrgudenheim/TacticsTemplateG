class_name SharedOpPitchLfoDepth
## FFT analog: smd_op_d7_pitch_lfo_depth @ 0x800165AC
##                (opcode 0xD7)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xD7 — PitchLFO_Depth at FFT smd_op_d7_pitch_lfo_depth
	## (jumptable 0x80028C68). 1 param. Identical formula to 0xE3 but
	## targets sub-slot 0 (pitch-LFO) at chan+0xF8 / 0xFA.
	##   depth = 256 / (param + 1); skip if param == 0xFF (wraps).
	## Affects 9 effects (Carbunkle, Odin, Cyclops, Masamune, Ultima,
	## Shock!, Blind, DarkWhisper, GrandCross). See
	## SMD_OPCODE_COVERAGE_STATUS.md §4.3.
	_ProbeCounters.opcode_d7_pitch_lfo_depth += 1
	var raw_d7: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var divisor_d7: int = (raw_d7 + 1) & 0xFF
	_Trace.emit("opcode_d7_pitch_lfo_depth", {
		"call_index": _ProbeCounters.opcode_d7_pitch_lfo_depth,
		"param": raw_d7,
		"channel_idx": channel.channel_idx,
	})
	if divisor_d7 == 0:
		return
	var depth_d7: int = 0x100 / divisor_d7
	# Iter-37 Bug A: FFT PC 0x800165D4 stores chan+0xFA (depth_reload /
	# our depth_delta) before PC 0x800165D8 stores chan+0xF8 (depth).
	# See MUSIC_ITER36_PITCH_LFO_DEPTH_EXPOSED_BUGS.md §1.
	channel.lfo_sub_depth_delta[0] = depth_d7
	channel.lfo_sub_depth[0] = depth_d7
