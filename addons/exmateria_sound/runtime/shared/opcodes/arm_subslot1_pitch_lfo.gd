class_name SharedOpArmSubslot1PitchLfo
## FFT analog: smd_op_e4 @ FUN_800166C8
##                (opcode 0xE4)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xE4 — FUN_800166C8 at jumptable 0x80028C9C = base
	## 0x80028B0C + (0xE4-0x80)*4. 3 params. Arms LFO sub-slot 1 with
	## mode 1 (pitch-LFO). Hardcoded-callback sibling of 0xE5
	## (FUN_8001676C) — same sub-slot, same mode, same rate-negation,
	## but with FIXED callback_idx=2 and dir_flags=3 (vs E5's
	## p2-derived values). Param[2] is stored as outer-delay
	## (subslot+0x16), not as a callback selector.
	##
	## FFT disasm (FUN_800166C8, scus_decompilation.c:3250):
	##   if (p1 != 0 && p0 != 0) {
	##       step = pitch_lfo_step_calc(-(p1 << 24), p0, 2);  ; a2=2 FIXED
	##       chan[0x10c] = step             ; step_source
	##       chan[0x112] = p0               ; inner_reload (depth)
	##       chan[0x11a] = 0x100            ; depth reset
	##       chan[0x100] = &LAB_800176E4    ; callback ptr (FIXED)
	##       chan[0x11d] = 2                ; callback_idx (FIXED)
	##       chan[0x11c] = 1                ; mode = 1 (pitch-LFO)
	##       chan[0x11e] = 3                ; active_dir = 3 (bits 0x1+0x2)
	##       chan[0x116] = p2               ; outer-delay
	##       pitch_lfo_period_reset(chan + 0x100);
	##   }
	##
	## Zombie (E293) fires this twice — once on v17, once on v19 — at
	## the start of the spell. Without a Godot handler, sub-slot 1's
	## pitch-LFO doesn't tick and the channel's pitch trajectory stays
	## flat (probe_lfo_subslot1_state diverges in row count + values).
	_ProbeCounters.opcode_e4_arm_subslot1_pitch_lfo += 1
	_Trace.emit("opcode_e4_arm_subslot1_pitch_lfo", {
		"call_index": _ProbeCounters.opcode_e4_arm_subslot1_pitch_lfo,
		"arg0_depth": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"arg1_rate": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
		"arg2_outer_delay": (op.params[2] if op.params.size() > 2 else 0) & 0xFF,
	})
	if op.params.size() < 3:
		return
	var p0_e4: int = op.params[0] & 0xFF
	var p1_e4_raw: int = op.params[1] & 0xFF
	if p0_e4 == 0 or p1_e4_raw == 0:
		return
	channel.lfo_sub_mode[1] = 1
	channel.lfo_sub_active[1] = 1
	var p1_signed: int = p1_e4_raw if p1_e4_raw < 0x80 else p1_e4_raw - 0x100
	# Rate negated (FFT `subu a0, zero, a0`), a2 fixed to 2.
	var step_source: int = _LfoStepCalc.step_calc(
			-p1_signed * 0x01000000, p0_e4, 2)
	channel.lfo_sub_step_source[1] = step_source
	channel.lfo_sub_accumulator[1] = 0
	channel.lfo_sub_inner_reload[1] = p0_e4
	# dir_flags FIXED to 3 (active + first-segment doubling).
	channel.lfo_sub_dir_flags[1] = 3
	channel.lfo_sub_callback_idx[1] = 2
	channel.lfo_sub_countdown[1] = 1
