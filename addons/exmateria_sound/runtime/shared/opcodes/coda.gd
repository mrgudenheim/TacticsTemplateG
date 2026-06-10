class_name SharedOpCoda
## FFT analog: smd_coda @ PC 0x80015B00
##                (jumptable @ 0x80028B70)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, _slot: _SS,
		_op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Coda — smd_coda at PC 0x80015B00.
	## If top.count > 0: save (continuation_pos, chan+0x7e) into the stack
	##   entry (FFT entry[8] / entry[3] — read by 0x9A RepeatBreak),
	##   dec count, jump back to back_pos, restore octave + bmidi.
	## Else: pop. Defensive no-op if stack empty.
	_ProbeCounters.opcode_coda += 1
	var _coda_count_pre: int = -1
	if not channel.loop_stack.is_empty():
		_coda_count_pre = channel.loop_stack[-1].count
	_Trace.emit("opcode_coda", {
		"call_index": _ProbeCounters.opcode_coda,
		"count_pre": _coda_count_pre,
	})
	if not channel.loop_stack.is_empty():
		var top: Dictionary = channel.loop_stack[-1]
		if top.count > 0:
			# FFT PC 0x80015B38 `sw a0, 0x8(a1)` — save Coda's incoming
			# opcode_ptr (= position after this Coda byte) as the loop's
			# post-loop continuation. PC 0x80015B48 `sb v0, 0x3(a1)`
			# saves chan+0x7e (bmidi_baseline_byte) for 0x9A to restore.
			top.coda_continuation_pos = channel.opcode_pos
			top.coda_bmidi_baseline = channel.bmidi_baseline_byte
			top.count -= 1
			channel.opcode_pos = top.back_pos
			channel.octave = top.octave
			channel.bmidi_baseline_byte = top.bmidi_baseline_byte
		else:
			channel.loop_stack.pop_back()
