class_name SharedOpLfoSubslotDynDisable
## FFT analog: smd_op_f7_lfo_subslot_dynamic_disable @ LAB_80016DEC
##                (opcode 0xF7)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xF7 — dynamic LFO sub-slot disable at FFT LAB_80016DEC
	## (jumptable 0x80028CE8). 1 param. Dynamic counterpart to 0xE7 / 0xEF
	## which target fixed sub-slots 1 / 2.
	## FFT MIPS:
	##   lbu  v0, 0x0(a0)       ; sub-slot index
	##   sll  v0, v0, 0x5       ; idx * 32 (sub-slot stride)
	##   addu a2, a2, v0
	##   lhu  v0, 0xfe(a2)      ; chan[+idx*32]+0xFE (active flags)
	##   andi v0, v0, 0xfffe    ; clear bit 0x1
	##   sh   v0, 0xfe(a2)
	## Affects 3 effects (Esuna, Meteorain, ThrowSpirit). See
	## SMD_OPCODE_COVERAGE_STATUS.md §4.4.
	_ProbeCounters.opcode_f7_lfo_subslot_dynamic_disable += 1
	var idx_f7: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	_Trace.emit("opcode_f7_lfo_subslot_dynamic_disable", {
		"call_index": _ProbeCounters.opcode_f7_lfo_subslot_dynamic_disable,
		"subslot_idx": idx_f7,
		"channel_idx": channel.channel_idx,
	})
	if idx_f7 < channel.lfo_sub_active.size():
		channel.lfo_sub_active[idx_f7] = 0
	# Mirror the FFT write to chan[+idx*32]+0xFE on the existing parity-
	# shadow field for sub-slot 1 (slot.word_11e). Sub-slots 0 / 2 don't
	# have dedicated slot mirrors yet — lfo_sub_active is the authoritative
	# state consumed by the LFO advance.
	if idx_f7 == 1:
		slot.word_11e &= ~0x1
