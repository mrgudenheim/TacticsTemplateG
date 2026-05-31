class_name SequencerOpVolLfoDepth
## FFT analog: smd_op_e3_vol_lfo_depth @ LAB_80016834
##                (opcode 0xE3)


static func apply(sequencer, ts, params) -> void:
	if ts.voice_idx >= 0 and params.size() > 0 and params[0] != 0xff:
		var d: int = 0x100 / (params[0] + 1)
		sequencer.mixer.set_voice_volume_lfo_depth(ts.voice_idx, d, d)
