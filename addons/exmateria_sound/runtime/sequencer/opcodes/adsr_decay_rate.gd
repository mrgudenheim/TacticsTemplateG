class_name SequencerOpAdsrDecayRate
## FFT analog: smd_op_c3_adsr_decay_rate @ LAB_800161c4
##                (opcode 0xC3)
##
## Single-param sibling of 0xC7 (which writes decay rate + sustain
## level together). FFT writes the byte at chan+0x66 (`sh v1, 0x66(a2)`)
## and ORs `WALKER_FLAG_ADSR1_MID` (bit 0x20) into chan+0x4. The walker
## reads `chan+0x66` as a1 for `FUN_8001B79C`, which uses the low 4 bits
## of a1 as the SPU ADSR1 mid-nibble (decay/sustain rate slot, bits 4-7
## of the SPU register).
##
## Mirrors the decay-half of `adsr_decay_sustain.gd` (0xC7): preserve
## bits 0-3 (sustain level) and bits 8-15 (attack rate + lin/exp), write
## bits 4-7 from `byte & 0xF`. The walker's `_fan_adsr1_mid` reads
## `(slot.adsr1 >> 4) & 0xF`.
##
## Fires in vanilla MUSIC_11/17/19/97 (10 occurrences). See
## research/working_documents/SMD_PARSER_GAPS.md §P0 0xC3.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var byte: int = (params[0] if params.size() > 0 else 0) & 0xFF
	var dr: int = byte & 0xF
	ts.ctx.channel.adsr1 = (ts.ctx.channel.adsr1 & 0xFF0F) | (dr << 4)
	ts.ctx.slot.adsr1 = ts.ctx.channel.adsr1
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_MID
