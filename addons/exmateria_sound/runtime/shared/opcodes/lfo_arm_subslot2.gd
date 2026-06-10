class_name SharedOpLfoArmSubslot2
## FFT analog: op_ec_lfo_arm_subslot2 @ LAB_80016974
##                (opcode 0xEC)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xEC — FUN_80016974 at jumptable XREF 0x80028CBC = base
	## 0x80028B0C + (0xEC-0x80)*4. 3 params. Arms LFO sub-slot 2
	## (chan+0x120..0x13e block) with mode 2 (pan-LFO), HARDCODED to
	## callback idx 3 (pitch_accum_callback). This is the simpler sibling
	## of 0xED (FUN_80016A14) which selects its callback from
	## (param[2] & 0xF).
	##
	## FFT disasm (PC 0x80016974..0x800169F0):
	##   lb   a0, 0x1(s1)         ; a0 = param[1] signed
	##   lbu  s2, 0x0(s1)         ; s2 = param[0] unsigned (inner_reload)
	##   beq  a0, zero, skip      ; if param[1] == 0, no arm
	##   beq  a1, zero, skip      ; if param[0] == 0, no arm
	##   sll  a0, a0, 0x18        ; a0 = p1 << 24 (sign-extended)
	##   jal  pitch_lfo_step_calc
	##   ori  a2, zero, 0x3       ; a2 = 3 FIXED (vs 0xED's p2&0xf)
	##   sw   v0, 0x12c(s0)       ; step_source
	##   sh   s2, 0x132(s0)       ; inner_reload = p0
	##   lbu  v1, 0x2(s1)         ; v1 = p2 (chan+0x136 / outer-delay)
	##   sh   0x100, 0x13a(s0)    ; depth = 256
	##   sw   pitch_accum_callback, 0x120(s0)   ; callback ptr (HARDCODED)
	##   sb   0x3, 0x13d(s0)      ; callback_idx = 3 (HARDCODED)
	##   sb   0x2, 0x13c(s0)      ; mode = 2 (pan-LFO)
	##   sh   0x3, 0x13e(s0)      ; active_dir = 3 (bit 0x1 + bit 0x2)
	##   sh   v1, 0x136(s0)       ; outer-delay = p2
	##
	## On protect_no_music ch1, this fires once at event 5 (after
	## BA E0 E2 AC 94) and arms sub-slot 2 to run mode-2 every tick of
	## the subsequent dt=96 Note. Every per-tick lfo_handler_tick call
	## then ORs bit 0x100 (CHAN1_VOL_PRESTAGE) into chan_word_1 and
	## writes chan+0x8a — the missing path PROTECT_RESIDUAL_VOL_INPUTS_
	## DEFICIT.md §3 traced.
	_ProbeCounters.opcode_ec_lfo_arm_subslot2 += 1
	_Trace.emit("opcode_ec_lfo_arm_subslot2", {
		"call_index": _ProbeCounters.opcode_ec_lfo_arm_subslot2,
		"channel_idx": channel.channel_idx,
	})
	if op.params.size() < 3:
		return
	var p0_ec: int = op.params[0] & 0xFF
	var p1_ec_raw: int = op.params[1] & 0xFF
	if p0_ec == 0 or p1_ec_raw == 0:
		return
	channel.lfo_sub_mode[2] = 2
	channel.lfo_sub_active[2] = 1
	# No `subu a0, zero, a0` here (matching 0xED, unlike 0xE5).
	var p1_signed: int = p1_ec_raw if p1_ec_raw < 0x80 else p1_ec_raw - 0x100
	# pitch_lfo_step_calc's a2 = 3 fixed (vs 0xED uses p2 & 0xF).
	# pitch_lfo_step_calc with a2 < 4 routes to `return a0 / a1`
	# (see _pitch_lfo_step_calc), so step_source = (p1<<24) / p0.
	var step_source: int = _LfoStepCalc.step_calc(
			p1_signed * 0x01000000, p0_ec, 3)
	channel.lfo_sub_step_source[2] = step_source
	channel.lfo_sub_accumulator[2] = 0
	channel.lfo_sub_inner_reload[2] = p0_ec
	# HARDCODED active_dir = 3 (bit 0x1 active + bit 0x2 = first-segment
	# doubling flag for pitch_accum_callback). Equivalent to 0xED with
	# (p2 & 0x10) == 0.
	channel.lfo_sub_dir_flags[2] = 3
	# HARDCODED callback_idx = 3 (pitch_accum_callback, the triangle-with-
	# doubling variant).
	channel.lfo_sub_callback_idx[2] = 3
	channel.lfo_sub_countdown[2] = 1
