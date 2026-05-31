class_name SequencerOpRaiseOctave
## FFT analog: smd_raise_octave @ LAB_800158fc
##                (opcode 0x95)


static func apply(_sequencer, ts, _params) -> void:
	# Pass 7.D.d — FFT chan+0x7E += 0xC. Track channel.octave (int) AND
	# bmidi_baseline_byte (byte form consumed by SharedComputePitch).
	ts.ctx.channel.octave += 1
	ts.ctx.channel.bmidi_baseline_byte = (ts.ctx.channel.bmidi_baseline_byte + 12) & 0xFF
