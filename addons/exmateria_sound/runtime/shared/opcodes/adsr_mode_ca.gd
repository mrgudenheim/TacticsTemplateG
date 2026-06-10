class_name SharedOpAdsrModeCa
## FFT analog: smd_op_ca_adsr2_mode @ LAB_80016298
##                (opcode 0xCA)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Opcode 0xCA — ADSR2 release mode modifier.
	## FFT handler at PC 0x80016298:
	##   lhu  v0, 0x4(a2)             ; v0 = walker_flag_word
	##   lbu  v1, 0x0(a0)             ; v1 = param byte
	##   ori  v0, v0, 0x80            ; set WALKER_FLAG_ADSR2_LOW
	##   sh   v0, 0x4(a2)             ; commit walker_flag_word
	##   ...                          ; arg_size = 1
	##   _sw  v1, 0x60(a2)            ; store byte at slot+0x60
	##
	## The byte at slot+0x60 is read by FUN_8001BAB8 (the ADSR2-low
	## helper) as the `a2` mode selector:
	##   a2 == 3 → mode_bits = 0
	##   a2 == 7 → mode_bits = 0x20   (release_mode_exp)
	##   else    → mode_bits = 0
	## mode_bits gets OR'd with the release_byte (slot+0x6A from 0xC5)
	## before the low 6 bits of SPU ADSR2 are written.
	##
	## Silent drivers also fire 0xCA (FFT has no silent-driver gating
	## here — the handler always runs and always sets the slot field).
	## Mirrors the existing pattern in _op_adsr_release / _op_adsr2_sustain.
	var p_ca: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	channel.adsr2_mode_byte = p_ca
	if voice_writes:
		slot.adsr2_mode_byte = p_ca
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW
		slot.adsr_opcode_modified = true
