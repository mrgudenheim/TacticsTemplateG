class_name SharedOpSlurOn
## FFT analog: smd_slur_on @ LAB_80015EA8
##                (opcode 0xB0)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## SlurOn — L80015EB0/EB4 (opcode 0xB0 jumptable
	## @0x80028BCC). Sets bit 0x800 (SLUR_PENDING) on slot+0x0.
	## This bit is sticky across the dispatcher entry CLEAR
	## (mask 0xf8ff preserves bit 0x800) and is consumed by the
	## post-Note propagation to OR bit 0x200 (VOL_PENDING) onto
	## slot+0x0, which gates the duration-tick arm.
	_ProbeCounters.opcode_slur_on += 1
	_Trace.emit("opcode_slur_on", {
		"call_index": _ProbeCounters.opcode_slur_on,
		"chan_word_0_pre": channel.channel_word_0 & 0xFFFF,
	})
	channel.channel_word_0 |= _SS.CHAN0_SLUR_PENDING
