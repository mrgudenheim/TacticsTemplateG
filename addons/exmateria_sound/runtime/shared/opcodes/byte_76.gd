class_name SharedOpByte76
## FFT analog: smd_op_ad_byte_76 @ LAB_80015E68
##                (opcode 0xAD)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## opcode 0xAD — modifies channel.byte_76 (FFT slot+0x76).
	## Per disasm L80015E68-94 (LAB_80015E68 at jumptable
	## 0x80028BC0):
	##   if operand != 0: slot+0x76 = sign_extend(slot+0x76 +
	##                                            signed_byte)
	##   if operand == 0: slot+0x76 = 0
	var p_ad: int = op.params[0] if op.params.size() > 0 else 0
	if p_ad == 0:
		channel.byte_76 = 0
	else:
		var signed_p: int = p_ad if p_ad < 0x80 else p_ad - 0x100
		var v: int = channel.byte_76 + signed_p
		# Truncate to signed 8-bit per FFT's `sb` store +
		# sign-extend on read at L800156A0-A4.
		v = v & 0xFF
		if v >= 0x80: v -= 0x100
		channel.byte_76 = v
