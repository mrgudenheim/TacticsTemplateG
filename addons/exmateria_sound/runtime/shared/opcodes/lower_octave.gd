class_name SharedOpLowerOctave
## FFT analog: smd_lower_octave @ LAB_80015A28
##                (jumptable @ 0x80028B64)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, _slot: _SS,
		_op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## LowerOctave — opcode 0x96
	_ProbeCounters.opcode_lower_octave += 1
	_Trace.emit("opcode_lower_octave", {
		"call_index": _ProbeCounters.opcode_lower_octave,
		"octave_pre": channel.bmidi_baseline_byte & 0xFFFF,
	})
	channel.octave = maxi(0, channel.octave - 1)
	# FFT's 0x96 handler at LAB_80015A28 subtracts 0xC (=12)
	# from chan+0x7e via `addiu v0, v0, -0xc`.
	channel.bmidi_baseline_byte = (channel.bmidi_baseline_byte - 12) & 0xFF
