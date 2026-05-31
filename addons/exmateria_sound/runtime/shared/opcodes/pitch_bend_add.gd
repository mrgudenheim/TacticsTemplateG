class_name SharedOpPitchBendAdd
## FFT analog: smd_add_pitch_bend @ 0x800162D8
##                (opcode 0xD1)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xD1 — smd_add_pitch_bend at PC 0x800162D8. FFT does:
	##   lbu  v1, 0x0(a0)           ; byte
	##   lhu  v0, 0x86(a2)           ; v0 = chan+0x86 (current)
	##   ...                          ; v0 += sb*32
	##   sh   v0, 0x86(a2)           ; chan+0x86 += sb*32 (ACCUMULATE)
	## Same field as D0 (chan+0x86 = channel.word_86), but adds instead
	## of sets. NOT affected by 0xAC (which writes chan+0x84) — D1
	## accumulation persists across instrument changes.
	_ProbeCounters.opcode_d1_pitch_bend += 1
	_Trace.emit("opcode_d1_pitch_bend", {
		"call_index": _ProbeCounters.opcode_d1_pitch_bend,
		"d1_byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	if op.params.size() > 0:
		var p_d1: int = op.params[0] & 0xFF
		if p_d1 >= 0x80: p_d1 -= 0x100
		# Sign-extend pre-add value to s16, add, re-mask, sign-extend.
		var current: int = channel.word_86
		var word_86_new: int = (current + p_d1 * 32) & 0xFFFF
		if word_86_new >= 0x8000: word_86_new -= 0x10000
		channel.word_86 = word_86_new
		channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
		slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH
