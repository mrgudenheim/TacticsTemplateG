class_name SharedOpDetune
## FFT analog: smd_op_d6_detune @ LAB_800163EC
##                (opcode 0xD6)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xD6 — historically named "Detune" but actually a PAN-offset
	## opcode. FFT LAB_800163EC (jumptable 0x80028C64). 1 param.
	## FFT MIPS:
	##   lbu  v0, 0x0(a0); addiu a0, a0, 0x01
	##   beq  v0, zero, LAB_80016408
	##   _sh  v0, 0x90(a2)        ; chan+0x90 = param (pan offset)
	##   lhu  v0, 0x6(a2)
	##   j    LAB_80016414
	##   _ori v0, v0, 0x4         ; chan+0x6 |= 0x4 (active gate)
	## LAB_80016408:               ; param == 0
	##   lhu  v0, 0x6(a2)
	##   andi v0, v0, 0xfffb      ; chan+0x6 &= ~0x4
	## LAB_80016414:
	##   sh   v0, 0x6(a2)
	##
	## chan+0x90 is the third addend in FFT's pan sum at PC 0x80017210:
	##   pan_arg = chan+0x90 + chan+0x8a + chan+0xae
	##   (then clamped to [0, 0x7F00] for SPU pan register)
	## So D6 sets a per-channel constant pan offset that combines with the
	## E8-set pan_offset_ae and the pan-LFO chan+0x8a output. The name
	## "Detune" persists in `OPCODE_INFO` for back-compat with the older
	## audit doc; this function and the field doc strings on
	## channel_state.gd describe the real semantics.
	##
	## Affects 1 effect (Haste / E032). See research/effect_sound/
	## working_documents/SMD_OPCODE_COVERAGE_STATUS.md §4.6.
	_ProbeCounters.opcode_d6_detune += 1
	var p_d6: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	_Trace.emit("opcode_d6_detune", {
		"call_index": _ProbeCounters.opcode_d6_detune,
		"param": p_d6,
		"channel_idx": channel.channel_idx,
	})
	if p_d6 == 0:
		# Param == 0: clear the active gate, preserve chan+0x90.
		slot.chan_6_detune_active = false
	else:
		# Non-zero: store as the new pan offset and set the active gate.
		channel.chan_90_value = p_d6
		slot.chan_6_detune_active = true
