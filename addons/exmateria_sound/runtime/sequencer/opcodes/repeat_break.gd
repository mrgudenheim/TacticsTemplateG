class_name SequencerOpRepeatBreak
## FFT analog: smd_repeat_break @ LAB_800159f8
##                (opcode 0x9A)


static func apply(sequencer, ts, _params) -> void:
	if ts.loop_stack.size() > 0:
		var entry: Array = ts.loop_stack[-1]
		if entry[1] == 0:  # Last iteration
			var depth := 1
			var search: int = ts.event_idx + 1
			while search < ts.events.size() and depth > 0:
				var e = ts.events[search]
				if e is SMDOpcodes.OpcodeEvent:
					if e.opcode == 0x98:
						depth += 1
					elif e.opcode == 0x99:
						depth -= 1
				search += 1
			ts.event_idx = search
			ts.loop_stack.pop_back()
			return
