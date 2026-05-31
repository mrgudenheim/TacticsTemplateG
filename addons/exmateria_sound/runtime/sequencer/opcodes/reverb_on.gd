class_name SequencerOpReverbOn
## FFT analog: smd_reverb_on @ 0x800160E4
##                (opcode 0xBA)


static func apply(_sequencer, ts, _params) -> void:
	# Pass 7.D.b — partial SFX-body adoption. The SFX side's
	# shared/opcodes/reverb_on.gd writes only `slot.walker_flag_word |=
	# WALKER_FLAG_ADSR2_HIGH` (its pool+0x70 mask is unmodeled).
	# Music's `reverb_send_enabled` write is the AUDIBLE side — note_handler
	# reads it for the voice_reverb routing. Pass 7.D.b keeps the audible
	# write here; the walker-flag arm will fold in when SFX-side reverb
	# parity work models pool+0x70 and we converge bodies.
	ts.ctx.channel.reverb_send_enabled = true
