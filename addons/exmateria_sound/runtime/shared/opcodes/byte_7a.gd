class_name SharedOpByte7a
## FFT analog: smd_op_a9_byte_7a @ LAB_80015DD0
##                (opcode 0xA9)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## opcode 0xA9 — sets slot+0x7A (formula case selector).
	## Per FFT LAB_80015dd0 (jumptable @0x80028BB0):
	##   `lbu v0, 0x0(a0); sh v0, 0x7a(a2)` — operand byte →
	##   slot+0x7A.
	## slot+0x7A drives the L800156D0-DC switch:
	##   == 15 → idle_timeout = (byte_76 + delta_time) - 1
	##   == 16 → idle_timeout =  byte_76 + delta_time
	##   else  → idle_timeout = (delta_time * slot+0x7A) >> 4
	var p_a9: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	channel.byte_7A = p_a9
