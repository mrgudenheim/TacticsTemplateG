class_name SharedOpPitchBendAdd16bit
## FFT analog: smd_op_d3_pitch_bend_add_16bit @ LAB_80016330
##                (opcode 0xD3)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xD3 — PitchBend_Add_16bit at FFT LAB_80016330 (jumptable
	## 0x80028C58). 2 params. 16-bit signed sibling of 0xD1 (which adds
	## sb*32 = 8-bit signed shifted). param[0]=signed high byte,
	## param[1]=unsigned low byte → combined as signed 16-bit delta to
	## chan+0x86 (the pitch-bend accumulator written by D0 / D1).
	## FFT MIPS:
	##   lbu   v0, 0x0(a0)
	##   lbu   a1, 0x1(a0)
	##   lhu   v1, 0x2(a2)      ; chan_word_1
	##   sll   v0, v0, 0x18
	##   sra   v0, v0, 0x10     ; sign-extended (sb << 8)
	##   addu  a1, a1, v0       ; signed 16-bit delta
	##   lhu   v0, 0x86(a2)
	##   ori   v1, v1, 0x200    ; CHAN1_PITCH_PRESTAGE
	##   sh    v1, 0x2(a2)
	##   addu  v0, v0, a1
	##   sh    v0, 0x86(a2)
	## Affects 7 effects (Shiva, LastDance, Chakra, Kiyomori, ThrowSpirit,
	## Ulmaguest, Paralyze). See SMD_OPCODE_COVERAGE_STATUS.md §4.2.
	_ProbeCounters.opcode_d3_pitch_bend_add_16bit += 1
	var p0_d3: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var p1_d3: int = (op.params[1] if op.params.size() > 1 else 0) & 0xFF
	var sb_d3: int = p0_d3 if p0_d3 < 0x80 else p0_d3 - 0x100
	var delta_d3: int = ((sb_d3 << 8) + p1_d3) & 0xFFFF
	if delta_d3 >= 0x8000:
		delta_d3 -= 0x10000
	var word_86_new_d3: int = (channel.word_86 + delta_d3) & 0xFFFF
	if word_86_new_d3 >= 0x8000:
		word_86_new_d3 -= 0x10000
	channel.word_86 = word_86_new_d3
	channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
	slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH
	_Trace.emit("opcode_d3_pitch_bend_add_16bit", {
		"call_index": _ProbeCounters.opcode_d3_pitch_bend_add_16bit,
		"delta": delta_d3,
		"word_86_post": word_86_new_d3,
		"channel_idx": channel.channel_idx,
	})
