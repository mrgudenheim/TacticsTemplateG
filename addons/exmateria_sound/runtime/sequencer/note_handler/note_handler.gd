class_name SequencerNoteHandler
## Per-note dispatch: stages all SPU register inputs (pitch, vol_l/r,
## ADSR1/2, sample addrs) on the slot + arms walker flags so the
## end-of-tick walker.tick + flush_tick pipeline commits the KON.
## Mirrors FFT's smd_note_handler @ 0x80015a40 → FUN_80017118 +
## FUN_80014590 staging path (Pass 7.E.F+G).
##
## ADSR override pattern (ts.adsr_*_override + ApplyAdsrOverrides)
## is kept until ADSR opcodes (C2/C4/C5/C6/C7/C9/CA) write
## channel.adsr1/2 directly with mid-track walker arming — a
## behavior-change follow-up. Same for vol_l/r computation (music's
## 0x5A00/0x2500 pan curve; FFT formula port deferred).

const _TraceWriter = preload("res://addons/exmateria_sound/runtime/sequencer/trace/trace_writer.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _SharedComputePitch = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_pitch.gd")
const _SharedComputeVolLr = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_vol_lr.gd")


static func apply(sequencer, ts, event) -> void:
	if ts.voice_idx < 0:
		return

	if event.is_note():
		var _octave: int = ts.ctx.channel.octave
		var midi_note: int = _octave * 12 + event.relative_key

		# Pass D1 foundation — FFT Note pre-pass at PC 0x800153B8-C4:
		# if (chan_word_0 & 0x8 = CHAN0_HAS_TONES) == 0:
		#     chan+0x94 = velocity << 8
		# Music's HAS_TONES bit is normally CLEAR (it's a play_sound init
		# marker only set by SFX init at FFT L80013CD0 — see slot_state.
		# gd:63), so this fires every note. Sets channel.chan_92_value
		# so the SFX-style vol formula has the FFT-faithful velocity
		# input. Currently shadowed — music's vol formula in note_
		# handler still applies the manual velocity * dynamics *
		# master_vol chain. The D1 full port (swap to SFX vol formula
		# reading chan_92) requires reconciling pan_offset_ae scale
		# differences (music: 0..127 unsigned, center=64; SFX: signed
		# offset around 0x4000) — deferred per docs/D1_VOL_FORMULA_
		# DESIGN.md.
		if (ts.ctx.channel.channel_word_0 & 0x8) == 0:
			ts.ctx.channel.chan_92_value = (event.velocity << 8) & 0xFFFF

		# FFT smd_note 0x8000 gate (PC 0x80015494-C4): when 0xAC's deferred-
		# arm bit is set on chan_word_0, clear it and arm the full walker
		# fan-out (incl. WALKER_FLAG_VOL_LR_SWEEP = 0x002) + chan_word_1
		# prestage bits. Bit 0x8000 of chan_word_0 is set by the else-
		# branch of Hyp_instrument_data_loader at PC 0x8001708C when
		# chan_word_0 lacks the HAS_TONES bits (0x4 | 0x8) — i.e., every
		# music-track 0xAC. SFX takes the if-branch and arms 0x1FF
		# directly inside instrument.gd; this consumer is music-side
		# only. See docs/MUSIC_VOL_REGISTER_SWEEP_INVESTIGATION.md.
		if (ts.ctx.channel.channel_word_0 & 0x8000) != 0:
			ts.ctx.channel.channel_word_0 &= 0x7FFF
			ts.ctx.channel.channel_word_1 |= 0x300
			ts.ctx.slot.walker_flag_word |= 0x1FF

		# FFT smd_note_set_bit_0x180 @ PC 0x80015470-74 — chan_word_0 |=
		# 0x180 (NOTE_FIRED | PITCH_REQ) unconditionally on every note
		# byte. The setter falls inside smd_dispatcher_per_channel and
		# fires post the 0x8000 deferred-arm consumer; bit 0x100 is then
		# one-shot, cleared by the next IRQ's per-tick mask `& 0xf8ff`
		# at PC 0x80015398 (mirrored in runtime.gd::_run_music_entity_iter
		# + sequencer.gd::tick). Pairs with PCSX
		# probe_per_channel_tick_entry chan_word_0 (Tier 1.5 — see
		# MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md §2). The SFX-side mirror
		# already exists in shared/note_handler/note_handler.gd:64.
		ts.ctx.channel.channel_word_0 |= (_SS.CHAN0_NOTE_FIRED | _SS.CHAN0_PITCH_REQ)

		var _slur: bool = (ts.ctx.channel.channel_word_0 & 0x800) != 0
		if ts.current_note >= 0 and not _slur:
			# Pass 7.E.F — retrigger KOFF deferred to flush_tick. The fresh
			# FLAG_PRIMARY_KON armed below causes flush_kon_commit's
			# _commit_kon to issue an internal mixer.key_off(voice)
			# immediately before mixer.key_on (FFT re-key-prep KOFF inside
			# FUN_8001ACF0). So no explicit KOFF arm here — the KON's
			# atomic KOFF+KON pair handles the retrigger.
			ts.current_note = -1
			ts.hold_note_for_retrigger = false

		# Pass 7.D.f — read audible-path instrument fields from channel.*
		# (populated by 0xAC's _load_inst_into_channel call).
		var _inst_idx: int = ts.ctx.channel.instrument_idx
		var has_sample: bool = false
		if _inst_idx < sequencer.waveset.instruments.size():
			var inst: WavesetParser.Instrument = sequencer.waveset.instruments[_inst_idx]
			if not inst.is_null:
				has_sample = true
		var fine_tune: int = ts.ctx.channel.fine_tune
		var adsr1: int = ts.ctx.channel.adsr1
		var adsr2: int = ts.ctx.channel.adsr2
		var start_addr: int = ts.ctx.channel.sample_start_addr
		var resolved_loop_addr: int = ts.ctx.channel.sample_loop_addr
		# Stage slot fields used by mixer.key_on_with_addresses on KON.
		# These writes happen regardless of walker bits — the SPU gets
		# the registers via the mixer.key_on() native call, not via
		# walker fan-out. The walker arms below match FFT's actual
		# per-Note arms (PC 0x80015434, 0x80015460); see
		# docs/MUSIC_PER_NOTE_WALKER_OVER_ARM_INVESTIGATION.md.
		ts.ctx.slot.sample_start_addr = start_addr
		ts.ctx.slot.sample_loop_addr = resolved_loop_addr
		ts.ctx.slot.adsr1 = adsr1
		ts.ctx.slot.adsr2 = adsr2
		# iter-25: copy inst byte 0xf (= channel.mode_byte_60, populated
		# from waveset ab[7]) into slot.adsr2_mode_byte. FFT
		# Hyp_instrument_data_loader does this at PC 0x80017014
		# (`sw v0, 0x60(a1)`); the walker's LOW writer reads
		# slot+0x60 as the release-mode selector (mode==7 → bit 5 set
		# = exponential release). Iter-23/24's framing said slot+0x5c
		# was the source; iter-25 found the walker's s0 register is
		# slot+4, so `lw a2, 0x5c(s0)` reads effective slot+0x60.
		# See docs/MUSIC_ITER25_VOICE_16_17_RELEASE_TAIL.md.
		ts.ctx.slot.adsr2_mode_byte = ts.ctx.channel.mode_byte_60
		# Iter-32: mirror channel.release_rate_byte (set by inst-load or
		# opcode 0xC5) onto slot.release_rate_byte = FFT slot+0x6A. The
		# walker's LOW writer reads slot+0x6A as the rate input
		# independent of the standing ADSR2 register. Without this copy
		# the slot field would lag the inst-load default and miss
		# mid-track 0xC5 mutations on per-note KEY-ON.
		# See docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
		ts.ctx.slot.release_rate_byte = ts.ctx.channel.release_rate_byte

		# FFT smd_note PC 0x80015434-38: per-Note arm of
		# WALKER_FLAG_ADSR2_LOW (the only walker bit FFT writes
		# directly on Note dispatch outside the 0x8000 gate path).
		ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW

		# Pass 7.D.d — FFT-faithful pitch path. Set channel.pre_pitch_acc_
		# u32 = pre_pitch_baseline << 16 (per SharedComputePitch.apply at
		# FFT LAB_80015458 PC 0x8001545C). Then evaluate the formula to
		# get the SPU raw_pitch via PitchTable.note_to_pitch — combines
		# pre_pitch_acc high + pitch_bend (chan+0x88 = LFO output) +
		# clamping per FFT FUN_80017424. The LFO's per-tick recompute in
		# Sequencer.tick re-runs evaluate() when channel.pitch_bend
		# changes (CHAN1_PITCH_PRESTAGE set), so mid-note vibrato lands.
		var pre_pitch_baseline: int = ((ts.ctx.channel.bmidi_baseline_byte + event.relative_key) & 0xFF) * 256 + fine_tune + ts.ctx.channel.word_86
		ts.ctx.channel.pre_pitch_acc_u32 = (pre_pitch_baseline & 0xFFFF) << 16
		ts.ctx.slot.fine_tune = fine_tune
		var pitch: int = _SharedComputePitch.evaluate_with_music_probe(ts.ctx.channel, ts.ctx.slot)
		ts.ctx.channel.pitch_state = pitch  # legacy field (no live consumer)
		# Stage pitch on slot. active_word bit 0x1 enables walker
		# fan-out (FFT FUN_80014590 per-slot gate at ram:80014638).
		# FFT smd_note PC 0x80015460 arms CHAN1_PITCH_PRESTAGE on
		# chan_word_1 (NOT WALKER_FLAG_PITCH directly); the per-tick
		# drain in Runtime._run_music_entity_iter / Sequencer.tick
		# transitions it to WALKER_FLAG_PITCH on the next IRQ. This
		# also recomputes pitch using mid-note LFO state. See
		# docs/MUSIC_PER_NOTE_WALKER_OVER_ARM_INVESTIGATION.md.
		ts.ctx.slot.pitch_staging = pitch
		ts.ctx.slot.active_word |= 0x1
		ts.ctx.channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE

		# Pass D1 — FFT-faithful vol_l/vol_r via SharedComputeVolLr.
		# apply() stages vol_staging_l/r AND arms WALKER_FLAG_VOL_LR_RAW
		# on slot.walker_flag_word, matching FFT PC 0x8001732C-30
		# (vol formula epilogue's unconditional `ori v0, v0, 0x1`).
		# Iter-14 fix: previously this site skipped the walker arm,
		# leaving per-note vol_register writes missing on voices that
		# don't go through the per-tick CHAN1_VOL_PRESTAGE drain
		# (voice 6 = 18 missing on MUSIC_34).
		# See docs/MUSIC_ITER14_VOL_LR_RAW_WALKER_ARM.md.
		_SharedComputeVolLr.apply(ts.ctx.channel, ts.ctx.slot, sequencer.master_vol)
		# Locals retained for the trace dict below (key_on trace).
		var vol_l: int = ts.ctx.slot.vol_staging_l
		var vol_r: int = ts.ctx.slot.vol_staging_r

		if has_sample:
			# Pass 7.E.F — KON deferred to flush_tick. Populate the slot
			# fields flush_tick._key_on_voice reads (instrument_idx,
			# reverb_send_enabled — pitch_staging, vol_staging_l/r,
			# adsr1/2, sample_start/loop_addr already populated above).
			# Clear any duration-KOFF pending so a fresh note in the same
			# tick supersedes the KOFF (avoids end-of-tick KOFF-after-KON
			# kill). FLAG_PRIMARY_KON triggers _commit_kon which issues
			# mixer.key_off(voice) before mixer.key_on(voice) — atomic
			# retrigger via FFT FUN_8001ACF0.
			ts.ctx.slot.instrument_idx = _inst_idx
			ts.ctx.slot.reverb_send_enabled = ts.ctx.channel.reverb_send_enabled
			ts.ctx.slot.flag_word &= ~_SS.FLAG_KOFF_PENDING
			ts.ctx.slot.flag_word |= _SS.FLAG_PRIMARY_KON
			# MUSIC_ITER59 — bridge slot → channel for the keyon_per_voice
			# precursor probe. The shared _arm_kon path sets this via the
			# CHAN0_KON_ARM gate which music doesn't traverse; without it
			# slot.last_kon_channel stays null on music KONs and the
			# probe's channel-state fields read -1.
			ts.ctx.slot.last_kon_channel = ts.ctx.channel
			_TraceWriter.trace(sequencer, ts, "key_on", {
				"midi_note": midi_note,
				"velocity": event.velocity,
				"delta_time": event.delta_time,
				"fine_tune": fine_tune,
				"pitch": pitch,
				"vol_l": vol_l,
				"vol_r": vol_r,
				"adsr1": adsr1,
				"adsr2": adsr2,
			})
		else:
			_TraceWriter.trace(sequencer, ts, "key_on_skipped", {
				"midi_note": midi_note,
				"velocity": event.velocity,
				"delta_time": event.delta_time,
				"reason": "missing_sample",
			})

		ts.current_note = midi_note
		ts.ctx.channel.note_duration = event.delta_time
		_TraceWriter.trace(sequencer, ts, "note", {
			"midi_note": midi_note,
			"velocity": event.velocity,
			"delta_time": event.delta_time,
		})

	elif event.is_tie():
		ts.ctx.channel.note_duration += event.delta_time
		_TraceWriter.trace(sequencer, ts, "tie", {
			"delta_time": event.delta_time,
		})

	else:  # Rest
		ts.ctx.channel.note_duration = event.delta_time
		_TraceWriter.trace(sequencer, ts, "rest_note", {
			"delta_time": event.delta_time,
		})
