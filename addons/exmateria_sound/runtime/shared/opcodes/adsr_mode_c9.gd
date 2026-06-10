class_name SharedOpAdsrModeC9
## FFT analog: smd_op_c9_adsr_mode @ LAB_8001627C
##                (opcode 0xC9)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Opcode 0xC9 — ADSR2-high mode store. FFT handler at PC 0x8001627C
	## (jumptable entry @ 0x80028C30):
	##   lhu   v0, 0x4(a2)            ; v0 = walker_flag_word
	##   lbu   v1, 0x0(a0)            ; v1 = param byte
	##   ori   v0, v0, 0x40           ; set WALKER_FLAG_ADSR2_HIGH
	##   sh    v0, 0x4(a2)            ; commit walker_flag_word
	##   ...                          ; arg_size = 1
	##   _sw   v1, 0x5c(a2)           ; store byte at slot+0x5c
	##
	## Same shape as 0xC4 (ADSR2 sustain rate, stores at slot+0x68) and
	## 0xCA (ADSR2 release mode, stores at slot+0x60) — sets the same
	## WALKER_FLAG_ADSR2_HIGH so the next walker pass fans out to
	## FUN_8001B9D4. The slot+0x5C value is consumed by FUN_8001B9D4 as
	## part of the sustain-mode selector path. No Godot consumer reads
	## byte_5c today (parity-shadow only); the walker arm is what
	## matches PCSX's probe_adsr2_register row count cad-for-cad on
	## bytecodes that use 0xC9 (disillusionment_3_no_music + cat0000
	## SFX bank).
	_ProbeCounters.opcode_c9_adsr += 1
	_Trace.emit("opcode_c9_adsr", {
		"call_index": _ProbeCounters.opcode_c9_adsr,
		"byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	var p_c9: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	if voice_writes:
		slot.byte_5c = p_c9
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_HIGH
		slot.adsr_opcode_modified = true
