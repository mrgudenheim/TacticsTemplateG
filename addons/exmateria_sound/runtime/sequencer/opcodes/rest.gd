class_name SequencerOpRest
## FFT analog: smd_rest @ 0x80015874
##                (opcode 0x80)

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_sequencer, ts, params) -> void:
	# FFT smd_rest body (PC 0x80015874-0x80015890):
	#   sh  v0, 0x74(a2)    ; note_duration
	#   ori v1, v1, 0x2     ; chan_word_1 |= 0x2  (KOFF arm)
	#   ori v0, v0, 0x400   ; chan_word_0 |= 0x400 (CHAN0_KON_ARM)
	# iter-16 fix: previously only note_duration was set; voices kept
	# playing through rests instead of releasing.
	# See docs/MUSIC_ITER16_SMD_REST_KOFF_ARM_FIX.md.
	ts.ctx.channel.note_duration = params[0] if params.size() > 0 else 0
	# Route FFT chan_word_1 bit 0x2 (KOFF arm) onto Godot's equivalent
	# slot.flag_word.FLAG_KOFF_PENDING consumer — flush_koff_post_loop
	# accumulates the bit and fires SPU KOFF mask. Skip if the track
	# has never KON'd a note (slot is None pre-first-note).
	if ts.ctx.slot != null:
		ts.ctx.slot.flag_word |= _SS.FLAG_KOFF_PENDING
	ts.ctx.channel.channel_word_0 |= _SS.CHAN0_KON_ARM
