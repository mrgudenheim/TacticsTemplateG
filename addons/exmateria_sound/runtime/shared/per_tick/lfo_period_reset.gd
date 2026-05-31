class_name SharedPerTickLfoPeriodReset
## FFT analog: per-tick LFO sub-slot **period_reset** at
##              PC 0x800157AC..0x80015804
##
## Fires inside per_channel_tick (FUN_8001517C) when the s4 != 0 gate
## at PC 0x80015718 passes (a Note byte dispatched this tick AND
## chan_word_0 bit 0x400 was set before the per-tick clear). Snaps
## active LFO sub-slots back to a clean baseline so triangle direction
## resets to +step_source instead of drifting through the swap path's
## `(dir | 0x4) ^ 0x8` toggle.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")


static func apply(channel: _CH) -> void:
	for sub_idx in range(_CH.LFO_SUB_SLOT_COUNT):
		# FFT period_reset gate at PC 0x800157B4-C0:
		#   andi v0, a1, 0x1 ; beq v0, zero, SKIP  ← bit 0 check
		#   andi v0, a1, 0x2 ; beq v0, zero, SKIP  ← bit 1 check
		# a1 is chan+0xFE (FFT-side combined `dir_flags` halfword).
		# Godot SPLITS this halfword into `lfo_sub_active` (bit 0) and
		# `lfo_sub_dir_flags` (bits 1+). So the FFT `bit 0` check is the
		# `lfo_sub_active != 0` check; the FFT `bit 1` check stays a
		# `dir_flags & 0x2` check. Pre-iter-50 the gate read
		# `(dir & 0x3) != 0x3` which assumed dir_flags carried bit 0
		# (FFT-style combined halfword), so it ALWAYS skipped on Godot —
		# voice 10's pitch-LFO period_reset never fired mid-run.
		if channel.lfo_sub_active[sub_idx] == 0:
			continue
		var dir: int = channel.lfo_sub_dir_flags[sub_idx]
		if (dir & 0x2) == 0:
			continue
		# FFT PC 0x800157D0: sw zero, -0x1A(a0) — clear sub-slot accumulator.
		# FFT PC 0x800157D4: sh t0, -0x0E(a0)  — countdown = t0 (=1).
		channel.lfo_sub_accumulator[sub_idx] = 0
		channel.lfo_sub_countdown[sub_idx] = 1
		# FFT PC 0x800157D8: sh v0, -0x0A(a0) — delay_counter = delay_reload
		#   (v0 was loaded from chan+0xF6 = delay_reload at PC 0x800157C8).
		# FFT PC 0x800157E4: sh v1, -0x06(a0) — depth = depth_reload
		#   (v1 was loaded from chan+0xFA = depth_reload at PC 0x800157CC).
		# Without these two resets, voice 10's pitch-LFO depth stays at 256
		# forever instead of returning to depth_reload (= 8 per the iter-49
		# 0xD7 dispatch trace) at each Note re-arm. See
		# MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md §4 follow-up + iter-49 voice
		# 10 LFO state divergence (PCSX depth=8 vs Godot depth=256 stuck).
		channel.lfo_sub_delay_counter[sub_idx] = channel.lfo_sub_delay_reload[sub_idx]
		channel.lfo_sub_depth[sub_idx] = channel.lfo_sub_depth_delta[sub_idx]
		channel.lfo_sub_dir_flags[sub_idx] = dir & ~0xC
		channel.channel_word_0 |= 0x100
