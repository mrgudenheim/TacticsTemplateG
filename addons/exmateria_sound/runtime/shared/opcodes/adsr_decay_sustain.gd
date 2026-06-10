class_name SharedOpAdsrDecaySustain
## FFT analog: smd_op_c7_adsr_decay_sustain @ LAB_80016238
##                (opcode 0xC7)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## ADSR Decay+SustainLevel modifier.
	## Disasm: FFT helpers L8001B7B0..7C0 (set_decay_rate) and
	## L8001B8C0..8D0 (set_sustain_level) modify ADSR1 register
	## 1F801C08+v*0x10 in-place (read, mask, OR, write back).
	## B7C0: andi v0,v0,0xff0f; sll a1,a1,4; or v0,v0,a1; sh
	## B8D0: andi v0,v0,0xfff0; or v0,v0,a1; sh
	## Mirror by updating slot.adsr1 bits 0-7 from the two
	## operands, preserving attack_rate (8-14) and attack_mode
	## (15).
	## Silent drivers also update channel.adsr1 decay+sustain
	## bits.
	var p_c7_dr: int = (op.params[0] if op.params.size() > 0 else 0) & 0xF
	var p_c7_sl: int = (op.params[1] if op.params.size() > 1 else 0) & 0xF
	_ProbeCounters.opcode_c7_adsr += 1
	_Trace.emit("opcode_c7_adsr", {
		"call_index": _ProbeCounters.opcode_c7_adsr,
		"byte0": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"byte1": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
	})
	channel.adsr1 = (channel.adsr1 & 0xFF00) | (p_c7_dr << 4) | p_c7_sl
	if voice_writes:
		slot.adsr1 = channel.adsr1
		slot.adsr_opcode_modified = true
