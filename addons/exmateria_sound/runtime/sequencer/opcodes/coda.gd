class_name SequencerOpCoda
## FFT analog: smd_coda @ LAB_80015988
##                (opcode 0x99)


static func apply(_sequencer, ts, _params) -> void:
	if ts.loop_stack.size() > 0:
		var entry: Array = ts.loop_stack[-1]
		if entry[1] > 0:
			entry[1] -= 1
			ts.ctx.channel.octave = entry[2]
			# iter-31 — mirror FFT smd_coda PC 0x80015B50 `sh v1, 0x7e(a2)`.
			# Without this, bmidi_baseline_byte drifts +12 per loop body
			# RaiseOctave, putting notes one octave high.
			if entry.size() > 3:
				ts.ctx.channel.bmidi_baseline_byte = entry[3]
			ts.event_idx = entry[0]
			return
		else:
			ts.loop_stack.pop_back()
