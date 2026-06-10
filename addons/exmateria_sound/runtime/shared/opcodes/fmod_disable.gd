class_name SharedOpFmodDisable
## FFT analog: smd_fmod_disable @ LAB_80015F18
##                (opcode 0xB3)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## opcode 0xB3 — SPU FMod disable (handler @ 0x80015F18).
	## FFT body:
	##   v0 = chan[+0x34]
	##   entity[+0x68] &= ~v0
	##   chan[+0x04] |= 0x4
	## Mirrors 0xB2 with AND-clear instead of OR-set.
	if voice_writes:
		slot.fmod_pending = 0
