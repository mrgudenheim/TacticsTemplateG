class_name SequencerOpReverbOff
## FFT analog: smd_reverb_off @ 0x80016110
##                (opcode 0xBB)


static func apply(_sequencer, ts, _params) -> void:
	# Pass 7.D.b — symmetric to reverb_on adoption. Audible reverb-send
	# clears here; SFX-side walker-flag arm omitted pending unified
	# reverb model.
	ts.ctx.channel.reverb_send_enabled = false
