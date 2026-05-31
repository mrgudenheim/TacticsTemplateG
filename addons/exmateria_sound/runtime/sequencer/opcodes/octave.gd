class_name SequencerOpOctave
## FFT analog: smd_octave @ LAB_800158e0
##                (opcode 0x94)


static func apply(_sequencer, ts, params) -> void:
	# Pass 7.D.d — FFT-faithful: also write chan+0x7e (bmidi_baseline_
	# byte = octave * 12 per FFT LAB_800159F0 PC 0x80015A04). Consumed
	# by SharedComputePitch.apply at Note dispatch.
	var new_octave: int = params[0] if params.size() > 0 else 4
	ts.ctx.channel.octave = new_octave
	ts.ctx.channel.bmidi_baseline_byte = (new_octave * 12) & 0xFF
