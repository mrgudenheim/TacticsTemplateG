class_name SequencerOpConditionalSeqFlag
## FFT analog: smd_op_d2_conditional_seq_flag @ LAB_80015ed8
##                (opcode 0xD2)


static func apply(sequencer, ts, _params) -> void:
	# FFT LAB_80015ed8: reads byte at ch+0x2d, tests bit 0; if SET,
	#   seq[0x68] |= ch[0x34]   (32-bit OR — propagates per-ch flag
	#                           bits into a sequencer-global word)
	#   ch[0x4] |= 0x4          (halfword flag)
	# If bit 0 of ch+0x2d is clear, the handler returns without
	# touching anything.
	# ch+0x2d is only written during channel-init paths; in MUSIC_34
	# both 0xD2 dispatches land on channels where ch+0x2d bit 0 is
	# clear (probe would see no audio effect). ch+0x34 and seq+0x68
	# readers live outside the sound-driver range; tracing their
	# audio effect is a separate iter.
	# Arg count 1 per FFT opcode-size table @ 0x80028d5e (encoded 0x02
	# = args+1); the handler doesn't READ the byte — dispatcher
	# advances the stream pointer before entering.
	pass
