class_name Runtime
## FFT analog: spu_updater_tick @ ram:800149dc.
##
## Single per-IRQ driver for music + SFX, running at 240 Hz (per
## FFT's BIOS-timer callback at ram:80017a18 RCnt2 fire). Walks
## SharedEntityList, fires walker passes, runs per-entity catchup
## loops, accumulates KON/KOFF, and renders SAMPLES_PER_IRQ samples
## per call.
##
## Behind a feature flag during Phase 3-5; Sequencer / EffectPlaySound
## continue to drive music + SFX via their existing tick paths until
## Phase 4/5 opt-in flips for the music + SFX harnesses, and Phase 6
## promotes Runtime as the default. Phase 7 deletes the legacy paths.
##
## Companion docs:
##   - docs/PASS_8_CADENCE_DESIGN.md — the *what* and *why*
##   - docs/PASS_8_IMPLEMENTATION.md — the *how*

const _SharedEntityList = preload("res://addons/exmateria_sound/runtime/shared/entity_list.gd")
const _SharedFlushTick = preload("res://addons/exmateria_sound/runtime/shared/flush_tick.gd")
const _SharedIrqWalker = preload("res://addons/exmateria_sound/runtime/shared/spu_irq_walker.gd")
const _MusicEntityState = preload("res://addons/exmateria_sound/runtime/music/music_entity_state.gd")
const _EffectEntity = preload("res://addons/exmateria_sound/runtime/effect_sound/entity_state.gd")
const _EffectPlaySound = preload("res://addons/exmateria_sound/runtime/effect_sound/play_sound.gd")
const _SharedPerTickAdvanceLfo = preload("res://addons/exmateria_sound/runtime/shared/per_tick/advance_lfo.gd")
const _SharedComputePitch = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_pitch.gd")
const _SharedComputeVolLr = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_vol_lr.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _AdvanceTrack = preload("res://addons/exmateria_sound/runtime/sequencer/per_tick/advance_track.gd")
const _PerTickLfoPeriodReset = preload("res://addons/exmateria_sound/runtime/shared/per_tick/lfo_period_reset.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeEmit = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_emit.gd")

const IRQ_HZ := 240
# 44100 / 240 = 183.75 — non-integer. _sample_acc accumulates the
# 60/240 remainder so every 4 IRQs we render 184 samples once
# (240 * 183 + 60 = 44100 exact). No drift.
const SAMPLES_PER_IRQ_BASE := Spu.SAMPLE_RATE / IRQ_HZ           # = 183
const SAMPLES_PER_IRQ_REM := Spu.SAMPLE_RATE % IRQ_HZ            # = 60

# Pass 8 Phase 7-unblock RC1.B — match the legacy SFX harness's
# per-sub-tick walker cadence (FLUSH_PER_DISPATCH = 8 walker fan-outs
# per outer-tick = 8 walker passes per Runtime.tick() IRQ). Without
# this, the catchup body + drainer + KOFF flush re-set walker_flag_word
# bits between Runtime's single-pass walker fires, and Cluster 1's
# walker_flag_word_entry / pitch_register / vol_register row counts
# inflate vs the PCSX baseline. Each pass is cheap when no bits are
# set (active_slots × 24 voices × ~1µs early-out), so over-walking is
# safe — see PASS_8_PHASE7_UNBLOCK_PLAN.md §RC1.B.
const WALKER_FAN_PER_IRQ := 8


var mixer: Spu
var _flush_tick: _SharedFlushTick = null
var _irq_walker: _SharedIrqWalker = null
var _unified_pool: UnifiedSlotPool = null
var _sample_acc: int = 0

# Opt-in: process ONLY SFX (_EffectEntity) entries from the shared list,
# skipping _MusicEntityState. The shared entity list is a process-wide
# singleton holding both music + SFX entities (Sequencer pushes music_entity
# there even when it drives music via its own legacy tick). A game-side SFX
# driver that owns a SEPARATE SPU (e.g. EffectSfxEngine on AudioEngine.sfx_spu)
# must not run music catchup / flush music slots against its own mixer, so it
# sets this true. Default false preserves the unified-driver + parity-harness
# behaviour (process every entity).
var sfx_only: bool = false

# Entity list this Runtime walks. Defaults to the process singleton (single-SPU
# / parity). A multi-SPU game engine injects a PER-UNIT list so each SPU's
# Runtime drives only its own entities. Set the matching list on each
# EffectPlaySound (set_entity_list) so seeded entities land in the right list.
var entity_list = null


func _init(p_mixer: Spu, p_flush_tick: _SharedFlushTick = null,
		p_irq_walker: _SharedIrqWalker = null) -> void:
	## Pass 8 phase 5 — the SFX harness owns its own _SharedFlushTick
	## instance (constructed alongside EffectSoundPool) and an _SharedIrqWalker
	## that the legacy per-sub-tick loop also drives. To keep KON/KOFF
	## accumulators in a single source of truth under --unified-driver,
	## the harness threads its instances through this constructor; Runtime
	## then uses them in its KON scan / commit / KOFF / walker phases.
	## When the args are null (music harness, debugging) Runtime
	## constructs its own UnifiedSlotPool-backed pair, matching the Pass 4
	## music opt-in behaviour.
	mixer = p_mixer
	if p_flush_tick != null:
		_flush_tick = p_flush_tick
	else:
		_unified_pool = UnifiedSlotPool.new()
		_flush_tick = _SharedFlushTick.new(_unified_pool, mixer)
	if p_irq_walker != null:
		_irq_walker = p_irq_walker
	else:
		if _unified_pool == null:
			_unified_pool = UnifiedSlotPool.new()
		_irq_walker = _SharedIrqWalker.new(_unified_pool, mixer)


## IRQ-start prolog — bump cadence counter + emit cadence_source /
## cadence_wallclock / envelope_tail / noise_clock / noise_status. Pass 10.A:
## one entry point for both music + SFX harnesses (formerly emitted from
## `EffectPlaySound.tick_irq_start` per-sub-tick inside render_effect_sound).
## Mirrors PCSX FUN_800149DC's prolog firing BEFORE `jal async_commit_walker`
## at 0x800149F0. The mixer is forwarded so the per-voice envelope_tail
## probe can reach `mixer.get_voice_debug_info(v)`; pass null to skip the
## voice-side emits (cadence_source + cadence_wallclock still fire).
##
## Call order per IRQ (both music + SFX harnesses):
##     rt.tick_irq_start(abs_sub)   # this method
##     rt.tick(abs_sub)             # walker + catchup + KON/KOFF
func tick_irq_start(abs_sub: int = 0) -> void:
	_EffectPlaySound.tick_irq_start_for_runtime(mixer, abs_sub)


## One 240 Hz IRQ tick. Returns true while any entity is still alive.
##
## `abs_sub` is the absolute sub-tick index from session start. Music's
## harness calls tick() with no argument (defaults to 0); SFX's harness
## passes the running `abs_sub` so silent-driver overlay bindings can
## gate on `binding.start_sub_tick` in _tick_extras_primaries_drainer.
##
## Order matches spu_updater_tick @ ram:800149dc and the legacy
## EffectPlaySound.tick_all_dispatchers sequencing exactly:
##   phase 0   : walker fan-out (WALKER_FAN_PER_IRQ passes) — drains the
##               PREVIOUS IRQ's staged pitch/vol/adsr/sample-addr bits
##               BEFORE this IRQ's catchup runs. Mirrors legacy SFX
##               harness (walker.tick before tick_all_dispatchers per
##               sub-tick) so register-write probes (adsr1_*, sample_*,
##               vol_register_sweep, pitch_register) emit at the same
##               cadence index as PCSX's FUN_800149DC prolog `async_
##               commit_walker` at 0x800149F0. Pass 8 Phase 7-unblock RC1.
##   phase 1   : per-entity catchup (sets walker bits, FLAG_PRIMARY_KON)
##   phase 1.5 : extras + primaries + drainer (RC2.A — mirrors legacy
##               tick_all_dispatchers: catchup → extras → primaries →
##               drainer → anchor latch → KON commit)
##   phase 1.75: cadence anchor latch — runs AFTER primaries so the
##               first-opcode-fire signal is visible, BEFORE KON commit
##               so post-anchor probe gates see _post_anchor=true
##   phase 2   : KON accumulator scan over active slots
##   phase 3   : KON commit (×1 for SFX entity, ×2 for music — see notes)
##   phase 4   : KOFF post-loop flush
func tick(abs_sub: int = 0) -> bool:
	# Per-IRQ order matches Sequencer.tick() (legacy music path):
	# catchup loop FIRST so AdvanceTrack sets FLAG_PRIMARY_KON; THEN
	# the KON scan drains it, the KOFF flush handles duration-expired
	# notes + clears per-tick flags, and walker passes drain the
	# staged pitch/vol/adsr writes. The "FFT-faithful" KON-scan-before-
	# catchup ordering from spu_updater_tick is achieved by
	# flush_kon_commit's internal rotate-pending-into-deferred pattern
	# (one IRQ of deferral is built into the commit, not the outer
	# ordering). Calling commit twice eager-drains the deferred buffer
	# so same-IRQ KON commit matches legacy behavior.
	var any_alive := false
	var ll = entity_list if entity_list != null else _SharedEntityList.get_singleton()
	var entities: Array = ll.walk()

	# Game SFX driver: ignore music entities entirely (they're driven by the
	# legacy Sequencer.tick on a separate SPU). Filtering here keeps every
	# downstream loop (probes, catchup, KON/KOFF scan) SFX-only in one place.
	if sfx_only:
		entities = entities.filter(func(e): return e is _EffectEntity)

	# Pass 10.C — per-entity walk probes for music entities. Mirrors
	# EffectPlaySound._run_entity_catchup's per_entity_iter +
	# per_entity_pass emit pattern (cure_no_music pattern) but applies
	# to _MusicEntityState entries. Fires once per music entity per IRQ
	# regardless of catchup-fire status (PCSX BP @ 0x80014BBC fires
	# unconditionally inside the LL walk). Gated on _post_anchor so
	# pre-anchor IRQs don't inflate Godot's count vs PCSX's.
	#
	# SFX entities still emit per_entity_iter from
	# EffectPlaySound._run_entity_catchup; doing it from there preserves
	# the existing silent-entity + cure pattern that PCSX captures.
	if _Trace._post_anchor:
		for ent in entities:
			if ent is _MusicEntityState:
				_EffectPlaySound._probe_per_entity_iter_count += 1
				# slot_10_pre — the s16 value PCSX reads at entity+0x10
				# (the gate field, signed). For the primary, emit -1
				# (Godot has no gate model — primary is implicitly
				# active and FFT bgez falls through). For a secondary
				# entity (built via apply_seed_dict from a savestate),
				# emit the captured gate value so the per_entity_pass
				# bgez-fall-through gate below sees PCSX-faithful state.
				var slot_10: int
				if ent.is_secondary:
					slot_10 = ent.gate if ent.gate < 0 else ent.gate & 0xFFFF
				else:
					slot_10 = -1
				_Trace.emit("per_entity_iter", {
					"call_index": _EffectPlaySound._probe_per_entity_iter_count,
					"chan_base": 0,
					"slot_10_pre": slot_10,
				})
				# per_entity_pass mirrors PCSX BP @ 0x80014BCC — the
				# fall-through after bgez at 0x80014BC4. Fires only when
				# slot+0x10 < 0 (entity active). Skipping inactive
				# secondaries closes the +2397 over-fire seen in
				# iter-30's first probe pair.
				if ent.is_active():
					_EffectPlaySound._probe_per_entity_pass_count += 1
					_Trace.emit("per_entity_pass", {
						"call_index": _EffectPlaySound._probe_per_entity_pass_count,
						"chan_base": 0,
						"slot_10_pre": slot_10,
					})

	# Phase 0 (Pass 8 Phase 7-unblock RC1): walker fan-out FIRST. Drains
	# the PREVIOUS IRQ's staged pitch/vol/adsr/sample-addr bits before
	# this IRQ's catchup + dispatcher.tick run. Legacy SFX harness fires
	# walker.tick(_r) inside the per-sub-tick loop BEFORE
	# play.tick_all_dispatchers, so register-write probes (adsr1_high/
	# low/mid, sample_*_addr, vol_register_sweep, pitch_register) report
	# the IRQ at which the walker drains them — not the IRQ at which the
	# dispatcher armed the bits. Mirroring that ordering recovers the
	# +1-cadence drift on the second KEY-ON pair (cad 362 → cad 361
	# under the previous end-of-IRQ walker). WALKER_FAN_PER_IRQ matches
	# the legacy harness's FLUSH_PER_DISPATCH=8 sub-tick fan-out.
	for _wi in range(WALKER_FAN_PER_IRQ):
		_irq_walker.tick(0)

	# Phase 1: per-entity catchup loop. AdvanceTrack runs here,
	# setting FLAG_PRIMARY_KON / walker_flag bits on slots. For SFX
	# entities, the catchup returns cadence_fired_this_irq so phase 1.5
	# can gate the drainer correctly (FFT FUN_80017118 only enters
	# LAB_80014CCC's sub-loop when the catchup fired).
	var sfx_cadence_fired: Dictionary = {}
	for ent in entities:
		if _entity_done(ent):
			continue
		any_alive = true
		if ent is _EffectEntity and ent.owning_play_sound != null:
			sfx_cadence_fired[ent] = ent.owning_play_sound._run_entity_catchup()
		else:
			# Music entity — gate the catchup body on FFT's slot+0x10
			# active flag (mirrors bgez at PC 0x80014BC4). Inactive
			# secondaries (gate >= 0) skip the catchup, matching PCSX's
			# branch-taken path so per_channel_tick / lfo_subslot probes
			# don't over-fire on the secondary's 12 channels.
			if ent is _MusicEntityState and not ent.is_active():
				continue
			_run_entity_catchup(ent)

	# Phase 1.5: per-IRQ extras + primaries + drainer for SFX entities.
	# Runs AFTER catchup (per FFT spu_updater_tick ordering) and BEFORE
	# the anchor latch — the first-opcode-fire signal that primaries can
	# set must be visible when the latch flips, so post-anchor probe
	# gates see _post_anchor=true at the right IRQ.
	for ent in entities:
		if ent is _EffectEntity and ent.owning_play_sound != null:
			var cf: bool = sfx_cadence_fired.get(ent, false)
			ent.owning_play_sound._tick_extras_primaries_drainer(abs_sub, cf)

	# Phase 1.75: cadence anchor latch. The first opcode dispatch fires
	# during phase 1's catchup or phase 1.5's primaries →
	# _Trace._first_dispatch_fired flips. Fire the latch here so
	# _post_anchor flips BEFORE phase 3's KON commit; otherwise the
	# first-IRQ keyon_per_voice / *_register probes are gated false and
	# Gate B loses the cad=0 row per audible voice.
	#
	# Pass 10.A — fires uniformly for music + SFX entities (formerly an
	# SFX-only `for ent in entities` loop with early break). The static
	# latch is idempotent (no-op once `_cadence_anchored` flips) and
	# music's first opcode dispatch also flips `_first_dispatch_fired`
	# via the shared dispatcher, so music capture now anchors cadence
	# at first-opcode-fire just like SFX does.
	_EffectPlaySound.check_anchor_latch_for_runtime(_flush_tick)

	# Phase 2: KON accumulator scan over all active slots from all
	# entities. Drains FLAG_PRIMARY_KON / FLAG_SECONDARY_KON into
	# _pending_kon_*.
	var has_sfx_entity := false
	for ent in entities:
		if ent is _EffectEntity and ent.owning_play_sound != null:
			has_sfx_entity = true
		for slot in _entity_active_slots(ent):
			_flush_tick.flush_kon_only_for_slot(slot)

	# Phase 3: KON commit. Music's legacy Sequencer.tick() fires this
	# twice (eager drain of the rotated deferred buffer so the SPU sees
	# key_on in the same IRQ — required for music's deterministic-from-
	# start invariant). Legacy SFX's tick_all_dispatchers fires it ONCE
	# (FFT FUN_8001ACF0(1, mask) is invoked exactly once per IRQ inside
	# FUN_80017118's per-entity epilogue), keeping the one-IRQ deferral
	# that matches PCSX entity+0x60 semantics. Pass 8 Phase 7-unblock —
	# pick the right cadence per entity type so SFX preserves its
	# pre-anchor seed → cad=1 commit chain and Cluster 2 probes pair.
	_flush_tick.flush_kon_commit()
	if not has_sfx_entity:
		_flush_tick.flush_kon_commit()

	# Phase 4: KOFF post-loop flush. Walks active slots, accumulates
	# FLAG_KOFF_PENDING, fires per-voice key_off + ADSR2 release.
	# Calls clear_per_tick_flags() per slot to zero flag_word for the
	# next IRQ.
	_flush_tick.flush_koff_post_loop()

	return any_alive


## Render SAMPLES_PER_IRQ_BASE (or +1 from the sub-sample accumulator)
## stereo PCM16 samples for one IRQ. The accumulator rolls over every
## 4 IRQs to absorb the 44100 % 240 = 60/240 remainder — over 1 sec
## we emit exactly 44100 samples (240 * 183 + 60 = 44100).
## If voice_idx >= 0, renders that single voice as MONO PCM16 (sibling
## of mixer.render_voice_pcm16 in render_effect_sound.gd's per-voice
## mode). Used by render_music_wav.gd --voice-idx=N to write
## spu_voice_NN.wav, matching SFX harness layout for per-voice scoring.
func render_irq_samples(voice_idx: int = -1) -> PackedInt32Array:
	var samples: int = SAMPLES_PER_IRQ_BASE
	_sample_acc += SAMPLES_PER_IRQ_REM
	if _sample_acc >= IRQ_HZ:
		samples += 1
		_sample_acc -= IRQ_HZ
	if voice_idx >= 0:
		return mixer.render_voice_pcm16(samples, voice_idx)
	return mixer.render_interleaved_pcm16(samples)


func _entity_active_slots(entity) -> Array:
	if entity is _MusicEntityState:
		return entity._gather_active_slots()
	elif entity is _EffectEntity:
		# Phase 5 — SFX entity reaches back to its EffectPlaySound to
		# surface the pool's active slots. Per-IRQ flush_kon_only walk
		# (phase 2 of Runtime.tick) iterates these.
		if entity.owning_play_sound == null:
			return []
		return entity.owning_play_sound._pool.active_slots()
	return []


func _entity_done(entity) -> bool:
	if entity is _MusicEntityState:
		return entity.all_tracks_done
	elif entity is _EffectEntity:
		# Phase 5 — EffectPlaySound mirrors its _cure_slot_10 transition
		# into entity.is_done at the post-cadence_body `andi 0x7fff`
		# site (the canonical end-of-spell signal). Runtime stops
		# firing _run_sfx_entity_iter once this flips true.
		return entity.is_done
	return true


## Decrement entity sub_tick_acc and run one catchup iter per
## 0x10000 of accumulated negativity. Music's decrement is tempo-
## driven (entity+0x78 = tempo_byte * tick_rate, written by 0xA0).
## SFX's is fixed at 0x6600 from FUN_800137D8.
##
## MAX_ITERS guards against runaway loops if the budget is mis-seeded
## (e.g. zero would loop forever). FFT itself has no explicit bound
## but in practice fires at most ~8 catchup iters per IRQ.
const MAX_CATCHUP_ITERS := 8


func _run_entity_catchup(entity) -> void:
	## Music-only path. SFX entities are dispatched directly in
	## Runtime.tick() phase 1 (so the cadence_fired bool can flow into
	## phase 1.5's drainer gate); this helper handles music only.
	if entity is _MusicEntityState:
		# Pass 10.C — entity_catchup_iter (phase=outer) captures the
		# pre-decrement sub_tick_acc + budget so the diff against PCSX
		# BP @ 0x80014CB8 (slot+0x74 load, pre `subu v0, v0, a1`) is
		# bit-exact. Gated on _post_anchor to skip pre-anchor IRQs.
		var sub_tick_acc_pre: int = entity.sub_tick_acc
		var sub_tick_budget: int = entity.sub_tick_budget
		entity.sub_tick_acc -= entity.sub_tick_budget
		if _Trace._post_anchor:
			_EffectPlaySound._diag_entity_catchup_iter_count += 1
			_Trace.emit("entity_catchup_iter", {
				"call_index": _EffectPlaySound._diag_entity_catchup_iter_count,
				"phase": "outer",
				"entity_acc_pre": sub_tick_acc_pre,
				"entity_budget": sub_tick_budget,
				"cure_slot_10": -1,
			})
		var iters := 0
		while entity.sub_tick_acc < 0 and iters < MAX_CATCHUP_ITERS:
			entity.sub_tick_acc += 0x10000
			iters += 1
			# Pass 10.C — spu_slot_loop fires per inner catchup iter
			# (PCSX BP @ 0x80014CCC = LAB_80014CCC sub-loop entry).
			if _Trace._post_anchor:
				_EffectPlaySound._probe_spu_slot_loop_count += 1
				_Trace.emit("spu_slot_loop", {
					"call_index": _EffectPlaySound._probe_spu_slot_loop_count,
				})
			_run_music_entity_iter(entity)


## One bytecode-tick iteration for a music entity. Mirrors the per-
## track loop body of Sequencer.tick() at sequencer.gd:427-484: LFO
## advance + pitch/vol prestage drain, KOFF arming on idle_timeout
## expiry, AdvanceTrack on note_duration expiry. The outer Runtime
## handles the per-IRQ KON/KOFF flush + walker fan-out.
func _run_music_entity_iter(entity: _MusicEntityState) -> void:
	var seq = entity.owning_sequencer
	if seq == null:
		return
	for ts in entity.tracks:
		if ts == null or ts.ctx == null:
			continue
		# FFT lfo_handler_tick per-channel loop top (PC 0x800174C8)
		# equivalent — fires the 4 LFO sub-slot state probes for music
		# at the same per-channel-per-IRQ cadence PCSX does. Gated on
		# post-anchor + cadence_index > 0 to drop pre-anchor IRQs.
		# Iter-38: emit BEFORE the ts.done gate — FFT's BP at
		# PC 0x800174C8 fires unconditionally for each of the s5
		# channels regardless of bytecode state. The conductor (track 0)
		# flips ts.done after EndBar but FFT still walks its channel
		# struct every IRQ. See docs/MUSIC_ITER38_LFO_HANDLER_DONE_TRACK_SKIP.md.
		if _Trace._post_anchor and _Trace._cadence_index > 0:
			_ProbeEmit.emit_lfo_handler_probes(ts.ctx.channel)
		# Pass 10.D — probe_per_channel_tick_entry. Mirrors PCSX BP @
		# 0x80015198 (per_channel_tick body entry, BEFORE the chan_word_0
		# selectivity gate at PC 0x800151A0). Each music track is one FFT
		# channel position in the per_channel_tick walk. Gated on
		# _post_anchor so pre-anchor IRQs don't inflate Godot's count.
		# chan_word_0 is the only alignment key (note_duration / chan_78
		# carry known divergences per manifest comments).
		if _Trace._post_anchor:
			_EffectPlaySound._probe_per_channel_tick_entry_count += 1
			_Trace.emit("per_channel_tick_entry", {
				"call_index": _EffectPlaySound._probe_per_channel_tick_entry_count,
				"chan_base": 0,
				"chan_word_0": ts.ctx.channel.channel_word_0 & 0xFFFF,
				"note_duration": ts.ctx.channel.note_duration & 0xFFFF,
				"chan_78": ts.ctx.channel.idle_timeout & 0xFFFF,
			})
		# Iter-38: bytecode-advance + walker body still gated on
		# ts.done — only the probe emits moved out of the skip path.
		if ts.done:
			continue
		# FFT smd_dispatcher_chan0_clear @ PC 0x80015394-98 — clears bits
		# 0x0700 (PITCH_REQ, VOL_PENDING, KON_ARM) at the top of
		# smd_dispatcher's per-channel body. The CRITICAL gate (mirrored
		# in shared/dispatcher.gd:509) is `note_duration == 0` — bytecode
		# dispatch only runs when the previous note's wait has drained.
		# Without this gate, KON_ARM set by duration-tick on a sustained
		# note (idle_timeout drain) would be wiped every IRQ instead of
		# persisting until the next bytecode walk consumes it, breaking
		# the period_reset gate for voice 10's pitch-LFO re-init. See
		# MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md §2 + §4 follow-up.
		var s2_snapshot: int = ts.ctx.channel.channel_word_0
		var _did_mask_clear: bool = false
		# FFT smd_dispatcher gate at PC 0x80015384: `bne chan+0x74, zero,
		# SKIP`. chan+0x74 is FFT's note_duration field. FFT reads
		# POST-decrement value (per_channel_tick decremented at PC
		# 0x80015290 BEFORE smd_dispatcher reads). Godot's probe BP and
		# this gate check PRE-decrement value, so use `== 1` to match
		# the post-decrement `== 0` semantic (1 pre-dec = 0 post-dec).
		if ts.ctx.channel.note_duration == 1 \
				and (ts.ctx.channel.channel_word_0 & 0xFFFF) != 0:
			ts.ctx.channel.channel_word_0 &= 0xf8ff
			_did_mask_clear = true
		# 1. LFO advance + pitch/vol prestage drain.
		if ts.voice_idx >= 0:
			_SharedPerTickAdvanceLfo.apply(ts.ctx.channel, ts.ctx.slot, true, true)
			if (ts.ctx.channel.channel_word_1 & _SS.CHAN1_PITCH_PRESTAGE) != 0:
				ts.ctx.slot.pitch_staging = _SharedComputePitch.evaluate_with_music_probe(ts.ctx.channel, ts.ctx.slot)
				ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH
				ts.ctx.channel.channel_word_1 &= ~_SS.CHAN1_PITCH_PRESTAGE
			if (ts.ctx.channel.channel_word_1 & _SS.CHAN1_VOL_PRESTAGE) != 0:
				_SharedComputeVolLr.apply(ts.ctx.channel, ts.ctx.slot, seq.master_vol)
				ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_VOL_LR_RAW
				ts.ctx.channel.channel_word_1 &= ~_SS.CHAN1_VOL_PRESTAGE
		# 2. Note key-off (duration expired). Mirrors sequencer.gd
		#    duration-KOFF arming — FLAG_KOFF_PENDING only (no
		#    FLAG_STREAM_END) so the release-rate clobber stays off.
		var _idle_drained_to_zero: bool = false
		if ts.ctx.channel.idle_timeout > 0:
			ts.ctx.channel.idle_timeout -= 1
			if ts.ctx.channel.idle_timeout == 0:
				_idle_drained_to_zero = true
		if ts.ctx.channel.idle_timeout <= 0 and ts.current_note >= 0 and ts.voice_idx >= 0:
			ts.ctx.slot.flag_word |= _SS.FLAG_KOFF_PENDING
			ts.current_note = -1
			ts.hold_note_for_retrigger = false
		# 3. Advance track (note_duration expired).
		if ts.ctx.channel.note_duration > 0:
			ts.ctx.channel.note_duration -= 1
		# FFT per_channel_tick PC 0x800152A8-C0 — end-of-note ADSR2
		# release-rate force. When note_duration just decremented to 1
		# AND chan_word_0 has CHAN0_LAST_NOTE_FLAG set (post-walker
		# look-ahead saw a Note ahead), force the SPU release_rate to
		# the canonical 0x06 and arm WALKER_FLAG_ADSR2_LOW so the
		# next walker pass commits the new low 6 bits. Mirrors
		# shared/dispatcher.gd:307-324 (SFX implementation). The
		# CHAN0_LAST_NOTE_FLAG bit is set/cleared by
		# sequencer/per_tick/advance_track.gd::_update_last_note_flag.
		# See docs/MUSIC_ADSR2_LOW_REGISTER_INVESTIGATION.md.
		if ts.ctx.channel.note_duration == 1 \
				and (ts.ctx.channel.channel_word_0 & _SS.CHAN0_LAST_NOTE_FLAG) != 0:
			# iter-39: FFT PC 0x800152B8 writes chan+0x6A = 6 — the
			# walker's rate-field source (iter-32). slot.adsr2's low
			# 6 will be re-composed by FUN_8001BAB8 on the next
			# walker pass; mirroring the adsr2 update here is
			# defensive (other code may read it before the walker
			# fires).
			ts.ctx.slot.release_rate_byte = 0x06
			ts.ctx.slot.adsr2 = (ts.ctx.slot.adsr2 & 0xFFC0) | 0x06
			ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW
		var wt: int = ts.ctx.channel.note_duration
		if ts.end_bar_pending and ts.current_note < 0 and wt <= 0:
			ts.done = true
			ts.end_bar_pending = false
			continue
		if wt <= 0 and not ts.done:
			_AdvanceTrack.apply(seq, ts)
		# FFT LFO sub-slot period_reset @ PC 0x800157AC..0x80015804. Gate
		# (mirrors shared/dispatcher.gd:586-598 + FFT PC 0x80015488):
		# bytecode dispatch ran this tick (`_did_mask_clear` proxy — same
		# `note_duration == 0` condition that enters smd_dispatcher's
		# body) AND pre-clear chan_word_0 (s2_snapshot) had KON_ARM. On
		# match, snap active LFO sub-slots back to depth = depth_reload,
		# acc = 0, countdown = 1, delay_counter = delay_reload, dir
		# clears bits 0xC. See MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md §4
		# follow-up (voice 10's pitch-LFO needs depth reset to escape
		# the stuck-at-256 fade-in tail).
		# Add `chan_word_0 & 0x100` post-advance_track check — a Note byte
		# actually dispatched this tick (note_handler sets PITCH_REQ via
		# the iter-49 |= 0x180). Without this, the gate over-fires on
		# bytecode walks that consume control opcodes only (no Note),
		# producing voice 10 dir=3 row count 207 (Godot) vs 161 (PCSX);
		# tightens to FFT's `s4 != 0` (note_dispatched) semantic.
		if _did_mask_clear and (s2_snapshot & 0x400) != 0 \
				and (ts.ctx.channel.channel_word_0 & 0x100) != 0:
			_PerTickLfoPeriodReset.apply(ts.ctx.channel)
		# FFT duration-tick KON_ARM @ PC 0x800152F0-F8 — fires at END of
		# per_channel_tick body, so the KON_ARM bit set by THIS IRQ
		# survives to the NEXT IRQ where it is captured by s2_snapshot at
		# the top of the body (PCSX probe_per_channel_tick_entry sees this
		# as 0x9401 vs Godot pre-fix 0x8001). Without the end-of-body
		# arm, voice 10's LFO never resets between notes because the
		# period_reset gate above never observes 0x400 in s2_snapshot.
		# See MUSIC_OPEN_BUGS_DEEP_REFACTOR_PLAN.md §4 follow-up.
		if _idle_drained_to_zero:
			ts.ctx.channel.channel_word_0 |= _SS.CHAN0_KON_ARM
	# Update entity completion gate.
	var all_done := true
	for ts in entity.tracks:
		if ts != null and not ts.done:
			all_done = false
			break
	entity.all_tracks_done = all_done


## Inner class — unified slot pool spanning music (voices 0-15) +
## SFX (voices 16-23). flush_tick + walker iterate this in place of
## MusicSlotPool / EffectSoundPool when Runtime drives. Walks
## SharedEntityList to gather active slots from all entities.
##
## Voice resolution: voice_for_slot(slot_idx) is ambiguous because
## music's slot_idx range (0-15) overlaps SFX's (0-7), but the slot
## object's `voice_mask` is pre-computed at slot allocation to be
## `1 << real_voice`, so we resolve through that. Music tracks set
## voice_mask = 1 << voice_idx at load_smd (sequencer.gd:218); SFX
## sets it in EffectSoundPool.allocate_pair (pool.gd:193-194).
class UnifiedSlotPool:
	# Inner-class preloads — CLI-mode class_name cache doesn't expose
	# the outer Runtime's constants, so each inner class reloads what
	# it needs directly.
	const _EntityListInner = preload("res://addons/exmateria_sound/runtime/shared/entity_list.gd")
	const _MusicEntityInner = preload("res://addons/exmateria_sound/runtime/music/music_entity_state.gd")
	const _EffectEntityInner = preload("res://addons/exmateria_sound/runtime/effect_sound/entity_state.gd")
	const _SfxPoolInner = preload("res://addons/exmateria_sound/runtime/effect_sound/pool.gd")

	const SPU_VOICE_BASE := 0
	const POOL_SLOT_COUNT := Spu.NUM_VOICES

	# Cache built per active_slots() call so voice_for_slot lookups
	# during the same IRQ phase are O(1). Reset implicitly on the
	# next walk.
	var _slot_to_voice: Dictionary = {}

	static func _voice_from_mask(mask: int) -> int:
		# Extract single-bit voice index from a `1 << voice` mask.
		# Bit-scan-forward — bounded at NUM_VOICES.
		if mask == 0:
			return -1
		var v: int = 0
		while (mask & 1) == 0 and v < Spu.NUM_VOICES:
			mask >>= 1
			v += 1
		return v

	func voice_for_slot(slot_idx: int) -> int:
		# O(1) via cache populated by active_slots(). Fallback to
		# identity (music's default) if uncached — Phase 4/5
		# guarantee active_slots() runs before flush/walker per IRQ
		# so the cache is always populated before consumption.
		if _slot_to_voice.has(slot_idx):
			return _slot_to_voice[slot_idx]
		return slot_idx

	func active_slots() -> Array:
		_slot_to_voice.clear()
		var out: Array = []
		var ll = _EntityListInner.get_singleton()
		for ent in ll.walk():
			if ent is _MusicEntityInner:
				for slot in ent._gather_active_slots():
					out.append(slot)
					_slot_to_voice[slot.slot_idx] = _voice_from_mask(slot.voice_mask)
			elif ent is _EffectEntityInner:
				# Phase 5 — SFX entity exposes its pool via
				# owning_play_sound (set at play_feds_pair's first-alloc
				# seed). EffectSoundPool.voice_for_slot returns
				# SPU_VOICE_BASE + slot_idx (= 16 + slot_idx), giving the
				# voice 16-23 range. NOTE: music's slot_idx range (0-15)
				# overlaps SFX's (0-7) in the _slot_to_voice cache. Until
				# voice_for_slot's signature switches to slot-object input
				# (Phase 7 cleanup), an SFX slot 0 collides with music
				# slot 0 in the same cache. Neither current harness drives
				# music + SFX together, so the collision is dormant.
				if ent.owning_play_sound == null:
					continue
				var ps = ent.owning_play_sound
				for slot in ps._pool.active_slots():
					out.append(slot)
					# Use the play's actual pool base (instance-configurable now)
					# instead of the static default, so an unlocked base-0 pool
					# resolves correctly here too.
					_slot_to_voice[slot.slot_idx] = ps._pool.voice_for_slot(slot.slot_idx)
		return out
