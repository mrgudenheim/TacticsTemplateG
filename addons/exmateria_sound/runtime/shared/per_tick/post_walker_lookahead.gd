class_name SharedPerTickPostWalkerLookahead
## FFT analog: post-walker look-ahead @ PC 0x80015534..0x80015694
##
## Mutates chan_word_0 bits 0x200 (VOL_PENDING) and 0x1000 (LAST_NOTE_FLAG)
## based on the next non-skip byte at the walker position. Does NOT
## dispatch and does NOT mutate channel.opcode_pos or channel.loop_stack.
## All advancement is local (peek_pos).
##
## Reads `_events` via dispatcher.get_events() — the accessor pattern
## avoids a preload cycle.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(dispatcher, channel: _CH) -> void:
	var events: Array = dispatcher.get_events()
	var peek_pos: int = channel.opcode_pos
	# Defensive iteration cap.
	var iter_cap: int = events.size() + channel.loop_stack.size() + 8
	while iter_cap > 0:
		iter_cap -= 1
		if peek_pos < 0 or peek_pos >= events.size():
			# Walked off the end. FFT (PC 0x80015688) only clears the
			# bit on a positively-identified non-Note terminator (0x80
			# Rest / 0x81 Fermata / 0x90 EndBar / 0xB0/0xB1 Slur).
			# Walking off the end is ambiguous — leave bit at whatever
			# the dispatcher last set (advance_track.gd:31 sets on Note
			# dispatch). MUSIC_ITER58: iter_cap-on-loops + this path were
			# clearing the bit inside deep Repeat/Coda structures, which
			# dropped the dispatcher.gd:307 end-of-note ADSR2-LOW=6 gate.
			return
		var ev = events[peek_pos]
		if ev is SMDOpcodes.NoteEvent:
			# PC 0x80015558 BNE → LAB_80015634 → PC 0x80015648
			# (`ori v0, v0, 0x1000`). Note terminator.
			channel.channel_word_0 |= _SS.CHAN0_LAST_NOTE_FLAG
			return
		var byte: int = (ev as SMDOpcodes.OpcodeEvent).opcode & 0xFF
		match byte:
			0x80:
				channel.channel_word_0 &= ~_SS.CHAN0_VOL_PENDING
				channel.channel_word_0 &= ~_SS.CHAN0_LAST_NOTE_FLAG
				return
			0x81:
				channel.channel_word_0 |= _SS.CHAN0_VOL_PENDING
				channel.channel_word_0 &= ~_SS.CHAN0_LAST_NOTE_FLAG
				return
			0x90:
				if channel.saved_loop_target_pos != 0:
					peek_pos += 1
					continue
				channel.channel_word_0 &= ~_SS.CHAN0_LAST_NOTE_FLAG
				return
			0xB0, 0xB1:
				channel.channel_word_0 &= ~_SS.CHAN0_VOL_PENDING
				channel.channel_word_0 &= ~_SS.CHAN0_LAST_NOTE_FLAG
				return
			0x99:
				# Coda: mirror coda.gd. Use the real loop_stack top
				# count (no virtualization) — when count > 0 follow
				# back_pos. The lookahead may re-enter the same Coda;
				# iter_cap bounds the walk so we don't spin. See
				# MUSIC_ITER58 §6.1 point 2.
				if not channel.loop_stack.is_empty() \
						and channel.loop_stack[-1].count > 0:
					peek_pos = channel.loop_stack[-1].back_pos
					continue
				peek_pos += 1
				continue
			0x9a:
				# RepeatBreak: matches repeat_break.gd — no-op in our
				# implementation (FFT's chan+0xac is observably zero at
				# every observed 0x9A dispatch, so it muddles past).
				peek_pos += 1
				continue
			_:
				peek_pos += 1
				continue
	# Iteration cap hit — bounded walk inside a Repeat body. Preserve
	# CHAN0_LAST_NOTE_FLAG so the dispatcher's last positive Note signal
	# survives; FFT only clears on a positively-identified non-Note
	# terminator (PC 0x80015534..0x80015694).
