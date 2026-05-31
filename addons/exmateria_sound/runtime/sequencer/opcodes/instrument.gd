class_name SequencerOpInstrument
## FFT analog: FUN_80015E30 @ 0x80015E30 → Hyp_instrument_data_loader
##                (opcode 0xAC)
## (Ghidra's `smd_instrument` label at 0x80015DD0 is actually opcode 0xA9
## — `smd_op_a9_set_slot7a` — which only writes chan+0x7A. Real 0xAC
## dispatches to FUN_80015E30 which calls Hyp_instrument_data_loader.)


static func apply(sequencer, ts, params) -> void:
	# Pass 7.D.f — FFT FUN_80015E30 instrument-reload. Loads the WAVESET
	# entry's ADSR1/2, fine_tune, and resolved sample start/loop addrs
	# into channel.* so note_handler can read them at key-on time
	# without re-resolving the waveset.
	var byte_val: int = params[0] if params.size() > 0 else 0
	ts.ctx.channel.byte_7A = byte_val
	sequencer._load_inst_into_channel(byte_val + 1, ts.ctx.channel)

	# FFT Hyp_instrument_data_loader trailer (PC 0x80017064-8C):
	#   if (chan_word_0 & 0x0C) != 0:
	#       chan_word_1     |= 0x300       (vol + pitch prestage)
	#       walker_flag_word |= 0x1FF      (immediate full walker arm)
	#   else:
	#       chan_word_0     |= 0x8000      (deferred arm; smd_note
	#                                       consumes it on the next Note)
	#
	# Music tracks initialise with chan_word_0 = 0x1 (no HAS_TONES), so
	# the else-branch is the live path for music. The deferred bit is
	# consumed in sequencer/note_handler/note_handler.gd's apply(); see
	# docs/MUSIC_VOL_REGISTER_SWEEP_INVESTIGATION.md. Without this branch
	# the walker never sees WALKER_FLAG_VOL_LR_SWEEP (0x002) so
	# probe_vol_register_sweep stays at 0 on Godot while PCSX emits ~43.
	if (ts.ctx.channel.channel_word_0 & 0xC) != 0:
		ts.ctx.channel.channel_word_1 |= 0x300
		ts.ctx.slot.walker_flag_word |= 0x1FF
	else:
		ts.ctx.channel.channel_word_0 |= 0x8000
