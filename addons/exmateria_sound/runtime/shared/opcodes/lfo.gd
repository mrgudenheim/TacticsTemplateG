class_name SharedOpLfo
## FFT analog: smd_op_d9_lfo @ FUN_800164D4
##                (opcode 0xD9)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	_ProbeCounters.opcode_d9_lfo += 1
	_Trace.emit("opcode_d9_lfo", {
		"call_index": _ProbeCounters.opcode_d9_lfo,
		"d9_byte0": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"d9_byte1": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
		"d9_byte2": (op.params[2] if op.params.size() > 2 else 0) & 0xFF,
	})
	## Real 0xD9 handler = FUN_800164D4 (jumptable 0x80028C70).
	## Differs from 0xD8/FUN_80016420:
	##   - rate sign IS preserved: lo = -rate² for rate<0 (vs
	##     0xD8 where rate² is always positive). Disasm
	##     L80016510-L8001651C: bgez+delay-slot mult a0,a0 =
	##     rate²; if rate<0 then v0=-rate; mult a0,v0 overwrites
	##     lo with rate*-rate = -rate².
	##   - param[2] is bit-decoded:
	##       bit 0x10 = mode flag (chan+0xFE = 1 vs 3)
	##       low 0x0F  = waveform_index, indexes
	##                  PTR_LAB_80028F54[wf_idx] for chan+0xE0
	##                  (LFO advance fn ptr — different
	##                  waveform per idx)
	##   - chan+0xF6 = 0 (vs 0xD8: chan+0xF6 = param[2] raw)
	##   - chan+0xFD = waveform_index (vs 0xD8: chan+0xFD = 3)
	##   - FUN_80016BF8 called with a2 = waveform_index (vs
	##     0xD8 a2=3).
	## Godot's LFO model has 6 fields — no waveform_table_ptr,
	## no mode_flag, no wf_idx byte. The only Godot-modelable
	## difference is rate-sign preservation. The bit-decoded
	## param[2] semantics + waveform-table-driven advance are
	## not modeled here.
	if op.params.size() >= 3:
		var step_p_d9: int = op.params[0] & 0xFF
		var rate_s8_d9: int = op.params[1] & 0xFF
		if rate_s8_d9 >= 0x80: rate_s8_d9 -= 0x100
		var rate_sq_d9: int = rate_s8_d9 * rate_s8_d9
		# Sign-preserving (FUN_800164D4): negate for rate<0
		var lo_d9: int = rate_sq_d9 if rate_s8_d9 >= 0 else -rate_sq_d9
		var a0_in_d9: int = (lo_d9 << 14)
		# Mask to MIPS 32-bit signed register width
		a0_in_d9 = a0_in_d9 & 0xFFFFFFFF
		if a0_in_d9 >= 0x80000000:
			a0_in_d9 -= 0x100000000
		var p2_d9: int = op.params[2] & 0xFF
		var mode_bit_d9: int = p2_d9 & 0x10
		var wf_idx_d9: int = p2_d9 & 0x0F
		var step_base_d9: int = a0_in_d9
		if voice_writes:
			slot.lfo_active = true
		# Iter-35: sub-slot 0 unified onto lfo_sub_*[0]. See
		# MUSIC_ITER35_PITCH_LFO_SUBSLOT0_UNIFICATION.md.
		channel.lfo_sub_step_source[0] = step_base_d9
		channel.lfo_sub_inner_reload[0] = max(1, step_p_d9)
		# Iter-37 Bug C: FFT PC 0x80016548-50 writes chan+0xFA = 0x100,
		# period_reset PC 0x80016DE8 mirrors chan+0xF8 = chan+0xFA.
		channel.lfo_sub_depth[0] = 0x100
		channel.lfo_sub_depth_delta[0] = 0x100
		# FFT PC 0x8001655C writes chan+0xF6 = 0 (D9 has no delay param),
		# period_reset PC 0x80016DE0 mirrors chan+0xF4 = chan+0xF6.
		channel.lfo_sub_delay_reload[0] = 0
		channel.lfo_sub_delay_counter[0] = 0
		# FFT pitch_lfo_period_reset (PC 0x80016DC0) clears sub+0x4
		# (accumulator) to 0 via `sw zero, 0x4(a0)`. For wf_idx 0
		# (LAB_80017648 — square wave) the accumulator value gates the
		# swap-toggle: starting at 0 → first swap sets to +step (matching
		# PCSX's 0/+step/0/+step square); starting at step_base produces
		# the inverted step/0/step/0 phase. Scope the FFT-correct init
		# to wf_idx 0; other wfs (1=triangle-via-direction-flip, 3, 6/7
		# noise) rely on the pre-existing step_base init to seed their
		# first-tick pitch_bend write at line 431-434, which fires
		# BEFORE the first countdown-driven swap. Setting these to 0
		# regresses voice 18/19 vol_register on reraise_no_music.
		if wf_idx_d9 == 0:
			channel.lfo_sub_accumulator[0] = 0
		else:
			channel.lfo_sub_accumulator[0] = step_base_d9
		# 0xD9 writes table[wf_idx] to FFT chan+0xE0 (sub-slot 0 callback
		# ptr) at PC 0x80016580 `sw v0, 0xe0(s1)`. wf_idx = param[2] & 0x0F
		# selects from PTR_LAB_80028F54:
		#   0 = LAB_80017648, 1 = LAB_80017690 (mode-1 swap — fires
		#   probe_lfo_swap BP at PC 0x800176CC), 2 = LAB_800176E4,
		#   3 = pitch_accum_callback, 4/5 = LAB_800177C0, 6 = FUN_8001780C,
		#   7 = FUN_80017878, 8+ = LAB_80017634.
		# Only wf_idx == 1 routes through LAB_80017690 — the only callback
		# whose body contains the PC 0x800176CC `sw a1, 0x4(a0)` that the
		# probe traps. The swap probe gate uses lfo_sub_callback_idx[0]==1
		# (iter-35: derived check, not a separate flag).
		channel.lfo_sub_callback_idx[0] = wf_idx_d9
		# probe_vol_prestage_lfo — mirrors the FFT per-tick handler at
		# L800157F0 that sets CHAN1_VOL_PRESTAGE once when chan+0xfe==3
		# (LFO mode 1 active). Empirically fires once per LFO init in
		# cure (the outer gate at L80015728 chan+0x4 & 0x4 is one-shot).
		# Emit the probe row at 0xD9 dispatch time matching FFT's first
		# per-tick iteration; values pair on lfo_mode_flags_pre=3.
		# D9 init writes chan+0xFE = (!mode_bit << 1) + 1 — 3 for cure
		# (mode_bit=0), 1 otherwise. Bit 0x1 → lfo_sub_active[0],
		# bit 0x2 → lfo_sub_dir_flags[0] bit 0x2 (no consumer in Godot
		# but tracked for probe parity).
		channel.lfo_sub_active[0] = 1
		channel.lfo_sub_dir_flags[0] = (0x2 if mode_bit_d9 == 0 else 0)
		# probe_vol_prestage_lfo — mirrors FFT per-tick handler at
		# L800157F0 that sets CHAN1_VOL_PRESTAGE once when chan+0xfe==3
		# (LFO mode 1 active). Empirically fires once per LFO init.
		# Emit AFTER setting the active flag so the probe sees the
		# post-D9 value (matches FFT which reads chan+0xfe after
		# pitch_lfo_period_reset has stored 3).
		var _mode_flags_pre: int = channel.lfo_sub_active[0] | channel.lfo_sub_dir_flags[0]
		_ProbeCounters.vol_prestage_lfo += 1
		_Trace.emit("vol_prestage_lfo", {
			"call_index": _ProbeCounters.vol_prestage_lfo,
			"lfo_mode_flags_pre": _mode_flags_pre & 0xFFFF,
		})
		# Also set vol prestage to mirror FFT's effect.
		channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE
		# Pre-write pitch_bend with the initial output to
		# handle "first-tick missing bend" case.
		var output_hi_init_d9: int = step_base_d9 >> 16
		if output_hi_init_d9 > 0x7FFF: output_hi_init_d9 = 0x7FFF
		elif output_hi_init_d9 < -0x8000: output_hi_init_d9 = -0x8000
		channel.pitch_bend = output_hi_init_d9
		# FFT D9 / pitch_lfo_period_reset path does NOT initialize the
		# sub-slot countdown at chan+0xF4 — it stays at its previous
		# value (0 at startup per the zero-init slot struct, hence
		# PCSX's first swap fires immediately at the cadence D9
		# dispatches — countdown==0 enters the swap branch at PC
		# 0x80017500 `beq v0, zero, LAB_8001751c`). Setting Godot's
		# countdown to 0 here mirrors that — _advance_lfo's
		# decrement-then-check will roll countdown to -1 and trigger
		# the swap on the same IRQ as D9 dispatch.
		channel.lfo_sub_countdown[0] = 0
