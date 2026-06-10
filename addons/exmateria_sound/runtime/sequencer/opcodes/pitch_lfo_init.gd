class_name SequencerOpPitchLfoInit
## FFT analog: smd_op_d8_pitch_lfo_init @ 0x80016420
##                (opcode 0xD8)
##
## Pass 7.D.d — Godot music now uses the GDScript FFT-faithful LFO
## engine (shared/per_tick/advance_lfo.gd), matching SFX. Drops the
## previous mixer.init_voice_pitch_lfo call into C++ (that engine is
## the DAW's port and stays in src/shared/ for the VST3 build, but
## Godot music doesn't reach into it anymore).
##
## Mirrors shared/opcodes/pitch_lfo_init.gd body — disasm-traced
## through LAB_80016438..L800164B0 + FUN_80016BF8 + FUN_80016DC0,
## probe-verified on the SFX side (probe d9_lfo_001).

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null or ts.voice_idx < 0:
		return
	if params.size() < 3:
		return
	var step_p: int = params[0] & 0xFF
	var rate_s8: int = params[1] & 0xFF
	if rate_s8 >= 0x80:
		rate_s8 -= 0x100
	var rate_sq: int = rate_s8 * rate_s8
	# FFT smd_op_d8 PC 0x80016464-0x80016470 calls pitch_lfo_step_calc
	# with hardcoded a2=3. pitch_lfo_step_calc at PC 0x80016C40 with
	# a2=3 ALWAYS divides by period (`div a0, a1; mflo a0`). The
	# previous "observed no division" comment cited probe d9_lfo_001
	# which is for 0xD9 — that opcode passes a2 = wf_idx and skips
	# division when wf_idx < 2 (PC 0x80016C18 early-out). 0xD8 always
	# divides. Iter-21 fix: divide step_base by step_p (period).
	# See docs/MUSIC_ITER21_PITCH_LFO_D8_DIVIDE_FIX.md.
	var step_base_pre: int = (rate_sq << 14) & 0xFFFFFFFF
	var step_base: int = (step_base_pre / max(1, step_p)) if step_p != 0 else 0
	var channel = ts.ctx.channel
	var slot = ts.ctx.slot
	slot.lfo_active = true
	# Iter-35: sub-slot 0 unified onto lfo_sub_*[0] (was flat lfo_*
	# fields). FFT chan+0xE0..0xFF mapping:
	#   sub_0+0x08 step_source ← step_base                     (lfo_sub_step_source[0])
	#   sub_0+0x12 inner_reload ← max(1, step_p)               (lfo_sub_inner_reload[0])
	#   sub_0+0x1D jumptable_idx = 3 (pitch_accum_callback)    (lfo_sub_callback_idx[0])
	#   sub_0+0x1E active_dir = 3 (bits 0+1)                   (lfo_sub_active[0]=1, dir_flags[0] bit 0x2)
	#   sub_0+0x04 accumulator = 0                             (lfo_sub_accumulator[0])
	#   sub_0+0x08 step_current = 0                            (lfo_sub_step_current[0])
	#   sub_0+0x10 countdown = 1                               (lfo_sub_countdown[0])
	# period_reset (PC 0x80016DC0) clears bits 0x4 / 0x8 of active_dir.
	# Iter-22 fix: wf_idx 3, not 1 (continuous accumulation triangle).
	# See docs/MUSIC_ITER22_PITCH_ACCUM_CALLBACK_WF3.md +
	# MUSIC_ITER34_LFO_MODE_FLAGS_PERIOD_RESET.md +
	# MUSIC_ITER35_PITCH_LFO_SUBSLOT0_UNIFICATION.md.
	channel.lfo_sub_step_source[0] = step_base
	channel.lfo_sub_inner_reload[0] = max(1, step_p)
	channel.lfo_sub_callback_idx[0] = 3
	channel.lfo_sub_active[0] = 1
	channel.lfo_sub_dir_flags[0] = 0x2
	channel.lfo_sub_accumulator[0] = 0
	channel.lfo_sub_step_current[0] = 0
	channel.lfo_sub_countdown[0] = 1
	# Iter-37 Bug C: FFT PC 0x80016484-88 writes chan+0xFA = 0x100
	# (depth_reload); pitch_lfo_period_reset PC 0x80016DE8 then mirrors
	# chan+0xF8 = chan+0xFA. Required once Bug B drops the default to 0.
	channel.lfo_sub_depth[0] = 0x100
	channel.lfo_sub_depth_delta[0] = 0x100
	# FFT PC 0x800164B0 (D8 delay-slot of jal period_reset) writes
	# chan+0xF6 = D8 param[2]; period_reset PC 0x80016DE0 mirrors
	# chan+0xF4 = chan+0xF6.
	var d8_param2: int = params[2] & 0xFF
	channel.lfo_sub_delay_reload[0] = d8_param2
	channel.lfo_sub_delay_counter[0] = d8_param2
	channel.pitch_bend = 0
	# Arm the prestage bit so the next tick's pitch_staging recompute
	# fires (Sequencer.tick reads channel_word_1 after advance_lfo).
	channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
