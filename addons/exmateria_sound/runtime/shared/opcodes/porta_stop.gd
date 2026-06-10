class_name SharedOpPortaStop
## FFT analog: smd_op_dc_porta_stop @ LAB_800163D4
##                (opcode 0xDC)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xDC — clear bit 0x1 of chan+0x6 at LAB_800163D4 (jumptable
	## 0x80028C70). FFT disasm:
	##   lhu  v0, 0x6(a2)
	##   andi v0, v0, 0xfffe
	##   sh   v0, 0x6(a2)
	## 0-byte payload. Mirror of 0xDB but on chan+0x6 instead of chan+0xFE.
	## Bit 0x1 of chan+0x6 = portamento_active gate. Clearing it stops the
	## porta-driven pre_pitch_acc advance in per_channel_tick at PC
	## 0x80015200 (`andi v0,a3,0x1; beq v0,zero,LAB_80015248`).
	_ProbeCounters.opcode_dc_porta_stop += 1
	_Trace.emit("opcode_dc_porta_stop", {
		"call_index": _ProbeCounters.opcode_dc_porta_stop,
		"porta_active_pre": 1 if channel.portamento_active else 0,
	})
	channel.portamento_active = false
