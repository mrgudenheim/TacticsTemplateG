class_name SharedOpAdsrRelease
## FFT analog: smd_release @ 0x800161E0
##                (opcode 0xC5)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## ADSR Release modifier.
	## Disasm: opcode 0xC5 → LAB_800161fc:
	##   lhu v0, 0x4(a2); ori v0,v0,0x80; sh v0,0x4(a2);
	##   sh v1, 0x2e(a2); sh v1, 0x6a(a2)   ; slot+0x6a = p0
	## Per-tick handler at L80014714-28 sees bit 0x80 of slot+0x4
	## and calls FUN_8001bab8(voice, slot+0x6a, slot+0x58) which
	## writes ADSR2 = (existing & 0xFFC0) | ((release_byte |
	## mode_a3) & 0x3F).
	## Mode a3 derives from slot+0x58: a2==7 → a3=0x20
	## (release_mode_exp), else a3=0.
	## Silent drivers also fire C5 (release modifier) so their
	## per-channel adsr2 reflects their bytecode's intended
	## release rate.
	var p_c5: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var release_mode_a3: int = 0  # default a3 (release_mode_exp=0)
	var new_release_low: int = (p_c5 | release_mode_a3) & 0x3F
	channel.adsr2 = (channel.adsr2 & 0xFFC0) | new_release_low
	# Iter-32: FFT opcode 0xC5 stores the raw operand byte to slot+0x6A
	# (`sh v1, 0x6a(a2)` at PC 0x80016218). The walker's LOW writer reads
	# slot+0x6A as the rate input (FUN_8001BAB8 a1), composing the mode
	# bit from slot+0x60 separately. Store the raw byte here; the walker
	# masks `& 0x1F` at read-time.
	# See docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
	channel.release_rate_byte = p_c5
	if voice_writes:
		slot.adsr2 = channel.adsr2
		slot.release_rate_byte = p_c5
		# FFT slot+0x4 bit 0x080 → FUN_8001BAB8 (ADSR2
		# release/low bits 0-5 helper).
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW
		slot.adsr_opcode_modified = true
