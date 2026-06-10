class_name SequencerOpFlagSetE6
## FFT analog: smd_op_e6_set_ch11E_bit0 @ LAB_8001686c
##                (opcode 0xE6)


static func apply(sequencer, ts, _params) -> void:
	# FFT LAB_8001686c sets bit 0 of ch+0x11E. 8+ reader sites in
	# BATTLE.BIN (0x8006A7DC and others) that gate per-note effect
	# calls with a (count-1)-iteration lookup into a 448-byte-stride
	# table at 0x801908CC. Those downstream effects aren't implemented
	# yet; setting the flag here is a no-op audio-wise but puts the
	# handler in place for when effect-hook work lands.
	# Pass 7.D — mirrors SFX shared/opcodes/set_subslot1_active.gd
	# dual write to slot.word_11e + channel.lfo_sub_active[1].
	ts.ctx.slot.word_11e |= 0x1
	ts.ctx.channel.lfo_sub_active[1] = 1
