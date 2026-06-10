class_name SequencerTraceWriter
## Per-tick debug trace builder for sequencer.gd.
##
## Builds row Dictionaries with sequencer-instance + track-instance state
## and appends them to `sequencer.debug_trace`. All emit sites cheap-no-op
## when `sequencer.debug_trace_enabled` is false.
##
## sequencer + ts are typed Variant — TrackState is an inner class of
## sequencer.gd so we can't preload-import its type without a cycle.


static func make_trace_row(sequencer, ts, kind: String, extra: Dictionary = {}) -> Dictionary:
	var row := {
		"kind": kind,
		"tick": sequencer.total_ticks,
		"frame": sequencer.rendered_frames_total,
		"tempo_bpm": sequencer.tempo_bpm,
		"track": ts.track_idx,
		"voice": ts.voice_idx,
		"event_idx": ts.event_idx,
		"wait_ticks": ts.ctx.channel.note_duration,
		"octave": ts.ctx.channel.octave,
		"instrument": (ts.ctx.channel.byte_7A + 1),
		"dynamics": ((ts.ctx.channel.expression_acc_s32 >> 24) & 0xFF),
		"pan": ts.ctx.channel.pan_offset_ae,
		"reverb": ts.ctx.channel.reverb_send_enabled,
		"current_note": ts.current_note,
		"note_ticks_remaining": ts.ctx.channel.idle_timeout,
		"slur": ((ts.ctx.channel.channel_word_0 & 0x800) != 0),
	}
	for key in extra.keys():
		row[key] = extra[key]
	return row


static func trace(sequencer, ts, kind: String, extra: Dictionary = {}) -> void:
	if not sequencer.debug_trace_enabled:
		return
	sequencer.debug_trace.append(make_trace_row(sequencer, ts, kind, extra))


static func trace_spu_write(sequencer, ts, register_name: String, value: int, extra: Dictionary = {}) -> void:
	if not sequencer.debug_trace_enabled:
		return
	sequencer.spu_trace_order += 1
	var row := make_trace_row(sequencer, ts, "spu_write", {
		"order": sequencer.spu_trace_order,
		"register": register_name,
		"value": value,
	})
	for key in ["octave", "dynamics", "pan", "reverb", "note_ticks_remaining", "slur"]:
		row.erase(key)
	sequencer.debug_trace.append(row)
