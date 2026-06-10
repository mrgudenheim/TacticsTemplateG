class_name SharedOpTimeSignature
## FFT analog: smd_op_97_time_signature @ LAB_80015a40
##                (opcode 0x97)


static func apply(sequencer, ts, params) -> void:
	# FFT LAB_80015a40: stores numerator at ch+0x38/0x3e, denominator at
	# ch+0x3c, and computes ch+0x3a = 0xC0 / (denominator * PPQN) as a
	# tick-per-beat counter reload. Every tick decrements ch+0x36; when
	# it hits 0, reload from ch+0x3a. The counter drives some per-beat
	# behavior we don't currently hook into anything audio-affecting,
	# but store the state so future code using beat markers has it.
	ts.time_sig_numerator = params[0] if params.size() > 0 else 4
	ts.time_sig_denominator = params[1] if params.size() > 1 else 4
