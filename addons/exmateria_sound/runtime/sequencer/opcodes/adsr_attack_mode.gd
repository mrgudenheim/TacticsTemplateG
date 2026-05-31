class_name SequencerOpAdsrAttackMode
## FFT analog: smd_op_c8_adsr_attack_mode @ LAB_80016260
##                (opcode 0xC8)
##
## Single-param ADSR1-high mode setter — the lin/exp ramp-mode companion
## to 0xC2 (`adsr_attack.gd`, attack rate). FFT writes the byte as a u32
## at chan+0x58 (`sw v1, 0x58(a2)`) and ORs `WALKER_FLAG_ADSR1_HIGH`
## (bit 0x10) into chan+0x4. The walker reads chan+0x58 as a2 for
## `spu_write_voice_adsr1_high_byte` (FUN_8001B938), which gates on
## `a2 == 5`: when set, bit 0x80 of the SPU ADSR1 upper byte is set
## (= bit 15 of the 16-bit register = exp ramp mode); otherwise lin.
##
## smd-player's encoding puts the lin/exp flag in `slot.adsr1` bit 15,
## which `_fan_adsr1_high` reads via `(slot.adsr1 & 0x8000) ? 5 : 0`.
## Mirror the FFT `byte == 5 → exp, else lin` rule by setting/clearing
## that bit. Preserves bits 0-14 (attack rate + decay + sustain level).
##
## Fires in vanilla MUSIC_58 (132 occurrences, always `C8 05` in the
## `AC instr → C8 05 → C2 attack → C5 release` instrument-setup macro).
## See research/working_documents/SMD_PARSER_GAPS.md §P0 0xC8.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var byte: int = (params[0] if params.size() > 0 else 0) & 0xFF
	if byte == 5:
		ts.ctx.channel.adsr1 = ts.ctx.channel.adsr1 | 0x8000
	else:
		ts.ctx.channel.adsr1 = ts.ctx.channel.adsr1 & 0x7FFF
	ts.ctx.slot.adsr1 = ts.ctx.channel.adsr1
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_HIGH
