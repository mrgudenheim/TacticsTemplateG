class_name SharedOpRaiseOctave
## FFT analog: smd_raise_octave @ LAB_80015A10
##                (jumptable @ 0x80028B60)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, _slot: _SS,
		_op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## RaiseOctave — opcode 0x95 at FFT LAB_80015A10. 0 params.
	## Adds 0xC (=12) to chan+0x7e via `addiu v0, v0, 0xc`. Pairs with
	## probe_opcode_raise_octave on octave_pre (chan+0x7e read pre-add).
	_ProbeCounters.opcode_raise_octave += 1
	_Trace.emit("opcode_raise_octave", {
		"call_index": _ProbeCounters.opcode_raise_octave,
		"octave_pre": channel.bmidi_baseline_byte & 0xFFFF,
	})
	channel.octave = mini(7, channel.octave + 1)
	channel.bmidi_baseline_byte = (channel.bmidi_baseline_byte + 12) & 0xFF
