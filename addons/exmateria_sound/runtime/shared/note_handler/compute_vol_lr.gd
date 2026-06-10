class_name SharedComputeVolLr
## FFT-faithful vol_l/vol_r formula for both music and SFX. Port of
## the SFX path in play_sound.gd:1589-1644 (which mirrors FFT
## FUN_80017118 PC 0x800171C4-L80017228). Stages slot.vol_staging_l/r
## from channel + slot inputs.
##
## Inputs (all on channel unless noted):
##   chan_98 = expression_acc_s32 high halfword (signed s16, dynamics)
##   chan_88 = chan_88_value (signed s16, vol-LFO accumulator)
##   chan_92 = chan_92_value (env multiplier; for music = velocity<<8,
##             for SFX = engine-init from FEDS table)
##   pool_96 = master_vol  (caller-supplied; SFX = 0x7F00, music =
##             sequencer.master_vol)
##   pan_ae  = pan_offset_ae (FFT chan+0xae signed pan offset; read
##             via `lh` in disasm so values 0x80..0xFF wrap to negative)
##   chan_8a = chan_8a_value (signed s16, pan-LFO accumulator)
##
## Output: slot.vol_staging_l / vol_staging_r (clamped 0..0x3FFF).
##
## Pan polynomial split (L80017220-L800172A0):
##   pan_base = clamp(0x4000 + chan_8a + pan, 0, 0x7F00)
##   if pan_base < 0x4000: a0_split = pan_base       (case A: L = poly_2, R = poly_1)
##   else:                 a0_split = 0x8000 - pan_base (case B: L = poly_1, R = poly_2)
##   poly_1 = (45 * a0_split) << 9 >> 14    ≈ a0 * 1.40625
##   poly_2 = 0x7F00 - (37 * a0_split) << 8 >> 14  ≈ 0x7F00 - a0 * 0.578

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(channel: _CH, slot: _SS, master_vol: int) -> void:
	# env_sample: signed sum of chan_98 (dynamics) + chan_88 (vol-LFO),
	# clamped to non-negative s15 range.
	var chan_98_u16: int = (channel.expression_acc_s32 >> 16) & 0xFFFF
	var chan_98_signed: int = chan_98_u16 - 0x10000 if chan_98_u16 >= 0x8000 else chan_98_u16
	var chan_88_u16: int = channel.chan_88_value & 0xFFFF
	var chan_88_signed: int = chan_88_u16 - 0x10000 if chan_88_u16 >= 0x8000 else chan_88_u16
	var env_sample: int = clampi(chan_98_signed + chan_88_signed, 0, 0x7FFF)
	var chan_92: int = channel.chan_92_value
	var voice_gated: int = (chan_92 * env_sample) >> 15
	var base_vol: int = (master_vol * voice_gated) >> 16
	# Pan: FFT smd_pan (0xE8) writes chan+0x92 = byte<<8, then the vol
	# formula reads it via `lh` at PC 0x80017210 — a signed 16-bit
	# read. Iter-54 split this off from the SFX-conflated pan_offset_ae
	# field; music's pan baseline now lives in chan_92_pan_baseline
	# (default 0x4000 = center, so primary channels without an explicit
	# 0xE8 dispatch get the FFT-typical center default instead of
	# hard-left case-A from a 0 read). See
	# MUSIC_ITER54_STEREO_PAN_BASELINE.md.
	var pan_u16: int = channel.chan_92_pan_baseline & 0xFFFF
	var pan_signed: int = pan_u16 - 0x10000 if pan_u16 >= 0x8000 else pan_u16
	var chan_8a_u16: int = channel.chan_8a_value & 0xFFFF
	var chan_8a_signed: int = chan_8a_u16 - 0x10000 if chan_8a_u16 >= 0x8000 else chan_8a_u16
	# FFT pan_base (PC 0x80017210-0x80017220): direct sum of chan_base+0x92
	# (smd_pan output = channel.pan_offset_ae per iter-12), chan_base+0x8C
	# (pan-LFO mode-2 accumulator = channel.chan_8a_value), and entity+0xAE
	# (never written in SCUS/BATTLE.BIN, empirically 0 — omitted). No
	# hardcoded center bias. See MUSIC_ITER13_PAN_BASELINE_FIX.md.
	var pan_base: int = clampi(pan_signed + chan_8a_signed, 0, 0x7F00)
	var a0_split: int
	var case_b: bool
	if pan_base < 0x4000:
		a0_split = pan_base
		case_b = false
	else:
		a0_split = 0x8000 - pan_base
		case_b = true
	var poly_1: int = ((45 * a0_split) << 9) >> 14
	var poly_2: int = 0x7F00 - (((37 * a0_split) << 8) >> 14)
	var vol_l_weight: int
	var vol_r_weight: int
	if case_b:
		vol_l_weight = poly_1
		vol_r_weight = poly_2
	else:
		vol_l_weight = poly_2
		vol_r_weight = poly_1
	slot.vol_staging_l = clampi((vol_l_weight * base_vol) >> 15, 0, 0x3FFF)
	slot.vol_staging_r = clampi((vol_r_weight * base_vol) >> 15, 0, 0x3FFF)
	# FFT PC 0x8001732C-30 — vol formula epilogue unconditionally sets
	# bit 0x1 of slot.walker_flag_word (= WALKER_FLAG_VOL_LR_RAW) so the
	# next walker pass fires FUN_8001B428 and writes vol_l/vol_r to SPU.
	# Every per-note KON's vol_register write in PCSX is downstream of
	# this. See docs/MUSIC_ITER14_VOL_LR_RAW_WALKER_ARM.md.
	slot.walker_flag_word |= _SS.WALKER_FLAG_VOL_LR_RAW
	# Music-side vol-formula probe emits. Mirror the PCSX-side
	# probe_vol_inputs + probe_vol_lr_staging that both fire at
	# BP 0x80017328 (FUN_80017118 vol-formula end, `sh a1, 0x3c(s0)`).
	# This surfaces the iter-12 pan-direction reversal (L/R swapped on
	# music: PCSX has L > R for voice 5 cad=1, Godot has L < R) by
	# pairing each side's pan inputs (chan_8a / chan_92 / pool_ae) and
	# vol_l/vol_r outputs. The chan_8a value is the suspect off-by-two
	# field — FFT's pan-LFO mode-2 writes chan+0x8C but Godot writes
	# chan_8a_value (chan+0x8A); a pcsx_chan_8a != 0 / godot_chan_8a == 0
	# divergence would confirm the field-naming bug. See
	# docs/MUSIC_ITER12_PAN_SCALE_FIX.md "what's still wrong: pan
	# direction" + "hypothesis for direction reversal".
	_ProbeCounters.vol_inputs_music += 1
	_Trace.emit("vol_inputs", {
		"call_index": _ProbeCounters.vol_inputs_music,
		"chan_88":    channel.chan_88_value & 0xFFFF,
		"chan_8a":    channel.chan_8a_value & 0xFFFF,
		# chan_90 (probe slot for s0+0x90 = chan_base+0x92) is the smd_pan
		# output. Iter-54: read from chan_92_pan_baseline (renamed off
		# the SFX-conflated pan_offset_ae).
		"chan_90":    channel.chan_92_pan_baseline & 0xFFFF,
		"chan_92":    channel.chan_92_value & 0xFFFF,
		"chan_98":    (channel.expression_acc_s32 >> 16) & 0xFFFF,
		"pool_96":    master_vol & 0xFFFF,
		# pool_ae (probe slot for s2+0xae = entity+0xAE) is never written
		# in SCUS or BATTLE.BIN — empirically 0 across MUSIC_34/MUSIC_28.
		# Iter-13 fix: was wrongly sourced from channel.pan_offset_ae.
		"pool_ae":    0,
	})
	_ProbeCounters.vol_lr_staging_music += 1
	_Trace.emit("vol_lr_staging", {
		"call_index": _ProbeCounters.vol_lr_staging_music,
		"vol_l":      slot.vol_staging_l & 0xFFFF,
		"vol_r":      slot.vol_staging_r & 0xFFFF,
	})
