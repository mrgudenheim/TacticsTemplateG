class_name SharedOpDynamics
## FFT analog: smd_dynamics @ 0x80016614
##                (opcode 0xE0)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	# probe_opcode_dynamics (GOLD #6). Mirror of FFT BP @ 0x80016614.
	# dynamics_byte = read8(a0) on FFT side = op.params[0] here.
	_ProbeCounters.opcode_dynamics += 1
	_Trace.emit("opcode_dynamics", {
		"call_index": _ProbeCounters.opcode_dynamics,
		"dynamics_byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"channel_idx": channel.channel_idx,
		"voice_writes": 1 if voice_writes else 0,
	})
	## Dynamics — opcode 0xE0 smd_dynamics at PC 0x80016614. Three writes:
	##   1. chan+0x98 := byte << 24    (PC 0x80016620, sw — expression
	##                                  accumulator initial value)
	##   2. chan+0x6 &= 0xfff7         (PC 0x8001662c — clears bit 0x8,
	##                                  disarming any in-flight 0xE2 burst)
	##   3. chan+0x2 |= 0x100          (PC 0x80016634 — vol prestage)
	## The drainer at FUN_80017118 reads `lh v1, 0x98(s0)` with s0 =
	## chan_base + 0x2, so it reads chan_base+0x9A = HIGH halfword of
	## chan+0x98 (= byte<<8 effectively). The 0xE2 expression burst then
	## ramps chan+0x98 in 32-bit space at PC 0x800151FC.
	# NB on LFO callback: an earlier comment here claimed
	# smd_dynamics writes LAB_800176E4 to slot+0x100 at PC 0x80016728,
	# disarming the swap probe. That PC is actually inside FUN_800166C8
	# (= opcode 0xE4 at jumptable 0x80028C9C), not smd_dynamics. FFT's
	# 0xE0 body is bounded by PC 0x80016614..0x80016638 and never
	# touches chan+0xE0 or chan+0x100. The previous
	# `channel.lfo_swap_probe_active = false` line here used to disarm
	# the probe on every E0 dispatch — incorrectly tying the probe gate
	# to a write that 0xE0 doesn't perform. Removed; the swap probe is
	# now armed/disarmed only by D9 (and E5, when sub-slot 1 modeling
	# is added) based on the actual wf_idx selected.
	# All three writes below are channel-side state per the dispatcher
	# contract (line 159-167): chan_word_1 bit, expression_acc_s32
	# (= FFT chan+0x98), vol_burst_active (= FFT chan+0x6 bit 0x8).
	# FFT's smd_dynamics writes these unconditionally per-channel — no
	# voice/silent gate. Gating on voice_writes here used to drop the
	# expression_acc seed on silent-driver channels; the next E2 on
	# that channel then saw expression_acc_s32 == 0, computed delta
	# == 0, and early-returned without arming vol_burst. Cure_4's
	# slot 4 (silent driver) received E0 #3 at cad 0 + E2 #4 at cad
	# 251 — Godot dropped the burst, costing 115 expression_ramp
	# fires and ~115 vol_inputs fires (diagnosed via
	# diag_vol_burst_transition, see VOL_FORMULA_GATE_DEFICIT.md).
	if op.params.size() > 0:
		channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE
		# byte is unsigned 0..127, so byte<<24 is 0..0x7F000000 (always
		# non-negative in s32). The drainer in play_sound.gd reads
		# `(expression_acc_s32 >> 16) & 0xFFFF` to get the high halfword
		# FFT's vol formula uses.
		channel.expression_acc_s32 = (op.params[0] & 0xFF) << 24
		# 0xE0 clears chan+0x6 bit 0x8, disarming any in-flight 0xE2
		# burst. FFT does NOT touch chan+0xa8 (vol_burst_counter) or
		# chan+0xa0 (expression_delta_s32) — they retain their prior
		# values until the next 0xE2 overwrites them. Since the per-tick
		# handler is gated on vol_burst_active, leaving stale counter /
		# delta values has no functional effect.
		var _was_active_e0: bool = channel.vol_burst_active
		channel.vol_burst_active = false
		# diag_vol_burst_transition (Godot-only). Emit on true→false
		# (FFT PC 0x8001662C `andi v1, v1, 0xfff7` clears chan+0x6
		# bit 0x8). Skip the noise of no-op disarms (already inactive).
		if _was_active_e0:
			_ProbeCounters.diag_vol_burst_transition += 1
			_Trace.emit("vol_burst_transition", {
				"call_index": _ProbeCounters.diag_vol_burst_transition,
				"channel_idx": channel.channel_idx,
				"transition": "disarm",
				"cause": "e0",
				"counter": channel.vol_burst_counter,
			})
		# NO direct WALKER_FLAG_VOL_LR_RAW stage here. FFT
		# defers vol_lr_raw to the post-Note-2 walker pass via
		# the slot+0x2 bit 0x100 → FUN_80017118 → L80017330
		# chain. Direct staging at 0xE0 doesn't model the
		# deferral and over-fires.
