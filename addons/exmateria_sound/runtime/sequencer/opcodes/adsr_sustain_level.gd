class_name SequencerOpAdsrSustainLevel
## FFT analog: smd_op_ca_adsr2_mode @ LAB_80016298
##                (opcode 0xCA)
##
## Pass D2 — was misidentified as "sustain_level" in the original
## music binding. FFT's 0xCA is the ADSR2-low release mode selector
## (stores at slot+0x60 = adsr2_mode_byte). Mirrors shared/opcodes/
## adsr_mode_ca.gd.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var byte: int = (params[0] if params.size() > 0 else 0) & 0xFF
	ts.ctx.channel.adsr2_mode_byte = byte
	ts.ctx.slot.adsr2_mode_byte = byte
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW
