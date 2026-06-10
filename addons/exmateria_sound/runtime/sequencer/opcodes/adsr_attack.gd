class_name SequencerOpAdsrAttack
## FFT analog: smd_op_c2_adsr_attack @ LAB_800161A8
##                (opcode 0xC2)
##
## Pass D2 — mid-track walker arming. Mirrors shared/opcodes/adsr_
## attack.gd: write attack_rate into channel.adsr1 bits 8-14
## (preserving bit 15 lin/exp + bits 0-7 decay/sustain), copy to
## slot.adsr1, arm WALKER_FLAG_ADSR1_HIGH so the walker fans out the
## SPU register update at end-of-tick. Mid-note attack-rate changes
## now audible.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var byte: int = (params[0] if params.size() > 0 else 0) & 0xFF
	var new_attack: int = byte & 0x7F
	ts.ctx.channel.adsr1 = (ts.ctx.channel.adsr1 & 0x80FF) | (new_attack << 8)
	ts.ctx.slot.adsr1 = ts.ctx.channel.adsr1
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_HIGH
