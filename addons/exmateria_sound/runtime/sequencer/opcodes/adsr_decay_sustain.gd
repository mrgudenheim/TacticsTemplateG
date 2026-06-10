class_name SequencerOpAdsrDecaySustain
## FFT analog: smd_op_c7_adsr_decay_sustain @ LAB_80016238
##                (opcode 0xC7)
##
## Pass D2 — mirrors shared/opcodes/adsr_decay_sustain.gd. Writes
## decay (bits 4-7) + sustain level (bits 0-3) into adsr1's low byte
## directly. Walker drains via _fan_adsr1_mid + _fan_adsr1_low.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var dr: int = ((params[0] if params.size() > 0 else 0) & 0xFF) & 0xF
	var sl: int = ((params[1] if params.size() > 1 else 0) & 0xFF) & 0xF
	ts.ctx.channel.adsr1 = (ts.ctx.channel.adsr1 & 0xFF00) | (dr << 4) | sl
	ts.ctx.slot.adsr1 = ts.ctx.channel.adsr1
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_MID | _SS.WALKER_FLAG_ADSR1_LOW
