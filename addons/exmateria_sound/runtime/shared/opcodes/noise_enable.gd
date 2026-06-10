class_name SharedOpNoiseEnable
## FFT analog: FUN_80015F44 @ 0x80015F44
##                (opcode 0xB4)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## opcode 0xB4 — SPU NOISE enable + clock.
	## Per FFT disasm L80015F44 (jumptable @0x80028BDC) +
	## L80019D88 (called helper L80019DB4-CC):
	##   slot+0x1E = operand & 0x3F
	##   SPUCNT bits 8-13 = (operand & 0x3F) << 8 (noise_clock)
	##   NON2 bit (1 << voice%16) set (slot's voice → noise mode)
	## Stash operand in noise_pending; flush_tick consumes per
	## tick and calls mixer.set_voice_noise + mixer.set_noise_clock.
	## Silent driver does not enable noise mode on the audible
	## voice.
	if voice_writes:
		var p_b4: int = (op.params[0] if op.params.size() > 0 else 0) & 0x3F
		slot.noise_clock_value = p_b4
		slot.noise_pending = p_b4
