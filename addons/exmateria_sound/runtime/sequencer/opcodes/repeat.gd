class_name SequencerOpRepeat
## FFT analog: smd_repeat @ LAB_80015960
##                (opcode 0x98)


static func apply(sequencer, ts, params) -> void:
	var count: int = (params[0] - 1) if params.size() > 0 else 0
	var _octave: int = ts.ctx.channel.octave
	# FFT smd_repeat PC 0x80015AF4/AFC: `lbu a0, 0x7e(a2); sb a0, 0x2(v1)`
	# saves chan+0x7e (bmidi_baseline_byte) so smd_coda can restore it
	# per iteration. Without this, RaiseOctave/LowerOctave inside the
	# loop body permanently drift bmidi_baseline_byte → notes one octave off.
	var _bmidi: int = ts.ctx.channel.bmidi_baseline_byte
	ts.loop_stack.append([ts.event_idx, count, _octave, _bmidi])
