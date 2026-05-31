class_name SharedFlushTick
## Per-tick effect-pool SPU flush — port of FUN_80017118 + spu_updater_tick
## post-loop + FUN_8001ACF0.
##
## Split into three methods that play_sound drives in FFT-faithful order
## from inside tick_all_dispatchers:
##
##   • flush_kon_only_for_slot(slot) — port of FUN_80017118 (PC
##     0x80017180-0x800173B8). Called INSIDE the entity catchup sub-loop,
##     once per slot, immediately after that slot's cadence_body fires.
##     Consumes walker_seed_pending + noise_pending, accumulates KON bits
##     into the per-IRQ pending buffers, clears FLAG_PRIMARY_KON /
##     FLAG_SECONDARY_KON from slot.flag_word (mirrors FFT (4D) `sh zero,
##     0x0(s0)` at PC 0x800173B8). FLAG_KOFF_PENDING is left for the
##     post-loop flush.
##
##   • flush_kon_commit() — port of FUN_8001ACF0(1, mask) in FUN_80017118's
##     epilogue. Called once after the catchup sub-loop and all dispatcher
##     ticks. Emits the mode=1 trace row + per-voice key_on commit.
##
##   • flush_koff_post_loop() — port of spu_updater_tick (PC
##     0x80014E04-0x80014EF0). Called once at the end of the IRQ. Walks
##     every active slot, accumulates the FLAG_KOFF_PENDING mask, fires
##     per-voice key_off + ADSR2 release writes, runs sustain re-arm,
##     clears per-tick flags. Emits the mode=0 trace row.
##
## The FFT-faithful sequencing comes from this split: FFT commits KON
## per-channel inside the sub-loop and KOFF once post-loop, on two
## adjacent IRQ phases. The prior combined tick() flushed both at once
## with a KOFF-wins mutex, which structurally dropped 56 voice-18 KOFFs
## on reraise_no_music (the byte_7A=16 silent-driver case where idle_
## timeout drains to 0 in the same IRQ a new Note dispatches). See
## RERAISE_KON_KOFF_IDLE_TIMEOUT_FAITHFUL_PORT_PLAN.md §3.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")

# probe_kon_koff_mask (Layer 5 synthesis) counter. Bumped at every
# FUN_8001ACF0 dispatch (one per tick per direction). Each row carries
# mode (0=KOFF, 1=KON) and the 24-bit voice mask passed in a1.
# Pairs with FFT BP @ 0x8001ACF0 (FUN_8001ACF0 entry) which captures
# (mode=a0, mask=a1) once per call.
static var _probe_kon_koff_mask_count: int = 0

# walker_seed_drain counter — bumped each time the deferred-arm
# consumer in flush_kon_only_for_slot fires (wide or narrow). Used to
# verify §7.1 of VOICE_18_ADSR1_HIGH_PREARM_PATCH.md: confirms that the
# seed drains BEFORE spu_voice_events sees the first KEYON (mode=wide
# for AC-before-Note, mode=narrow for Note-before-AC).
static var _probe_walker_seed_drain_count: int = 0
# diag_keyon_per_voice — Godot half of the per-voice KEYON ledger
# (PCSX BP @ FUN_8001ACF0). Increments once per committed KEYON in
# _commit_kon. See _commit_kon below for the emit site.
static var _probe_keyon_per_voice_count: int = 0


func _emit_kon_koff_mask_trace(mode: int, mask: int) -> void:
	if not _Trace._post_anchor or _Trace._cadence_index <= 0:
		return
	if mask == 0:
		return
	_probe_kon_koff_mask_count += 1
	_Trace.emit("kon_koff_mask", {
		"call_index": _probe_kon_koff_mask_count,
		"mode": mode,
		"mask": mask,
	})


# _pool is duck-typed (untyped) to accept both EffectSoundPool and
## MusicSlotPool. Both expose active_slots(), voice_for_slot(slot_idx),
## SPU_VOICE_BASE, POOL_SLOT_COUNT. Pass 7.E.A — untyped so music can
## reuse the same per-IRQ flush machinery.
var _pool = null
var _mixer: Spu


func _init(pool, mixer: Spu) -> void:
	_pool = pool
	_mixer = mixer


# Per-IRQ pending KON state, populated by flush_kon_only_for_slot inside
# the entity catchup sub-loop and ROTATED INTO _deferred_kon_* by
# flush_kon_commit at IRQ end. Mirrors FFT FUN_80017118's s4/s5
# accumulators (PCs 0x80017394 / 0x800173B4): per-channel walker visits
# each slot inside the catchup sub-loop, fills entity+0x60, and the
# NEXT IRQ's spu_updater_tick reads/clears that field at PC
# 0x80014A70..0x80014AC4 before calling FUN_8001ACF0(1, mask).
var _pending_kon_s4: int = 0
var _pending_kon_s5: int = 0
var _pending_kon_dict: Dictionary = {}   # voice_idx -> _SS

# Deferred-commit buffer — PCSX entity+0x60 analog. flush_kon_commit
# flushes THIS buffer (the PREVIOUS IRQ's accumulation) and then rotates
# _pending_kon_* into it, so the actual SPU key_on lands one IRQ after
# the dispatch that armed it. See KEYON_COMMIT_DEFERRAL_PROBE_DEFICIT.md
# §3 / §7.1.
var _deferred_kon_s4: int = 0
var _deferred_kon_s5: int = 0
var _deferred_kon_dict: Dictionary = {}


func flush_kon_only_for_slot(slot: _SS) -> void:
	## Port of FFT FUN_80017118 (4A-4D) at PCs 0x80017180-0x800173B8 —
	## per-channel KON walker invoked INSIDE the entity catchup sub-loop
	## immediately after the slot's cadence_body. Accumulates KON bits
	## into _pending_kon_s4 / _pending_kon_s5 and clears the KON flags
	## from slot.flag_word (mirrors (4D) at PC 0x800173B8). FLAG_KOFF_
	## PENDING stays set — the post-loop KOFF flush in spu_updater_tick
	## (PC 0x80014EEC) reads it after the catchup loop completes.
	##
	## Per-slot walker_seed_pending consumption + noise_pending consumption
	## stay here (they were tied to per-slot dispatcher work).
	var flag: int = slot.flag_word
	var voice: int = _pool.voice_for_slot(slot.slot_idx)

	# walker_seed_pending wide consumer (AC-before-Note path).
	if slot.walker_seed_pending and (flag & _SS.FLAG_PRIMARY_KON) != 0:
		slot.walker_flag_word |= 0x1FF
		slot.walker_seed_pending = false
		_probe_walker_seed_drain_count += 1
		_Trace.emit("walker_seed_drain", {
			"call_index": _probe_walker_seed_drain_count,
			"voice": voice,
			"mode": "wide",
			"mask": 0x1FF,
		})
	# walker_seed_pending narrow consumer (Note-before-AC path).
	if slot.walker_seed_pending_narrow and (flag & _SS.FLAG_PRIMARY_KON) != 0:
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_HIGH
		slot.walker_seed_pending_narrow = false
		_probe_walker_seed_drain_count += 1
		_Trace.emit("walker_seed_drain", {
			"call_index": _probe_walker_seed_drain_count,
			"voice": voice,
			"mode": "narrow",
			"mask": _SS.WALKER_FLAG_ADSR1_HIGH,
		})

	# Opcode 0xB4 noise-enable consumer (FFT L80015F44 + L80019D88).
	if slot.noise_pending >= 0:
		_mixer.set_voice_noise(voice, true)
		_mixer.set_noise_clock(slot.noise_pending)
		slot.noise_pending = -1

	# Opcode 0xB7 noise-disable consumer (FFT L80016060). FFT writes the
	# SPU NoiseOn register every IRQ from entity[+0x6c] (aggregated by
	# Hyp_spu_updater_callee_2 at FUN_80014FF8); clearing the bit at the
	# opcode dispatch lets the next IRQ deassert noise on the voice.
	# Godot's mixer routes noise per-voice, so clear it directly here.
	if slot.noise_disable_pending:
		_mixer.set_voice_noise(voice, false)
		slot.noise_disable_pending = false

	# Opcode 0xB2 / 0xB3 SPU FMod-enable/disable consumer. Mirrors PCSX's
	# FModOn pair semantic: enabling FMod on voice N sets Chan::FMod=1 on
	# voice N AND Chan::FMod=2 on voice N-1 (the freq source). Disable
	# clears both back to 0. See V21_FMOD_PITCH_MODULATION_FIX.md +
	# FMOD_GENERALIZATION_PLAN.md.
	if slot.fmod_pending >= 0:
		if slot.fmod_pending == 1 and voice > 0:
			_mixer.set_voice_fmod(voice - 1, 2)
			_mixer.set_voice_fmod(voice, 1)
		elif slot.fmod_pending == 0 and voice > 0:
			_mixer.set_voice_fmod(voice - 1, 0)
			_mixer.set_voice_fmod(voice, 0)
		slot.fmod_pending = -1

	# KON accumulators. Mutex against FLAG_KOFF_PENDING is REMOVED here —
	# FFT separates KOFF (post-loop spu_updater_tick) and KON (per-slot
	# FUN_80017118) into different IRQ phases, so they can co-fire without
	# fighting. See RERAISE_KON_KOFF_IDLE_TIMEOUT_FAITHFUL_PORT_PLAN.md §3.1.
	var suppressed: bool = (slot.active_word & _SS.ACTIVE_WORD_KON_SUPPRESS) != 0
	if (flag & _SS.FLAG_PRIMARY_KON) != 0 and not suppressed:
		_pending_kon_s4 |= slot.voice_mask
		_pending_kon_dict[voice] = slot
	if (flag & _SS.FLAG_SECONDARY_KON) != 0:
		_pending_kon_s5 |= slot.voice_mask
		_pending_kon_dict[voice] = slot

	# Mirror FFT (4D) `sh zero, 0x0(s0)` at PC 0x800173B8 — clear KON
	# arms here so they don't double-fire next IRQ. FLAG_KOFF_PENDING /
	# FLAG_STREAM_END stay for flush_koff_post_loop; clear_per_tick_flags
	# zeroes the rest at the very end of the IRQ.
	slot.flag_word &= ~(_SS.FLAG_PRIMARY_KON | _SS.FLAG_SECONDARY_KON)


func flush_kon_commit() -> void:
	## FFT FUN_8001ACF0(1, s4|s5) — the single KON SPU write per IRQ.
	## Mirrors PCSX's one-IRQ deferral: spu_updater_tick at IRQ-start
	## reads entity+0x60 (the PREVIOUS IRQ's accumulation), clears it,
	## and calls FUN_8001ACF0(1, mask). The dispatch-loop fan-out later
	## in the same IRQ refills entity+0x60 for the NEXT IRQ. We model
	## that here by committing _deferred_kon_* first, then rotating
	## _pending_kon_* into _deferred_kon_*.
	# Observational accumulator probe — emitted before commit so the
	# trace captures "what KON/KOFF FFT would commit this IRQ".
	_emit_kon_koff_accumulator_trace()
	if (_deferred_kon_s4 | _deferred_kon_s5) != 0:
		_commit_kon(_deferred_kon_s4, _deferred_kon_s5, _deferred_kon_dict)
	# Rotate THIS IRQ's pending into NEXT IRQ's deferred (mirrors
	# FUN_80017118 setting entity+0x60 from chan_word_0 KON bits during
	# the per-entity dispatch sub-loop).
	_deferred_kon_s4 = _pending_kon_s4
	_deferred_kon_s5 = _pending_kon_s5
	_deferred_kon_dict = _pending_kon_dict.duplicate()
	_pending_kon_s4 = 0
	_pending_kon_s5 = 0
	_pending_kon_dict.clear()


func clear_deferred_kon() -> void:
	## §9.2 — wipe pre-anchor KON bits that rotated into the deferred
	## buffer before the cadence anchor latched. Called once from
	## play_sound on the anchor latch flip so the first post-anchor
	## commit doesn't carry pre-anchor seed residue.
	_deferred_kon_s4 = 0
	_deferred_kon_s5 = 0
	_deferred_kon_dict.clear()


func emit_koff_now(mask: int) -> void:
	## One-shot SPU KOFF write outside the per-IRQ commit cycle. Mirrors
	## FFT FUN_8001ACF0(0, mask): feds_channel_resolver (0x80013B20) emits
	## this on the prior tenant's voice mask BEFORE rebinding chan_word_0
	## bit 0x1, regardless of whether the SPU voice is still producing
	## audible PCM. EffectSoundPool.allocate_pair calls this on slot
	## re-tenant so probe_kon_koff_mask gains the cad 1212/1343 rows that
	## PCSX emits for zombie_no_music's BATTLE.BIN-driven catalog replays.
	## See research/effect_sound/working_documents/
	## ZOMBIE_CATALOG_REPLAY_SILENT_FIX_PLAN.md Stage C-1.
	if mask == 0:
		return
	for voice in range(_pool.SPU_VOICE_BASE,
			_pool.SPU_VOICE_BASE + _pool.POOL_SLOT_COUNT):
		var bit: int = 1 << voice
		if (mask & bit) == 0:
			continue
		_mixer.key_off(voice)
	_emit_kon_koff_mask_trace(0, mask)


func reset_voice_routing(mask: int) -> void:
	## Clear per-voice SPU noise + FMod (pitch-mod) routing for the voices in
	## `mask`. Mirrors FFT FUN_800137d8 (slot allocator @ 0x80013834), which
	## zeroes the per-entity noise mask (slot+0x6c) — and the FMod mask
	## (slot+0x68) — at slot allocation. FFT rebuilds the SPU NON/PMON registers
	## each IRQ from those masks, so zeroing at alloc means a REUSED voice does
	## not carry the prior effect's noise/pitch-mod mode into the next sound
	## (e.g. an ice summon's noise voice reused by a later effect). We write the
	## SPU registers directly at alloc instead of via a per-IRQ mask rebuild.
	if mask == 0:
		return
	for voice in range(_pool.SPU_VOICE_BASE,
			_pool.SPU_VOICE_BASE + _pool.POOL_SLOT_COUNT):
		if (mask & (1 << voice)) == 0:
			continue
		_mixer.set_voice_noise(voice, false)
		_mixer.set_voice_fmod(voice, 0)


func flush_koff_post_loop() -> void:
	## FFT spu_updater_tick post-loop KOFF flush (PC 0x80014E04-0x80014EF0).
	## Walks every active slot, accumulates the FLAG_KOFF_PENDING mask,
	## fires per-voice key_off + ADSR2 release writes, runs sustain re-arm,
	## and clears per-tick flags via slot.clear_per_tick_flags().
	var koff_mask := 0
	for slot in _pool.active_slots():
		var flag: int = slot.flag_word
		var voice: int = _pool.voice_for_slot(slot.slot_idx)
		var koff_pending: bool = (flag & _SS.FLAG_KOFF_PENDING) != 0

		if koff_pending:
			koff_mask |= slot.voice_mask
			_mixer.key_off(voice)
			# FFT KOFF-driven ADSR2 release write at PC 0x80014EBC-C0.
			# Gated to STREAM_END KOFFs so TTL-boundary KOFFs (already
			# handled by the per_channel_tick release-prep gate in
			# dispatcher.gd) don't double-fire — see existing comment
			# block in the prior tick() implementation.
			if (flag & _SS.FLAG_STREAM_END) != 0:
				var koff_release_low: int = 6  # FFT a1=0x6 at PC 0x80014EBC
				var koff_spu_value: int = (slot.adsr2 & 0xFFC0) | koff_release_low
				if _Trace._post_anchor and _Trace._cadence_index > 0:
					SharedIrqWalker._probe_adsr2_low_register_count += 1
					_Trace.emit("adsr2_low_register", {
						"call_index": SharedIrqWalker._probe_adsr2_low_register_count,
						"voice": voice,
						"adsr2": koff_spu_value,
					})
				_mixer.set_voice_adsr2_low(voice, koff_release_low, 0)
				slot.adsr2 = koff_spu_value

		# Walker re-arm during sustain — preserves the existing
		# FUN_80017118-adjacent logic (per-IRQ ADSR2 transition staging).
		var sustain_active: bool = slot.force_envelope_open and not koff_pending
		if sustain_active and slot.adsr2 != slot.prev_adsr2:
			slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_HIGH
		slot.prev_adsr2 = slot.adsr2

		# FUN_80017118 L12002 `sh zero, 0x0(s0)` per-tick clear. After
		# this point FLAG_KOFF_PENDING / FLAG_STREAM_END / any residual
		# KON flag is gone — fresh state for the next IRQ.
		slot.clear_per_tick_flags()

	# FUN_8001ACF0(0, koff_mask) — single KOFF SPU write per IRQ.
	_emit_kon_koff_mask_trace(0, koff_mask)


static var _probe_kon_koff_accumulator_count: int = 0

func _emit_kon_koff_accumulator_trace() -> void:
	# Per-tick aggregate of what FFT-faithful (kon_mask, koff_mask) would
	# be on this tick. Called from flush_kon_commit BEFORE the deferred
	# buffer is flushed; the kon_mask read is the DEFERRED buffer (the
	# PREVIOUS IRQ's accumulation, which is about to be committed —
	# mirrors PCSX reading entity+0x60 at IRQ start). KOFF mask is
	# observed from slot.flag_word (FLAG_KOFF_PENDING survives until
	# flush_koff_post_loop). FFT's KOFF-wins mutex is gone — the two
	# events live in different IRQ phases and can co-fire (see
	# RERAISE_KON_KOFF_IDLE_TIMEOUT_FAITHFUL_PORT_PLAN.md §3.1).
	if not _Trace._post_anchor or _Trace._cadence_index <= 0:
		return
	var kon_mask: int = _deferred_kon_s4 | _deferred_kon_s5
	var koff_mask: int = 0
	for slot in _pool.active_slots():
		var bit: int = 1 << _pool.voice_for_slot(slot.slot_idx)
		if (slot.flag_word & _SS.FLAG_KOFF_PENDING) != 0:
			koff_mask |= bit
	if kon_mask == 0 and koff_mask == 0:
		return
	_probe_kon_koff_accumulator_count += 1
	_Trace.emit("kon_koff_accumulator", {
		"call_index": _probe_kon_koff_accumulator_count,
		"kon_mask": kon_mask,
		"koff_mask": koff_mask,
	})


func _commit_kon(s4: int, s5: int, pending_kon: Dictionary) -> void:
	## SPU KON commit. The MIPS code OR's s4 + s5 into a 24-bit voice
	## mask (a2) and writes both KON_LO (low 16 bits) and KON_HI (bits
	## 16-23) atomically. We replicate per-voice via the C++ mixer.
	## The re-key-prep KOFF (PCSX FUN_8001AED4 `sh a2,0x18c(v0)`) is
	## INTERNAL to FUN_8001ACF0 and does not emit its own probe row —
	## the probe BP captures only the outer call's (mode,mask) tuple.
	## We call _mixer.key_off here without tracing, then emit one batched
	## KON event for the combined s4|s5 mask.
	var combined: int = s4 | s5
	var emitted_kon_mask: int = 0
	for voice in range(_pool.SPU_VOICE_BASE,
			_pool.SPU_VOICE_BASE + _pool.POOL_SLOT_COUNT):
		var bit: int = 1 << voice
		if (s4 & bit) == 0:
			continue
		_mixer.key_off(voice)
	for voice in range(_pool.SPU_VOICE_BASE,
			_pool.SPU_VOICE_BASE + _pool.POOL_SLOT_COUNT):
		var bit: int = 1 << voice
		if (combined & bit) == 0:
			continue
		var slot = pending_kon.get(voice, null)
		if slot == null:
			continue
		var is_primary: bool = (s4 & bit) != 0
		# SECONDARY KON in FFT is the a0=0 update-only path that doesn't
		# issue a fresh SPU KEY_ON. For SILENT DRIVER voices our
		# mixer.key_on side-effect of sample-restart produces audible
		# spikes. For AUDIBLE voices the key_on path was maintaining
		# alignment within tolerance. Until Spu gains a dedicated
		# update-only API, gate secondary KON on lfo_active (= the
		# d9-bearing audible voice).
		if is_primary or slot.lfo_active:
			_key_on_voice(voice, slot, is_primary)
			emitted_kon_mask |= bit
			# diag_keyon_per_voice — paired with PCSX
			# diag_keyon_per_voice.lua (BP @ FUN_8001ACF0). Emits one
			# row per ACTUAL KEYON committed (after the is_primary /
			# lfo_active gate, which is what PCSX's KEYON mask bit set
			# reflects). Captures slot_idx + is_primary so we can spot
			# Godot-only re-KEYs (e.g. silent-driver overlays that fire
			# extra KEYONs PCSX doesn't). cure_no_music v20 shows 4
			# extra Godot KEYONs at cadences 1, 21, 41, 61, 82 that
			# need an attributable source.
			if _Trace._post_anchor:
				_probe_keyon_per_voice_count += 1
				# MUSIC_ITER59 — KON precursor state for cadence-skew
				# attribution. iter-48 + MUSIC_86 voice 13/14 analysis
				# shows ~half of KONs fire 1 cad early on Godot vs PCSX.
				# Capture channel state at KON-commit time so we can
				# classify Δ=0 (aligned) vs Δ=-1 (early) KONs by what
				# distinguishes them. last_kon_channel is set in
				# note_handler when the Note dispatch arms FLAG_PRIMARY_
				# KON; survives until the next KON for this slot.
				# opcode_pos / opcode_bytes are SFX-specific (music
				# tracks the bytecode via TrackState.event_idx); we omit
				# them so the row stays compact + uniform across paths.
				var ch = slot.last_kon_channel
				_Trace.emit("keyon_per_voice", {
					"call_index": _probe_keyon_per_voice_count,
					"voice": voice,
					"slot_idx": slot.slot_idx,
					"source": "primary" if is_primary else "secondary",
					"flag_word": slot.flag_word,
					"channel_idx": ch.channel_idx if ch != null else -1,
					"chan_word_0": ch.channel_word_0 if ch != null else -1,
					"note_duration": ch.note_duration if ch != null else -1,
					"chan_78_idle_timeout": ch.idle_timeout if ch != null else -1,
					"walker_flag_word": slot.walker_flag_word,
				})
	# Single batched KON emit per tick with combined mask.
	_emit_kon_koff_mask_trace(1, emitted_kon_mask)


func _key_on_voice(voice: int, slot: _SS, is_primary: bool) -> void:
	## Per-voice SPU KEYON. Passes slot.adsr1 / slot.adsr2 unmodified —
	## the slot's standing register values (set by prestage + opcode
	## 0xC2/0xC7/0xC9/0xCA dispatch) match what FFT's walker fan-out
	## would write. A prior `& 0x80FF` here zeroed the attack-rate field
	## under the misreading that FFT does so at KEYON; PCSX captures show
	## the opposite (voice 18 first-KEYON adsr1 = 0x32FF, not 0x00FF).
	## See KEYON_ADSR1_MASK_AND_ORDERING_PATCH.md §3.1.
	var adsr1: int = slot.adsr1
	var adsr2: int = slot.adsr2

	# Enable reverb send for primary-KON audible voices. Routes the
	# voice through the reverb buffer, which continues decaying after
	# KOFF.
	# Use instrument-default sample addresses (key_on) when slot hasn't
	# bound explicit ones. The feds resource_id → instrument-bank mapping
	# is a documented follow-up (slot.sample_start_addr stays 0 today).
	# Pass 7.E.F — AND with slot.reverb_send_enabled so music's per-track
	# 0xBA/0xBB toggle is respected. SFX defaults true → unchanged.
	var reverb_enabled: bool = is_primary and slot.reverb_send_enabled
	if slot.sample_start_addr != 0:
		_mixer.key_on_with_addresses(
			voice,
			slot.instrument_idx,
			slot.pitch_staging & 0xFFFF,
			slot.vol_staging_l,
			slot.vol_staging_r,
			adsr1,
			adsr2,
			slot.sample_start_addr,
			slot.sample_loop_addr,
			reverb_enabled,
		)
	else:
		_mixer.key_on(
			voice,
			slot.instrument_idx,
			slot.pitch_staging & 0xFFFF,
			slot.vol_staging_l,
			slot.vol_staging_r,
			adsr1,
			adsr2,
			reverb_enabled,
		)

	# (Removed) Synthetic first_keyon 0x1FF arm. This was a Godot-only
	# arm site with no FFT analog — it incidentally matched PCSX's
	# cad=1 walker visibility on cure_no_music but over-armed cure_4
	# voice 18 (+1) and cure_4 v18/v19 re-bind at cad=497 (+2). The
	# correct mechanism lives in _process_slot's walker_seed_pending
	# consumer, which fires the deferred prestage arm only when
	# play_sound saw ac_before_first_note for the bytecode. See
	# CAUSE_A_PRESTAGE_TIMING_ISSUE.md §5 option (a-revised).
