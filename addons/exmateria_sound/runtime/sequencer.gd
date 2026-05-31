class_name Sequencer
## Tick-based SMD sequencer driving the SPU mixer.
## Track 0 = conductor (tempo, time sig). Tracks 1+ = instrument voices.

const _TraceWriter = preload("res://addons/exmateria_sound/runtime/sequencer/trace/trace_writer.gd")
const _TraceOpcode = preload("res://addons/exmateria_sound/runtime/sequencer/trace/trace_opcode.gd")
const _OpcodeTable = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/_table.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _SharedPerTickAdvanceLfo = preload("res://addons/exmateria_sound/runtime/shared/per_tick/advance_lfo.gd")
const _SharedComputePitch = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_pitch.gd")
const _SharedComputeVolLr = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_vol_lr.gd")
const _SharedEntityList = preload("res://addons/exmateria_sound/runtime/shared/entity_list.gd")
const _AdvanceTrack = preload("res://addons/exmateria_sound/runtime/sequencer/per_tick/advance_track.gd")
const _NoteHandler = preload("res://addons/exmateria_sound/runtime/sequencer/note_handler/note_handler.gd")
const _MusicEntityState = preload("res://addons/exmateria_sound/runtime/music/music_entity_state.gd")
const _MusicChannelContext = preload("res://addons/exmateria_sound/runtime/music/music_channel_context.gd")
const _MusicSlotPool = preload("res://addons/exmateria_sound/runtime/music/music_slot_pool.gd")
const _SharedFlushTick = preload("res://addons/exmateria_sound/runtime/shared/flush_tick.gd")
const _SharedIrqWalker = preload("res://addons/exmateria_sound/runtime/shared/spu_irq_walker.gd")
const _PerTickLfoPeriodReset = preload("res://addons/exmateria_sound/runtime/shared/per_tick/lfo_period_reset.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Runtime = preload("res://addons/exmateria_sound/runtime/runtime.gd")

var mixer: Spu
var waveset: WavesetParser
var native_sequencer := FFTSmdSequencerNative.new()
var tracks: Array[TrackState] = []
var tempo_bpm: float = 120.0
var samples_per_tick: float = 0.0
var tick_accumulator: float = 0.0
var total_ticks: int = 0
var master_vol: int = 0x7F00
# Pass 6 shadow state — FFT-faithful music entity (header fields,
# master vol/pan/reverb, tempo accumulators). Populated by load_smd
# alongside the existing instance fields; no consumer reads it yet.
# Pass 7+ migrates dispatch onto this object cluster-by-cluster.
var music_entity: _MusicEntityState = null
# Pass 7.E.A — inert walker + flush instances. Constructed in _init.
# Pass 7.E.B/C/D/E/F/G migrate per-IRQ SPU writes onto these one
# register class at a time. Until then they don't run (no tick() calls
# from Sequencer.tick).
var _music_slot_pool: _MusicSlotPool = null
var _flush_tick: _SharedFlushTick = null
var _irq_walker: _SharedIrqWalker = null
var rendered_frames_total: int = 0
var debug_trace_enabled := false
var debug_trace: Array = []
var debug_runtime_poll_enabled := false
var spu_trace_order: int = 0
var _use_native_core := false
var _native_mode := false
var _runtime = null
# Opcode probe: turn individual control opcodes into no-ops (still
# parsed, still dispatched, but _process_opcode returns early). Used
# for before/after audio-diff validation of opcode implementations —
# render twice, once with the opcode disabled, measure the audio
# delta to confirm the handler actually changes output audibly.
var disabled_opcodes: Dictionary = {}  # {op_byte: true}


class TrackState:
	var track_idx: int = -1
	var events: Array = []
	var event_idx: int = 0
	var done: bool = false

	# Pass 7.A bridge — paired ChannelState/SlotState halfword storage.
	# Populated by load_smd; the source of truth for octave / slur / pan /
	# volume / instrument / reverb / wait_ticks (= note_duration) /
	# note_ticks_remaining (= idle_timeout) / base_pitch (= pitch_state) /
	# flag_0xFE / flag_0x11E. Variant-typed to avoid a preload cycle:
	# the context preloads channel_state.gd / slot_state.gd, and music
	# opcode files (which preload sequencer.gd indirectly) would form
	# a circular dependency on a typed field.
	var ctx = null

	# Note lifetime state (no FFT halfword equivalent — Godot renderer
	# uses `-1` sentinel for "no note playing").
	var current_note: int = -1
	var hold_note_for_retrigger: bool = false

	# Pass D2 — ADSR opcodes (C2/C4/C5/C6/C7/C9/CA) now write
	# channel.adsr1/2 directly and arm walker bits mid-track. The
	# five ts.adsr_*_override fields + ApplyAdsrOverrides indirection
	# are gone; mid-track ADSR changes are now audible.

	# Pass 7.D.d — pitch-LFO state migrated onto channel.lfo_* /
	# channel.lfo_sub_*[0] (FFT-faithful field set), driven per tick
	# by SharedPerTickAdvanceLfo.apply in tick(). The 10 ts.pitch_lfo_*
	# fields that lived here were dead code (declared, read by
	# update_pitch_lfo.gd, never written) — deleted.

	# Loop / repeat state — Godot-renderer bookkeeping, no FFT halfword.
	var loop_stack: Array = []  # [[event_idx, count, octave, bmidi_baseline_byte], ...]
	var loop_point: int = -1
	var end_bar_pending: bool = false

	# Conductor-track time-signature state. FFT writes chan+0x38/0x3C
	# but ChannelState doesn't model those (SFX side hasn't been
	# exercised on 0x97). Pass 7.D.h-equivalent migration deferred.
	var time_sig_numerator: int = 4
	var time_sig_denominator: int = 4

	# Pass D2 — 0xC6 low-nibble slide moved to walker arming via
	# direct channel.adsr1 write + WALKER_FLAG_ADSR1_LOW. The
	# adsr1_low_slide_target / _pending fields are gone.

	var voice_idx: int = -1


func _resolve_voice_addresses(inst: WavesetParser.Instrument) -> Dictionary:
	var start_addr := Spu.RAM_INSTRUMENT_BASE + inst.sample_offset + inst.start_offset_bytes
	var end_addr := start_addr + inst.sample_size
	# iter-40: FFT PC 0x80016FE0-F0 computes loop_addr as
	#   loop_addr = sample_offset + loop_offset      (NO WAVESET_RAM_BASE)
	# whereas start_addr at PC 0x80016FDC adds WAVESET_RAM_BASE.
	# Godot's `inst.sample_size` IS FFT's loop_offset (same bytes
	# [4..5] of the waveset entry; see waveset_parser.gd:85).
	# Mirrors shared/opcodes/instrument.gd:62.
	# See docs/MUSIC_ITER40_SAMPLE_REPEAT_ADDR_OFFSET.md.
	var loop_addr := inst.sample_offset + inst.sample_size

	if inst.has_explicit_loop_start and inst.loop_offset_bytes >= 0:
		loop_addr = inst.sample_offset + inst.loop_offset_bytes

	return {
		"start_addr": start_addr,
		"loop_addr": loop_addr,
		"end_addr": end_addr,
	}


## Pass 7.D.f — load a WAVESET instrument's audible fields (ADSR1/2,
## fine_tune, resolved sample start/loop addrs) into a ChannelState.
## Mirrors SFX's shared/opcodes/instrument.gd lines 38-49. Called by
## the 0xAC opcode handler and by load_smd's per-track init pre-load
## so notes fired before any 0xAC see populated channel.* fields.
func _load_inst_into_channel(idx: int, channel) -> void:
	channel.instrument_idx = idx
	if waveset == null or idx < 0 or idx >= waveset.instruments.size():
		return
	var inst: WavesetParser.Instrument = waveset.instruments[idx]
	if inst.is_null:
		return
	channel.fine_tune = inst.fine_tune
	channel.adsr1 = inst.adsr1
	channel.adsr2 = inst.adsr2
	# iter-24: propagate instrument's full mode bytes (FFT
	# PC 0x80016FFC-0x80017014). The walker reads channel→slot mode_byte_5c
	# (via slot.byte_5c) to select ADSR2 LOW writer mode bits.
	channel.mode_byte_58 = inst.mode_byte_58
	channel.mode_byte_5c = inst.mode_byte_5c
	channel.mode_byte_60 = inst.mode_byte_60
	# Iter-32: FFT instrument-load also populates slot+0x6A from waveset
	# byte 3 low 5 bits. note_handler copies channel.release_rate_byte
	# to slot.release_rate_byte at Note dispatch. See
	# docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
	channel.release_rate_byte = inst.release_rate_byte
	var addrs: Dictionary = _resolve_voice_addresses(inst)
	channel.sample_start_addr = int(addrs.start_addr)
	channel.sample_loop_addr = int(addrs.loop_addr)
	# Iter-46: FFT Hyp_instrument_data_loader PC 0x80017064-8C — after
	# field copies, sets chan+0x0 |= 0x8000 when (chan_word_0 & 0xC) == 0
	# (the dispatcher's pending-KON staging gate at PC 0x80015494). The
	# other branch (bits 0x4 | 0x8 set) writes chan+0x2 |= 0x300 +
	# chan+0x4 |= 0x1FF for direct slot KON arming; deferred — that gate
	# is never met by music tracks (channel_word_0 starts at 0x1, no bit
	# 0x4 or 0x8). See MUSIC_ITER46_CHAN_WORD_0_BIT_0X8000_INSTRUMENT_LOAD_GATE.md.
	if (channel.channel_word_0 & 0xC) == 0:
		channel.channel_word_0 |= 0x8000


## Shim for shared/opcodes/* that call `dispatcher.get_waveset()` —
## music's Sequencer plays the dispatcher role when its opcode adapter
## (sequencer/opcodes/_table.gd::_dispatch_shared) routes a shared
## opcode body. Used by 0xAD instrument_reload (and 0xAC if ever
## bound — music has its own 0xAC instead).
func get_waveset() -> WavesetParser:
	return waveset


func _init(p_mixer: Spu, p_waveset: WavesetParser) -> void:
	mixer = p_mixer
	waveset = p_waveset
	_update_timing()
	# Pass 7.E.A — construct inert walker + flush. Pool wraps tracks[].
	# No tick() calls yet; instances are live but won't write SPU regs
	# until Pass 7.E.B+ migrates the music note_handler register paths.
	_music_slot_pool = _MusicSlotPool.new(self)
	_flush_tick = _SharedFlushTick.new(_music_slot_pool, mixer)
	_irq_walker = _SharedIrqWalker.new(_music_slot_pool, mixer)
	# Pass 9 — Runtime is the music production driver. Construct
	# unconditionally so get_runtime() always returns a usable instance.
	# Sequencer.tick() (GDScript per-PPQ path) remains for the native-
	# fallback in smd_player.gd and the per-voice render paths in
	# render_smd.gd / render_session_utils.gd that depend on
	# tick_accumulator + samples_per_tick directly.
	_runtime = _Runtime.new(mixer)


func _update_timing() -> void:
	samples_per_tick = (Spu.SAMPLE_RATE * 60.0) / (tempo_bpm * SMDOpcodes.PPQ)


func set_use_native_core(enabled: bool) -> void:
	# Explicit opt-in only. The legacy GDScript path remains the default
	# because several debug/export scripts still drive Spu directly.
	_use_native_core = enabled


func get_runtime():
	## Harness reaches the Runtime instance for IRQ-rate render loops
	## via this accessor. Runtime is constructed unconditionally in
	## _init() (Pass 9).
	return _runtime


func _native_mode_allowed() -> bool:
	return _use_native_core and not debug_runtime_poll_enabled and disabled_opcodes.is_empty()


func _try_enable_native_mode(smd: SMDParser.SMDFile) -> void:
	_native_mode = false
	if not _native_mode_allowed():
		return

	native_sequencer.set_reverb_algorithm(mixer.get_reverb_algorithm())
	var ok := native_sequencer.load_instruments(_build_native_instrument_payload(waveset.instruments), waveset.adpcm_data)
	if ok:
		ok = native_sequencer.load_sequence(smd.initial_tempo, _build_native_track_payload(smd.track_events))
	if ok:
		_native_mode = true
		_sync_from_native()


func load_smd(smd: SMDParser.SMDFile) -> void:
	tracks.clear()
	tempo_bpm = smd.initial_bpm
	tick_accumulator = 0.0
	total_ticks = 0
	rendered_frames_total = 0
	debug_trace.clear()
	_update_timing()

	for i in range(smd.track_events.size()):
		var ts := TrackState.new()
		ts.track_idx = i
		ts.events = smd.track_events[i]
		if i > 0 and (i - 1) < Spu.NUM_VOICES:
			ts.voice_idx = i - 1
		# Pass 7.A — pair each TrackState with a MusicChannelContext
		# (channel/slot halfword storage). No reads/writes use it yet;
		# Pass 7.B/C migrate field by field. The slot_idx mirrors the
		# voice mapping music currently uses (track i ≥ 1 → voice i-1).
		var slot_idx := i - 1 if i > 0 else 0
		ts.ctx = _MusicChannelContext.new(slot_idx)
		# Iter-44: MusicChannelContext._init seeds channel.channel_idx from
		# slot_idx (= max(0, i-1)), which collides on track 0 (conductor)
		# vs track 1 — both end up with channel_idx=0. FFT walks per-channel
		# structs at entity+0xB8 + i*0xB0 (one struct per track, FFT channel
		# position == track i), so probe rows ordered by chan_base must pair
		# against Godot track i. Override channel_idx to track_idx so every
		# music probe carries the FFT chan_base index, eliminating the
		# duplicate-0 row + restoring row alignment for lfo_subslot{0..3}_state
		# and every other channel_idx-keyed probe. slot_idx stays for the
		# SPU-voice mapping (voice_mask + ts.voice_idx). See
		# MUSIC_ITER44_CHANNEL_IDX_DUPLICATE_ROW_ALIGNMENT.md.
		ts.ctx.channel.channel_idx = i
		# Pass 7.E.F — populate slot.voice_mask so flush_kon_only_for_slot
		# and flush_koff_post_loop have a non-zero bit to accumulate.
		# SFX sets this in EffectSoundPool.allocate_pair; music's analog
		# is here at track bind. Track 0 (conductor) keeps voice_mask = 0
		# since it has no SPU voice.
		if ts.voice_idx >= 0:
			ts.ctx.slot.voice_mask = 1 << ts.voice_idx
			# Pass 7.D.d / D1 — channel.channel_word_0 must be != 0 for
			# the LFO advance gate at PC 0x800174D0. Bit 0x1 = alive.
			# Music does NOT set CHAN0_HAS_TONES (0x008) — that bit is
			# a play_sound init marker (per FFT L80013CD0) used by SFX
			# only. With HAS_TONES clear, FFT's note pre-pass at PC
			# 0x800153B8-C4 fires the per-note velocity → chan+0x94
			# write every Note (rather than only first-note as it does
			# for SFX). Music's bytecode relies on this for per-note
			# dynamics.
			ts.ctx.channel.channel_word_0 |= 0x1
			# bmidi_baseline_byte = octave * 12 per FFT chan+0x7e. Music's
			# default octave is 4 (from MusicChannelContext init); align
			# with the SFX-faithful baseline so SharedComputePitch.evaluate
			# sees the right a1 = baseline + relative_key.
			ts.ctx.channel.bmidi_baseline_byte = (ts.ctx.channel.octave * 12) & 0xFF
		# Pass 7.D.f — pre-load the default WAVESET instrument so the
		# first key-on (before any 0xAC) reads valid channel.adsr1/2/
		# fine_tune/sample_start/loop_addr. instrument_idx default is
		# 1 (set in MusicChannelContext._init); this seeds the audible
		# fields from WAVESET[1].
		_load_inst_into_channel(ts.ctx.channel.instrument_idx, ts.ctx.channel)
		tracks.append(ts)

	# Pass 6 — populate shadow MusicEntityState from the SMD header.
	# Mirrors FFT FUN_800136C0 (header parse) + FUN_800137D8 (per-channel
	# defaults). Fields not read by current dispatch; Pass 7+ rewires.
	# Pass 8 phase 1 — unlink prior music_entity (if reloading) and
	# push the fresh one onto SharedEntityList. The singleton holds
	# music + SFX entities together; Pass 8 phase 3+ wires the unified
	# Runtime.tick() that walks it. No consumer yet.
	if music_entity != null:
		_SharedEntityList.get_singleton().unlink(music_entity)
	music_entity = _MusicEntityState.new()
	music_entity.channel_count = smd.track_count
	music_entity.nchans = smd.track_events.size()
	music_entity.voice_mask_base = smd.assoc_wds_id
	music_entity.master_vol_raw = smd.initial_volume << 8  # FFT seed = byte<<8
	music_entity.tempo_high = smd.initial_tempo << 16      # FFT entity+0x7C = byte<<16
	# Pass 8 phase 2 — seed entity+0x15 (ppqn), entity+0x3a (subcounter
	# reload), and entity+0x8a (tick_rate_mul). SharedOpTempo's 0xA0
	# dispatch computes `entity+0x78 = tempo_byte * tick_rate_mul`.
	# FFT init's hardcoded entity+0x78 = 0x6600 with implied
	# tempo_byte = 0x66 means tick_rate_mul = 0x100. SFX has its own
	# per-entity init at allocate_pair time.
	music_entity.ppqn = SMDOpcodes.PPQ
	music_entity.tick_rate = 0x100
	music_entity.subcounter_reload = int(0x30 / max(1, SMDOpcodes.PPQ))
	# Sub_tick_budget defaults to FFT's 0x6600 (set as the field default
	# in MusicEntityState). The conductor track's first 0xA0 overrides
	# within the first few IRQs.
	music_entity.sub_tick_budget = 0x6600
	# Pass 8 phase 3 — backref for Runtime's catchup iter. Both refs
	# are unused until set_use_unified_driver(true); legacy
	# Sequencer.tick() path doesn't read them.
	music_entity.owning_sequencer = self
	music_entity.tracks = tracks
	music_entity.all_tracks_done = false
	_SharedEntityList.get_singleton().push(music_entity)

	_try_enable_native_mode(smd)

	# The header tempo is often wrong (e.g. 4.7 BPM). The conductor
	# track's Tempo opcode overrides it on the first tick. We do NOT
	# pre-process here -- Python doesn't, and pre-processing would
	# consume the conductor's first Rest, putting it one step ahead.


func all_done() -> bool:
	for t in tracks:
		if not t.done:
			return false
	return true


func set_disabled_opcodes(ops: Array) -> void:
	## Mark opcodes as probe-disabled (dispatcher returns early before
	## mutating state). Pass an Array of op_byte ints (e.g. [0xD8, 0xE4]).
	disabled_opcodes.clear()
	for op in ops:
		disabled_opcodes[int(op)] = true


func set_debug_trace_enabled(enabled: bool) -> void:
	debug_trace_enabled = enabled
	native_sequencer.set_debug_trace_enabled(enabled)


func set_debug_runtime_poll_enabled(enabled: bool) -> void:
	debug_runtime_poll_enabled = enabled


func get_debug_trace() -> Array:
	if _native_mode:
		return native_sequencer.get_debug_trace()
	return debug_trace.duplicate(true)


func clear_debug_trace() -> void:
	debug_trace.clear()
	spu_trace_order = 0
	native_sequencer.clear_debug_trace()


func set_sampled_voice_trace_enabled(enabled: bool) -> void:
	if _native_mode:
		native_sequencer.set_sampled_voice_trace_enabled(enabled)
		return
	mixer.set_sampled_voice_trace_enabled(enabled)


func set_sampled_voice_trace_dense(enabled: bool) -> void:
	if _native_mode:
		native_sequencer.set_sampled_voice_trace_dense(enabled)
		return
	mixer.set_sampled_voice_trace_dense(enabled)


func set_sampled_voice_trace_voices(voice_indices: PackedInt32Array) -> void:
	if _native_mode:
		native_sequencer.set_sampled_voice_trace_voices(voice_indices)
		return
	mixer.set_sampled_voice_trace_voices(voice_indices)


func get_sampled_voice_trace() -> Array:
	if _native_mode:
		return native_sequencer.get_sampled_voice_trace()
	return mixer.get_sampled_voice_trace()


func _sync_from_native() -> void:
	tempo_bpm = native_sequencer.get_tempo_bpm()
	samples_per_tick = native_sequencer.get_samples_per_tick()
	tick_accumulator = native_sequencer.get_tick_accumulator()
	total_ticks = native_sequencer.get_total_ticks()


func _tick_native() -> bool:
	var ok := native_sequencer.tick()
	_sync_from_native()
	return ok


func _render_native_tick_pcm16() -> PackedInt32Array:
	var pcm := native_sequencer.render_tick_pcm16()
	rendered_frames_total += pcm.size() / 2
	_sync_from_native()
	return pcm


func _render_native_frames_only_pcm16(num_samples: int) -> PackedInt32Array:
	if num_samples <= 0:
		return PackedInt32Array()
	var pcm := native_sequencer.render_frames_only_pcm16(num_samples)
	rendered_frames_total += num_samples
	_sync_from_native()
	return pcm


func _pcm16_to_frames(pcm: PackedInt32Array) -> PackedVector2Array:
	var frame_count := pcm.size() / 2
	var out := PackedVector2Array()
	out.resize(frame_count)
	var inv_32767 := 1.0 / 32767.0
	for i in range(frame_count):
		out[i] = Vector2(float(pcm[i * 2]) * inv_32767, float(pcm[i * 2 + 1]) * inv_32767)
	return out


func _build_native_track_payload(track_events: Array) -> Array:
	var tracks_payload: Array = []
	tracks_payload.resize(track_events.size())
	for track_idx in range(track_events.size()):
		var src_track: Array = track_events[track_idx]
		var dst_track: Array = []
		dst_track.resize(src_track.size())
		for event_idx in range(src_track.size()):
			var event = src_track[event_idx]
			if event is SMDOpcodes.NoteEvent:
				dst_track[event_idx] = {
					"kind": "note",
					"velocity": event.velocity,
					"relative_key": event.relative_key,
					"delta_time": event.delta_time,
				}
			elif event is SMDOpcodes.OpcodeEvent:
				dst_track[event_idx] = {
					"kind": "opcode",
					"opcode": event.opcode,
					"params": event.params,
				}
		tracks_payload[track_idx] = dst_track
	return tracks_payload


func _build_native_instrument_payload(instruments: Array) -> Array:
	var payload: Array = []
	payload.resize(instruments.size())
	for i in range(instruments.size()):
		var inst = instruments[i]
		payload[i] = {
			"is_null": inst.is_null,
			"fine_tune": inst.fine_tune,
			"adsr1": inst.adsr1,
			"adsr2": inst.adsr2,
			"sample_offset": inst.sample_offset,
			"sample_size": inst.sample_size,
			"loop_start": inst.loop_start,
			"loop_offset_bytes": inst.loop_offset_bytes,
			"has_explicit_loop_start": inst.has_explicit_loop_start,
			"has_loop_repeat": inst.has_loop_repeat,
			"start_offset_bytes": inst.start_offset_bytes,
			"start_sample_skip": inst.start_sample_skip,
		}
	return payload


func tick() -> bool:
	## Advance all tracks by one tick. Returns false when done.
	if _native_mode:
		return _tick_native()

	if all_done():
		return false

	for ts in tracks:
		if not ts.done and ts.voice_idx >= 0 and ts.ctx != null:
			# Pass 7.D.d — FFT-faithful LFO via the GDScript engine. The
			# old C++ path (mixer.init_voice_pitch_lfo + per-render
			# fft_tick_pitch_lfo) is now off for Godot music — opcodes
			# 0xD7/D8 stopped calling into mixer. advance_lfo updates
			# channel.pitch_bend; when CHAN1_PITCH_PRESTAGE is set, we
			# recompute slot.pitch_staging via compute_pitch.evaluate and
			# arm WALKER_FLAG_PITCH so the walker emits the modulated
			# SPU pitch.
			_SharedPerTickAdvanceLfo.apply(ts.ctx.channel, ts.ctx.slot, true, true)
			if (ts.ctx.channel.channel_word_1 & _SS.CHAN1_PITCH_PRESTAGE) != 0:
				ts.ctx.slot.pitch_staging = _SharedComputePitch.evaluate_with_music_probe(ts.ctx.channel, ts.ctx.slot)
				ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH
				ts.ctx.channel.channel_word_1 &= ~_SS.CHAN1_PITCH_PRESTAGE
			# Pass D1.2 — per-tick vol-recompute via SharedComputeVolLr.
			# 0xE0 (dynamics) + 0xE8 (pan) arm CHAN1_VOL_PRESTAGE on
			# mid-track change; this drains it by restaging vol_staging_
			# l/r and arming WALKER_FLAG_VOL_LR_RAW so the walker emits
			# the SPU update at end-of-tick.
			if (ts.ctx.channel.channel_word_1 & _SS.CHAN1_VOL_PRESTAGE) != 0:
				_SharedComputeVolLr.apply(ts.ctx.channel, ts.ctx.slot, master_vol)
				ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_VOL_LR_RAW
				ts.ctx.channel.channel_word_1 &= ~_SS.CHAN1_VOL_PRESTAGE
		# Note key-off. Pass 7.D — channel.idle_timeout is the source of
		# truth. ts.note_ticks_remaining no longer written.
		var _idle_drained_to_zero: bool = false
		if not ts.done and ts.ctx != null and ts.ctx.channel.idle_timeout > 0:
			ts.ctx.channel.idle_timeout -= 1
			if ts.ctx.channel.idle_timeout == 0:
				_idle_drained_to_zero = true
		var _ntr: int = ts.ctx.channel.idle_timeout
		if not ts.done and _ntr <= 0 and ts.current_note >= 0 and ts.voice_idx >= 0:
			_TraceWriter.trace(self, ts, "key_off", {
				"reason": "duration",
				"midi_note": ts.current_note,
			})
			# Pass 7.E.F — defer duration-KOFF to flush_tick.flush_koff_post_
			# loop. FLAG_KOFF_PENDING only (no FLAG_STREAM_END) — duration
			# KOFFs are NOT bytecode-end, so they shouldn't trigger the
			# FFT release-rate clobber at PC 0x80014EBC (a1=0x6 ADSR2 low
			# write that gates on STREAM_END in flush_koff_post_loop:260).
			# Music's release rate stays at WAVESET inst.adsr2's value.
			# If a fresh note arrives in advance_track below in the same
			# tick, note_handler clears FLAG_KOFF_PENDING before arming
			# FLAG_PRIMARY_KON.
			ts.ctx.slot.flag_word |= _SS.FLAG_KOFF_PENDING
			ts.current_note = -1
			ts.hold_note_for_retrigger = false

		# FFT smd_dispatcher_chan0_clear @ PC 0x80015394-98 — gated on
		# note_duration == 1 (= FFT post-decrement 0 — see runtime.gd
		# matching gate). Legacy Sequencer.tick mirror.
		var _s2_snapshot: int = ts.ctx.channel.channel_word_0 if ts.ctx != null else 0
		var _did_mask_clear: bool = false
		if not ts.done and ts.ctx != null \
				and ts.ctx.channel.note_duration == 1 \
				and (ts.ctx.channel.channel_word_0 & 0xFFFF) != 0:
			ts.ctx.channel.channel_word_0 &= 0xf8ff
			_did_mask_clear = true
		# Advance track. Pass 7.D — channel.note_duration is the source of
		# truth. ts.wait_ticks no longer written.
		if not ts.done and ts.ctx != null and ts.ctx.channel.note_duration > 0:
			ts.ctx.channel.note_duration -= 1
		# FFT per_channel_tick PC 0x800152A8-C0 — end-of-note ADSR2 release-
		# rate force. Mirror of the same block in Runtime._run_music_entity_iter.
		# See docs/MUSIC_ADSR2_LOW_REGISTER_INVESTIGATION.md.
		if not ts.done and ts.ctx != null \
				and ts.ctx.channel.note_duration == 1 \
				and (ts.ctx.channel.channel_word_0 & _SS.CHAN0_LAST_NOTE_FLAG) != 0:
			ts.ctx.slot.adsr2 = (ts.ctx.slot.adsr2 & 0xFFC0) | 0x06
			ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW
		var _wt: int = ts.ctx.channel.note_duration
		if ts.end_bar_pending and ts.current_note < 0 and _wt <= 0:
			ts.done = true
			ts.end_bar_pending = false
			continue
		if _wt <= 0 and not ts.done:
			_AdvanceTrack.apply(self, ts)
		# FFT LFO sub-slot period_reset @ PC 0x800157AC..0x80015804 —
		# legacy Sequencer.tick mirror of runtime.gd's reset gate
		# (+PITCH_REQ tightening).
		if not ts.done and ts.ctx != null \
				and _did_mask_clear and (_s2_snapshot & 0x400) != 0 \
				and (ts.ctx.channel.channel_word_0 & 0x100) != 0:
			_PerTickLfoPeriodReset.apply(ts.ctx.channel)
		# FFT duration-tick KON_ARM @ PC 0x800152F0-F8 — fires at END of
		# per_channel_tick body so KON_ARM set THIS IRQ survives to NEXT
		# IRQ's s2_snapshot. Mirrors runtime.gd post-period_reset arm.
		if _idle_drained_to_zero and ts.ctx != null:
			ts.ctx.channel.channel_word_0 |= _SS.CHAN0_KON_ARM

	# Pass 7.E.F+G — drain flush_tick KON/KOFF arms set during this
	# tick. Order mirrors FFT spu_updater_tick:
	#   1. flush_kon_only_for_slot per slot — accumulates FLAG_PRIMARY_
	#      KON / FLAG_SECONDARY_KON into _pending_kon_*.
	#   2. flush_kon_commit ×2 — first call rotates _pending → _deferred
	#      (one-IRQ deferral mirrors PCSX entity+0x60); second call
	#      drains _deferred so music's deterministic-from-start rendering
	#      sees eager KON commit. SFX uses the single-call deferred form
	#      via play_sound.gd; calling twice here is music-only.
	#   3. flush_koff_post_loop — fires KOFFs for FLAG_KOFF_PENDING slots
	#      + per_tick_clear.
	# Then walker drain (Pass 7.E.B). Two passes mirror FUN_800149DC's
	# two walker fan-out calls per IRQ.
	for ts in tracks:
		if ts.ctx == null:
			continue
		_flush_tick.flush_kon_only_for_slot(ts.ctx.slot)
	_flush_tick.flush_kon_commit()
	_flush_tick.flush_kon_commit()
	_flush_tick.flush_koff_post_loop()
	_irq_walker.tick(0)
	_irq_walker.tick(1)

	total_ticks += 1
	return true


func render_tick() -> PackedVector2Array:
	## Render audio samples for one tick duration.
	if _native_mode:
		return _pcm16_to_frames(_render_native_tick_pcm16())
	var num_samples := int(tick_accumulator + samples_per_tick)
	tick_accumulator = (tick_accumulator + samples_per_tick) - float(num_samples)
	return render_frames_only(num_samples)


func render_tick_pcm16() -> PackedInt32Array:
	if _native_mode:
		return _render_native_tick_pcm16()
	var num_samples := int(tick_accumulator + samples_per_tick)
	tick_accumulator = (tick_accumulator + samples_per_tick) - float(num_samples)
	return render_frames_only_pcm16(num_samples)


func render_frames_only(num_samples: int) -> PackedVector2Array:
	if _native_mode:
		return _pcm16_to_frames(_render_native_frames_only_pcm16(num_samples))
	if num_samples > 0:
		var frames := mixer.render(num_samples)
		rendered_frames_total += num_samples
		if debug_runtime_poll_enabled:
			capture_runtime_polls()
		return frames
	return PackedVector2Array()


func render_frames_only_pcm16(num_samples: int) -> PackedInt32Array:
	if _native_mode:
		return _render_native_frames_only_pcm16(num_samples)
	if num_samples > 0:
		var pcm := mixer.render_interleaved_pcm16(num_samples)
		rendered_frames_total += num_samples
		if debug_runtime_poll_enabled:
			capture_runtime_polls()
		return pcm
	return PackedInt32Array()


func has_active_audio() -> bool:
	if _native_mode:
		return native_sequencer.has_active_audio()
	return mixer.get_active_voice_count() > 0


func get_active_voice_count() -> int:
	if _native_mode:
		return native_sequencer.get_active_voice_count()
	return mixer.get_active_voice_count()


func capture_runtime_polls() -> void:
	if _native_mode:
		return
	if not debug_trace_enabled:
		return
	for ts in tracks:
		if ts.voice_idx < 0:
			continue
		var runtime := mixer.get_voice_debug_info(ts.voice_idx)
		var active := bool(runtime.get("on", false))
		var _wt_poll: int = ts.ctx.channel.note_duration
		if not active and ts.current_note < 0 and _wt_poll <= 0 and ts.done:
			continue
		var row := _TraceWriter.make_trace_row(self, ts, "poll", {
			"track_reverb": ts.ctx.channel.reverb_send_enabled,
			"track_current_note": ts.current_note,
			"track_note_ticks_remaining": ts.ctx.channel.idle_timeout,
			"track_done": ts.done,
		})
		for key in runtime.keys():
			row[key] = runtime[key]
		debug_trace.append(row)


func _process_note(ts: TrackState, event) -> void:
	# Pass 10.B — music's event_dispatch probe + anchor latch flip.
	# Mirrors shared/dispatcher.gd::_dispatch (SFX-side equivalent).
	# Flipping _first_dispatch_fired here lets Runtime's anchor latch
	# (Pass 10.A) reset cadence_index at first-music-fire, so Tier-A
	# probes (cadence_source, vol_register, etc.) emit post-anchor for
	# music sessions just like they do for SFX. The PCSX-side
	# probe_event_dispatch.lua BP @ 0x800153A4 fires for music too,
	# so this is the correct semantic mirror.
	if not _Trace._first_dispatch_fired:
		_Trace._first_dispatch_fired = true
		_Trace._cadence_index = 0
	_ProbeCounters.event_dispatch += 1
	_Trace.emit("event_dispatch", {
		"call_index": _ProbeCounters.event_dispatch,
		"event_type": "note",
		"byte": int(event.velocity) & 0xFF,
		"slot_idx": ts.ctx.slot.slot_idx if ts.ctx != null and ts.ctx.slot != null else -1,
		"is_silent": false,
	})
	_NoteHandler.apply(self, ts, event)


func _process_opcode(ts: TrackState, event) -> void:
	var op: int = event.opcode
	var params: PackedInt32Array = event.params
	_TraceOpcode.trace_opcode(self, ts, event)

	# Pass 10.B — music's event_dispatch probe + anchor latch flip.
	# See _process_note above for rationale.
	if not _Trace._first_dispatch_fired:
		_Trace._first_dispatch_fired = true
		_Trace._cadence_index = 0
	_ProbeCounters.event_dispatch += 1
	_Trace.emit("event_dispatch", {
		"call_index": _ProbeCounters.event_dispatch,
		"event_type": "opcode",
		"byte": op & 0xFF,
		"slot_idx": ts.ctx.slot.slot_idx if ts.ctx != null and ts.ctx.slot != null else -1,
		"is_silent": false,
	})

	# Opcode probe: render as if this opcode had no handler. The trace
	# still records the dispatch (so player_opcode_dispatch_counts is
	# unchanged) — only the state mutation is skipped. Enables
	# before/after audio-diff validation per opcode.
	if disabled_opcodes.has(op):
		return

	_OpcodeTable.dispatch(op, self, ts, params)
