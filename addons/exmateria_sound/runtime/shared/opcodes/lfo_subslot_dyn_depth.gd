class_name SharedOpLfoSubslotDynDepth
## FFT analog: smd_op_f2_lfo_subslot_dynamic_depth @ LAB_80016C70
##                (opcode 0xF2)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xF2 — LFO_SubSlot_DynamicDepth at FFT LAB_80016C70
	## (jumptable 0x80028CD4). 2 params. Dynamic counterpart to the
	## fixed-target depth opcodes (0xD7 / 0xE3 / 0xEB).
	## FFT MIPS:
	##   lbu  v1, 0x1(a0)         ; param[1]
	##   lhu  v0, 0xae(a2)        ; chan+0xAE (active sub-slot index from 0xF0)
	##   addiu v1, v1, 0x01
	##   sll  v0, v0, 0x5         ; idx * 32 (sub-slot stride)
	##   addiu v0, v0, 0xe0       ; sub-slot block base = chan + 0xE0 + idx*32
	##   andi v1, v1, 0xff
	##   beq  v1, zero, end       ; skip if (param[1]+1) wraps to 0
	##   _addu a2, a2, v0         ; rebase chan pointer to sub-slot block
	##   ori  v0, zero, 0x100
	##   div  v0, v1
	##   mflo v0                  ; depth = 256 / (param[1]+1)
	##   lbu  v1, 0x0(a0)         ; param[0]
	##   sh   v1, 0x16(a2)        ; sub-slot+0x16 = param[0] (outer-delay reload)
	##   sh   v0, 0x1a(a2)        ; sub-slot+0x1A = depth_reload (our depth_delta)
	##   sh   v0, 0x18(a2)        ; sub-slot+0x18 = depth (current)
	##
	## Companion to 0xF0 LFO_SubSlot_Select (which seeds chan+0xae with
	## the sub-slot index) and 0xF1 LFO_SubSlot_Update (which sets depth+
	## rate of the same selected sub-slot). 0xF2's distinguishing role is
	## the simultaneous outer-delay + depth update without touching rate.
	##
	## Affects 1 effect (GrandCross / E409). See
	## SMD_OPCODE_COVERAGE_STATUS.md §4.8.
	_ProbeCounters.opcode_f2_lfo_subslot_dynamic_depth += 1
	var p0_f2: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var p1_f2: int = (op.params[1] if op.params.size() > 1 else 0) & 0xFF
	# F0 mirrors the selected sub-slot index into channel.pan_offset_ae
	# (FFT chan+0xAE is overloaded for both 0xE8 pan and 0xF0/F1/F2
	# sub-slot selection — bytecode that mixes 0xE8 with the F0 family
	# corrupts on both PCSX and Godot, mirrored by us).
	var idx_f2: int = channel.pan_offset_ae & 0xFF
	_Trace.emit("opcode_f2_lfo_subslot_dynamic_depth", {
		"call_index": _ProbeCounters.opcode_f2_lfo_subslot_dynamic_depth,
		"param0_outer_delay": p0_f2,
		"param1_depth_divisor": p1_f2,
		"subslot_idx": idx_f2,
		"channel_idx": channel.channel_idx,
	})
	if idx_f2 >= channel.lfo_sub_depth.size():
		return
	var divisor_f2: int = (p1_f2 + 1) & 0xFF
	if divisor_f2 == 0:
		# FFT early-returns when (param[1]+1) & 0xFF == 0 (param[1] == 0xFF).
		return
	# Iter-37 Bug A: FFT 0xF2 at PC 0x80016CA8/CAC writes BOTH chan+0x1A
	# (depth_reload / our depth_delta) AND chan+0x18 (depth) — same
	# dual-store pattern as 0xD7 (PC 0x800165D4/D8). The pre-iter-37 code
	# only wrote the depth field, leaving depth_delta at its default
	# (256 → tripped the no-scale gate on the first per-tick ramp).
	# 0xF2 does NOT call pitch_lfo_period_reset; it just updates
	# reload + current values inline.
	var depth_f2: int = 0x100 / divisor_f2
	channel.lfo_sub_delay_reload[idx_f2] = p0_f2
	channel.lfo_sub_depth_delta[idx_f2] = depth_f2
	channel.lfo_sub_depth[idx_f2] = depth_f2
