class_name SharedPerTickStreamEnd
## FFT analog: end-of-stream KOFF logic at L8001adf0 + L800159ac
##
## When the feds opcode stream is exhausted AND there's no remaining
## note duration, fire one-shot end-of-stream housekeeping:
##   - Arm KOFF_PENDING (audible primaries only)
##   - Set FLAG_STREAM_END so flush_tick deactivates the slot
##   - Mirror EndBar's bit-clear so case-16 spurious S in flag_word
##     doesn't fire mid-stream
##   - Clear slot.active_word bit 0x1 so the walker gate disarms

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(dispatcher, channel: _CH, slot: _SS) -> void:
	if channel.opcode_pos >= dispatcher.get_events().size() and channel.note_duration == 0:
		if not channel.stream_end_fired:
			# Replace "all-channels-done" rule with "last KON-firer's
			# stream_end fires KOFF". Probe spu_keyoff confirmed PCSX
			# fires v20 KOFF at sub_tick 141.5 (= ch6 silent driver
			# stream_end), v21 KOFF at 131.5 (= ch7 silent driver
			# stream_end). Earlier silent drivers do NOT trigger KOFF —
			# only the channel that fired the most-recent primary KON.
			# For audible-only sessions (cure) the audible IS the
			# last_kon_channel, so its stream_end fires KOFF correctly.
			var fire_koff: bool = (slot.last_kon_channel == channel)
			# Fallback for cure-style audible-only with no overlay: if
			# nobody armed last_kon_channel (e.g. all KONs were
			# secondary), preserve original "audible without silent
			# overlay" behavior.
			if slot.last_kon_channel == null and \
					not channel.is_silent_driver and not channel.has_silent_overlay:
				fire_koff = true
			if fire_koff:
				slot.flag_word |= _SS.FLAG_KOFF_PENDING
				slot.flag_word |= _SS.FLAG_STREAM_END
			slot.driving_channels -= 1
			# Mirror EndBar's bit-clear here to suppress the case-16
			# spurious S in flag_word.
			slot.flag_word &= ~(_SS.FLAG_PRIMARY_KON | _SS.FLAG_SECONDARY_KON)
			# Empty/exhausted bytecode reaches stream-end without ever
			# dispatching EndBar (0x90). Mirror the EndBar clear here so
			# end-of-stream and EndBar are semantically equivalent.
			slot.active_word &= ~0x1
			channel.stream_end_fired = true
			# Mirror FFT's PC 0x800159ac end-of-Note channel-deactivation
			# handler which ORs 0x54 (incl. bit 0x4 = FLAG_PITCH_UPDATE)
			# into chan+0x04 BEFORE zeroing chan+0x00. The bit persists
			# through the silent period until the kill chain reactivates
			# the channel.
			channel.pending_kill_pitch_flush = true
