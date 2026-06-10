class_name SharedOpRepeat
## FFT analog: smd_repeat @ PC 0x80015AB8
##                (jumptable @ 0x80028B6C)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, _slot: _SS,
		op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Repeat — smd_repeat at PC 0x80015AB8.
	## Pushes (count = param-1, back_pos, octave) onto loop_stack.
	## Body runs N times (1 initial + N-1 jump-backs).
	## FFT also saves chan+0x7E (bmidi_baseline_byte) at Repeat-time
	## per PC 0x80015AF4 (`lbu a0, 0x7e(a2); sb a0, 0x2(v1)`); Coda's
	## continue path restores it at PC 0x80015B50 (`sh v1, 0x7e(a2)`).
	## Without it, 0x96 LowerOctave inside the loop body permanently
	## drifts bmidi_baseline_byte instead of resetting each iteration.
	var n: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	_ProbeCounters.opcode_repeat += 1
	_Trace.emit("opcode_repeat", {
		"call_index": _ProbeCounters.opcode_repeat,
		"repeat_count": n,
	})
	channel.loop_stack.append({
		"count": n - 1,
		"back_pos": channel.opcode_pos,   # already past Repeat event
		"octave": channel.octave,
		"bmidi_baseline_byte": channel.bmidi_baseline_byte,
		# coda_continuation_pos / coda_bmidi_baseline are populated by
		# the first 0x99 Coda fire inside the loop body (FFT
		# `sw a0, 0x8(a1); sb v0, 0x3(a1)` at PC 0x80015B38 / 0x80015B48).
		# 0x9A RepeatBreak reads them to jump out of the final iteration.
		# Default to back_pos / current bmidi so a 0x9A fired before any
		# Coda still has a non-junk target.
		"coda_continuation_pos": channel.opcode_pos,
		"coda_bmidi_baseline": channel.bmidi_baseline_byte,
	})
