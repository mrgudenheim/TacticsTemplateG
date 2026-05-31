class_name SharedOpPortamentoInit
## FFT analog: smd_op_d4_portamento @ LAB_80016364
##                (opcode 0xD4)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Portamento init — LAB_80016364.
	## 2 params: param[0] = u8 target, param[1] = s8 rate.
	## Both 0 → disable (clears portamento_active).
	## Else: pre_pitch_delta_u32 = (s8 rate << 24) / target;
	##       portamento_active = true (= chan+0x6 bit 0x1 set).
	## Probe chan_9c_001 confirmed cure D4 90 08 → 932067 =
	## 0x000E38E3 bit-exact match against this formula.
	_ProbeCounters.opcode_d4_portamento += 1
	_Trace.emit("opcode_d4_portamento", {
		"call_index": _ProbeCounters.opcode_d4_portamento,
		"d4_byte0": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"d4_byte1": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
	})
	if op.params.size() >= 2:
		var target_u8: int = op.params[0] & 0xFF
		var rate_s8: int = op.params[1] & 0xFF
		if rate_s8 >= 0x80: rate_s8 -= 0x100
		if target_u8 == 0 or rate_s8 == 0:
			channel.portamento_active = false
			channel.portamento_target_counter = -1
		else:
			channel.pre_pitch_delta_u32 = ((rate_s8 << 24) / target_u8) & 0xFFFFFFFF
			channel.portamento_active = true
			# Seed FFT's slot+0xa6 counter with the target.
			# Per-tick handler at PC 0x80015214-0x80015230
			# decrements this and clears porta_active when it
			# reaches 0.
			channel.portamento_target_counter = target_u8
