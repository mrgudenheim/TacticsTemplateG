class_name SequencerOpAdsr1LowNibbleSlide
## FFT analog: smd_op_c6_adsr1_low_slide @ LAB_8001621c
##                (opcode 0xC6)
##
## Pass D2 — write low nibble of adsr1 directly + arm walker. The
## walker's _fan_adsr1_low RMW emits the SPU update at end-of-tick;
## the previous direct mixer.set_voice_adsr1_low call is dropped
## (its effect is now via the walker, same SPU register).

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var byte: int = (params[0] if params.size() > 0 else 0) & 0xF
	ts.ctx.channel.adsr1 = (ts.ctx.channel.adsr1 & 0xFFF0) | byte
	ts.ctx.slot.adsr1 = ts.ctx.channel.adsr1
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_LOW
