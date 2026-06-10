class_name SharedOpPanLfo
## FFT analog: smd_op_ed_pan_lfo @ FUN_80016A14
##                (opcode 0xED)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xED — FUN_80016a14 at jumptable 0x80028CC0 = base
	## 0x80028B0C + (0xED-0x80)*4. 3 params. Mirror of 0xE5 but arms
	## LFO sub-slot 2 (chan+0x120..0x13e block) with mode 2 (pan-LFO):
	##   PC 0x80016aa0 `sb v0, 0x13c(s1)` v0=2 → mode byte = 2
	##   PC 0x80016aa4 `sh s0, 0x13e(s1)` s0=0x1 or 0x3 → active flags
	##   PC 0x80016aac `sw v1, 0x120(s1)` v1=callback → vtable ptr
	## Mode 2 makes lfo_handler_tick's switch at PC 0x80017564 fall
	## through to LAB_800175CC and write chan+0x8a (pan-LFO output).
	## On cure_4_no_music the bytecode dispatches 0xED exactly once
	## (cad 241 on voice 21 chan_base 0x80037878) — that single arm
	## kicks off the chan_8a sawtooth from cad 197 onward in
	## probe_vol_inputs. Early-returns at FFT PC 0x80016a40 /
	## 0x80016a4c mirror param[1] == 0 / param[0] == 0.
	if op.params.size() < 3:
		return
	var p0_ed: int = op.params[0] & 0xFF
	var p1_ed_raw: int = op.params[1] & 0xFF
	if p0_ed == 0 or p1_ed_raw == 0:
		return
	# Sub-slot 2 mode 2 (pan-LFO). channel_state.gd defaults
	# lfo_sub_mode[2] = 2; set it explicitly so callers that reset
	# the array don't accidentally fall through to inactive mode.
	channel.lfo_sub_mode[2] = 2
	channel.lfo_sub_active[2] = 1
	# Unlike 0xE5, the 0xED handler at FUN_80016a14 does NOT negate
	# param[1] (no `subu a0, zero, a0` between the lb and the sll<<24);
	# pan-LFO ramps in the positive direction by default. The rest
	# of the state machine mirrors 0xE5.
	var p1_signed: int = p1_ed_raw if p1_ed_raw < 0x80 else p1_ed_raw - 0x100
	var p2_ed: int = op.params[2] & 0xFF
	var step_source: int = _LfoStepCalc.step_calc(
			p1_signed * 0x01000000, p0_ed, p2_ed & 0xF)
	channel.lfo_sub_step_source[2] = step_source
	# pitch_lfo_period_reset preserves step_current — see the matching
	# _op_e5_3param comment.
	channel.lfo_sub_accumulator[2] = 0
	channel.lfo_sub_inner_reload[2] = p0_ed
	# Initial dir_flags per PC 0x80016A98 `addiu s0, s0, 0x1` where
	# s0 = (p2 & 0x10 ? 0 : 2). Bit-0x10 set → 1 (bits 0x1 only).
	# Bit-0x10 clear → 3 (bits 0x1, 0x2). For cure_4 voice 21
	# p2=19 (= 0x13) has bit-0x10 set → dir_flags = 1.
	channel.lfo_sub_dir_flags[2] = 1 if (p2_ed & 0x10) != 0 else 3
	channel.lfo_sub_callback_idx[2] = p2_ed & 0xF
	channel.lfo_sub_countdown[2] = 1
