class_name SharedOpVolLfoDepth
## FFT analog: smd_op_e3_vol_lfo_depth @ LAB_80016834
##                (opcode 0xE3)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xE3 — VolumeLFO_Depth at FFT LAB_80016834 (jumptable
	## 0x80028C98). 1 param. Sister of 0xD7 (pitch-LFO depth) and 0xEB
	## (pan-LFO depth). Sets sub-slot 1's vol-LFO depth = 256 / (param+1).
	## FFT MIPS:
	##   lbu  v0, 0x0(a0); addiu v0, v0, 0x01; andi v1, v0, 0xff
	##   beq  v1, zero, end; _addiu a0, a0, 0x01
	##   ori  v0, zero, 0x100; div v0, v1; mflo v0
	##   sh   v0, 0x11a(a2)   ; chan+0x11A = depth
	##   sh   v0, 0x118(a2)   ; chan+0x118 = depth (mirror)
	## param = 0 → depth = 256 (max). param = 0xFF → wraps to 0, skip.
	## Affects 16 effects (Bolt3, Bolt4, Demi, Silence, Shiva, Odin, Silf,
	## Cyclops, HeavenThunder, Asura, SilenceSong, WaveAround,
	## TripleThunder, Destroy, Dispose, TwoHands). See
	## research/effect_sound/working_documents/SMD_OPCODE_COVERAGE_STATUS.md §4.1.
	_ProbeCounters.opcode_e3_vol_lfo_depth += 1
	var raw_e3: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var divisor_e3: int = (raw_e3 + 1) & 0xFF
	_Trace.emit("opcode_e3_vol_lfo_depth", {
		"call_index": _ProbeCounters.opcode_e3_vol_lfo_depth,
		"param": raw_e3,
		"channel_idx": channel.channel_idx,
	})
	if divisor_e3 == 0:
		return
	var depth_e3: int = 0x100 / divisor_e3
	channel.lfo_sub_depth[1] = depth_e3
	# Parity-shadow mirrors of chan+0x118 / chan+0x11A. Fields preexist on
	# slot_state for 0xE2's earlier vol-scale division output; 0xE3 reuses
	# them per FFT's `sh v0, 0x118/0x11a` writes.
	slot.word_118 = depth_e3
	slot.word_11a = depth_e3
