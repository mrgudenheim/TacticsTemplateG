class_name SharedOpVolScale
## FFT analog: smd_expression @ 0x80016680
##                (opcode 0xE2)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Opcode 0xE2 — smd_expression at PC 0x80016680 (jumptable
	## @0x80028C94 = base 0x80028b0c + (0xE2-0x80)*4). 2 params.
	## Arms a per-tick vol-burst: seeds chan+0xa8 (vol_burst_counter)
	## with param[0] and sets chan+0x6 bit 0x8 (vol_burst_active).
	## The per-tick handler in cadence_body then sets chan_word_1 bit
	## 0x100 (CHAN1_VOL_PRESTAGE) on each tick until the counter wraps
	## to 0.
	## NB on opcode numbering: the Ghidra annotation at PC 0x80016680
	## labels this "Opcode 0xE1", but FFT's actual dispatcher arithmetic
	## (lw at PC 0x800154e4 with base 0x8003-0x74f4 = 0x80028b0c) routes
	## byte 0xE2 here. 0xE1 → LAB_80016640 (relative-dynamics add to
	## chan+0x98, clears chan+0x6 bit 0x8). The function name
	## _op_e2_vol_scale is also a misattribution — LAB_80016834
	## (vol-scale division) is opcode 0xE3, not 0xE2. Kept the function
	## name so external probe configs / orchestrator references don't
	## break; the body now implements what 0xE2 actually does.
	## FFT early-returns when param[0] == 0 (PC 0x80016694
	## `beq a1, zero, LAB_800166c0`) — mirror that so the gate never
	## arms with a 0 seed (would otherwise underflow to 0xFFFF and fire
	## the burst for 65535 ticks).
	## FFT also computes chan+0xa0 = ((sb param[1] << 24) - chan+0x98)
	## / param[0] as the per-tick expression-ramp delta, but Godot does
	## not currently model chan+0xa0 or the underlying expression
	## accumulator. Arming the burst alone still produces the extra
	## vol_lr_staging drains PCSX shows (the 48-fire gap).
	## See research/effect_alignment/PER_CHANNEL_TICK_BIT100_ISSUE.md.
	_ProbeCounters.opcode_e2_vol_scale += 1
	_Trace.emit("opcode_e2_vol_scale", {
		"call_index": _ProbeCounters.opcode_e2_vol_scale,
		"e2_byte0": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"e2_byte1": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
		"channel_idx": channel.channel_idx,
		"expression_acc_s32_pre": channel.expression_acc_s32,
	})
	if op.params.size() < 2:
		return
	var seed: int = op.params[0] & 0xFF
	if seed == 0:
		# FFT PC 0x80016694 `beq a1, zero, LAB_800166c0` — param[0] == 0
		# returns without touching the gate or chan+0xa0.
		return
	# FFT PC 0x80016680 `lb v0, 0x1(a0)` — param[1] is a SIGNED byte.
	var sb_target: int = op.params[1] & 0xFF
	if sb_target >= 0x80:
		sb_target -= 0x100
	# target_u32 = sb_target << 24, sign-extended 32-bit.
	var target_u32: int = (sb_target << 24)
	# Wrap to 32-bit s32 range so the subtract below matches FFT's
	# 32-bit arithmetic.
	if target_u32 >= 0x80000000:
		target_u32 -= 0x100000000
	# delta_target_minus_current = (sb_target << 24) - chan+0x98.
	# FFT PC 0x80016698 `subu v0, v0, v1`.
	var delta_total: int = target_u32 - channel.expression_acc_s32
	if delta_total == 0:
		# FFT PC 0x8001669c `beq v0, zero, LAB_800166c0` — already at
		# target, return without arming the burst.
		return
	# FFT PC 0x800166a4-a8 `div v0, a1; mflo v1` — signed integer
	# divide. GDScript / on ints truncates toward zero for positive
	# operands; MIPS div rounds toward zero too, so semantics match
	# as long as we keep both operands signed.
	var per_tick_delta: int = delta_total / seed
	channel.expression_delta_s32 = per_tick_delta
	var _was_active_e2: bool = channel.vol_burst_active
	channel.vol_burst_counter = seed
	channel.vol_burst_active = true
	# diag_vol_burst_transition (Godot-only). Emit on the false→true edge
	# (FFT PC 0x800166B0-B8 chan+0x6 |= 0x8 + chan+0xa8 = seed). Re-arm
	# while already active also captured (cause="e2_rearm") so the diff
	# vs PCSX shows whether seed gets refreshed mid-burst.
	_ProbeCounters.diag_vol_burst_transition += 1
	_Trace.emit("vol_burst_transition", {
		"call_index": _ProbeCounters.diag_vol_burst_transition,
		"channel_idx": channel.channel_idx,
		"transition": "arm",
		"cause": "e2_rearm" if _was_active_e2 else "e2",
		"counter": seed,
	})
