class_name SharedOpSlurOff
## FFT analog: smd_slur_off @ LAB_80015EC0
##                (opcode 0xB1)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## SlurOff — L80015EC0/EC8 (opcode 0xB1 jumptable
	## @0x80028BD0). Clears bit 0x800 (SLUR_PENDING) via
	## `andi v0, v0, 0xf7ff`.
	channel.channel_word_0 &= ~_SS.CHAN0_SLUR_PENDING
