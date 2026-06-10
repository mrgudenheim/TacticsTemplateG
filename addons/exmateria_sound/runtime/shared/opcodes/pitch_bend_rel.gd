class_name SharedOpPitchBendRel
## FFT analog: smd_op_d2_rel_pitch_bend @ LAB_80016304
##                (opcode 0xD2)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xD2 — relative pitch bend at LAB_80016304 (jumptable
	## 0x80028C5C). FFT disasm:
	##   lbu  v1, 0x0(a0)         ; v1 = byte payload (u8)
	##   lhu  v0, 0x86(a2)         ; v0 = chan+0x86 (pitch_bend)
	##   lhu  a1, 0x2(a2)          ; a1 = chan_word_1
	##   sll  v1, v1, 0x18         ; v1 <<= 24
	##   sra  v1, v1, 0x15         ; v1 >>= 21 → signed (s8 << 3) = sb * 8
	##   addu v0, v0, v1
	##   ori  a1, a1, 0x200        ; CHAN1_PITCH_PRESTAGE
	##   sh   v0, 0x86(a2)
	##   sh   a1, 0x2(a2)
	## Same field as 0xD1 (chan+0x86 = channel.word_86), same prestage
	## bit, but byte scale is 8 instead of 32. 1-byte payload.
	_ProbeCounters.opcode_d2_rel_pitch_bend += 1
	_Trace.emit("opcode_d2_rel_pitch_bend", {
		"call_index": _ProbeCounters.opcode_d2_rel_pitch_bend,
		"d2_byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	if op.params.size() > 0:
		var p_d2: int = op.params[0] & 0xFF
		if p_d2 >= 0x80: p_d2 -= 0x100
		var current: int = channel.word_86
		var word_86_new: int = (current + p_d2 * 8) & 0xFFFF
		if word_86_new >= 0x8000: word_86_new -= 0x10000
		channel.word_86 = word_86_new
		channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
		slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH
