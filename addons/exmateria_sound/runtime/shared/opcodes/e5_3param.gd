class_name SharedOpE5_3param
## FFT analog: smd_op_e5 @ FUN_8001676C
##                (opcode 0xE5)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xE5 — FUN_8001676c at jumptable 0x80028CA0 = base
	## 0x80028b0c + (0xE5-0x80)*4. 3 params. Initializes LFO sub-slot 1
	## (chan+0x100..0x11e block) with mode 1 (vol-L):
	##   PC 0x800167FC `sb v0, 0x11c(s1)` v0=1 → mode byte = 1
	##   PC 0x80016800 `sh s0, 0x11e(s1)` s0=3 → active flags = 0x3
	##                                               (bit 0x1 + bit 0x2)
	##   PC 0x80016808 `sw v1, 0x100(s1)` v1=callback → LFO callback ptr
	## Mode 1 makes lfo_handler_tick's switch at PC 0x80017564
	## (`beq v1, v0=1, LAB_800175B4`) take the mode-1 path which fires
	## chan_word_1 |= 0x100 every cadence (PC 0x800175C0 `ori v1, v1,
	## 0x100`). _advance_lfo's new sub-slot 1/2 block above replicates
	## this. Early-returns at FFT PC 0x80016798 / 0x800167A4 mirror
	## param[0] == 0 / param[1] == 0 → don't arm.
	## (NB: the prior Godot comment claimed this handler was LAB_
	## 8001686c at jumptable 0x80028CA4 — that's actually opcode 0xE6,
	## not 0xE5. 0xE6 just sets ch+0x11e bit 0x1, a different no-op
	## shadow. Keeping the slot.word_11e |= 0x1 write so the prior
	## parity-shadow state still pairs; layered on the real E5 work.)
	_ProbeCounters.opcode_e5 += 1
	_Trace.emit("opcode_e5_3param", {
		"call_index": _ProbeCounters.opcode_e5,
		"byte0": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"byte1": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
		"byte2": (op.params[2] if op.params.size() > 2 else 0) & 0xFF,
	})
	slot.word_11e |= 0x1
	if op.params.size() < 3:
		return
	var p0_e5: int = op.params[0] & 0xFF
	var p1_e5_raw: int = op.params[1] & 0xFF
	if p0_e5 == 0 or p1_e5_raw == 0:
		return
	# Sub-slot 1 mode 1 (vol-L). channel_state.gd already defaults
	# lfo_sub_mode[1] = 1, but set it explicitly so callers that reset
	# the array don't accidentally fall through to inactive mode.
	channel.lfo_sub_mode[1] = 1
	channel.lfo_sub_active[1] = 1
	# FFT FUN_8001676c PC 0x800167B4 negates param[1] BEFORE feeding
	# into pitch_lfo_step_calc (`subu a0, zero, a0`), giving the
	# vol-LFO a descending-ramp default direction. This is the only
	# functional difference between the 0xE5 (vol) and 0xED (pan)
	# arms — both share the same pitch_lfo_step_calc math.
	# Initial dir_flags = (p2 bit-0x10 set) ? 1 : 3 (PC 0x800167B0..0x800167F4):
	#   s0 = sltiu(p2 & 0x10, 1) << 1  → 0 or 2
	#   s0 += 1                          → 1 or 3
	# Bit-0x10 set → 1 (bits 0x1 only). Bit-0x10 clear → 3 (bits 0x1, 0x2).
	# Neither bit 0x4 nor 0x8 set initially → first swap won't double
	# and won't negate; step starts equal to step_source.
	var p1_signed: int = p1_e5_raw if p1_e5_raw < 0x80 else p1_e5_raw - 0x100
	var p2_e5: int = op.params[2] & 0xFF
	var step_source: int = _LfoStepCalc.step_calc(
			-p1_signed * 0x01000000, p0_e5, p2_e5 & 0xF)
	channel.lfo_sub_step_source[1] = step_source
	# FFT pitch_lfo_period_reset (PC 0x80016DC0) does NOT zero step_current
	# (sub+0x8) — it only resets accumulator (sub+0x4) and reloads the
	# countdown to 1. Re-arms therefore PRESERVE step_current from the
	# prior LFO cycle. (Cure_4's voice 18/19 re-arms at cad 497 inherit
	# step_current from the cad 241 cycle's last swap — verified via
	# probe_lfo_subslot1_state.)
	channel.lfo_sub_accumulator[1] = 0
	channel.lfo_sub_inner_reload[1] = p0_e5
	# pitch_lfo_period_reset clears bits 0x4 and 0x8 of dir_flags but
	# preserves the rest, then 0xE5 sets bit 0x1 (active) + maybe bit 0x2
	# via the `s0 = (p2 & 0x10 ? 0 : 2) + 1` math.
	channel.lfo_sub_dir_flags[1] = 1 if (p2_e5 & 0x10) != 0 else 3
	# Per-sub-slot LFO callback variant. FFT 0xE5 PC 0x800167EC selects
	# from PTR_LAB_80028f54[(p2 & 0xf) * 4]. cure_4's voice 18/19
	# first arm uses p2=3 (pitch_accum_callback / triangle); the
	# re-arm uses p2=4 (LAB_800177c0 / sawtooth).
	channel.lfo_sub_callback_idx[1] = p2_e5 & 0xF
	# pitch_lfo_period_reset (FFT PC 0x80016DC0) sets inner_countdown
	# = 1, so the first per-tick call decrements to 0 → swap path → step
	# loaded from source.
	channel.lfo_sub_countdown[1] = 1
