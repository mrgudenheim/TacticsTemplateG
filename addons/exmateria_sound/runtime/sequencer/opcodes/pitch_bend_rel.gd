class_name SequencerOpPitchBendRel
## FFT analog: smd_op_d2_rel_pitch_bend @ LAB_80016304
##                (opcode 0xD2 — jumptable @ 0x80028C54)
##
## §I.2 binding fix (2026-05-25). Music previously bound 0xD2 to
## a misnamed `ConditionalSeqFlag` no-op based on a label confusion;
## the actual FFT handler is PitchBendRel. Body matches SFX's
## shared/opcodes/pitch_bend_rel.gd:
##   chan+0x86 += signed_byte * 8
##   chan_word_1 |= CHAN1_PITCH_PRESTAGE (0x200)
##   walker_flag_word |= WALKER_FLAG_PITCH (0x4)
##
## 1-param payload (FFT arg-size table entry 0x02 = 1 opcode byte + 1
## param byte). The byte is sign-extended s8.
##
## Music renderer doesn't read word_86 yet, so this change is
## audio-invisible — but the halfwords are now FFT-faithful, ready
## for Pass 7.E/F flush adoption.


const CHAN1_PITCH_PRESTAGE := 0x200
const WALKER_FLAG_PITCH := 0x4


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	if params.size() == 0:
		return
	var p: int = params[0] & 0xFF
	if p >= 0x80:
		p -= 0x100
	var word_86_new: int = (ts.ctx.channel.word_86 + p * 8) & 0xFFFF
	if word_86_new >= 0x8000:
		word_86_new -= 0x10000
	ts.ctx.channel.word_86 = word_86_new
	ts.ctx.channel.channel_word_1 |= CHAN1_PITCH_PRESTAGE
	ts.ctx.slot.walker_flag_word |= WALKER_FLAG_PITCH
