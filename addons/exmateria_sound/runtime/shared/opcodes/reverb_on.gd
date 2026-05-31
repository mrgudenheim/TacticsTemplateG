class_name SharedOpReverbOn
## FFT analog: smd_reverb_on @ 0x800160E4
##                (opcode 0xBA)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	_ProbeCounters.opcode_reverb_on += 1
	_Trace.emit("opcode_reverb_on", {
		"call_index": _ProbeCounters.opcode_reverb_on,
		"walker_flag_word_pre": slot.walker_flag_word & 0xFFFF,
	})
	## ReverbOn — opcode 0xBA, smd_reverb_on @ 0x800160E4 (jumptable
	## entry @ 0x80028BF4). 0 params. FFT does TWO writes:
	##   1. pool+0x70 |= chan+0x34   (sets this voice's bit in the
	##      pool's reverb-enable mask, the per-channel mask of voices
	##      with reverb send routed through SPU REVERB)
	##   2. slot+0x4 |= 0x40         (= WALKER_FLAG_ADSR2_HIGH)
	## We mirror only #2 — the pool+0x70 register has no Godot
	## equivalent (`reverb_enabled` in flush_tick.gd is hardcoded to
	## `is_primary` at KEYON time, so the mask bit is audibly
	## invisible here). #2 is also redundant in practice because
	## 0xC4 fires immediately after each 0xBA in observed streams
	## and sets the same flag — kept for parity.
	if voice_writes:
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_HIGH
