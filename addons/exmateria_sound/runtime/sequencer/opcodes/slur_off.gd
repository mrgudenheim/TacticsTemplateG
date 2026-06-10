class_name SequencerOpSlurOff
## FFT analog: smd_slur_off @ LAB_80015EC0
##                (opcode 0xB1)


static func apply(_sequencer, ts, _params) -> void:
	# Pass 7.D.b — FFT-faithful body. Matches SFX shared/opcodes/slur_off.gd
	# which clears CHAN0_SLUR_PENDING via `andi 0xF7FF`.
	ts.ctx.channel.channel_word_0 &= ~0x800
