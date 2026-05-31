class_name SharedOpAdsr2Sustain
## FFT analog: smd_op_c4_adsr2_sustain @ LAB_800161C4
##                (opcode 0xC4)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## ADSR2 Sustain Bits modifier.
	## Disasm: opcode 0xC4 → LAB_800161e0:
	##   lhu v0, 0x4(a2); ori v0,v0,0x40; sh v0,0x4(a2);
	##   sh v1, 0x68(a2)             ; slot+0x68 = p0
	## Per-tick handler at L80014714-28 sees bit 0x40 of slot+0x4
	## and calls FUN_8001b9d4(voice, slot+0x64, slot+0x58) which
	## writes ADSR2 = (low 6 bits preserved) | ((sustain_byte |
	## mode_a3) << 6).
	## Mode a3 derives from slot+0x58 (a2 in the helper):
	##   a2==1: a3=0 ; a2==5: a3=0x200 ; a2==7: a3=0x300 ;
	##   else 0x100.
	var p_c4_raw: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	# probe_opcode_adsr2_sustain (GOLD #9). Mirror of FFT BP @ 0x800161E0
	# (smd_adsr2_sustain entry, opcode 0xC4 handler). FFT reads the raw
	# param byte with `lbu v1, 0x0(a0)`; emit that same raw byte here so
	# the pair-validator compares pre-mask values bit-exact.
	_ProbeCounters.opcode_adsr2_sustain += 1
	_Trace.emit("opcode_adsr2_sustain", {
		"call_index": _ProbeCounters.opcode_adsr2_sustain,
		"c4_byte": p_c4_raw,
	})
	var p_c4: int = p_c4_raw & 0x7F
	var mode_bits: int = 0x100  # default a3 (sustain_decrease=1)
	var new_sustain_high: int = ((p_c4 | mode_bits) << 6) & 0xFFC0
	channel.adsr2 = (channel.adsr2 & 0x3F) | new_sustain_high
	if voice_writes:
		slot.adsr2 = channel.adsr2
		# FFT slot+0x4 bit 0x040 → FUN_8001B9D4 (ADSR2
		# sustain/high bits 6-15 helper).
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_HIGH
		slot.adsr_opcode_modified = true
