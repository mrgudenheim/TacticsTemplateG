class_name SharedOpFmodEnable
## FFT analog: Hyp_smd_op_test_ch2d_bit0 @ 0x80015ED8
##                (opcode 0xB2)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## opcode 0xB2 — SPU FMod enable (Hyp_smd_op_test_ch2d_bit0 @ 0x80015ED8).
	## FFT body:
	##   if (chan[+0x2D] & 1) == 0: no-op
	##   else: entity[+0x68] |= chan[+0x34]; chan[+0x04] |= 0x4
	## chan[+0x34] is the precomputed (1 << voice_idx) mask pre-staged when
	## play_sound binds the channel to a slot. The walker FUN_8001_4F58
	## OR-accumulates entity[+0x68] per IRQ into the SPU FMon register,
	## which makes the SPU set Chan::FMod=1 on the voice (and Chan::FMod=2
	## on the previous voice as the freq-channel modulation source).
	##
	## Silent driver does NOT arm FMod on the audible voice — only the
	## audible channel's bytecode drives the routing change.
	if voice_writes:
		slot.fmod_pending = 1
