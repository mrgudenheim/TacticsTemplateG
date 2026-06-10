class_name SequencerOpSlurOn
## FFT analog: smd_slur_on @ LAB_80015EA8
##                (opcode 0xB0)


static func apply(_sequencer, ts, _params) -> void:
	# Pass 7.D.b — FFT-faithful body. Matches SFX shared/opcodes/slur_on.gd
	# at line 25: sets CHAN0_SLUR_PENDING (0x800) on channel_word_0.
	# The ts.slur TrackState mirror was dropped (all readers route via
	# ctx.channel.channel_word_0 per Pass 7.B.slur).
	ts.ctx.channel.channel_word_0 |= 0x800
