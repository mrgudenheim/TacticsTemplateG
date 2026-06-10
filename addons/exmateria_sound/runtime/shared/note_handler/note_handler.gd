class_name SharedNoteHandler
## FFT analog: Note handler at PC 0x80015428 + 0x8001545C
##              (inline byte < 0x80 path in smd_interpreter_tick)
##
## In FFT, the Note handler is inline at the top of smd_interpreter_tick
## (PC 0x80015428..0x80015520, ~30 lines of MIPS). Extracted here as a
## single class with static funcs mirroring each sub-stage so probe
## sites stay grep-able by FFT PC.
##
## Public entry: `apply(dispatcher, channel, slot, note, s2_snapshot)`.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _ComputePitch = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_pitch.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS,
		note: SMDOpcodes.NoteEvent, s2_snapshot: int) -> void:
	# probe_note_handler (GOLD #3). Mirror of FFT BP @ 0x80015428.
	_ProbeCounters.note_handler += 1
	_Trace.emit("note_handler", {
		"call_index": _ProbeCounters.note_handler,
		"delta_time": note.delta_time & 0xFFFF,
		"relative_key": note.relative_key & 0xFF,
		"slot_idx": slot.slot_idx,
		"is_silent": channel.is_silent_driver,
	})
	## Note opcode (0x00..0x7F) — Note pre-pass + Note handler at 0x80015428.
	## Per FFT semantics (FUN_80017118 L800171b8/L80017334):
	##   bit 0x100 = vol prestage   (drains to walker bit 0x1)
	##   bit 0x200 = pitch prestage (drains to walker bit 0x4)

	# FFT PC 0x80015432-0x80015438: every Note dispatch sets walker_
	# flag_word bit 0x080 unconditionally.
	slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW

	var voice_writes: bool = not channel.is_silent_driver

	# Pre-pass: arm CHAN1_PITCH_PRESTAGE so the upcoming drainer fires
	# walker bit 0x4.
	channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE

	if note.is_rest():
		channel.channel_word_0 |= _SS.CHAN0_KON_ARM
		channel.note_duration = note.delta_time & 0xFFFF
		return

	if note.is_tie():
		channel.note_duration = note.delta_time & 0xFFFF
		return

	# True Note: stage pitch from velocity + relative_key + octave.

	# smd_note_finetune_store @ PC 0x800153C4 — stage raw note_byte<<8 at
	# chan+0x92. Gated by bit 0x008 of chan+0x0 (CHAN0_HAS_TONES).
	if (channel.channel_word_0 & _SS.CHAN0_HAS_TONES) == 0:
		channel.chan_92_value = (note.note_byte << 8) & 0xFFFF

	# FFT L80015460-0x5464: atomic write of slot+0x2 |= 0x200.
	slot.flag_word |= _SS.FLAG_VOL_UPDATE
	channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE | _SS.CHAN1_VOL_PRESTAGE
	channel.channel_word_0 |= (_SS.CHAN0_NOTE_FIRED | _SS.CHAN0_PITCH_REQ)   # 0x180

	# probe_note_post_state (GOLD #4). Mirror of FFT BP @ 0x80015494.
	_ProbeCounters.note_post_state += 1
	_Trace.emit("note_post_state", {
		"call_index": _ProbeCounters.note_post_state,
		"chan_0_mask_180": channel.channel_word_0 & 0x180,
		"chan_2_mask_200": slot.flag_word & 0x200,
	})

	_apply_instrument_to_slot(channel, slot)
	_arm_kon(channel, slot, s2_snapshot, voice_writes)
	_compute_durations(channel, note)

	# Stage the pitch value via the pitch helper.
	var _baseline_pitch: int = _ComputePitch.apply(channel, slot, note)
	# Stash raw velocity for the drainer in play_sound.gd.
	slot.note_velocity_raw = note.velocity


static func _apply_instrument_to_slot(channel: _CH, slot: _SS) -> void:
	## Silent drivers copy sample addresses AND ADSR. Audible primary
	## still owns instrument_idx + fine_tune (slot-side state used in
	## pitch formula and inst-binding semantics).
	if channel.instrument_idx >= 0:
		var copy_full: bool = not channel.is_silent_driver
		if copy_full:
			slot.instrument_idx = channel.instrument_idx
			slot.fine_tune = channel.fine_tune
		slot.adsr1 = channel.adsr1
		slot.adsr2 = channel.adsr2
		slot.prev_adsr2 = slot.adsr2
		slot.sample_start_addr = channel.sample_start_addr
		slot.sample_loop_addr = channel.sample_loop_addr


static func _arm_kon(channel: _CH, slot: _SS, s2_snapshot: int, voice_writes: bool) -> void:
	## Snapshot-conditional primary KON (the s4 binding from L9519–9534):
	## only when channel_word_0 had 0x400 set at dispatcher entry.
	if (s2_snapshot & _SS.CHAN0_KON_ARM) != 0:
		slot.flag_word |= _SS.FLAG_PRIMARY_KON
		slot.last_kon_channel = channel
		if voice_writes:
			slot.force_envelope_open = true


static func _compute_durations(channel: _CH, note: SMDOpcodes.NoteEvent) -> void:
	## Arm/reset the idle-timeout TTL + derive note_duration / idle_timeout
	## from byte_76 + delta_time + byte_7A case selector.
	channel.ttl_sub_ticks = 180

	# Apply slot+0x7A case selector per FFT L800156CC-700.
	var v1: int = note.delta_time + channel.byte_76
	if v1 > 0:
		channel.note_duration = v1 & 0xFFFF
		var idle: int
		match channel.byte_7A:
			15:
				idle = v1 - 1
			16:
				idle = v1
			_:
				idle = (note.delta_time * channel.byte_7A) >> 4
		if idle == 0:
			idle = 1
		channel.idle_timeout = idle
	else:
		# Alternate path L800156B8-C8.
		var new_b76: int = channel.byte_76 + note.delta_time
		new_b76 = new_b76 % 256
		if new_b76 >= 0x80: new_b76 -= 0x100
		channel.byte_76 = new_b76
		var v1_alt: int = maxi(1, note.delta_time + v1)
		channel.note_duration = v1_alt & 0xFFFF
		channel.idle_timeout = v1_alt
