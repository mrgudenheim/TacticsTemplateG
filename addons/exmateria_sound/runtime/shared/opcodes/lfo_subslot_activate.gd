class_name SharedOpLfoSubslotActivate
## FFT analog: smd_op_f6_lfo_subslot_activate @ FUN_80016D64
##                (opcode 0xF6)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")
const _PitchLfoPeriodReset = preload("res://addons/exmateria_sound/runtime/shared/per_tick/pitch_lfo_period_reset.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xF6 — FUN_80016D64 at jumptable 0x80028CE4 = base
	## 0x80028B0C + (0xF6-0x80)*4. 1 param. Activates the LFO sub-slot
	## specified by param[0]. Completes the F0/F1/F6 dynamic-subslot
	## sequence: F0 selects + arms waveform, F1 sets depth+rate,
	## F6 ACTIVATES.
	##
	## FFT disasm (FUN_80016D64):
	##   subslot = chan + 0xe0 + param[0] * 0x20
	##   pitch_lfo_period_reset(subslot)
	##   subslot[0x1e] |= 1          ; set "active" bit
	##
	## pitch_lfo_period_reset (FUN_80016DC0):
	##   subslot[0x10] = 1
	##   subslot[0x04] = 0
	##   subslot[0x1e] &= 0xFFF3      ; clear bits 0x4 + 0x8
	##   subslot[0x14] = subslot[0x16]   ; outer-delay reload
	##   subslot[0x18] = subslot[0x1a]   ; depth reload (=0x100 from F0)
	_ProbeCounters.opcode_f6_lfo_subslot_activate += 1
	_Trace.emit("opcode_f6_lfo_subslot_activate", {
		"call_index": _ProbeCounters.opcode_f6_lfo_subslot_activate,
		"arg0_subslot_idx": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	if op.params.size() < 1:
		return
	var subslot_idx: int = op.params[0] & 0xFF
	if subslot_idx >= 4:
		return
	# Iter-37 Bug D: full period_reset (5 fields). Was only writing 3
	# (countdown, accumulator, dir_flags); missing delay_counter =
	# delay_reload and depth = depth_reload (= our depth_delta).
	_PitchLfoPeriodReset.apply(channel, subslot_idx)
	# Then set bit 0x1 (active).
	channel.lfo_sub_active[subslot_idx] = 1
