class_name SharedOpClearSubslot2
## FFT analog: op_ef_clear_subslot2 @ LAB_80016AF0
##                (opcode 0xEF)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xEF — LAB_80016AF0 at jumptable XREF 0x80028CC8. 0 params.
	## Clears bit 0x1 of chan+0x13E (sub-slot 2 active flag), disarming
	## the mode-2 pan-LFO. FFT disasm:
	##   lhu  v0, 0x13e(a2)
	##   andi v0, v0, 0xfffe       ; clear bit 0x1
	##   sh   v0, 0x13e(a2)
	## On protect_no_music ch1, fires at event 21 (after `80 EF`) — the
	## pause-then-disarm boundary at the end of the dt=96+24+24+... run.
	_ProbeCounters.opcode_ef_clear_subslot2 += 1
	_Trace.emit("opcode_ef_clear_subslot2", {
		"call_index": _ProbeCounters.opcode_ef_clear_subslot2,
		"channel_idx": channel.channel_idx,
	})
	channel.lfo_sub_active[2] = 0
