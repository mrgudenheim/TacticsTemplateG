class_name SharedOpNoiseDisable
## FFT analog: smd_noise_disable @ LAB_80016060
##                (opcode 0xB7)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## opcode 0xB7 — SPU NOISE disable (handler @ 0x80016060,
	## jumptable 0x80028BE8).
	## FFT body:
	##   v0 = chan[+0x34]                ; 1 << voice mask
	##   entity[+0x6c] &= ~v0            ; clear voice bit in noise mask
	##   slot[+0x04] |= 0x10             ; walker_flag_word |= 0x10
	## entity[+0x6c] is aggregated each IRQ by Hyp_spu_updater_callee_2
	## (FUN_80014FF8) and written to SPU NoiseOn (0x1F801D94/D96) via
	## FUN_80019B5C, so clearing the bit here turns off the voice's noise
	## mode on the next IRQ. Mirrors 0xB4 with AND-clear instead of OR-set.
	## cure_4 voice 18's bytecode dispatches this between the first-note
	## decay and the AC(0F) tonal instrument load.
	if voice_writes:
		slot.noise_disable_pending = true
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_HIGH
