class_name SharedOpChan6Bit2Toggle
## FFT analog: smd_op_d5_chan6_bit2_toggle @ LAB_800163BC
##                (opcode 0xD5)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xD5 — chan+0x6 bit 0x2 toggle at LAB_800163BC (jumptable
	## 0x80028C6C). FFT disasm:
	##   lhu  v0, 0x6(a2)
	##   xori v0, v0, 0x2
	##   sh   v0, 0x6(a2)
	## 0-byte payload. Bit 0x2 of chan+0x6 is read at per_channel_tick
	## PC 0x80015208 (`_andi v0,a3,0x2; bne v0,zero,LAB_80015234`): when
	## set, the porta target-counter decrement/clear path is skipped, so
	## portamento runs indefinitely until 0xDC clears bit 0x1 or a fresh
	## 0xD4 reinitializes. Modeled by toggling channel.chan_6_bit_2 and
	## gating the cadence_body porta-counter decrement on it.
	_ProbeCounters.opcode_d5_chan6_bit2_toggle += 1
	_Trace.emit("opcode_d5_chan6_bit2_toggle", {
		"call_index": _ProbeCounters.opcode_d5_chan6_bit2_toggle,
		"chan_6_bit_2_pre": 1 if channel.chan_6_bit_2 else 0,
	})
	channel.chan_6_bit_2 = not channel.chan_6_bit_2
