class_name SharedOpPitchLfoInit
## FFT analog: smd_op_d8_pitch_lfo_init @ 0x80016420
##                (opcode 0xD8)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## PitchLFO_Init (FUN_80016420 / jumptable 0x80028C6C).
	## Per disasm L80016438..L800164B0 + FUN_80016BF8 with a2=3:
	##   step_base = (rate^2 << 14)        (observed-undivided
	##                                      per probe)
	##   period_reload = step_param  (chan+0xF2)
	##   countdown init via FUN_80016DC0 = 1 (first tick triggers
	##                                       swap)
	## Probe d9_lfo_001 captured chan+0xEC = (rate^2 << 14)
	## UNDIVIDED for cure params 04 55 01 → chan+0xEC =
	## 0x070E4000 = 7225<<14. We follow observed (no-division)
	## until source resolves.
	## 3 params: param[0]=step(u8), param[1]=rate(s8), param[2]=
	## period byte (stored chan+0xF6, role TBD).
	if op.params.size() >= 3:
		var step_p: int = op.params[0] & 0xFF
		var rate_s8: int = op.params[1] & 0xFF
		if rate_s8 >= 0x80: rate_s8 -= 0x100
		var rate_sq: int = rate_s8 * rate_s8
		var a0_in: int = (rate_sq << 14) & 0xFFFFFFFF
		# Disasm of FUN_80016BF8 with a2=3 would divide by step_p,
		# but observed savestate skips this. Use observed
		# (no-division).
		var step_base: int = a0_in
		# Silent driver doesn't activate LFO on the audible
		# voice.
		if voice_writes:
			slot.lfo_active = true
		# Iter-35: sub-slot 0 unified onto lfo_sub_*[0]. dir_flags bit
		# 0x8 set (was lfo_dir_negate=true). See
		# MUSIC_ITER35_PITCH_LFO_SUBSLOT0_UNIFICATION.md.
		channel.lfo_sub_step_source[0] = step_base
		channel.lfo_sub_inner_reload[0] = max(1, step_p)
		# Iter-37 Bug C: FFT PC 0x80016484-88 writes chan+0xFA = 0x100,
		# then period_reset (PC 0x80016DE8) mirrors chan+0xF8 = chan+0xFA.
		# Required after Bug B dropped the default to 0.
		channel.lfo_sub_depth[0] = 0x100
		channel.lfo_sub_depth_delta[0] = 0x100
		# FFT PC 0x800164B0 (delay slot of jal period_reset) writes
		# chan+0xF6 = D8 param[2]; period_reset PC 0x80016DE0 mirrors
		# chan+0xF4 = chan+0xF6.
		var d8_param2_sfx: int = op.params[2] & 0xFF
		channel.lfo_sub_delay_reload[0] = d8_param2_sfx
		channel.lfo_sub_delay_counter[0] = d8_param2_sfx
		# FFT order on the D9-init tick: opcode walk (D9 →
		# AC → 94 → Note pre-pass) THEN LFO advance, so the
		# initial swap from state+0x10=1 (FUN_80016DC0
		# L12552) fires on the SAME tick the Note pitch
		# register is written. Our dispatcher runs LFO
		# advance before opcode walk, so we replicate by
		# firing the first swap inline at D9 init: set
		# pitch_bend = +step, mark dir_negate=true so the
		# next swap produces -step, and load countdown with
		# the full period for the second swap.
		channel.lfo_sub_accumulator[0] = step_base
		channel.lfo_sub_dir_flags[0] = (channel.lfo_sub_dir_flags[0] & ~0x4) | 0x8
		var output_hi_init: int = step_base >> 16
		if output_hi_init > 0x7FFF: output_hi_init = 0x7FFF
		elif output_hi_init < -0x8000: output_hi_init = -0x8000
		channel.pitch_bend = output_hi_init
		channel.lfo_sub_countdown[0] = channel.lfo_sub_inner_reload[0]
