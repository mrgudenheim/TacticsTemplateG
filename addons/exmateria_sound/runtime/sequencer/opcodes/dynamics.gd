class_name SequencerOpDynamics
## FFT analog: smd_dynamics @ 0x80016614
##                (opcode 0xE0)

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	# Pass 7.D — FFT 0xE0 dynamics: chan+0x98 = byte<<24. Matches SFX
	# shared/opcodes/dynamics.gd.
	# Pass D1.2 — also arm CHAN1_VOL_PRESTAGE so Sequencer.tick's per-
	# tick vol-recompute fires SharedComputeVolLr.apply, restages slot.
	# vol_staging_l/r with the new dynamics value, and arms
	# WALKER_FLAG_VOL_LR_RAW. Mid-track dynamics now audible.
	var new_vol: int = params[0] if params.size() > 0 else 127
	ts.ctx.channel.expression_acc_s32 = new_vol << 24
	ts.ctx.channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE
