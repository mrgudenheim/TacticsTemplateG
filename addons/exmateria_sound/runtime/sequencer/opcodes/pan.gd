class_name SequencerOpPan
## FFT analog: smd_pan @ LAB_8001689c
##                (opcode 0xE8)

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	# FFT smd_pan (PC 0x8001689C-B8) writes chan+0x92 = byte<<8. The
	# vol formula `FUN_80017118` reads chan+0x92 via `lh v0, 0x90(s0)`
	# at PC 0x80017210 (s0=chan+0x2 → addr=chan+0x92), then adds it to
	# pan_base. So pan is byte<<8 in FFT's 15-bit-style scale.
	#
	# Godot maps FFT's chan+0x92 onto `channel.pan_offset_ae` (despite
	# the misleading field name — see channel_state.gd:228 comment and
	# docs/MUSIC_OPCODE_E8_FIELD_MISMATCH.md). The earlier Pass 7.D
	# write `pan_offset_ae = byte` left the value at the byte scale,
	# but compute_vol_lr.gd treats it as a signed 8-bit offset (-128
	# to +127) — much smaller pan range than FFT's signed 16-bit.
	# Scale up by 8 to match FFT's `byte << 8` value before vol formula
	# consumes it; this gives Godot the same stereo split as PCSX.
	#
	# (Note: compute_vol_lr.gd still sign-extends pan_offset_ae from
	# 8-bit. After this fix, the byte<<8 value is up to 0x7F00 = 32512
	# which OVERFLOWS s8. The compute_vol_lr will treat it as a
	# negative pan after sign-extension. This is a follow-up
	# compute_vol_lr fix — but the iter 12 first-step is just the
	# scale match here; the formula read-side update comes next.)
	#
	# CHAN1_VOL_PRESTAGE arm matches FFT PC 0x800168A8.
	# SFX path (shared/opcodes/pan.gd) is unchanged.
	#
	# Iter-54 — write to chan_92_pan_baseline (the new dedicated music
	# pan field). Previously this wrote pan_offset_ae which was
	# overloaded with the SFX byte-offset semantic + the 0xF0 lfo subslot
	# index (FFT chan+0xae). See MUSIC_ITER54_STEREO_PAN_BASELINE.md.
	ts.ctx.channel.chan_92_pan_baseline = (params[0] if params.size() > 0 else 0) << 8
	ts.ctx.channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE
