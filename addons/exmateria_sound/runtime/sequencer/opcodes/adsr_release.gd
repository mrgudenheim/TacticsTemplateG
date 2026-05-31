class_name SequencerOpAdsrRelease
## FFT analog: smd_release @ 0x800161E0
##                (opcode 0xC5)
##
## Pass D2 — mirrors shared/opcodes/adsr_release.gd. Release rate goes
## into adsr2 bits 0-4 (slot+0x6A on FFT). Default mode bits = 0.
## Walker's _fan_adsr2_low ORs slot.adsr2_mode_byte == 7 → 0x20.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var byte: int = (params[0] if params.size() > 0 else 0) & 0xFF
	var release_low: int = byte & 0x3F
	ts.ctx.channel.adsr2 = (ts.ctx.channel.adsr2 & 0xFFC0) | release_low
	ts.ctx.slot.adsr2 = ts.ctx.channel.adsr2
	# Iter-32: FFT 0xC5 also stores the raw operand to slot+0x6A
	# (`sh v1, 0x6a(a2)` at PC 0x80016218). Walker's LOW writer reads
	# slot+0x6A as the rate input independent of slot.adsr2's low bits.
	# See docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
	ts.ctx.channel.release_rate_byte = byte
	ts.ctx.slot.release_rate_byte = byte
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW
