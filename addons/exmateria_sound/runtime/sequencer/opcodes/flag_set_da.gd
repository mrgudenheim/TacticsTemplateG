class_name SequencerOpFlagSetDa
## FFT analog: smd_op_da_set_chFE_bit0 @ LAB_800165e4
##                (opcode 0xDA)


static func apply(sequencer, ts, _params) -> void:
	# FFT LAB_800165e4 sets bit 0 of ch+0xFE. BATTLE.BIN has no readers
	# of this flag (only writers) — likely dead code, possibly used by
	# SCUS or external driver code. Store anyway so the handler dispatch
	# graph is complete.
	# Iter-35: sub-slot 0 unified — bit 0x1 of chan+0xFE is
	# lfo_sub_active[0].
	ts.ctx.channel.lfo_sub_active[0] = 1
