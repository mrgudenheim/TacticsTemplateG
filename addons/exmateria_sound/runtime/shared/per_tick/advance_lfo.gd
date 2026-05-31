class_name SharedPerTickAdvanceLfo
## FFT analog: lfo_handler_tick @ LAB_80017690 + sub-slot iterator at
##              PC 0x800174E4..0x800175E0
##
## Pre-IRQ LFO state advance. Called every dispatcher.tick() before
## the opcode walker. Decrements per-channel + per-sub-slot countdowns,
## fires waveform callbacks at zero, accumulates step contributions
## into chan+0x88 / chan+0x8a, sets pitch / vol prestage flags.
##
## Returns true iff a mode-1 triangle swap fired this call — caller
## tracks `lfo_swap_fired` for downstream prestage decisions.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(channel: _CH, slot: _SS, voice_writes: bool, cadence_fired: bool) -> bool:
	## (1c) PitchLFO advance — port of LAB_80017690. Decrements countdown;
	## on wrap, swaps direction and updates current output. The output's
	## UPPER halfword (>> 16, sign-preserving) is added to chan+0x88 =
	## channel.pitch_bend, which feeds the formula.
	## Per LAB_800175A4 + LAB_80017568: chan+0x88 = (chan+0x88_pre + (output >> 16))
	## but pre-pass clears chan+0x88 before LFO add, so net chan+0x88 =
	## output >> 16.
	## Returns true iff a swap fired this call (caller-tracked
	## `lfo_swap_fired`).
	var lfo_swap_fired: bool = false
	# FFT per_channel_tick PC 0x800151BC pre-clears chan+0x88 and
	# chan+0x8a every cadence before lfo_handler_tick runs. The mode-1
	# and mode-2 stores at PC 0x800175C8 / 0x800175DC are `addu`-based
	# accumulators, so the net per-tick value equals the sub-slot
	# callback contribution(s) for that tick. Mirror that here at the
	# top of _advance_lfo (mode-0's chan+0x86 path bypasses chan+0x86
	# entirely in Godot — pitch_bend is written directly — so we only
	# clear the mode-1/mode-2 outputs).
	if cadence_fired:
		channel.chan_88_value = 0
		channel.chan_8a_value = 0
	# Silent driver doesn't run LFO advance — slot.lfo_active is the
	# audible pair's flag and silent driver's swaps would clobber the
	# audible voice's pitch_bend.
	# FFT lfo_handler_tick PC 0x800174EC `andi v0, v0, 0x1; beq v0, zero,
	# LAB_800175e4` — gate on bit 0x1 of chan+0xFE (lfo_mode_flags).
	# 0xDB FlagClear (PC 0x800165FC) clears this bit, disabling the LFO
	# sub-slot for subsequent ticks. cure_no_music's 0xDB at cad 361
	# zeroes slot_b's chan+0xFE bit 0x1 — PCSX's LFO then skips slot_b,
	# so chan+0x88 stays at the per_channel_tick cleared 0 from then on.
	# FFT-aligned outer gate (CAD_497_WF_IDX_6_PRNG_DESYNC.md §5.1).
	# Replaces the prior `slot.lfo_active` gate with `channel.channel_word_0
	# != 0` to mirror lfo_handler_tick PC 0x800174D0 exactly. EndBar
	# (PC 0x800159CC equivalent in _op_endbar) clears chan_word_0, so
	# this naturally disarms the LFO advance once a channel's bytecode
	# terminates — matching FFT's behavior. The `voice_writes` gate is a
	# Godot defensive lift that PCSX doesn't have; silent drivers don't
	# write `pitch_bend` to the audible voice on Godot, so dropping their
	# PRNG advance here is harmless for audio but matters for PRNG
	# parity. Keep it for now; if PCSX-side prng-step pairing confirms
	# FFT advances silent-driver PRNG, drop it then.
	# Iter-35: sub-slot 0 unified onto lfo_sub_*[0]; bit 0x1 of chan+0xFE
	# is lfo_sub_active[0]. See
	# MUSIC_ITER35_PITCH_LFO_SUBSLOT0_UNIFICATION.md.
	if voice_writes and cadence_fired \
			and channel.channel_word_0 != 0 \
			and channel.lfo_sub_active[0] != 0:
		# FFT lfo_handler_tick PC 0x800174F8: `lhu v0, -0x8(s1)` reads
		# chan+0xF4 (sub-slot delay_counter). When non-zero, decrement
		# and skip callback this tick (early-return at PC 0x80017514
		# `j LAB_800175E4`). Iter-35: this gate was previously missing
		# on sub-slot 0; added here for FFT-faithful behavior.
		if channel.lfo_sub_delay_counter[0] != 0:
			channel.lfo_sub_delay_counter[0] -= 1
		else:
			# FFT lfo_handler_tick body. pitch_lfo_period_reset (called
			# by D9) DOES NOT initialize chan+0xF4 (delay_counter) — it
			# stays at the slot's zero-init value. So when delay_counter
			# is 0, every tick runs the callback path.
			#
			# The DIRECTION REVERSAL is a separate countdown inside the
			# callback (LAB_80017690 chan+0x10): every period_reload ticks,
			# the callback flips sign of the step. Between direction flips,
			# the step value is constant, so chan+0x88 stays at the same
			# value (after the per-tick clear at PC 0x800151BC + per-tick
			# mode-0 add via accumulator pattern).
			var _wf_idx: int = channel.lfo_sub_callback_idx[0]
			# wf_idx=6 (FUN_8001780C) advances the engine PRNG once at the
			# top of every callback invocation regardless of countdown
			# (PC 0x80017818 — the unconditional JAL whose return value is
			# clobbered by the lhu at PC 0x80017820). That side effect must
			# happen even on ticks where the accumulator doesn't update.
			if _wf_idx == 6:
				_LfoPrng.step()
			channel.lfo_sub_countdown[0] -= 1
			if channel.lfo_sub_countdown[0] <= 0:
				channel.lfo_sub_countdown[0] = channel.lfo_sub_inner_reload[0]
				if _wf_idx == 3:
					# LAB_80017744 — pitch_accum_callback (FFT 0xD8 default).
					# FFT period boundary (PC 0x80017760-0x800177A4):
					#   countdown = inner_reload
					#   if active_dir bit 0x4: countdown *= 2
					#   step_current = (bit 0x8 set) ? -step_source : +step_source
					#   active_dir |= 0x4; active_dir ^= 0x8
					# See docs/MUSIC_ITER22_PITCH_ACCUM_CALLBACK_WF3.md +
					# MUSIC_ITER34_LFO_MODE_FLAGS_PERIOD_RESET.md.
					var dir0: int = channel.lfo_sub_dir_flags[0]
					if (dir0 & 0x4) != 0:
						channel.lfo_sub_countdown[0] = channel.lfo_sub_inner_reload[0] * 2
					# else: keep countdown = inner_reload (already assigned above)
					var src0: int = channel.lfo_sub_step_source[0]
					if (dir0 & 0x8) != 0:
						channel.lfo_sub_step_current[0] = -src0
					else:
						channel.lfo_sub_step_current[0] = src0
					channel.lfo_sub_dir_flags[0] = (dir0 | 0x4) ^ 0x8
				elif _wf_idx == 4 or _wf_idx == 5:
					# LAB_800177C0 swap-path (scus_disassembly.txt:13742..13747).
					# On countdown-zero: accumulator resets to 0 and countdown
					# reloads. The per-tick `addu` in the non-swap path is what
					# normally ramps the accumulator; this swap branch is the
					# reset boundary. wf_idx=4 and 5 both route to LAB_800177C0
					# per PTR_LAB_80028F54[4]/[5]. Voice 19's D9 (byte2=4) on
					# haste_no_music hits wf_idx=4 — without this branch Godot
					# fell through to the swap-with-negation default below,
					# producing ±step alternation instead of the
					# sawtooth-with-reset that PCSX produces. See
					# V19_WF_IDX_4_SAWTOOTH_FIX.md for the disasm trace and
					# per-IRQ probe data.
					channel.lfo_sub_accumulator[0] = 0
				elif _wf_idx == 0:
					# LAB_80017648 — square-wave callback. Used by reraise_no_
					# music voice 21 (D9 04 28 00 → wf_idx=0). See dispatcher
					# comments archive for full FFT trace.
					if channel.lfo_sub_accumulator[0] != 0:
						channel.lfo_sub_accumulator[0] = 0
					else:
						channel.lfo_sub_accumulator[0] = channel.lfo_sub_step_source[0]
				elif _wf_idx == 6 or _wf_idx == 7:
					# FUN_80017878 (wf_idx=7) and FUN_8001780C (wf_idx=6) —
					# noise pitch-LFO callbacks. Both pull a fresh PRNG
					# sample, multiply by step_source-derived divisor, and
					# overwrite the accumulator.
					var prng_val: int = _LfoPrng.step()
					var step_src: int = channel.lfo_sub_step_source[0]
					var acc: int
					if _wf_idx == 7:
						var step_div_7: int = _LfoStepCalc.sra_s32(step_src, 14)
						acc = step_div_7 * prng_val - step_src
					else:
						var step_div_6: int = _LfoStepCalc.sra_s32(step_src, 15)
						acc = step_div_6 * prng_val
					acc = acc & 0xFFFFFFFF
					if acc >= 0x80000000:
						acc -= 0x100000000
					channel.lfo_sub_accumulator[0] = acc
				else:
					# wf_idx == 1 (LAB_80017690 mode-1 swap) and all unmodeled
					# indices fall through to triangle-via-direction-flip.
					lfo_swap_fired = true
					var step: int = channel.lfo_sub_step_source[0]
					var _dir_pre: int = channel.lfo_sub_dir_flags[0]
					var _dir_negate_pre: bool = (_dir_pre & 0x8) != 0
					if _dir_negate_pre:
						step = -step
					channel.lfo_sub_accumulator[0] = step
					channel.lfo_sub_dir_flags[0] = _dir_pre ^ 0x8
					# probe_lfo_swap (Layer 5 synthesis). Mirror of FFT BP
					# @ 0x800176CC — the `sw a1, 0x4(a0)` swap commit
					# inside LAB_80017690 (mode-1 swap callback). Gated on
					# the SFX D9 wf_idx=1 selection (derived from
					# lfo_sub_callback_idx[0]).
					if channel.lfo_sub_callback_idx[0] == 1:
						_ProbeCounters.lfo_swap += 1
						_Trace.emit("lfo_swap", {
							"call_index": _ProbeCounters.lfo_swap,
							"lfo_output_signed": channel.lfo_sub_accumulator[0],
							"dir_negate_pre": 1 if _dir_negate_pre else 0,
							"channel_idx": channel.channel_idx,
							"lfo_wf_idx": channel.lfo_sub_callback_idx[0],
						})
					# Pre-iter-35 the wf=1 swap branch set
					# `lfo_first_elapsed = true` but the iter-34 mirror to
					# `lfo_mode_flags` was wf=3-only. PCSX confirms FFT's
					# wf=1 swap callback (LAB_80017690) DOES NOT set bit
					# 0x4 of chan+0xFE — cure_no_music 0xDB @ cad 361 reads
					# chan+0xFE = 3 (bits 0+1 only). Iter-35: don't set
					# bit 0x4 here.
			else:
				# Non-swap-tick path: wf_idx=4/5 sawtooth accumulates every tick.
				if _wf_idx == 4 or _wf_idx == 5:
					var new_acc: int = channel.lfo_sub_accumulator[0] + channel.lfo_sub_step_source[0]
					new_acc = new_acc & 0xFFFFFFFF
					if new_acc >= 0x80000000:
						new_acc -= 0x100000000
					channel.lfo_sub_accumulator[0] = new_acc
			# wf_idx=3 pitch_accum_callback (LAB_800177A8) — accumulator
			# += step_current runs UNCONDITIONALLY on every tick (both
			# period-boundary and non-boundary paths fall through to
			# the same accumulator update at PC 0x800177A8-0x800177BC).
			# Placed after the if/else so it fires regardless.
			if _wf_idx == 3:
				var acc3: int = channel.lfo_sub_accumulator[0] + channel.lfo_sub_step_current[0]
				acc3 = acc3 & 0xFFFFFFFF
				if acc3 >= 0x80000000:
					acc3 -= 0x100000000
				channel.lfo_sub_accumulator[0] = acc3
			# Per-tick LFO dispatch write — FFT mode 0 (LAB_8001759C..B0)
			# `addu v0, v0, a0; sh v0, 0x86(s0)` runs every tick. Depth
			# scaling ports fft_spu_lfo_tools.cpp lines 122-128:
			#   if (depth < 0x100): scaled = (accum >> 8) * depth >> 16;
			#                       depth += depth_delta
			#   else:               scaled = accum >> 16
			# Default depth is 256 (= 0x100, the no-scale branch). 0xD7
			# PitchLfoDepth + 0xE3 VolLfoDepth + 0xEB PanLfoDepth + 0xF2
			# dynamic-depth set values < 0x100 to trigger the fade-in.
			var output_pre: int
			if channel.lfo_sub_depth[0] < 0x100:
				output_pre = (channel.lfo_sub_accumulator[0] >> 8) * channel.lfo_sub_depth[0]
				output_pre = output_pre >> 16
				channel.lfo_sub_depth[0] = (channel.lfo_sub_depth[0] + channel.lfo_sub_depth_delta[0])
			else:
				output_pre = channel.lfo_sub_accumulator[0] >> 16
			var output_hi: int = output_pre
			if output_hi > 0x7FFF: output_hi = 0x7FFF
			elif output_hi < -0x8000: output_hi = -0x8000
			channel.pitch_bend = output_hi
			# FFT lfo_handler_tick mode-0 path (PC 0x800175A4-0x800175E0) sets
			# chan_word_1 |= 0x200 (PITCH_PRESTAGE).
			channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
	# Sub-slot iterator (modes 1/2 for vol/pan LFO).
	if cadence_fired and channel.channel_word_0 != 0:
		for sub_idx in range(_CH.LFO_SUB_SLOT_COUNT):
			if channel.lfo_sub_active[sub_idx] == 0:
				continue
			var mode: int = channel.lfo_sub_mode[sub_idx]
			if mode != 1 and mode != 2:
				continue
			var cb_idx: int = channel.lfo_sub_callback_idx[sub_idx]
			var acc: int = channel.lfo_sub_accumulator[sub_idx]
			if cb_idx == 2:
				# LAB_800176E4 — simpler swap callback than triangle.
				var cd_post_idx2: int = channel.lfo_sub_countdown[sub_idx] - 1
				if cd_post_idx2 != 0:
					channel.lfo_sub_countdown[sub_idx] = cd_post_idx2
				else:
					var dir_idx2: int = channel.lfo_sub_dir_flags[sub_idx]
					var src_idx2: int = channel.lfo_sub_step_source[sub_idx]
					if (dir_idx2 & 0x8) != 0:
						src_idx2 = -src_idx2
					channel.lfo_sub_countdown[sub_idx] = channel.lfo_sub_inner_reload[sub_idx]
					channel.lfo_sub_step_current[sub_idx] = src_idx2
					channel.lfo_sub_dir_flags[sub_idx] = dir_idx2 ^ 0x8
				acc = (acc + channel.lfo_sub_step_current[sub_idx]) & 0xFFFFFFFF
			elif cb_idx == 4 or cb_idx == 5:
				# LAB_800177c0 — sawtooth.
				var cd_post_sw: int = channel.lfo_sub_countdown[sub_idx] - 1
				if cd_post_sw == 0:
					channel.lfo_sub_accumulator[sub_idx] = 0
					channel.lfo_sub_countdown[sub_idx] = channel.lfo_sub_inner_reload[sub_idx]
					acc = 0
				else:
					channel.lfo_sub_countdown[sub_idx] = cd_post_sw
					acc = (acc + channel.lfo_sub_step_source[sub_idx]) & 0xFFFFFFFF
			else:
				# pitch_accum_callback PC 0x80017744..0x800177B8.
				var cd_post: int = channel.lfo_sub_countdown[sub_idx] - 1
				if cd_post != 0:
					channel.lfo_sub_countdown[sub_idx] = cd_post
				else:
					var reload: int = channel.lfo_sub_inner_reload[sub_idx]
					var dir: int = channel.lfo_sub_dir_flags[sub_idx]
					var new_countdown: int = reload
					if (dir & 0x4) != 0:
						new_countdown = reload << 1
					channel.lfo_sub_countdown[sub_idx] = new_countdown
					var src: int = channel.lfo_sub_step_source[sub_idx]
					if (dir & 0x8) != 0:
						channel.lfo_sub_step_current[sub_idx] = -src
					else:
						channel.lfo_sub_step_current[sub_idx] = src
					channel.lfo_sub_dir_flags[sub_idx] = (dir | 0x4) ^ 0x8
				acc = (acc + channel.lfo_sub_step_current[sub_idx]) & 0xFFFFFFFF
			if acc >= 0x80000000: acc -= 0x100000000
			channel.lfo_sub_accumulator[sub_idx] = acc
			var contribution: int = _LfoStepCalc.sra_s32(acc, 16)
			if mode == 1:
				channel.chan_88_value = (channel.chan_88_value + contribution) & 0xFFFF
			else:
				channel.chan_8a_value = (channel.chan_8a_value + contribution) & 0xFFFF
			channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE
	return lfo_swap_fired
