class_name SequencerOpFlagClearDb
## FFT analog: smd_op_db_clear_chFE_bit0 @ LAB_800165fc
##                (opcode 0xDB)


static func apply(sequencer, ts, _params) -> void:
	# Companion to 0xDA. Clears bit 0 of ch+0xFE. FFT LAB_800165fc.
	# Iter-35: sub-slot 0 unified — bit 0x1 of chan+0xFE is
	# lfo_sub_active[0].
	ts.ctx.channel.lfo_sub_active[0] = 0
