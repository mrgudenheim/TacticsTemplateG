class_name SharedOpLfoSubslotSelect
## FFT analog: smd_op_f0_lfo_subslot_select @ LAB_80016B08
##                (opcode 0xF0)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xF0 — LAB_80016B08 at jumptable 0x80028CCC = base
	## 0x80028B0C + (0xF0-0x80)*4. 3 params. Sub-slot SELECTOR + LFO INIT.
	## Companion of 0xF1 (FUN_80016B80) which UPDATES the selected
	## sub-slot's depth+rate; together they're the dynamic-subslot pair
	## (cf. 0xEC/0xED which target fixed sub-slot 2).
	##
	## FFT disasm (LAB_80016B08..0x80016B7C):
	##   sh   param[0],          0xae(chan)         ; chan+0xae = subslot_idx
	##   subslot = chan + 0xe0 + subslot_idx * 0x20
	##   sb   param[1] & 0xf,    0x1d(subslot)      ; waveform_idx
	##   sw   PTR_LAB_80028F54[wf_idx], 0x0(subslot); waveform callback ptr
	##   sh   (param[1] & 0x10 ? 0 : 2), 0x1e(subslot) ; active_dir flags
	##   sh   0x100,             0x1a(subslot)      ; depth reset
	##   sh   0,                 0x16(subslot)      ; outer-delay = 0
	##   sb   param[2],          0x1c(subslot)      ; mode byte
	##   return param + 3
	##
	## chan+0xae is OVERLOADED in FFT — 0xE8 Pan writes pan offset to the
	## same field; 0xF0 writes subslot index; 0xF1 reads it as subslot
	## index. Bytecode that mixes 0xE8 with 0xF0/0xF1 in the same channel
	## corrupts on both PCSX and Godot — we mirror the overload via
	## `pan_offset_ae`. Fire2 (E017) doesn't trip this; the captured run
	## fires 0xF0 once with subslot=0, waveform=3 on v19/ch3.
	_ProbeCounters.opcode_f0_lfo_subslot_select += 1
	_Trace.emit("opcode_f0_lfo_subslot_select", {
		"call_index": _ProbeCounters.opcode_f0_lfo_subslot_select,
		"arg0_subslot_idx": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"arg1_byte": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
		"arg2_byte": (op.params[2] if op.params.size() > 2 else 0) & 0xFF,
	})
	if op.params.size() < 3:
		return
	var subslot_idx: int = op.params[0] & 0xFF
	# lfo_sub_* arrays are size 4 in channel_state.gd. FFT doesn't bounds-
	# check (the bytecode is assumed well-formed); we do, defensively.
	if subslot_idx >= 4:
		return
	var arg1: int = op.params[1] & 0xFF
	var arg2: int = op.params[2] & 0xFF
	channel.pan_offset_ae = subslot_idx
	channel.lfo_sub_callback_idx[subslot_idx] = arg1 & 0x0F
	# subslot+0x1e: 2 if bit-0x10 clear (first-segment doubling), 0 if set.
	# Neither value has bit 0x1 — 0xF0 effectively DEACTIVATES the subslot.
	# lfo_handler_tick (PC 0x800174E4-0x800174F0) gates each iteration on
	# bit 0x1 of subslot+0x1e:
	#   lhu v0, 0x2(s1)   ; s1 = chan+0xFC + N*0x20 (subslot N's +0x1E)
	#   andi v0, v0, 0x1
	#   beq v0, zero, LAB_800175e4  ; skip if inactive
	# So FFT runs the LFO tick only when bit 0x1 is set. 0xF0 NEVER sets
	# it. Mirror by explicitly clearing lfo_sub_active.
	#
	# Empirical note: on Fire2 a previous draft that set lfo_sub_active=1
	# gave a slightly better full_mix cos_dist (0.0021 vs 0.0084), but
	# that's FFT-incorrect. The discrepancy hints at a different LFO
	# divergence elsewhere that the over-activation accidentally masks —
	# tracked separately, not addressed here.
	channel.lfo_sub_dir_flags[subslot_idx] = 0 if (arg1 & 0x10) != 0 else 2
	# Iter-37 Bug A pattern: FFT writes sub+0x1A (depth_reload / our
	# depth_delta), NOT sub+0x18 (current depth). The pre-iter-37 code
	# wrote the wrong field, which happened to "work" because F6 (which
	# is supposed to mirror depth = depth_reload via period_reset) didn't
	# call period_reset either. Iter-37 fixes both: F0 writes depth_delta,
	# F6 invokes the period_reset helper which copies depth = depth_delta.
	channel.lfo_sub_depth_delta[subslot_idx] = 0x100
	# Iter-37: FFT also writes sub+0x16 (delay_reload) = 0 here; period_reset
	# in F6 then mirrors delay_counter = delay_reload = 0.
	channel.lfo_sub_delay_reload[subslot_idx] = 0
	channel.lfo_sub_mode[subslot_idx] = arg2
	channel.lfo_sub_active[subslot_idx] = 0
