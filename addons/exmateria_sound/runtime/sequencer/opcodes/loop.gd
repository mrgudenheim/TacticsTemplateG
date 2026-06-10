class_name SequencerOpLoop
## FFT analog: smd_save_loop_target @ LAB_800158c4
##                (opcode 0x91)


static func apply(sequencer, ts, _params) -> void:
	ts.loop_point = ts.event_idx
