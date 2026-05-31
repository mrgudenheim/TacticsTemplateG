class_name SharedOpOctave
## FFT analog: smd_octave @ LAB_800159F0
##                (jumptable @ 0x80028B5C)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, _slot: _SS,
		op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	# probe_opcode_octave (GOLD #8). Mirror of FFT BP @ 0x800159F0.
	# octave_byte = read8(a0) on FFT side = op.params[0] here.
	_ProbeCounters.opcode_octave += 1
	_Trace.emit("opcode_octave", {
		"call_index": _ProbeCounters.opcode_octave,
		"octave_byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	## Octave — sets channel.octave
	if op.params.size() > 0:
		channel.octave = op.params[0]
		# FFT's 0x94 handler at LAB_800159F0 also writes
		# `octave_param * 12` to chan+0x7e (sh v0, 0x7e(a2)
		# at PC 0x80015A04). Godot's bmidi_baseline_byte ≡
		# chan+0x7e low byte.
		channel.bmidi_baseline_byte = (op.params[0] * 12) & 0xFF
