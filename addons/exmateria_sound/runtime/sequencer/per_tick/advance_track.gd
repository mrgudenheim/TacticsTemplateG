class_name SequencerAdvanceTrack
## Pulls events off ts.events until the track has consumed enough delta
## time to satisfy its wait_ticks budget, firing notes and routing
## opcodes through sequencer's dispatch path. Mirrors FFT's
## smd_advance_track inner loop.

const _TraceOpcode = preload("res://addons/exmateria_sound/runtime/sequencer/trace/trace_opcode.gd")
const _NoteLifeTicks = preload("res://addons/exmateria_sound/runtime/sequencer/helpers/note_life_ticks.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")



# Mirror of FFT post-walker look-ahead at PC 0x80015534-94. FFT peeks the
# IMMEDIATELY-NEXT byte (chan+0x16 stream pointer + 0). If that byte is a
# Note (< 0x80) → SET CHAN0_LAST_NOTE_FLAG (bit 0x1000). If it's an opcode
# byte (>= 0x80) → CLEAR. The previous Godot logic peeked ts.events[event_idx]
# AFTER the post-note scan consumed Rests/Fermatas/opcodes, which makes
# Godot see the NEXT NoteEvent past those skips and SET the bit, while FFT
# (peeking one byte) sees an opcode and CLEARS. That divergence shows up on
# probe_per_channel_tick_entry chan_word_0 (e.g. track 1 cad 3: PCSX 0x0181
# vs Godot 0x1181 pre-fix). MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md §6.
#
# MUSIC_ITER58: extended to traverse Repeat/Coda. The doc-described
# clearing set is {0x80 Rest, 0x81 Fermata, 0x90 EndBar w/o loop, 0xB0/B1
# Slur}. Other opcodes (0x99 Coda, 0x9A RepeatBreak, and anything else)
# advance past. Without the 0x99 Coda follow, MUSIC_86 (71 Repeat/Coda
# pairs) drops CHAN0_LAST_NOTE_FLAG inside loop bodies whenever a Note
# is followed by a Coda byte, even though the loop body restarts with a
# Note — which kills the dispatcher.gd:307 end-of-note ADSR2-LOW=6
# force-release gate and leaves the SPU release rate at the instrument's
# slow value (rms_ratio = 1.42 on MUSIC_86 pre-fix).
static func _update_last_note_flag_at(ts, peek_idx: int) -> void:
	var events: Array = ts.events
	var iter_cap: int = events.size() + ts.loop_stack.size() + 8
	while iter_cap > 0:
		iter_cap -= 1
		if peek_idx < 0 or peek_idx >= events.size():
			# Walked off the end. FFT (PC 0x80015688) only clears the
			# bit on a positively-identified non-Note terminator;
			# end-of-events is ambiguous — leave the flag at whatever
			# the dispatcher last set.
			return
		var peek = events[peek_idx]
		if peek is SMDOpcodes.NoteEvent and peek.is_note():
			ts.ctx.channel.channel_word_0 |= _SS.CHAN0_LAST_NOTE_FLAG
			return
		# Non-Note event at peek_idx — figure out which terminator class.
		if not (peek is SMDOpcodes.OpcodeEvent):
			# Tied-note placeholder (NoteEvent with is_note()==false) and
			# any non-opcode artifact — fall through past it.
			peek_idx += 1
			continue
		var byte: int = (peek as SMDOpcodes.OpcodeEvent).opcode & 0xFF
		match byte:
			0x80, 0x81, 0xB0, 0xB1:
				ts.ctx.channel.channel_word_0 &= ~_SS.CHAN0_LAST_NOTE_FLAG
				return
			0x90:
				if ts.loop_point >= 0:
					peek_idx += 1
					continue
				ts.ctx.channel.channel_word_0 &= ~_SS.CHAN0_LAST_NOTE_FLAG
				return
			0x99:
				# Coda — follow back_pos when the top loop entry still
				# has iterations left. Mirrors sequencer/opcodes/coda.gd:
				# entry = [event_idx, count, octave, bmidi]. entry[1] > 0
				# means the loop will body-rewind; entry[0] is the
				# event_idx jumped to (set to ts.event_idx in repeat.gd).
				if not ts.loop_stack.is_empty() \
						and ts.loop_stack[-1][1] > 0:
					peek_idx = ts.loop_stack[-1][0]
					continue
				peek_idx += 1
				continue
			_:
				peek_idx += 1
				continue
	# Iteration cap hit — bounded walk inside a Repeat body. Preserve
	# CHAN0_LAST_NOTE_FLAG so the dispatcher's last positive Note signal
	# survives. FFT only clears on a positively-identified non-Note
	# terminator (PC 0x80015534..0x80015694).


static func apply(sequencer, ts) -> void:
	var accumulated := 0
	var note_fired := false
	# iter-53 safety: the EndBar (0x90) loop-back can produce an
	# infinite advance-track iteration if a track's bytecode has a
	# 0x91→0x90 pair with no time-consuming events between them.
	# Well-formed FFT music never does this, but the guard catches
	# malformed input + bounds worst-case CPU. Conservative cap of
	# 8× the event count is more than enough for a single per-tick
	# call (each call should consume ≥1 event of time, normally).
	var _loop_guard: int = 0
	var _loop_guard_max: int = ts.events.size() * 8

	while not ts.done and ts.event_idx < ts.events.size():
		_loop_guard += 1
		if _loop_guard > _loop_guard_max:
			push_warning("AdvanceTrack: loop guard tripped on track ",
				ts.track_idx, " event_idx=", ts.event_idx,
				" — malformed loop section (0x91→0x90 with no time-consuming events)")
			ts.done = true
			break
		var event = ts.events[ts.event_idx]

		if event is SMDOpcodes.NoteEvent:
			if event.is_note():
				if accumulated > 0 and not note_fired:
					ts.ctx.channel.note_duration = accumulated
					return

				ts.event_idx += 1
				note_fired = true
				sequencer._process_note(ts, event)
				accumulated += event.delta_time

				# Capture the FFT-equivalent "immediately-next byte after the
				# Note" so _update_last_note_flag below peeks the same event
				# FFT's stream-pointer lookahead at PC 0x80015538 sees,
				# BEFORE the post-note scan consumes Rests / Fermatas /
				# opcodes. See MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md §6.
				# MUSIC_ITER58: also a post-scan lookahead (post_idx) is
				# fired below to emulate FFT's Rest-dispatch tick — the
				# end-of-note ADSR2-LOW=6 gate reads the flag at the END
				# of total accumulated wait, which corresponds to FFT's
				# T_rest_start tick lookahead state, not T_note.
				var lookahead_idx: int = ts.event_idx

				# Post-note scan: fermata extends, rest adds wait
				var note_sustain: int = event.delta_time
				while ts.event_idx < ts.events.size():
					var next_evt = ts.events[ts.event_idx]
					if next_evt is SMDOpcodes.OpcodeEvent and next_evt.opcode == 0x81:
						_TraceOpcode.trace_opcode(sequencer, ts, next_evt)
						var dur: int = next_evt.params[0] if next_evt.params.size() > 0 else 0
						accumulated += dur
						note_sustain += dur
						ts.event_idx += 1
					elif next_evt is SMDOpcodes.OpcodeEvent and next_evt.opcode == 0x80:
						_TraceOpcode.trace_opcode(sequencer, ts, next_evt)
						accumulated += next_evt.params[0] if next_evt.params.size() > 0 else 0
						ts.event_idx += 1
					elif next_evt is SMDOpcodes.OpcodeEvent:
						ts.event_idx += 1
						sequencer._process_opcode(ts, next_evt)
						if ts.done or ts.end_bar_pending:
							break
					else:
						break
				var hold_for_retrigger := false
				if ts.event_idx < ts.events.size():
					var next_evt = ts.events[ts.event_idx]
					var _slur: bool = (ts.ctx.channel.channel_word_0 & 0x800) != 0
					hold_for_retrigger = next_evt is SMDOpcodes.NoteEvent and next_evt.is_note() and accumulated == note_sustain and not _slur
				ts.hold_note_for_retrigger = hold_for_retrigger
				# FFT computes note lifetime separately from the raw event wait.
				# Current PCSX captures for the problematic MUSIC_34 lanes show the
				# common 0x0F gate mode, which yields duration - 1 before release.
				ts.ctx.channel.idle_timeout = _NoteLifeTicks.compute(note_sustain)
				ts.ctx.channel.note_duration = accumulated
				_update_last_note_flag_at(ts, lookahead_idx)
				# MUSIC_ITER58: second lookahead at post-scan position
				# emulates FFT's tick AFTER Rest/Fermata dispatch (FFT
				# runs lookahead per tick; Godot batches Note + post-Note
				# opcodes into one call). The end-of-note ADSR2-LOW=6
				# gate at runtime.gd:472 reads the flag at
				# note_duration == 1, i.e. the END of total accumulated
				# wait — which matches the post-scan lookahead's state,
				# not the pre-scan one. Without this, Note → Rest → Note
				# patterns (MUSIC_86: 1218 Rests / 900 Notes) leave the
				# flag CLEARED for the entire Rest period, killing 88
				# end-of-note release-rate writes on PCSX.
				if lookahead_idx != ts.event_idx:
					_update_last_note_flag_at(ts, ts.event_idx)
				return
			else:
				ts.event_idx += 1
				accumulated += event.delta_time

		elif event is SMDOpcodes.OpcodeEvent:
			ts.event_idx += 1
			if event.opcode == 0x80:
				# FFT-faithful pre-Note Rest dispatch. PC 0x8001588C sets
				# chan_word_0 |= 0x400 (KON_ARM) which the dispatcher's
				# post-handler check at PC 0x80015510 reads — bit 0x400
				# in chan_word_0 & 0x500 causes per_channel_tick to exit.
				# Without this exit, Godot batches all conductor-track
				# preamble Tempo (0xA0) opcodes at cad=0 instead of
				# spreading them across cadences; that produced a +0.64%
				# catchup-rate divergence vs PCSX. Dispatching via
				# _process_opcode sets channel.note_duration = rest_byte
				# (see sequencer/opcodes/rest.gd); subsequent IRQs
				# decrement note_duration and skip dispatch until 0.
				# See docs/MUSIC_TEMPO_DRIFT_ROOT_CAUSE.md.
				sequencer._process_opcode(ts, event)
				return
			elif event.opcode == 0x81:
				# Fermata in pre-Note phase is left as inline-accumulate.
				# Music's Fermata always follows a Note in well-formed
				# bytecode (it extends a sustaining note); a pre-Note
				# Fermata is an edge case not observed in MUSIC_34. The
				# FFT smd_fermata handler (PC 0x80015DD0) sets
				# chan_word_0 |= 0x100 + chan+0x74 = byte and exits, but
				# the Godot SequencerOpFermata.apply does
				# `ts.ctx.channel.idle_timeout += params[0]` — which on
				# pre-Note (idle_timeout = -1) gives a sentinel value
				# that misbehaves. Leaving inline-consume preserves the
				# accumulator model for this edge case.
				_TraceOpcode.trace_opcode(sequencer, ts, event)
				accumulated += event.params[0] if event.params.size() > 0 else 0
			else:
				sequencer._process_opcode(ts, event)
				if ts.done:
					ts.ctx.channel.note_duration = accumulated
					return

	# End of events
	if not ts.done:
		if ts.loop_point >= 0:
			ts.event_idx = ts.loop_point + 1
		else:
			ts.done = true
