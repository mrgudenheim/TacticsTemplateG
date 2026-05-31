class_name SharedPerTickPitchStaging
## FFT analog: per_channel_tick pitch-stage block at PC 0x80015234+
##
## Stages walker PITCH bit + chan_word_1 PITCH_PRESTAGE based on the
## current pre-pitch accumulator and pitch_bend state. Runs every
## dispatcher.tick() after _advance_lfo. Tracks `porta_was_active`
## (pre-decrement state) so the deactivation tick still fires.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")

const FLUSH_PER_DISPATCH := 8


static func apply(channel: _CH, slot: _SS, voice_writes: bool,
		cadence_fired: bool, porta_was_active: bool) -> void:
	## SINGLE pitch_staging recompute per tick — uses current
	## pre_pitch_acc + current pitch_bend (just-updated by LFO if swap).
	##
	## The accumulator MUST advance every sub_tick (120Hz) because PCSX's
	## +21-per-sub_tick pitch deltas confirm 14.22-per-sub_tick chan+0x82
	## increment.
	channel.tick_phase = (channel.tick_phase + 1) % FLUSH_PER_DISPATCH
	if porta_was_active and channel.pre_pitch_delta_u32 != 0:
		var fire_pitch_update: bool = false
		if porta_was_active and cadence_fired:
			fire_pitch_update = true
		if fire_pitch_update:
			slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH
			channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
			var acc_s32: int = channel.pre_pitch_acc_u32
			if acc_s32 >= 0x80000000: acc_s32 -= 0x100000000
			var delta_s32: int = channel.pre_pitch_delta_u32
			if delta_s32 >= 0x80000000: delta_s32 -= 0x100000000
			slot.debug_pitch_acc_at_update = acc_s32
			slot.debug_pitch_delta_at_update = delta_s32
			slot.debug_pitch_bend_at_update = channel.pitch_bend
	elif voice_writes and slot.lfo_active and (slot.walker_flag_word & _SS.WALKER_FLAG_PITCH) != 0:
		# When LFO is active WITHOUT portamento, the LFO swap above
		# already updated channel.pitch_bend. Set the prestage bit so
		# the drainer refreshes pitch_staging every tick the per-tick
		# LFO advances pitch_bend.
		# Iter-35: sub-slot 0 unified — bit 0x1 of chan+0xFE is
		# lfo_sub_active[0].
		if channel.lfo_sub_active[0] != 0:
			channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
