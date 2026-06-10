class_name SharedOpReverbOff
## FFT analog: smd_reverb_off @ 0x80016110
##                (opcode 0xBB)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## ReverbOff — opcode 0xBB, smd_reverb_off @ 0x80016110 (jumptable
	## entry @ 0x80028BF8). 0 params. Mirror of 0xBA with the pool+0x70
	## bit CLEARED instead of set:
	##   1. pool+0x70 &= ~chan+0x34
	##   2. slot+0x4  |= 0x40       (= WALKER_FLAG_ADSR2_HIGH — same as 0xBA)
	## The walker arm is the only structurally-observable write in our
	## model (see _op_reverb_on); the pool+0x70 difference is invisible
	## because `reverb_enabled` is hardcoded. Lands the probe row so
	## downstream walker fan-out emits match PCSX cad-for-cad on bytecodes
	## that use 0xBB (e.g. zombie's catalog-replay path's pair 12 ch1).
	_ProbeCounters.opcode_reverb_off += 1
	_Trace.emit("opcode_reverb_off", {
		"call_index": _ProbeCounters.opcode_reverb_off,
		"walker_flag_word_pre": slot.walker_flag_word & 0xFFFF,
	})
	if voice_writes:
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_HIGH
