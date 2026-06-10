class_name EffectPlaySound
## play_sound + feds_channel_resolver bridge — port of FUN_800125A8 +
## FUN_80013B20.
##
## In FFT, play_sound(sound_id) routes to feds_channel_resolver, which:
##   1. Looks up the resource node via (a1 >> 16) — the feds resource_id.
##   2. Reads `feds + 0x14 + config*4` to get an `entry_val` that encodes
##      the per-config slot_idx.
##   3. Allocates a pair starting at slot_idx (free-list walk).
##   4. Initializes both slots' channel-state words and binds opcode streams.
##
## The exact entry_val → slot_idx derivation is not yet fully traced.
## For first-pass cure_single we accept slot_idx as a caller-supplied
## parameter; once the formula is resolved this becomes self-deriving.


const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _Pool = preload("res://addons/exmateria_sound/runtime/effect_sound/pool.gd")
const _Dispatcher = preload("res://addons/exmateria_sound/runtime/shared/dispatcher.gd")
const _EntityCatchup = preload("res://addons/exmateria_sound/runtime/effect_sound/entity_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _FlushTick = preload("res://addons/exmateria_sound/runtime/shared/flush_tick.gd")
const _SharedEntityList = preload("res://addons/exmateria_sound/runtime/shared/entity_list.gd")

# probe_play_sound_call (GOLD #1) counter. The PCSX BP at 0x800125C0
# counts every audio-enabled play_sound entry; this counts every
# play_feds_pair entry to match.
static var _probe_play_sound_call_count: int = 0

# probe_cadence_source (Layer 0 anchor) counter. The PCSX BP at
# 0x800149DC counts every RCnt2 IRQ fire (Clock 1). We increment this
# at the start of tick_all_dispatchers, which is Godot's per-IRQ entry
# point. The same counter is also written into _Trace._cadence_index so
# every Clock 2 event row gets stamped with the pulse it fired in.
static var _probe_cadence_source_count: int = 0
# Set once when _Dispatcher._first_dispatch_fired flips true. The
# post-tick block below resets _probe_cadence_source_count to 0 the
# tick after that flip so the next tick's increment lands at 1 —
# matching PCSX's probe_cadence_source where CADENCE_INDEX gets
# zeroed inside the same event_dispatch fire that anchors cadence.
static var _cadence_anchored: bool = false

# Synthesis-layer probes (Layer 5) — match the FFT FUN_80017118 commit
# sites (PCs 0x80017324/0x80017328 for vol L/R, 0x80017368 for pitch).
static var _probe_vol_lr_staging_count: int = 0
static var _probe_vol_inputs_count: int = 0
# probe_vol_formula_stages (Layer 5 BISECTION) — captures the four
# intermediate accumulator stages inside FFT FUN_80017118's vol formula
# (PC 0x800171C4..0x80017310). Pairs with PCSX BPs at 0x800171F4 /
# 0x8001720C / 0x8001722C / 0x80017248. Each Godot iteration of the
# vol_prestage block emits 4 rows tagged with stage ∈ {env_sample,
# voice_gated, global_gated, pan_base}. Bisects reraise voice_21's
# residual cos_dist ≈ 0.40 to the first stage where Godot and PCSX
# diverge. See research/effect_sound/working_documents/
# PROBE_VOL_FORMULA_STAGES_INTRODUCED.md.
static var _probe_vol_formula_stages_count: int = 0
static var _probe_pitch_staging_count: int = 0
static var _probe_pitch_inputs_count: int = 0
# probe_pitch_formula_stages (Layer 5 BISECTION) — companion to
# probe_vol_formula_stages. Captures the five intermediate values of FFT
# FUN_80017118's pitch formula at PC 0x80017340..0x80017370:
# pitch_base, pitch_bend, pool_a2, midi_sum, pitch_result. Each Godot
# iteration of the pitch_prestage block emits 5 rows so a row diff
# isolates which input drifts first on the chronic voice_21 cos_dist
# ≈ 0.40 (vol formula already proven bit-exact). See
# research/effect_sound/working_documents/
# PROBE_PITCH_FORMULA_STAGES_INTRODUCED.md.
static var _probe_pitch_formula_stages_count: int = 0
static var _probe_fun80017118_clear_count: int = 0

# Cadence-layer probes (top-down localization). Layer 1 fires once per
# active entity per IRQ; Layer 2 fires only when FFT's slot+0x10 < 0
# gate (PC 0x80014BC4) lets per-entity work proceed. Godot has no
# slot+0x10 model yet so both layers emit at the same point — Layer 2
# is expected to FAIL on count until the gate is ported.
static var _probe_per_entity_iter_count: int = 0
static var _probe_per_entity_pass_count: int = 0
# Layer 3: entity sub-loop iter (FFT LAB_80014CCC entry inside the
# per-entity work). One emit per cadence_body fire.
static var _probe_spu_slot_loop_count: int = 0
# Cadence-chain extension into per_channel_tick. Emitted 8× per
# spu_slot_loop iteration (once per FFT channel position) so the count
# matches PCSX BP @ 0x80015198 = `lhu t1, 0x0(a1)` entry, BEFORE the
# selectivity gate at PC 0x800151A0.
static var _probe_per_channel_tick_entry_count: int = 0
# Layer 4 paired: FUN_80017118 entry (= drain function call). One emit
# per _drain_prestage_all_slots() invocation.
static var _probe_fun80017118_entry_count: int = 0
# Layer 4 paired: FUN_80017118 inner per-slot iter at PC 0x80017194.
# One emit per slot iteration in _drain_prestage_all_slots loop.
static var _probe_fun80017118_iter_count: int = 0

# Godot-side bisecting probe for the _prestage_first_instrument choice.
# One emit per play_feds_pair _bind_slot call, capturing which instrument
# index the prestage staged and which source it used:
#   "ac_before_note"   — first AC dispatches before first Note in event order;
#                        uses inst[first_ac.params[0] + 1] (existing path).
#   "allocator_default"— first Note dispatches before first AC (or no AC at
#                        all but Notes exist); uses inst[1] to mirror FFT's
#                        slot allocator default seed (slot.instrument_idx = 0
#                        resolved via the +1 rule). cure_4 voice 18 is the
#                        canonical case — see
#                        research/effect_sound/working_documents/CURE_4_CH2_DEFAULT_INSTRUMENT_INVESTIGATION.md.
# No PCSX-side analog yet; this is the Godot leg of the bisection — pair it
# manually with spu_voice_events.jsonl first-KEYON start_addr columns.
static var _probe_prestage_first_instrument_count: int = 0

# diag_slot2_init_state — Godot side of the slot-state-post-bind diag.
# Fires at the END of play_feds_pair (mirroring PCSX BP at
# play_sound_callee_12d40 exit PC 0x80012E74). Emits one row per slot
# (×8) per pair-bind call so we can compare slot 2's chan_word_0 /
# note_duration cross-side at bind time.
static var _diag_slot2_init_state_count: int = 0

# diag_entity_catchup_iter — Godot-only bisection probe for the tail-end
# catchup-loop drift on cure_4 (KON_CLUSTER_AND_CATCHUP_DRIFT.md §4.5).
# Fires once per inner-loop iteration of the entity_acc catchup `while`
# in _run_entity_catchup, capturing entity_acc before/after the
# apply_sub_loop_fire, the slot+0x10 gate value, the safety counter,
# and whether the gate let cadence_body fire. Pairs with PCSX BP at
# PC 0x80014CCC (LAB_80014CCC, the sub-loop body entry) to find where
# Godot fires an extra iteration at end-of-cure_4 (cad 496+497 instead
# of cad 498 like PCSX).
static var _diag_entity_catchup_iter_count: int = 0
# diag_cadence_wallclock — paired with PCSX diag_cadence_wallclock.lua.
# Emits {cadence_index, sub_tick, godot_sample_count} once per
# tick_all_dispatchers post-anchor call, so we can diff samples-per-
# cadence vs PCSX's PCSX.SPU.getSampleCount(). Answers the implicit
# question "does cadence_index N mean the same wall-clock moment on
# both sides?" See SMD_PLAYBACK_SPEED_INVESTIGATION.md.
static var _diag_cadence_wallclock_count: int = 0

# diag_envelope_tail — paired with PCSX diag_envelope_tail.lua. Emits
# {voice, env_state, env_vol, ...} per voice per cadence so the post-
# KEYON envelope decay can be diffed sample-by-sample against PCSX's
# envelope curve. See PROTECT_NO_MUSIC_AUDIBLE_GAP_RESOLUTION.md
# §8.1.1: protect_no_music's 649 ms audible-window gap is in the SPU
# envelope tail (FFT-side dispatch is bit-exact between PCSX and Godot).
static var _diag_envelope_tail_count: int = 0

# probe_noise_clock / probe_noise_status — paired change-detect emits.
# Track the last-emitted value(s) so we only fire a row on transition,
# matching PCSX's Lua probes. _last_noise_per_voice is -1-init (sentinel
# for "no row yet") so the first observed state always emits.
static var _probe_noise_clock_count: int = 0
static var _probe_noise_clock_last: int = -1
static var _probe_noise_status_count: int = 0
static var _probe_noise_status_last: Array = []  # per-voice last bit (-1 = unset)

# Sstate-derived entity-list snapshot for the seeder. Populated by
# render_effect_sound from --entity-state=<json> (produced by
# smd-player/workspace/orchestrator/extract_entity_state.py). When
# null the seeder push_errors — sstate seeding is mandatory now that the
# per-effect --entity-acc-cad0 / hardcoded silent-driver values have
# been deleted. See ENTITY_ACC_SAVESTATE_PORT_PLAN.md.
static var _entity_state_seed: Variant = null

# Per-slot chan-side residue (music-engine state frozen at savestate
# time) — used by emit_lfo_handler_inactive on dormant slots to emit
# probe rows that match PCSX's chan-side reads instead of zeros. Set
# by render_effect_sound.gd from chan_lfo_residue.json. Keyed by
# slot_idx (0-7); each value is the per-slot dict with chan_word_0,
# pre_pitch_lo/hi, word_86, pitch_bend, subslot_0/1/2/3.
# See DORMANT_SLOT_PROBE_RESIDUE_SEED.md.
static var _slot_residue: Dictionary = {}

# Slots, dispatchers, mixer + pool state owned by the caller.
var _pool: _Pool
var _dispatchers: Array = []  # parallel to pool slots — null when slot is free (legacy primary-pair binding)
var _channels: Array = []      # parallel to pool slots — null when slot is free (primary)

# Optional mixer ref for diag_envelope_tail. Set by render_effect_sound via
# set_mixer_for_diagnostics(); when null, the envelope-tail emit is skipped
# (no-op for callers that don't supply a mixer, e.g. unit tests).
var _diag_mixer: Spu = null

# Flush-tick instance — drives the FFT-faithful KOFF/KON commit split
# (FUN_80017118 per-slot walker + spu_updater_tick post-loop KOFF flush).
# Set by render_effect_sound via set_flush_tick(); when null, the flush
# calls inside tick_all_dispatchers no-op (legacy callers that don't run
# the full SPU pipeline keep working). See
# RERAISE_KON_KOFF_IDLE_TIMEOUT_FAITHFUL_PORT_PLAN.md §3.1.
var _flush_tick: _FlushTick = null

# Entity list this play pushes its effect entity onto. Defaults to the process
# singleton (single-SPU / parity harness). A multi-SPU game engine injects a
# PER-UNIT list via set_entity_list() so each SPU's Runtime walks only its own
# entities (otherwise one unit's Runtime would drive every unit's entities).
var _entity_list = null

# Entity-level catch-up state — one per pair allocation (mirrors FFT's
# linked-list of effect-entity slots; cure spell allocates 1 effect entity).
# Type via the preloaded const (`_EntityCatchup`) rather than the global
# `class_name`, since the class-cache is only refreshed by the headed
# editor — fresh class_names are invisible in --script invocations until
# the user reopens the project.
var _entity_catchup = null

# Silent driver entities seeded from the sstate's entity linked list
# (DAT_80032A50 → 0x80038B80 → 0x800387F0 → 0x800370E0). Filled by
# `_seed_entities_from_state` from `_entity_state_seed`. Silents have
# positive slot+0x10 → bgez at PC 0x80014BC4 always takes the skip → no
# per-entity work, but they still iterate per IRQ so per_entity_iter
# row counts pair structurally.
var _silent_entities: Array = []

# Cure entity's slot+0x10 (entity gate flag). FFT's bgez at PC 0x80014BC4
# skips per-entity work when this >= 0; passes when negative. Initialized
# from probe_entity_dump (-32766 = 0xFFFF8002, bit 15 + bit 1 set).
# Probe data shows cure stays negative for IRQs 1..519 then transitions
# to 0x0002 (= 2) at IRQ 520. The trigger: at cadence 519 endbar fires
# for both cure channels with no active loop, opcode handler zeroes
# slot+0x58, and the SAME IRQ's spu_updater_tick reaches LAB_80014D70 →
# slot+0x58==0 → LAB_80014DD0 → andi 0x7fff → bit 15 cleared. Modeled
# below in _run_entity_catchup: post-cadence_body check zeroes the gate
# when both cure slots' active_word bit 0 is cleared (the endbar-no-loop
# signal — see dispatcher.gd::_op_endbar). See DRAIN_RATE_INVESTIGATION.md
# §13.
var _cure_slot_10: int = -32766
# Refs to the cure pair's pool slots, captured at play_feds_pair time.
# Used by the slot_10 transition check in _run_entity_catchup.
var _cure_slot_a = null
var _cure_slot_b = null

# Extra channel bindings (silent driver overlays).
# Each entry: { channel: ChannelState, dispatcher: Dispatcher,
#               target_slot_idx: int, start_sub_tick: int, started: bool }
# The channel's target_slot_idx points to an EXISTING pool slot that the
# primary pair already owns. tick_all_dispatchers() walks both _dispatchers
# (1:1 primary) AND _extra_bindings (N:1 overlay) — multiple dispatchers
# write flag bits to the same slot's flag_word via OR.
var _extra_bindings: Array = []


var _waveset: WavesetParser = null


func _init(pool: _Pool, waveset: WavesetParser = null) -> void:
	_pool = pool
	_waveset = waveset
	_dispatchers.resize(_pool.POOL_SLOT_COUNT)
	_channels.resize(_pool.POOL_SLOT_COUNT)


func set_mixer_for_diagnostics(mixer: Spu) -> void:
	## Wire a mixer reference for diag_envelope_tail's per-cadence emit.
	## Optional — when unset, the emit is skipped (legacy callers that
	## don't run the envelope-tail diag keep working unchanged).
	_diag_mixer = mixer


func set_entity_list(entity_list) -> void:
	_entity_list = entity_list


func _list():
	return _entity_list if _entity_list != null else _SharedEntityList.get_singleton()


func set_flush_tick(flush: _FlushTick) -> void:
	## Wire the per-IRQ flush instance. tick_all_dispatchers calls into
	## flush.flush_kon_only_for_slot inside the catchup sub-loop, then
	## flush.flush_kon_commit + flush.flush_koff_post_loop at IRQ end
	## (mirroring FFT's spu_updater_tick → FUN_80017118 → post-loop
	## KOFF flush sequencing).
	_flush_tick = flush


# FFT slot+0x10 effect-load arming bit (bgez at PC 0x80014BC4). Sstate
# captures the entity BEFORE this bit is set; the seeder ORs it in to
# put the active entity into the runtime-armed state.
const _ENTITY_GATE_ARM_BIT: int = 0x8000


func _seed_entities_from_state() -> bool:
	## Materialize _entity_catchup + _silent_entities from
	## _entity_state_seed (extracted from the savestate by
	## smd-player/workspace/orchestrator/extract_entity_state.py).
	##
	## Discriminator: an entity with channel_count > 2 is the effect
	## entity (cure_no_music = 8 channels); channel_count <= 2 marks a
	## silent driver. The two silent drivers are bit-identical across
	## all captured savestates (verified — see
	## ENTITY_ACC_SAVESTATE_VERIFICATION.md Q2).
	##
	## For the effect entity the seeder also:
	##   1. ORs bit 15 (0x8000) into gate. FFT's effect-load path arms
	##      slot+0x10 with this bit so the bgez at PC 0x80014BC4 falls
	##      through into per-entity work. Sstate captures the entity
	##      pre-arming; runtime starts post-arming. (Same value the
	##      _cure_slot_10 = -32766 default has always reflected.)
	##   2. Drains entity_acc by entity_budget until acc < budget. This
	##      walks N "no-fire" outer_decrements from the sstate snapshot
	##      down to the canonical cad=0 init range [0, ENTITY_BUDGET) —
	##      subcounter/pass/measure don't change because no sub-loop
	##      fires happen during the warmup. After the warmup the
	##      catchup loop's first IRQ produces exactly one fire and
	##      lands acc at the cad=1 value PCSX reports. Eliminates the
	##      per-session --entity-acc-cad0 back-calc that the orchestrator
	##      used to derive from probe_entity_dump.jsonl.
	if _entity_state_seed == null:
		return false
	var ents: Array = _entity_state_seed.get("entities", [])
	if ents.is_empty():
		return false
	_silent_entities.clear()
	_entity_catchup = null
	for raw in ents:
		var ec = _EntityCatchup.new()
		ec.entity_acc        = int(raw.get("entity_acc", _EntityCatchup.ENTITY_ACC_INIT))
		ec.entity_budget     = int(raw.get("entity_budget", _EntityCatchup.ENTITY_BUDGET_INIT))
		ec.entity_subcounter = int(raw.get("subcounter", _EntityCatchup.ENTITY_SUBCOUNTER_INIT))
		ec.entity_wrap_reset = int(raw.get("wrap_reset", _EntityCatchup.ENTITY_WRAP_RESET_DEFAULT))
		ec.entity_pass       = int(raw.get("pass", 1))
		ec.entity_measure    = int(raw.get("measure", 0))
		ec.entity_gate       = int(raw.get("gate", 0)) & 0xFFFF
		var channel_count: int = int(raw.get("channel_count", 0))
		if channel_count > 2:
			# Active effect entity — drain to cad=0 init and arm gate.
			while ec.entity_acc >= ec.entity_budget and ec.entity_budget > 0:
				ec.entity_acc -= ec.entity_budget
			# Arm bit 15 of gate; store on the slot_10 tracker since the
			# catchup loop reads `_cure_slot_10` (not the entity struct).
			var armed_gate: int = (int(raw.get("gate", 0)) | _ENTITY_GATE_ARM_BIT) & 0xFFFF
			if armed_gate >= 0x8000:
				armed_gate -= 0x10000
			_cure_slot_10 = armed_gate
			_entity_catchup = ec
		else:
			_silent_entities.append(ec)
	if _entity_catchup == null:
		push_error("EffectPlaySound: entity_state seed has no active entity " +
				"(channel_count > 2); cannot drive cure trajectory")
		return false
	# Pass 8 phase 5 — push the active effect entity onto the shared
	# entity LL so Runtime.tick() can walk it. owning_play_sound lets
	# Runtime._run_sfx_entity_iter call back into this EffectPlaySound
	# to fire the per-IRQ catchup body. Silent entities are NOT pushed:
	# the legacy _run_entity_catchup body emits per_entity_iter probes
	# for them internally, so the unified driver fires the SFX pipeline
	# exactly once per IRQ (via the active entity) and the existing code
	# walks _silent_entities itself.
	_entity_catchup.owning_play_sound = self
	_entity_catchup.is_done = false
	_list().push(_entity_catchup)
	return true


func _promote_next_silent_entity() -> bool:
	## Activate the next eligible entity from _silent_entities and use it
	## as the new `_entity_catchup`. Mirrors FFT's per-target fresh-entity
	## allocation inside feds_channel_resolver (0x80013B20 →
	## play_sound_callee_12d40 0x80012D40, stride-0x160 walk of
	## g_sound_resource_list at DAT_80032a60 — `*puVar3 & 1` filters in-use
	## slots; non-matching slots become allocator targets and get
	## FUN_800137d8 init'd to defaults).
	##
	## Picks the first entity whose savestate-captured gate is non-zero
	## (an FFT-side eligibility marker — silent-driver entities loaded
	## from the savestate all carry gate=1, exhausted/cleared entries
	## carry 0 and are skipped). Applies the FUN_800137d8 init values via
	## EffectEntityCatchupState.reset(): entity_acc = 0x10000,
	## entity_budget = 0x6600, entity_subcounter = 1, entity_wrap_reset
	## = 48 (effect-side, = 0x30 / slot+0x15 with slot+0x15 = 1), pass =
	## 1, measure = 0. Re-arms _cure_slot_10 with the gate-bit-15 marker
	## so the per_entity_pass gate in _run_entity_catchup falls through
	## and lets cadence_body fire on the freshly-rebound slots.
	##
	## On overwrite: the prior _entity_catchup is discarded. For zombie
	## the audible-primary entity has already wound through its first-
	## target trajectory and is exhausted by cad ~750 (v20/v21 PCM
	## window ends ~cad 810 PCSX vs cad 198360-samples / 183-per-cadence
	## on Godot pre-fix) — by cad ~1184 (catalog replay) the old entity
	## adds nothing and can be safely replaced. See
	## ZOMBIE_CATALOG_REPLAY_SILENT_FIX_PLAN.md §4.3.
	for i in range(_silent_entities.size()):
		var ent = _silent_entities[i]
		if ent == null:
			continue
		if int(ent.entity_gate) == 0:
			continue
		# Reset to FUN_800137d8 defaults (effect-side wrap_reset = 48).
		ent.reset()
		# Re-arm the gate so _run_entity_catchup's bgez fall-through fires
		# cadence_body. Mirrors the same arm path _seed_entities_from_state
		# applies to the active entity at first_alloc time.
		_cure_slot_10 = -32766  # 0xFFFF8002 signed — bit 15 + bit 1 set.
		# Pass 8 phase 5 — rotate the shared-entity-LL membership. The
		# prior active entity (exhausted, audible window long over) is
		# unlinked so the unified driver doesn't re-fire it; the new one
		# is pushed in its place. owning_play_sound + is_done mirror what
		# _seed_entities_from_state set on the original active entity.
		if _entity_catchup != null:
			_entity_catchup.is_done = true
			_list().unlink(_entity_catchup)
		ent.owning_play_sound = self
		ent.is_done = false
		_entity_catchup = ent
		_silent_entities.remove_at(i)
		_list().push(_entity_catchup)
		return true
	return false


func play_feds_pair(feds: FedsBank, pair_idx: int, slot_idx: int,
		sound_id: int = -1) -> bool:
	## Allocate a pool pair starting at `slot_idx`, bind the feds pair's
	## two channels' opcode streams to dispatchers, and prime each slot's
	## active_word so the per-tick flush picks them up.
	##
	## `sound_id` (when >= 0) drives the chan+0x92 init lookup via
	## FedsBank.chan_92_for — mirrors FFT's per-sound-id table read at
	## FUN_80013B20 PC 0x80013BFC. Pass the value resolved by
	## EffectSoundResolver (the FFT-side a1 & 0xFFFF — NOT the
	## timeline keyframe sid). When < 0, channel_state.gd's default
	## stands. See research/effect_sound/working_documents/
	## CHAN_92_STATIC_PORT_PLAN.md.
	##
	## Returns false on allocation conflict (caller may free + retry).
	# Cadence anchor has moved from play_sound to first event_dispatch
	# (see _Dispatcher._dispatch + probe_event_dispatch.lua). play_sound
	# is now a pure counter probe; cadence_index for this row reflects
	# whatever the current pulse is, which is pre-anchor and uninteresting
	# for pairing. No reset here.
	_probe_play_sound_call_count += 1
	_Trace.emit("play_sound", { "call_index": _probe_play_sound_call_count })
	if feds == null:
		return false
	if pair_idx < 0 or pair_idx >= feds.num_pairs:
		push_warning("EffectPlaySound: pair %d out of range (%d pairs)" % [pair_idx, feds.num_pairs])
		return false

	var allocated := _pool.allocate_pair(slot_idx)
	if allocated.is_empty():
		return false

	# Init: one EffectEntityCatchupState per CURE ENTITY (= per spell
	# allocation), mirroring FFT slot-allocator FUN_800137d8 at PC
	# 0x800137d8..0x800138a8 which allocates the entity exactly once and
	# every subsequent sound dispatch on that spell reuses it. cure_4
	# fires 3 play_feds_pair calls (cad=72 main, cad=72 secondary, cad=495
	# tertiary) — only the first one creates the entity; the later two
	# must NOT reset _entity_catchup or its accumulated entity_acc, or
	# the catchup-loop trajectory snaps back to the cad=0 init value
	# mid-run and diverges from PCSX. See diff_entity_acc.py output
	# pre/post this gate for the cad=495 reset behaviour.
	var first_alloc: bool = _entity_catchup == null
	# BATTLE.BIN-driven catalog replay path. PCSX entity_state.json for
	# zombie_no_music shows three entities in the linked list at savestate-
	# restore time: the audible primary (channel_count=8) plus two silent
	# drivers (channel_count=2 each). FFT's FUN_8006FA18 per-target
	# status-effect dispatcher fires func_0x80044018 once per target →
	# routes through play_sound → feds_channel_resolver, which walks
	# g_sound_resource_list (FUN_80012D40, stride-0x160 at DAT_80032a60)
	# for a free entity and allocates a fresh entity per target. Godot's
	# `_entity_catchup` is a single-slot model — when the catalog replay
	# fires at cad ~1184/~1314 with `_entity_catchup` already non-null
	# (audible primary's entity, by now exhausted with `entity_acc` near 0
	# and the v20/v21 audible window long over), we promote one of the
	# silent-driver entities into `_entity_catchup` to mirror FFT's fresh-
	# entity allocation. Without this, the catalog-replayed slot's
	# dispatcher binds correctly but never receives cadence-body fires
	# because the exhausted entity_acc loops zero times — leaving the
	# pair_rate pinned at 0.26 despite Stage A.1 of
	# ZOMBIE_PAIR_RATE_ROOT_CAUSE_FIX_PLAN.md. See
	# ZOMBIE_CATALOG_REPLAY_SILENT_FIX_PLAN.md Stage C-2 for the full
	# derivation.
	#
	# Heuristic for "is this a battle_sfx_replay": the catalog-replayed
	# calls come in with `feds.resource_id == 0` (global SFX bank cat 0000)
	# and a sound_id whose high-word category matches (= 0). Timeline-
	# driver calls for the audible primary use the per-effect bank (non-
	# zero resource_id) so they don't trip this branch.
	var is_battle_sfx_replay: bool = false
	if not first_alloc and feds != null and feds.resource_id == 0 \
			and sound_id >= 0 and ((sound_id >> 16) & 0xFFFF) == 0:
		is_battle_sfx_replay = true
	if first_alloc:
		# Seed _entity_catchup + _silent_entities from the sstate-derived
		# entity linked list. cure_4 fires 3 play_feds_pair calls but only
		# the first one creates the entities; later calls re-enter
		# play_feds_pair with `_entity_catchup` already non-null and skip
		# this block, preserving the accumulated cad-by-cad trajectory.
		if not _seed_entities_from_state():
			push_error("EffectPlaySound: no _entity_state_seed available; " +
					"render_effect_sound must set it from --entity-state=<json>")
			return false
	elif is_battle_sfx_replay:
		if not _promote_next_silent_entity():
			push_warning("EffectPlaySound: no spare silent entity for " +
					"battle_sfx replay (sid=0x%x)" % sound_id)
			# Fall through — slot rebind still happens; only the entity-
			# driven catchup will lag (matching pre-fix behavior).

	# Per-voice WAV comparison shows VOICE 21 is the cure-audible voice
	# (continuous 1.03-2.78s, peaks 18000) while VOICE 20 is sparse (only
	# 2 brief KON spikes, 0.1% active). slot N → voice (16+N), so
	# slot 5 = voice 21 (audible).
	# ch0 → slot 4 (= voice 20 = driver), ch1 → slot 5 (= voice 21 =
	# audible w/ D9+D4 LFO).
	var slot_a: _SS = allocated[0]
	var slot_b: _SS = allocated[1]
	# Capture refs for the Layer 2 slot+0x10 transition check in
	# _run_entity_catchup. See _cure_slot_10 doc above.
	_cure_slot_a = slot_a
	_cure_slot_b = slot_b

	# FFT's per_channel_tick dispatcher walks RAM bytes from the channel's
	# offset onwards without a per-channel boundary — a stub channel like
	# cure_4 pair 2 ch A (`D2 08`, no 0x90 EndBar) flows into the next
	# channel's bytecode (channel 5: `BA AC ... 60 C1 90`), so its slot
	# dispatches channel 5's Note. Use `get_channel_events_from` so each
	# slot's events array extends past its own channel until end-of-feds;
	# the 0x90 EndBar handler naturally terminates audible channels. See
	# VOICE_18_KON_NEVER_FIRES.md follow-up.
	var events_a: Array = feds.get_channel_events_from(pair_idx * 2)
	var events_b: Array = feds.get_channel_events_from(pair_idx * 2 + 1)

	_bind_slot(slot_a, events_a, feds.resource_id, sound_id, feds)
	_bind_slot(slot_b, events_b, feds.resource_id, sound_id, feds)

	# Effect-load-time arming. The first Note dispatched on each channel
	# needs its snapshot of channel_word_0 to have bit 0x400 set so it
	# promotes to a primary KON. Pre-arm both channels here.
	# Also OR bits 0x008 + 0x001 to match FFT L80013CD0's hardcoded init
	# value 0x409 (= CHAN0_KON_ARM | 0x009) — bits 0x009 are persistent
	# slot-allocation residue that FFT's Note-handler mask 0xF8FF at
	# L80015394 explicitly preserves across Note dispatches.
	_channels[slot_a.slot_idx].channel_word_0 |= _SS.CHAN0_KON_ARM | 0x009
	_channels[slot_b.slot_idx].channel_word_0 |= _SS.CHAN0_KON_ARM | 0x009
	slot_a.active_word = 1
	slot_b.active_word = 1
	# walker_flag_word `|= 0x1FF` is NOT seeded here. FFT only sets those
	# bits inside the SetInstrument data-loader at PC 0x80017078-
	# 0x80017088 (Hyp_instrument_data_loader). The slot allocator never
	# pre-seeds walker bits. _bind_slot → _prestage_first_instrument
	# instead defers the per-voice 0x1FF arm into walker_seed_pending
	# (gated on ac_before_first_note); flush_tick._process_slot drains
	# it on the first post-anchor FLAG_PRIMARY_KON IRQ. See
	# CAUSE_A_PRESTAGE_TIMING_ISSUE.md.

	# TTL is armed by Note dispatch (in dispatcher.gd _handle_note primary-
	# KON path). Both slots start disabled so inactive slots (e.g. cure's
	# slot_a with empty ch0 = just 0x90 EndBar) never fire TTL-driven
	# events. ttl_sub_ticks is per-channel.
	_channels[slot_a.slot_idx].ttl_sub_ticks = -1
	_channels[slot_b.slot_idx].ttl_sub_ticks = -1

	# diag_slot2_init_state — mirror PCSX's all-slot snapshot at
	# play_sound_callee_12d40 exit. Sign-extend note_duration to s16
	# to match PCSX's `lh` semantics.
	_diag_slot2_init_state_count += 1
	for _diag_slot in range(_pool.POOL_SLOT_COUNT):
		var _ch = _channels[_diag_slot]
		var _cw0: int = 0
		var _nd: int = 0
		if _ch != null:
			_cw0 = _ch.channel_word_0 & 0xFFFF
			var _nd_raw: int = _ch.note_duration & 0xFFFF
			_nd = _nd_raw - 0x10000 if _nd_raw >= 0x8000 else _nd_raw
		_Trace.emit("slot2_init_state", {
			"call_index": _diag_slot2_init_state_count,
			"slot_idx": _diag_slot,
			"chan_word_0": _cw0,
			"note_duration": _nd,
		})

	return true


func _apply_lfo_state_seed(channel: _CH) -> void:
	## Replay savestate-pre-armed LFO state into a freshly-allocated
	## ChannelState — port of §7.1 in VOICE_19_RMS_CHAN_8A_PAN_LFO_DIVERGENCE.md.
	##
	## FFT's per-channel struct (chan_base = effect_entity + 0xB8 + ch_idx*0x160)
	## carries four 0x20-byte LFO sub-slot blocks at chan+0xE0 / +0x100 /
	## +0x120 / +0x140. Each block stores accumulator, step_source,
	## countdown, depth, mode_byte, callback_idx, and active_dir bits —
	## the inputs lfo_handler_tick reads when accumulating chan+0x88 /
	## chan+0x8a every per_channel_tick. PCSX captures the savestate
	## mid-spell with this state already populated (mode-2 step_source
	## on the silent-driver channels), but Godot's ChannelState._init
	## resets it all to zero. After load, even though no opcode in the
	## traced bytecode arms mode-2 pan-LFO on those silent drivers, PCSX
	## still accumulates chan_8a from the savestate-resident sub-slot 2
	## state. Without replaying it here, Godot's chan_8a stays at 0 for
	## three of the four silent-driver/audible channels, producing the
	## 240/592 chan_8a mismatch that drives voice_19.rms_spec_err 0.034.
	##
	## Schema: see research/tools/sstate_entity_extract.py
	## `_PER_CHANNEL_FIELDS` + `_SUBSLOT_BASES`. _entity_state_seed is the
	## JSON dict produced by extract_entity_state.py and assigned via
	## render_effect_sound._apply_entity_state. The effect entity is the
	## one with channel_count > 2; silent-driver-only entities (cc<=2)
	## carry their own per-channel LFO state but Godot doesn't run their
	## bytecode (their dispatchers aren't bound), so we leave that for §7.2.
	if _entity_state_seed == null:
		return
	var ents: Array = _entity_state_seed.get("entities", [])
	var effect_chans: Array = []
	for raw in ents:
		if int((raw as Dictionary).get("channel_count", 0)) > 2:
			effect_chans = (raw as Dictionary).get("channels", [])
			break
	if effect_chans.is_empty():
		return
	var slot_idx: int = channel.channel_idx
	if slot_idx < 0 or slot_idx >= effect_chans.size():
		return
	var raw_chan: Dictionary = effect_chans[slot_idx]
	# chan+0x88 / chan+0x8a — vol / pan LFO accumulator outputs. The per-
	# cadence pre-clear in _advance_lfo wipes these every tick, so seeding
	# matters only for the cad=0 read before the first _advance_lfo runs.
	# Probe-level harmless but symmetrically applied for parity.
	channel.chan_88_value = int(raw_chan.get("chan_88", 0)) & 0xFFFF
	channel.chan_8a_value = int(raw_chan.get("chan_8a", 0)) & 0xFFFF
	# Sub-slot 0 — iter-35: unified onto lfo_sub_*[0] (was flat lfo_*).
	var s0: Dictionary = raw_chan.get("sub_0", {})
	if not s0.is_empty():
		channel.lfo_sub_accumulator[0] = int(s0.get("accumulator", 0))
		channel.lfo_sub_step_source[0] = int(s0.get("step_source", 0))
		var cd_seed0: int = int(s0.get("countdown", 0)) & 0xFFFF
		if cd_seed0 == 0:
			# Match FFT pitch_lfo_period_reset: a zero countdown reads as
			# "fire immediately" via PC 0x80017500 `beq v0, zero, swap`.
			# Godot's _advance_lfo decrements first; 0 → -1 would wrap.
			# Setting to 1 means "fire this tick" symmetric with PCSX.
			cd_seed0 = 1
		channel.lfo_sub_countdown[0] = cd_seed0
		channel.lfo_sub_inner_reload[0] = int(s0.get("inner_reload", 0)) & 0xFFFF
		# FFT play_sound per-channel init at PC 0x80013D5C runs a
		# `sh zero, 0xfe(a1)` loop over all 4 sub-slots, clearing the
		# chan+0xfe halfword (sub_0 active_dir). Silent-driver-only
		# entities bypass that init and retain the savestate's active_dir.
		# The 4cdb32b0 fix applied the same gate to sub-slots 1+;
		# ICE_V21_PITCH_LFO_SUBSLOT_0_SEED_DEFICIT.md covers the residual
		# sub_0 case where ice V21's savestate carries active_dir=3 from
		# a prior 0xD9 dispatch but PCSX's `probe_lfo_subslot0_state`
		# shows runtime active_dir=0 across 231 captures (FFT init
		# cleared it). Audible primaries leave the active flag and
		# dir_flags at channel_state.gd's defaults (0) so the pitch-LFO
		# gate at dispatcher.gd:340 fails — matching FFT.
		if channel.is_silent_driver:
			var active_dir0: int = int(s0.get("active_dir", 0)) & 0xFFFF
			channel.lfo_sub_active[0] = active_dir0 & 0x1
			channel.lfo_sub_dir_flags[0] = active_dir0 & 0xFE
		var cb_idx0: int = int(s0.get("callback_idx", 0xFF)) & 0xFF
		if cb_idx0 != 0xFF:
			channel.lfo_sub_callback_idx[0] = cb_idx0
	# Sub-slots 1, 2, 3 — Godot's per-sub-slot arrays.
	for sub_idx in range(1, _CH.LFO_SUB_SLOT_COUNT):
		var key: String = "sub_%d" % sub_idx
		var ss: Dictionary = raw_chan.get(key, {})
		if ss.is_empty():
			continue
		channel.lfo_sub_accumulator[sub_idx]   = int(ss.get("accumulator", 0))
		channel.lfo_sub_step_current[sub_idx]  = int(ss.get("step_current", 0))
		channel.lfo_sub_step_source[sub_idx]   = int(ss.get("step_source", 0))
		var cd_seed: int = int(ss.get("countdown", 0)) & 0xFFFF
		channel.lfo_sub_countdown[sub_idx]     = cd_seed
		channel.lfo_sub_inner_reload[sub_idx]  = int(ss.get("inner_reload", 0)) & 0xFFFF
		var depth_seed: int = int(ss.get("depth", 0)) & 0xFFFF
		# Preserve the channel_state.gd default depth=256 when the
		# savestate has depth=0 (the slot-allocator pre-init value).
		# A depth of 0 multiplies the contribution to zero via the
		# PC 0x80017534 slti / mult branch.
		if depth_seed != 0:
			channel.lfo_sub_depth[sub_idx] = depth_seed
		var depth_reload: int = int(ss.get("depth_reload", 0)) & 0xFFFF
		if depth_reload != 0:
			channel.lfo_sub_depth_delta[sub_idx] = depth_reload
		var mode_seed: int = int(ss.get("mode", 0)) & 0xFF
		# When the savestate has mode=0 it means "uninitialized" (the
		# default seed in channel_state.gd already covers slot 0/1/2
		# with the correct mode mapping). Only overwrite when the
		# savestate carries an explicit mode value.
		if mode_seed != 0:
			channel.lfo_sub_mode[sub_idx] = mode_seed
		var cb_idx: int = int(ss.get("callback_idx", 0)) & 0xFF
		if cb_idx != 0:
			channel.lfo_sub_callback_idx[sub_idx] = cb_idx
		var active_dir_seed: int = int(ss.get("active_dir", 0)) & 0xFFFF
		# FFT play_sound init at PC 0x80013D5C (`sh zero, 0xfe(a1)` loop)
		# clears chan+0x{xe,11e,13e,15e} (active_dir of all 4 sub-slots)
		# for every channel that goes through the audible-primary bind path
		# (per-channel init loop body, gated on lhu 0x0(s6) at PC 0x80013CB0).
		# Silent-driver-only entities skip this init and retain the savestate
		# sub-slot active_dir — that's the mechanism behind the VOICE_19
		# chan_8a accumulation. probe_lfo_subslot1_state on cure V21 confirms
		# PCSX runtime active_dir=0 throughout (savestate active_dir=3 was
		# overwritten by play_sound init). Mirror that asymmetry: only seed
		# active_dir on silent drivers. Audible primaries get active=0 (the
		# channel_state.gd default), matching FFT's runtime clear. Without
		# this gate, Godot's mode-1 vol LFO on V21 fires from cad 0 onward,
		# ramping chan+0x88 to non-zero values that PCSX never produces —
		# producing the cure_no_music full_mix amplitude oscillation around
		# half PCSX RMS.
		if channel.is_silent_driver:
			channel.lfo_sub_active[sub_idx]    = active_dir_seed & 0x1
			channel.lfo_sub_dir_flags[sub_idx] = active_dir_seed & 0xFE
	# chan_word_0 outer gate. lfo_handler_tick at PC 0x800174D0 skips
	# the channel entirely when chan+0x0 reads zero. The savestate
	# captures channels pre-bind with cw0=0 even on channels whose
	# sub-slot 2 state is populated — when the spell's bytecode runs
	# Note/SetInstrument/etc., it sets cw0 != 0 and lfo_handler_tick
	# starts walking the channel's sub-slots. Mirroring that here
	# means we DON'T pre-seed chan_word_0 — the bytecode's own
	# CHAN0_KON_ARM (set by play_feds_pair after this seeder runs)
	# is sufficient to pass the gate.


func _apply_chan_92_init(channel: _CH, feds: FedsBank, sound_id: int) -> void:
	## chan+0x92 init seed (mirrors FFT FUN_80013B20 PC 0x80013BFC-D2C):
	##     chan_92 = min((0x6000 * feds[data_offset + sound_id]) >> 7, 0x7FFF)
	## sound_id is `a1 & 0xFFFF` at function entry — the resolver-resolved
	## id (id_a/id_b/id_c per channel mode), not the timeline keyframe
	## sid (see CHAN_92_FEDS_VERIFICATION.md Q2). When sound_id is -1
	## (legacy hardcoded play_feds_pair path with no timeline driver),
	## leave channel_state.gd's default (18432, cure_4-shaped) in place.
	if feds == null or sound_id < 0:
		return
	channel.chan_92_value = feds.chan_92_for(sound_id)


func _bind_slot(slot: _SS, events: Array, resource_id: int,
		sound_id: int = -1, feds: FedsBank = null) -> void:
	var dispatcher := _Dispatcher.new()
	dispatcher.bind(events, _waveset)
	_dispatchers[slot.slot_idx] = dispatcher

	var channel := SharedChannelState.new(slot.slot_idx, _pool.voice_for_slot(slot.slot_idx))
	channel.opcode_pos = 0
	# Mirror FFT play_sound init order: L80013CB0-CD0 writes 0x409 (=
	# CHAN0_KON_ARM | CHAN0_HAS_TONES | 0x001) to chan_word_0 BEFORE the
	# jal Hyp_instrument_data_loader at 0x80013D80. That init is what
	# arms the `(chan_word_0 & 0xC) != 0` gate at PC 0x80017064. Without
	# the HAS_TONES set pre-prestage, Godot's gate reads chan_word_0=0
	# on every bind (fresh ChannelState) and the immediate-arm path in
	# _prestage_first_instrument never fires. The CHAN0_KON_ARM / 0x001
	# portion of 0x409 stays at play_feds_pair line 476-477 (post-bind).
	# See CURE_4_V18_WALKER_MISS_AT_CAD_495_INVESTIGATION.md.
	channel.channel_word_0 |= _SS.CHAN0_HAS_TONES
	_apply_chan_92_init(channel, feds, sound_id)
	# Replay savestate-resident LFO state. Must run BEFORE the per-channel
	# bytecode dispatches its first opcode (which can re-arm sub-slot
	# state through 0xE5/0xED handlers), so the seed represents FFT's
	# pre-savestate-load condition.
	_apply_lfo_state_seed(channel)
	# Allocator-default baseline byte (chan+0x7E ≡ FFT's octave baseline).
	# diag_spu_pitch_writer.jsonl shows FFT's slot-bind path issues a
	# pre-anchor SPU pitch register write via FUN_800144D0 → FUN_8001B628
	# (= spu_write_voice_pitch) for voice 18 with value=4078, before any
	# cure_4 opcode dispatches. PitchTable.note_to_pitch(60, inst[1]
	# .fine_tune=-19) = 4078 bit-exact — the FFT-side pre-stage is
	# equivalent to baseline byte 60 (= octave 5, middle C) feeding the
	# formula path. Set the baseline for EVERY slot at bind time so the
	# first Note-formula evaluation produces the right pitch regardless
	# of dispatch order: Note-before-Octave channels (cure_4 v18) keep
	# baseline=60 and Octave-before-Note channels (cure_no_music v20,
	# cure_4 v19/20/21) overwrite it when their Octave opcode dispatches.
	# See CURE_4_CH2_VOICE_18_PITCH_DEFAULT_INVESTIGATION.md §5 option
	# (iii); mechanism confirmed by diag_spu_pitch_writer.lua (hyp B).
	channel.bmidi_baseline_byte = 60
	_channels[slot.slot_idx] = channel

	# resource_id << 16 = SPU VRAM bank base. This translates to an
	# instrument_idx into the loaded waveset; for first-pass we leave
	# instrument_idx = 0 (the default audition path) and let the
	# dispatcher's Instrument opcode (0xAC) override at runtime.
	slot.instrument_idx = 0

	# Pre-stage instrument data from the FIRST 0xAC opcode in the
	# bytecode. FFT's slot allocator path implicitly loads instrument
	# state at slot binding (the Hyp_instrument_data_loader at PC
	# 0x80017078-88 fires off the slot-allocator chain — see
	# VOICE_18_KON_NEVER_FIRES.md). Without this, channels whose
	# bytecode runs Notes BEFORE their 0xAC dispatch (e.g. cure_4 pair 1
	# ch A: B4 3F C2 32 E0 23 E2 78 00 60 0C ... AC 0F) KON the SPU
	# voice with slot.sample_start_addr=0, silencing the voice. Mirror
	# the dispatcher's 0xAC handler effect now so KON sees real sample
	# addresses on the first walker pass.
	_prestage_first_instrument(channel, slot, events)


func _prestage_first_instrument(channel: _CH, slot: _SS, events: Array) -> void:
	# Locate first 0xAC and first Note in dispatch order. Edit A's
	# ac_before_first_note gate (CAUSE_A_PRESTAGE_TIMING_ISSUE.md §3.1):
	# the walker bit-set is only PCSX-faithful for voices whose AC
	# dispatches before their first Note. Voice 18 on cure_4 has Note
	# before AC, and PCSX never fires walker_flag_word=0x1FF on v18's
	# first walker pass — the over-arm here was the +1 cad=1 v18 entry
	# in the cure_4 cluster delta. Instrument-data staging (channel/
	# slot fields) still runs unconditionally so the slot has correct
	# sample addresses regardless of dispatch order.
	#
	# Edit B's allocator-default branch (CURE_4_CH2_DEFAULT_INSTRUMENT_INVESTIGATION.md
	# §5 option iii / hypothesis B): when ac_before_first_note is false,
	# Godot used to pre-load the bytecode's LATER AC operand. That's wrong —
	# PCSX's first KEYON for such a voice uses the FFT slot allocator's
	# default seed, not the AC the bytecode dispatches later. FFT's
	# allocator sets slot.instrument_idx = 0, and Hyp_instrument_data_loader
	# resolves that to WAVESET inst[1] via the +1 indexing rule (mirrors
	# dispatcher.gd:1338-1341 `_op_instrument`). cure_4 voice 18 is the
	# canonical case: bytecode is `Noise C2_decay Dynamics Expression
	# Note×5 Coda 0xB7 Instrument(0F) Octave Release Note EndBar`, and
	# PCSX's voice 18 first KEYON matches inst[1] (start=4112, loop=48,
	# adsr2=0x5FC6) — not inst[16] from the later AC 0F.
	var first_ac: SMDOpcodes.OpcodeEvent = null
	var first_ac_idx: int = -1
	var first_note_idx: int = -1
	for i in range(events.size()):
		var evt = events[i]
		if evt is SMDOpcodes.OpcodeEvent and (evt as SMDOpcodes.OpcodeEvent).opcode == 0xAC:
			if first_ac == null:
				first_ac = evt as SMDOpcodes.OpcodeEvent
				first_ac_idx = i
		elif evt is SMDOpcodes.NoteEvent and first_note_idx == -1:
			first_note_idx = i
	if _waveset == null:
		return
	var ac_before_first_note: bool = \
			first_ac != null and (first_note_idx == -1 or first_ac_idx < first_note_idx)
	# Post-anchor immediate-arm path. PCSX's Hyp_instrument_data_loader runs at
	# play_sound time with slot.inst_idx still at the slot-allocator default
	# (=0 → waveset[1]); the bytecode's later AC opcode dispatches at runtime
	# and triggers a SECOND walker arm via _op_instrument. Pre-anchor binds
	# can peek at the first AC because Godot's deferred walker_seed_pending
	# only drains at the first post-anchor FLAG_PRIMARY_KON — by which time
	# any AC opcode before that Note has already dispatched in PCSX too.
	# Post-anchor immediate binds (e.g. cure_4 third play_sound at cad 495)
	# MUST stage waveset[1] so the cad-N walker write matches PCSX's cad-N
	# walker write; the cad-N+3 walker write from _op_instrument then matches
	# PCSX's cad-N+3 walker write. See CURE_4_V18_WALKER_MISS_AT_CAD_495_
	# INVESTIGATION.md §4 / probe_sample_start_addr_register row diffs.
	var is_post_anchor_immediate: bool = \
			_Trace._post_anchor and (channel.channel_word_0 & 0x000C) != 0
	var idx: int
	var prestage_source: String
	if is_post_anchor_immediate:
		if first_note_idx == -1:
			return
		idx = 1
		prestage_source = "post_anchor_immediate"
	elif ac_before_first_note:
		var idx_runtime: int = first_ac.params[0] if first_ac.params.size() > 0 else 0
		idx = idx_runtime + 1
		prestage_source = "ac_before_note"
	else:
		# Allocator-default path. Skip staging entirely when there are no
		# Notes either — nothing will KEY on, so leave the slot zeroed
		# (preserves the prior early-return semantics for empty/EndBar-only
		# channels like cure_no_music slot_a).
		if first_note_idx == -1:
			return
		# WAVESET index 1 (= runtime instrument_idx 0 + 1). All FFT effects
		# observed so far share this allocator default; if a future effect
		# shows a different default, capture the relevant slot field at
		# Hyp_slot_allocator entry via diag_slot_allocator.lua (see
		# CURE_4_CH2_DEFAULT_INSTRUMENT_INVESTIGATION.md §4).
		idx = 1
		prestage_source = "allocator_default"
	if idx >= _waveset.instruments.size():
		return
	var inst: WavesetParser.Instrument = _waveset.instruments[idx]
	if inst.is_null:
		return
	_probe_prestage_first_instrument_count += 1
	_Trace.emit("prestage_first_instrument", {
		"call_index": _probe_prestage_first_instrument_count,
		"slot_idx": slot.slot_idx,
		"voice": _pool.voice_for_slot(slot.slot_idx),
		"idx": idx,
		"source": prestage_source,
		"first_ac_param": (first_ac.params[0] \
				if (first_ac != null and first_ac.params.size() > 0) else -1),
		"first_ac_idx": first_ac_idx,
		"first_note_idx": first_note_idx,
	})
	# Channel-side stage (mirror dispatcher.gd:1256-1275).
	channel.instrument_idx = idx
	channel.fine_tune = inst.fine_tune
	channel.adsr1 = inst.adsr1
	channel.adsr2 = inst.adsr2
	channel.sample_start_addr = Spu.RAM_INSTRUMENT_BASE \
			+ inst.sample_offset + inst.start_offset_bytes
	channel.sample_loop_addr = inst.sample_offset + inst.sample_size
	# Slot-side stage (mirror dispatcher.gd:1276-1289). play_feds_pair is
	# only used for audible primaries (voice_writes always true).
	slot.instrument_idx = idx
	slot.fine_tune = inst.fine_tune
	slot.adsr1 = inst.adsr1
	slot.adsr2 = inst.adsr2
	slot.prev_adsr2 = slot.adsr2
	slot.adsr_opcode_modified = false
	slot.sample_start_addr = channel.sample_start_addr
	slot.sample_loop_addr = channel.sample_loop_addr
	# Walker re-arm + chan_word_1 bits — mirrors dispatcher.gd:1308-1310.
	# The dispatcher gates this on (channel_word_0 & 0xC) != 0; the
	# caller in play_feds_pair sets bit 0x008 immediately after
	# _bind_slot returns (line 224-225), so this would always pass.
	# channel_word_1 |= 0x300 stays unconditional so vol/pitch staging
	# drain at next IRQ.
	channel.channel_word_1 |= 0x300
	# Mirror FFT Hyp_instrument_data_loader PC 0x80017064-0x80017088:
	#   PC 0x80017064  andi v0, v1, 0xc           ; chan_word_0 & 0xC
	#   PC 0x80017068  beq  v0, zero, skip
	#   PC 0x80017070  lhu  v0, 0x2(a1)           ; slot.flag_word
	#   PC 0x80017074  lhu  v1, 0x4(a1)           ; slot.walker_flag_word
	#   PC 0x80017078  ori  v0, v0, 0x300         ; flag_word |= 0x300
	#   PC 0x8001707C  ori  v1, v1, 0x1ff         ; walker_flag_word |= 0x1FF
	#   PC 0x80017080  sh   v0, 0x2(a1)
	#   PC 0x80017088  _sh  v1, 0x4(a1)
	# PCSX arms IMMEDIATELY on every play_sound. Pre-anchor (FIRST_OPCODE_
	# FIRED hasn't latched yet) those writes land in spu_initial_state.json
	# residue instead of the capture WAV; Godot mirrors that by reading the
	# residue and skipping pre-anchor walker arms via walker_seed_pending.
	# Post-anchor (e.g. cure_4's third play_sound at cad 494/495, the
	# animate_tick fire of cure_4 itself), the arm MUST fire immediately —
	# otherwise the cad-495 walker fan-out collapses into the later cad-498
	# note-KON walker pass and voices 18+19 miss the second-note instrument
	# re-init writes. See CURE_4_V18_WALKER_MISS_AT_CAD_495_INVESTIGATION.md.
	if is_post_anchor_immediate:
		slot.walker_flag_word |= 0x1FF
		slot.flag_word |= _SS.FLAG_PRIMARY_KON | _SS.FLAG_SECONDARY_KON
	elif ac_before_first_note:
		# Pre-anchor AC-before-Note: defer the full 0x1FF arm to the
		# first post-anchor FLAG_PRIMARY_KON. flush_tick._process_slot
		# consumes walker_seed_pending. See CAUSE_A_PRESTAGE_TIMING_
		# ISSUE.md §5 option (a-revised).
		slot.walker_seed_pending = true
	else:
		# Pre-anchor Note-before-AC: PCSX's FFT engine still arms a
		# SUBSET of the walker bits via the instrument-loader's residue
		# pass — specifically WALKER_FLAG_ADSR1_HIGH (0x10). Without
		# this arm, voice 18 on cure_4 misses its first ADSR1_HIGH
		# walker fan-out → first KEYON sees adsr1=0x00FF instead of
		# 0x32FF. The narrow arm avoids the 9-fan-out regression the
		# original `if ac_before_first_note:` gate was guarding against.
		# See VOICE_18_ADSR1_HIGH_PREARM_PATCH.md.
		slot.walker_seed_pending_narrow = true


func get_dispatcher(slot_idx: int) -> _Dispatcher:
	if slot_idx < 0 or slot_idx >= _dispatchers.size():
		return null
	return _dispatchers[slot_idx]


func tick_irq_start(current_sub_tick: int = 0) -> void:
	## Instance shim — see tick_irq_start_for_runtime below for body.
	## Routes the instance's `_diag_mixer` into the shared static so
	## legacy SFX-only callers (if any remain) keep working.
	tick_irq_start_for_runtime(_diag_mixer, current_sub_tick)


static func tick_irq_start_for_runtime(mixer: Spu,
		current_sub_tick: int = 0) -> void:
	## IRQ-start phase of the per-sub_tick driver. Bumps the cadence
	## counter and emits cadence_source / cadence_wallclock /
	## diag_envelope_tail so that walker.tick (which runs AFTER this
	## inside render_effect_sound.gd) reads the just-bumped
	## `_Trace._cadence_index`. Mirrors PCSX FUN_800149DC's prolog
	## firing BEFORE `jal async_commit_walker` at 0x800149F0. See
	## WALKER_TICK_PRE_CADENCE_BUMP_DEFICIT.md §8.
	##
	## Pass 10.A — static so Runtime can fire it for music + SFX
	## uniformly. `mixer` is optional; when null the envelope_tail /
	## noise_* emits are skipped (caller didn't wire a mixer).
	##
	## Invariant: the anchor latch zeroes `_cadence_index` at end of
	## sub_tick K → next sub_tick's tick_irq_start bumps to 1.
	# Clock 1 pulse: bump first so any Clock 2 event (including walker
	# fan-out emits between this call and rt.tick) gets stamped with
	# the right cadence_index by _Trace.emit's auto-injection.
	_probe_cadence_source_count += 1
	_Trace._cadence_index = _probe_cadence_source_count
	# Pre-anchor pulses (before first event_dispatch fires) are not
	# emitted — mirrors PCSX's probe_cadence_source FIRST_OPCODE_FIRED
	# gate. Once the dispatcher's first-fire reset has run AND our local
	# count has been zeroed (one tick later via check_anchor_latch_for_
	# runtime), cadence_source emits at cadence_index=1,2,... matching
	# PCSX's post-anchor stream.
	if _cadence_anchored:
		_Trace.emit("cadence_source", {
			"call_index": _probe_cadence_source_count,
			"cadence_index": _probe_cadence_source_count,
		})
		# diag_cadence_wallclock — Godot half of the PCSX
		# diag_cadence_wallclock.lua probe. samples_per_sub = 183
		# (44100 / 30 / 8 integer div). `current_sub_tick` is abs_sub,
		# the index of THIS sub-tick — so samples already emitted
		# before it = abs_sub*183.
		_diag_cadence_wallclock_count += 1
		_Trace.emit("cadence_wallclock", {
			"call_index": _diag_cadence_wallclock_count,
			"cadence_index": _probe_cadence_source_count,
			"sub_tick": current_sub_tick,
			"godot_sample_count": current_sub_tick * 183,
		})
		# diag_envelope_tail — per-voice env_state/env_vol/raw_pitch/L+R
		# vol snapshot. Cadence-aligned with PCSX (BP @ RCnt2 IRQ entry).
		# Tail filter (on || env_vol > 0) matches the PCSX side. See
		# PROTECT_NO_MUSIC_AUDIBLE_GAP_RESOLUTION.md §8.1.1.
		if mixer != null:
			_emit_envelope_tail_for_runtime(mixer, current_sub_tick)
			_emit_noise_clock_change_for_runtime(mixer)
			_emit_noise_status_change_for_runtime(mixer)


func check_anchor_latch() -> void:
	## Instance shim — see check_anchor_latch_for_runtime below for body.
	check_anchor_latch_for_runtime(_flush_tick)


static func check_anchor_latch_for_runtime(flush_tick: _FlushTick) -> void:
	## Cadence anchor latch — runs once when the dispatcher's first-fire
	## flag flips. Must run BEFORE the per-IRQ KON/KOFF commits so the
	## first post-anchor keyon emit (keyon_per_voice, kon_koff_mask,
	## kon_koff_accumulator, *_register) lands under post_anchor=true.
	## Without this ordering, the initial play_feds_pair pre-seeded
	## FLAG_PRIMARY_KON gets flushed before the latch flips, the SPU
	## key_on still fires, but the probe trace loses one row per audible
	## voice (e.g. reraise: v18/v19/v20/v21 each lose their cad=0
	## keyon_per_voice emit).
	##
	## Pass 10.A — static so Runtime fires it once per IRQ for music
	## OR SFX entities (the SFX-only loop is gone). The flush_tick arg
	## is the same shared instance Runtime holds in `_flush_tick`.
	##
	## Idempotent — guarded by `not _cadence_anchored`.
	if _Trace._first_dispatch_fired and not _cadence_anchored:
		_cadence_anchored = true
		_probe_cadence_source_count = 0
		_Trace._cadence_index = 0
		_Trace._post_anchor = true
		# §9.2 — drop any pre-anchor KON bits that already rotated into
		# the deferred buffer (e.g. play_feds_pair's seed arming) so the
		# first post-anchor commit only carries post-anchor Note arming.
		# See KEYON_COMMIT_DEFERRAL_PROBE_DEFICIT.md §9.2.
		if flush_tick != null:
			flush_tick.clear_deferred_kon()


static func _emit_envelope_tail_for_runtime(mixer: Spu,
		current_sub_tick: int) -> void:
	## Per-cadence envelope sample for diag_envelope_tail (paired with
	## PCSX diag_envelope_tail.lua). Iterates all 24 SPU voices; emits one
	## row per voice that is currently audible (on==true OR env_vol>0 so
	## the release tail is captured too). Schema matches the PCSX side so
	## a future diff_envelope_tail.py can pair row-by-row.
	if mixer == null:
		return
	# samples_per_sub = 44100 / 30 / 8 = 183 (matches render_effect_sound.gd's
	# integer-div constant). Same value cadence_wallclock uses for its
	# godot_sample_count field. Reported here under the PCSX-compatible
	# name `spu_sample` so the future diff script can zip rows by name.
	var spu_sample: int = current_sub_tick * 183
	for v in range(24):
		var info: Dictionary = mixer.get_voice_debug_info(v)
		if info.is_empty():
			continue
		var on_val: bool = bool(info.get("on", false))
		# Emit env_vol_raw (un-shifted internal envelope, 0..32767 scale)
		# instead of env_vol (which is raw >> kOutputShift = raw >> 5, max
		# ~1023). PCSX's PCSX.SPU.getVoiceInfo.envelopeVol is already on
		# the 0..32767 scale (clamped by adsr.cc:86), so reading env_vol_raw
		# here gives apples-to-apples comparison without rescaling in the
		# diff script. See PROTECT_NO_MUSIC_AUDIBLE_GAP_RESOLUTION.md §8.1.1
		# follow-up: the first capture run with env_vol exposed the 32x
		# scale mismatch that made the threshold-crossing summary useless.
		var env_vol: int = int(info.get("env_vol_raw", info.get("env_vol", 0)))
		if not on_val and env_vol <= 0:
			continue
		_diag_envelope_tail_count += 1
		_Trace.emit("envelope_tail", {
			"call_index": _diag_envelope_tail_count,
			"cadence_index": _probe_cadence_source_count,
			"voice": v,
			"spu_sample": spu_sample,
			"on": on_val,
			"stop": bool(info.get("stop", false)),
			"adsr_state": int(info.get("env_state", 0)),
			"env_vol": env_vol,
			"raw_pitch": int(info.get("raw_pitch", 0)),
			"left_volume": int(info.get("left_volume", 0)),
			"right_volume": int(info.get("right_volume", 0)),
			"noise": bool(info.get("noise_on", false)),
			"fmod": int(info.get("fmod", 0)),
			"noise_clock": int(info.get("noise_clock", 0)),
			# Bisect-only diag fields (PCSX side ignores; safe to add). Used
			# by VOICE_20_ENV_VOL_DECAY_SUSTAIN_DIVERGENCE.md investigation.
			"sustain_level": int(info.get("sustain_level", -1)),
			"decay_rate": int(info.get("decay_rate", -1)),
			# MUSIC_ITER59: full per-voice ADSR register-state pair for
			# voices 13/14 env_vol root-cause attribution. Schema matches
			# PCSX probe_envelope_tail.lua extension.
			"attack_rate": int(info.get("attack_rate", -1)),
			"attack_mode_exp": int(info.get("attack_mode_exp", -1)),
			"sustain_rate": int(info.get("sustain_rate", -1)),
			"sustain_mode_exp": int(info.get("sustain_mode_exp", -1)),
			"sustain_increase": int(info.get("sustain_increase", -1)),
			"release_rate": int(info.get("release_rate", -1)),
			"release_mode_exp": int(info.get("release_mode_exp", -1)),
			"adsr1": int(info.get("adsr1", -1)),
			"adsr2": int(info.get("adsr2", -1)),
		})


static func _emit_noise_clock_change_for_runtime(mixer: Spu) -> void:
	## probe_noise_clock — Godot half. Mirrors PCSX
	## probe_noise_clock.lua: read the mixer's global noise_clock (=
	## SPU NoiseShift|NoiseStep, range 0..63) and emit a row only on
	## transition. Read via get_voice_debug_info(0)["noise_clock"]
	## (same global value for any voice index).
	if mixer == null:
		return
	var info: Dictionary = mixer.get_voice_debug_info(0)
	if info.is_empty():
		return
	var clk: int = int(info.get("noise_clock", 0))
	if clk == _probe_noise_clock_last:
		return
	_probe_noise_clock_last = clk
	_probe_noise_clock_count += 1
	_Trace.emit("noise_clock", {
		"call_index": _probe_noise_clock_count,
		"cadence_index": _probe_cadence_source_count,
		"noise_clock": clk,
	})


static func _emit_noise_status_change_for_runtime(mixer: Spu) -> void:
	## probe_noise_status — Godot half. Mirrors PCSX
	## probe_noise_status.lua: for each voice, read noise_on; emit a
	## row only when the per-voice bit toggles. Pre-allocates the
	## change-tracker array on first call so all 24 voices have a -1
	## sentinel that triggers an initial emit when set.
	if mixer == null:
		return
	if _probe_noise_status_last.size() != 24:
		_probe_noise_status_last.resize(24)
		for i in range(24):
			_probe_noise_status_last[i] = -1
	for v in range(24):
		var info: Dictionary = mixer.get_voice_debug_info(v)
		if info.is_empty():
			continue
		var n: int = 1 if bool(info.get("noise_on", false)) else 0
		if n == _probe_noise_status_last[v]:
			continue
		_probe_noise_status_last[v] = n
		_probe_noise_status_count += 1
		_Trace.emit("noise_status", {
			"call_index": _probe_noise_status_count,
			"cadence_index": _probe_cadence_source_count,
			"voice": v,
			"noise": (n == 1),
		})


func _emit_vol_formula_stage(slot: _SS, stage: String, value: int) -> void:
	## Mirror PCSX probe_vol_formula_stages.lua. Four rows per drain pass
	## per active channel, tagged with the stage name + value (signed
	## intermediate accumulator). slot_2b is read from slot.instrument_idx
	## (= chan+0x2B in FFT; instrument index byte the PCSX probe captures
	## as a voice-identity hint). No anchor gate: PCSX probe gates only on
	## FIRST_OPCODE_FIRED, and this helper fires downstream of event_dispatch
	## from _drain_prestage_all_slots — sibling probes (vol_inputs,
	## vol_lr_staging, vol_register) at the same call site emit without an
	## anchor gate and pair with PCSX.
	_probe_vol_formula_stages_count += 1
	_Trace.emit("vol_formula_stage", {
		"call_index": _probe_vol_formula_stages_count,
		"stage": stage,
		"value": value,
		"slot_2b": slot.instrument_idx & 0xFF,
	})


func _emit_pitch_formula_stage(slot: _SS, stage: String, value: int) -> void:
	## Mirror PCSX probe_pitch_formula_stages.lua. Five rows per pitch-
	## prestage iteration per active channel, tagged with the stage name +
	## value. Stages and their value semantics (matching the PCSX side):
	##   pitch_base   = s16 (chan+0x82 high half of pre_pitch_acc)
	##   pitch_bend   = u16 (chan+0x88, FFT `lhu`)
	##   pool_a2      = s16 (pool+0xa2 global bias; 0 for cure/reraise)
	##   midi_sum     = s32 (base + bend + pool_a2, pre-sll/sra)
	##   pitch_result = u16 (final masked pitch 0..0x3FFF)
	## slot_2b mirrors the vol-formula stage convention.
	## No anchor gate — see _emit_vol_formula_stage's note.
	_probe_pitch_formula_stages_count += 1
	_Trace.emit("pitch_formula_stage", {
		"call_index": _probe_pitch_formula_stages_count,
		"stage": stage,
		"value": value,
		"slot_2b": slot.instrument_idx & 0xFF,
	})


func _run_entity_catchup() -> bool:
	## Drive the entity-level catch-up FIRST, mirroring FFT's
	## outer_loop × per_slot × sub_loop structure at LAB_80014ccc. When
	## the catch-up fires N times in one IRQ, every channel runs
	## cadence_body N times before any per-IRQ work below. Returns
	## `cadence_fired_this_irq`: true iff the catch-up fired ≥ 1 time.
	## Bounded retry (_safety = 8; FFT itself has no explicit bound but
	## in practice fires at most a handful per IRQ).
	var cadence_fired_this_irq: bool = false
	if _entity_catchup != null:
		# Per-entity iteration: matches FFT's spu_updater_tick walk of
		# DAT_80032a50's linked list. PCSX cure_no_music order:
		# silent[0] (head) → silent[1] → cure (end). Per IRQ:
		#   - per_entity_iter fires for EVERY entity (PC 0x80014BBC entry).
		#   - per_entity_pass fires only when slot+0x10 < 0 lets the bgez
		#     at PC 0x80014BC4 fall through. Silent entities have positive
		#     slot+0x10 → no per_entity_pass. Cure entity has no slot+0x10
		#     model yet so it emits unconditionally — Layer 2 will still
		#     FAIL on cure (1680 vs 519), but Layer 1 should now PAIR.
		# Gated on _cadence_anchored to mirror PCSX's FIRST_OPCODE_FIRED.
		# See DRAIN_RATE_INVESTIGATION.md §12.
		# Counters increment only when emit fires so call_index 1 maps to
		# PCSX's call_index 1 (PCSX increments inside the FIRST_OPCODE_FIRED
		# gate). Without this, Godot's pre-anchor iterations bump the
		# counter and the validator's call_index zip mismatches.
		if _cadence_anchored:
			for _silent in _silent_entities:
				_probe_per_entity_iter_count += 1
				_Trace.emit("per_entity_iter", {
					"call_index": _probe_per_entity_iter_count,
					"chan_base": 0,
					"slot_10_pre": 1,  # positive = silent (gate skipped)
				})
			# Cure entity (linked-list tail). per_entity_iter always emits
			# (PCSX BP at 0x80014BBC fires before the gate). per_entity_pass
			# emits only when slot+0x10 < 0 (PCSX BP at 0x80014BCC is in
			# the bgez fall-through path).
			_probe_per_entity_iter_count += 1
			_Trace.emit("per_entity_iter", {
				"call_index": _probe_per_entity_iter_count,
				"chan_base": 0,
				"slot_10_pre": _cure_slot_10,
			})
			if _cure_slot_10 < 0:
				_probe_per_entity_pass_count += 1
				_Trace.emit("per_entity_pass", {
					"call_index": _probe_per_entity_pass_count,
					"chan_base": 0,
					"slot_10_pre": _cure_slot_10,
				})
		# Per-entity work block — gated on slot+0x10 < 0 to mirror FFT's
		# bgez at PC 0x80014BC4. When the gate is positive (cure ended),
		# skip apply_outer_decrement, the entity_acc catchup loop, and
		# all per-channel cadence_body calls. cadence_fired_this_irq stays
		# false → drain doesn't fire downstream → matches FFT's "entire
		# block skipped" behavior. See DRAIN_RATE_INVESTIGATION.md §13.
		if _cure_slot_10 < 0:
			# Capture entity_acc + budget BEFORE the outer decrement so we
			# can emit the "outer" diag row with values matching PCSX BP @
			# 0x80014CB8 (which captures v0 = entity_acc loaded from
			# slot+0x74 pre-`subu v0, v0, a1`, and a1 = entity_budget).
			var _diag_entity_acc_pre_outer: int = _entity_catchup.entity_acc
			var _diag_entity_budget: int = _entity_catchup.entity_budget
			_entity_catchup.apply_outer_decrement()
			if _cadence_anchored:
				_diag_entity_catchup_iter_count += 1
				_Trace.emit("entity_catchup_iter", {
					"call_index": _diag_entity_catchup_iter_count,
					"phase": "outer",
					"entity_acc_pre": _diag_entity_acc_pre_outer,
					"entity_budget": _diag_entity_budget,
					"cure_slot_10": _cure_slot_10,
				})
			var _safety: int = 8
			while _entity_catchup.entity_acc < 0 and _safety > 0:
				cadence_fired_this_irq = true
				var _diag_entity_acc_pre: int = _entity_catchup.entity_acc
				# probe_spu_slot_loop (Layer 3 paired). PCSX BP at PC
				# 0x80014CCC = LAB_80014CCC fires once per entity-loop
				# sub-iteration. PCSX cure: 207.
				if _cadence_anchored and _Trace.is_enabled():
					_probe_spu_slot_loop_count += 1
					_Trace.emit("spu_slot_loop", {
						"call_index": _probe_spu_slot_loop_count,
					})
				# fire cadence_body for ALL primary channels (FFT per_channel_tick × 8)
				for slot_idx in range(_pool.POOL_SLOT_COUNT):
					var ch_b = _channels[slot_idx]
					# probe_per_channel_tick_entry — paired with PCSX BP @
					# PC 0x80015198. FFT iterates all 8 chan struct
					# positions per per_channel_tick call regardless of
					# which are active.
					if _cadence_anchored and _Trace.is_enabled():
						_probe_per_channel_tick_entry_count += 1
						var _pct_cw0: int = 0
						var _pct_nd: int = 0
						var _pct_idle: int = 0
						if ch_b != null:
							_pct_cw0 = ch_b.channel_word_0 & 0xFFFF
							var _nd_raw: int = ch_b.note_duration & 0xFFFF
							_pct_nd = _nd_raw - 0x10000 if _nd_raw >= 0x8000 else _nd_raw
							_pct_idle = ch_b.idle_timeout & 0xFFFF
						_Trace.emit("per_channel_tick_entry", {
							"call_index": _probe_per_channel_tick_entry_count,
							"chan_word_0": _pct_cw0,
							"note_duration": _pct_nd,
							"chan_78": _pct_idle,
						})
					if ch_b == null:
						if _cadence_anchored and _Trace.is_enabled():
							_Dispatcher.emit_smd_interpreter_inactive(slot_idx)
							_Dispatcher.emit_lfo_handler_inactive(slot_idx, _slot_residue.get(slot_idx, {}))
						continue
					var slot_b := _pool.get_slot(slot_idx)
					if slot_b == null:
						if _cadence_anchored and _Trace.is_enabled():
							_Dispatcher.emit_smd_interpreter_inactive(slot_idx)
							_Dispatcher.emit_lfo_handler_inactive(slot_idx, _slot_residue.get(slot_idx, {}))
						continue
					(_dispatchers[slot_idx] as _Dispatcher).cadence_body(ch_b, slot_b)
					# FFT FUN_80017118 walker fires INSIDE the entity catchup
					# sub-loop iteration. Per-slot KON arms set by cadence_body
					# must accumulate into the IRQ's pending_kon buffer before
					# the post-loop KOFF flush.
					if _flush_tick != null:
						_flush_tick.flush_kon_only_for_slot(slot_b)
				# silent-driver overlays — share the entity catch-up cadence.
				for binding_b in _extra_bindings:
					if not binding_b.started:
						continue
					var b_slot := _pool.get_slot(binding_b.target_slot_idx)
					if b_slot == null:
						continue
					(binding_b.dispatcher as _Dispatcher).cadence_body(binding_b.channel, b_slot)
					if _flush_tick != null:
						_flush_tick.flush_kon_only_for_slot(b_slot)
				_entity_catchup.apply_sub_loop_fire()
				if _cadence_anchored:
					_diag_entity_catchup_iter_count += 1
					# Mirrors PCSX BP @ 0x80014CCC (LAB_80014ccc — sub-loop
					# body entry). entity_acc_current matches slot+0x74 read
					# at that BP site (post-prior-iter sw at 0x80014CE8 or
					# post-outer-decrement sw at 0x80014CC0).
					_Trace.emit("entity_catchup_iter", {
						"call_index": _diag_entity_catchup_iter_count,
						"phase": "inner",
						"entity_acc_current": _diag_entity_acc_pre,
						"entity_acc_post": _entity_catchup.entity_acc,
						"cure_slot_10": _cure_slot_10,
						"safety": _safety,
					})
				_safety -= 1
		# Layer 2 slot+0x10 transition. FFT clears bit 15 of slot+0x10 in
		# the SAME IRQ that endbar fires with no active loop on a channel:
		# the no-loop endbar handler zeroes slot+0x58, then later in the
		# IRQ spu_updater_tick reaches LAB_80014D70 → slot+0x58==0 →
		# LAB_80014DD0 → andi 0x7fff (PC 0x80014DD8). For cure, both
		# channels' endbars at cadence 519 trigger this. The endbar handler
		# in dispatcher.gd is the only writer that clears
		# `slot.active_word & 0x1` (initialized to 1 at allocation), so
		# both cure slots having `active_word & 0x1 == 0` is the unique
		# end-of-cure signal. Match FFT's andi 0x7fff: cleared bit 15
		# leaves 0x8002 → 0x0002 (= 2). See DRAIN_RATE_INVESTIGATION.md §13.
		# Flip _cure_slot_10 positive (= "cure entity dormant", kills
		# per-channel ticks) only when EVERY allocated pool slot has hit
		# EndBar / cleared active_word. The original check looked at
		# _cure_slot_a/b only — the slots from the LAST play_feds_pair
		# call. For single-sound effects (cure_no_music) those are the
		# only slots, so it was fine. For multi-sound effects (cure_4)
		# the last-allocated pair is often a short bytecode that
		# finishes long before the longer-running pair on slots 4+5
		# — flipping _cure_slot_10 early killed slot 4's Repeat-4 loop
		# mid-iteration (see SMD_REPEAT_CODA_BUG.md). Replace the
		# narrow check with a scan of all currently-busy slots.
		if _cure_slot_10 < 0:
			var all_allocated_done: bool = true
			for slot_i in range(_pool.POOL_SLOT_COUNT):
				if _pool.is_free(slot_i):
					continue
				var sl: _SS = _pool.get_slot(slot_i)
				if sl != null and (sl.active_word & 0x1) != 0:
					all_allocated_done = false
					break
			# Defensive: require at least one slot to have been
			# allocated (otherwise the gate would flip immediately at
			# cad 0 before any sound starts, which would silence the
			# entire render).
			var any_allocated: bool = false
			for slot_i in range(_pool.POOL_SLOT_COUNT):
				if not _pool.is_free(slot_i):
					any_allocated = true
					break
			if all_allocated_done and any_allocated:
				_cure_slot_10 = _cure_slot_10 & 0x7FFF  # andi 0x7fff
				# Pass 8 phase 6 — DO NOT unlink the entity from
				# SharedEntityList here. Legacy `_run_entity_catchup`
				# keeps emitting per_entity_iter / per_entity_pass probes
				# every IRQ post-spell (gated only on _cadence_anchored,
				# not on _cure_slot_10). The actual catchup body work +
				# slot_10 transition + drainer are skipped via the
				# _cure_slot_10 < 0 gate INSIDE this function. Unlinking
				# under unified mode would make Runtime stop calling
				# _run_entity_catchup entirely, losing the post-spell
				# probe stream and breaking Gate B's per_entity_iter
				# pairing. is_done stays false on purpose so Runtime's
				# entity walk keeps iterating the still-active LL entry.
	return cadence_fired_this_irq


func _tick_extras_primaries_drainer(current_sub_tick: int, cadence_fired: bool) -> void:
	## Pass 8 Phase 7 — per-IRQ tail of the SFX pipeline (extras →
	## primaries → drainer), called from Runtime.tick() phase 1.5 right
	## after the catchup. `cadence_fired` is the return value of
	## `_run_entity_catchup()` — true iff the entity sub-loop fired at
	## least once this IRQ. The drainer gate (FUN_80017118) only runs
	## when the catchup sub-loop entered LAB_80014CCC.
	_tick_extra_bindings(current_sub_tick, cadence_fired)
	_tick_primary_dispatchers(cadence_fired)
	if cadence_fired:
		_drain_prestage_all_slots()


func _tick_extra_bindings(current_sub_tick: int, cadence_fired_this_irq: bool) -> void:
	## Walk the silent-driver overlay bindings (N:1 to pool slots).
	for binding in _extra_bindings:
		if not binding.started:
			if current_sub_tick < binding.start_sub_tick:
				continue
			binding.started = true
		var slot := _pool.get_slot(binding.target_slot_idx)
		# FFT FUN_8001749C / FUN_80017118 (the LFO/flush trio members)
		# iterate independently of slot+0x0 gates — they fire per-driver-
		# slot pair, not per-channel-state. The correct gate is
		# dispatcher.tick's internal `channel.channel_word_0 == 0: return`,
		# which skips the FUN_80015138/FUN_80015324 work but lets the
		# pre-line recorders fire. So just don't skip here.
		if slot == null:
			continue
		(binding.dispatcher as _Dispatcher).tick(binding.channel, slot, cadence_fired_this_irq)


func _tick_primary_dispatchers(cadence_fired_this_irq: bool) -> void:
	## Walk the primary 1:1 dispatchers indexed by slot_idx.
	for slot_idx in range(_pool.POOL_SLOT_COUNT):
		var disp = _dispatchers[slot_idx]
		if disp == null:
			continue
		var slot := _pool.get_slot(slot_idx)
		if slot == null:
			continue
		var channel = _channels[slot_idx]
		(disp as _Dispatcher).tick(channel, slot, cadence_fired_this_irq)


func _drain_prestage_all_slots() -> void:
	## Per-tick drainer + computation. Mirrors FFT FUN_80017118
	## L800171b0..L800173B8 — BOTH the prestage drain to walker_flag_word
	## AND the SINGLE-SOURCE-OF-TRUTH computation of vol_staging /
	## pitch_staging.
	##
	## Architectural goal: eliminate the duplication where 0xE0, 0xE8,
	## Note, and porta paths each wrote vol_staging/pitch_staging
	## independently with order-dependent semantics (Pan re-clamping
	## Note's 14-bit value back to 7-bit, etc.). Opcode handlers store
	## RAW INPUTS (channel.expression_acc_s32, channel.pan_offset_ae,
	## slot.note_velocity_raw, channel.pitch_state, channel.pre_pitch_acc_u32,
	## channel.pitch_bend) and set prestage bits; this drainer reads ALL
	## inputs together and writes vol_staging / pitch_staging ONCE per
	## tick per slot.
	##
	## Disasm references (FFT FUN_80017118):
	##   ram:800171b0 lhu  s1, 0(s0)        ; load channel_word_1
	##   ram:800171b8 andi v0, s1, 0x100    ; vol prestage gate
	##   ram:800171c4 lh   v1, 0x98(s0)     ; chan+0x9a (envelope?)
	##   ram:80017204 lh   v1, 0x96(s2)     ; chan+0x96 (dynamics)
	##   ram:80017218 lh   a0, 0xae(s2)     ; chan+0xae (pan)
	##   (formula at L800171c4-L80017310 produces L/R vol)
	##   ram:80017324 sh   a2, 0x3a(s0)     ; commit L vol → chan+0x3c
	##   ram:80017328 sh   a1, 0x3c(s0)     ; commit R vol → chan+0x3e
	##   ram:8001732c ori  v0, v0, 0x1      ; OR walker bit 0x1
	##   ram:80017330 sh   v0, 0x2(s0)      ; commit walker_flag_word
	##   ram:80017334 andi v0, s1, 0x200    ; pitch prestage gate
	##   ram:80017340 lh   a0, 0x80(s0)     ; chan+0x82 pitch baseline
	##   ram:80017358 jal  FUN_80017424     ; SPU pitch encode
	##   ram:80017368 sh   v0, 0x46(s0)     ; commit pitch → chan+0x48
	##   ram:8001736c ori  v1, v1, 0x4      ; OR walker bit 0x4
	##   ram:80017370 sh   v1, 0x2(s0)      ; commit walker_flag_word
	##   ram:800173b8 sh   zero, 0x0(s0)    ; clear channel_word_1
	##
	## NOTE on the vol formula: the literal FFT formula at L800171c4-
	## L80017310 reads ~7 chan/slot fields (chan+0x96, chan+0x9a,
	## chan+0xae, chan+0x98, etc.). Several of these are not yet mapped
	## in Godot. We use a SIMPLIFIED formula matching Godot's pre-refactor
	## Note-handler scaling (preserves audio fidelity). The literal FFT
	## formula transcription is queued as future work once the unmapped
	## fields are probed.
	# probe_fun80017118_entry (Layer 4 paired). PCSX BP at PC 0x80017118
	# = function entry of FUN_80017118. One emit per call. PCSX cure: 208.
	if _cadence_anchored:
		_probe_fun80017118_entry_count += 1
		_Trace.emit("fun80017118_entry", {
			"call_index": _probe_fun80017118_entry_count,
		})
	for slot_idx in range(_pool.POOL_SLOT_COUNT):
		# probe_fun80017118_iter (Layer 4 paired). PCSX BP at PC 0x80017194
		# = the inner per-slot iteration gate. FFT iterates all 8 slots
		# per FUN_80017118 call regardless of whether the slot is active —
		# so emit BEFORE the null-slot guards. PCSX cure: 1664 (= 208
		# entries × 8 slot iters per entry).
		if _cadence_anchored:
			_probe_fun80017118_iter_count += 1
			_Trace.emit("fun80017118_iter", {
				"call_index": _probe_fun80017118_iter_count,
			})
		var d_slot := _pool.get_slot(slot_idx)
		if d_slot == null:
			continue
		var d_channel = _channels[slot_idx]
		if d_channel == null:
			continue
		# FFT PC 0x80017194 `beq v0, zero, LAB_800173bc` — skip the
		# entire per-slot body (vol/pitch formulas + chan_word_1 clear
		# at PC 0x800173B8) when chan_word_0 == 0. Endbar zeroes
		# chan_word_0 at spell-end, so this gate suppresses the 2 extra
		# cadence-519 pitch_staging/clear fires Godot was emitting after
		# endbar dispatched (PCSX leaves chan_word_1 bit 0x200 set but
		# never drains it because the iter loop exits via this gate).
		if d_channel.channel_word_0 == 0:
			continue
		# FFT's FUN_80017118 reaches the per-slot exit (PC 0x800173B8)
		# every drain pass for active slots — no walker_seed_pending
		# style shortcut. vol_lr_raw suppression pre-Note happens at the
		# walker layer via the bit-0x002-clears-bit-0x001 mutex (see
		# spu_irq_walker.gd:79-89), not at the drain layer. Letting the
		# drain run unconditionally per slot:
		#   - probe_fun80017118_clear emits per drain pass (matches PCSX
		#     distribution, eliminates +2 cadence drift)
		#   - chan_word_1 clears per pass (matches FFT's exit-clear at
		#     PC 0x800173B8, no bit accumulation across pre-Note ticks)
		#   - vol/pitch staging stays gated INSIDE on bits 0x100/0x200
		# See research/effect_alignment/WALKER_SEED_PENDING_ISSUE.md.
		# (Removed empirical per-tick envelope ramp.) The FFT-faithful
		# ramp of chan+0x98 += chan+0xa0 now lives in
		# dispatcher.gd::cadence_body (PC 0x800151EC..0x800151FC) and
		# is driven by channel.expression_acc_s32 / expression_delta_s32
		# armed by opcode 0xE2 smd_expression. probe_expression_ramp
		# matched PCSX bit-exact across all 70 fires on cure_no_music,
		# so this empirical model is no longer needed.
		var s1: int = d_channel.channel_word_1

		if (s1 & _SS.CHAN1_VOL_PRESTAGE) != 0:
			# Compute vol from the envelope accumulator. Mirrors FFT
			# FUN_80017118 L800171c4-L80017310 + the L/R split at
			# LAB_80017260 / LAB_800172a0:
			#   a3 = clamp(chan_98 + chan_88, 0, 0x7FFF)         ; env sample
			#   a3 = (chan_92 * a3) >> 15                        ; voice-active gate
			#   a3 = (pool_96 * a3) >> 16                        ; global dynamics
			#   a0 = clamp(chan_90 + chan_8a + pan_ae, 0, 0x7F00); pan baseline
			#   {a1, a2} = pan_split_polynomial(a0)              ; L/R weights
			#   vol_l = (a2 * a3) >> 15                          ; commit chan+0x3a
			#   vol_r = (a1 * a3) >> 15                          ; commit chan+0x3c
			# chan_92, pool_96, chan_90 are sourced as constants here for cure
			# correctness; the FFT init ops have not been traced yet.
			# See VOL_FORMULA_PORT_PLAN.md phases 1-3.
			# FFT vol formula at PC 0x800171c4 reads `lh v1, 0x98(s0)`
			# where s0 = chan_base + 0x2 (set at PC 0x80017188
			# `addiu s0, s3, 0x2`), so 0x98(s0) = chan_base+0x9A = the
			# HIGH halfword of chan+0x98 (the 32-bit expression-acc).
			# 0xE0 writes byte<<24 → high halfword = byte<<8; the 0xE2
			# burst ramps in 32-bit space, with the high halfword
			# advancing by `expression_delta_s32 >> 16` per fire (+439
			# per fire on cure_no_music, as probe_vol_inputs confirms).
			# FFT PC 0x800171C4..0x800171E4: a3 = clamp(chan_98 + chan_88, 0, 0x7FFF)
			# where both halfwords are signed. chan_88 is the vol-LFO
			# accumulator written by lfo_handler_tick's mode-1 path.
			var chan_98_u16: int = (d_channel.expression_acc_s32 >> 16) & 0xFFFF
			var chan_98_signed: int = chan_98_u16 - 0x10000 if chan_98_u16 >= 0x8000 else chan_98_u16
			var chan_88_u16: int = d_channel.chan_88_value & 0xFFFF
			var chan_88_signed: int = chan_88_u16 - 0x10000 if chan_88_u16 >= 0x8000 else chan_88_u16
			var env_sample: int = clampi(chan_98_signed + chan_88_signed, 0, 0x7FFF)
			_emit_vol_formula_stage(d_slot, "env_sample", env_sample)
			var chan_92: int = d_channel.chan_92_value
			var pool_96: int = 0x7F00
			var voice_gated: int = (chan_92 * env_sample) >> 15
			_emit_vol_formula_stage(d_slot, "voice_gated", voice_gated)
			var base_vol: int = (pool_96 * voice_gated) >> 16
			_emit_vol_formula_stage(d_slot, "global_gated", base_vol)
			# Pan baseline (chan_90=0x4000 cure-constant + chan_8a + pan_ae).
			# chan_8a is the pan-LFO accumulator written by lfo_handler_tick's
			# mode-2 path at PC 0x800175DC; FFT reads it as a signed halfword
			# at PC 0x80017214 (`lh v1, 0x8a(s0)`).
			# NB: this `0x4000` is FFT slot+0x90 (= absolute chan_base+0x92 —
			# the env-multiplier / pan-baseline field). It is NOT the same
			# field as the `chan_base+0x90` that opcode 0xD6 writes to —
			# despite the channel_state.chan_90_value field naming. D6's
			# write target (slot+0x8E in our convention) currently has no
			# downstream reader in this pan formula; integrating D6's audible
			# effect requires identifying the FFT consumer of chan_base+0x90
			# (out of scope of the initial D6 state-tracking patch).
			var pan: int = d_channel.pan_offset_ae
			var chan_8a_u16: int = d_channel.chan_8a_value & 0xFFFF
			var chan_8a_signed: int = chan_8a_u16 - 0x10000 if chan_8a_u16 >= 0x8000 else chan_8a_u16
			var pan_base: int = clampi(0x4000 + chan_8a_signed + pan, 0, 0x7F00)
			_emit_vol_formula_stage(d_slot, "pan_base", pan_base)
			# L/R polynomial split. Case A (pan_base < 0x4000): a0_split =
			# pan_base, a1=poly_1=L, a2=poly_2=R. Case B (pan_base >= 0x4000):
			# a0_split = 0x8000 - pan_base, a2=poly_1=L, a1=poly_2=R.
			# Cure has pan=0 → pan_base=0x4000 → case B, a0_split=0x4000,
			# both polys → 23040, vol_l = vol_r = (23040 * base_vol) >> 15.
			var a0_split: int
			var case_b: bool
			if pan_base < 0x4000:
				a0_split = pan_base
				case_b = false
			else:
				a0_split = 0x8000 - pan_base
				case_b = true
			# poly_1 = ((45 * a0) << 9) >> 14 ≈ a0 * 1.40625
			var poly_1: int = ((45 * a0_split) << 9) >> 14
			# poly_2 = 0x7F00 - ((37 * a0) << 8) >> 14 ≈ 0x7F00 - a0 * 0.578
			var poly_2: int = 0x7F00 - (((37 * a0_split) << 8) >> 14)
			var vol_l_weight: int
			var vol_r_weight: int
			if case_b:
				vol_l_weight = poly_1
				vol_r_weight = poly_2
			else:
				vol_l_weight = poly_2
				vol_r_weight = poly_1
			d_slot.vol_staging_l = clampi((vol_l_weight * base_vol) >> 15, 0, 0x3FFF)
			d_slot.vol_staging_r = clampi((vol_r_weight * base_vol) >> 15, 0, 0x3FFF)
			# probe_vol_inputs (Layer 5 synthesis). Sibling of
			# probe_vol_lr_staging — same BP @ 0x80017328. Captures every
			# chan/pool field FFT's vol formula reads at L800171c4..0x18.
			# Only chan_98 + pool_ae have Godot mirrors; the other 5 are
			# unmapped envelope fields. We emit 0 for those — validator
			# will fail on them, but JSONL captures FFT's envelope state
			# on PCSX side (first measurement).
			_probe_vol_inputs_count += 1
			# Surface the constants the drainer above actually consumes
			# (chan_90, chan_92, pool_96) so the validator can compare them
			# against PCSX. chan_88 / chan_8a now carry the per-tick LFO
			# accumulator outputs populated by dispatcher.gd::_advance_lfo
			# (Bug B). chan_90 / pool_96 remain FFT-observed constants
			# from probe_vol_inputs (cure_no_music: chan_90=0x4000,
			# pool_96=0x7F00); chan_92 comes from channel.chan_92_value.
			_Trace.emit("vol_inputs", {
				"call_index": _probe_vol_inputs_count,
				"chan_88": d_channel.chan_88_value & 0xFFFF,
				"chan_8a": d_channel.chan_8a_value & 0xFFFF,
				"chan_90": 0x4000,
				"chan_92": d_channel.chan_92_value & 0xFFFF,
				"chan_98": (d_channel.expression_acc_s32 >> 16) & 0xFFFF,
				"pool_96": 0x7F00,
				"pool_ae": d_channel.pan_offset_ae & 0xFFFF,
			})
			# probe_vol_lr_staging (Layer 5 synthesis). Mirror of FFT
			# BP @ 0x80017328 — vol L/R committed to chan+0x3a/0x3c.
			_probe_vol_lr_staging_count += 1
			_Trace.emit("vol_lr_staging", {
				"call_index": _probe_vol_lr_staging_count,
				"vol_l": d_slot.vol_staging_l & 0xFFFF,
				"vol_r": d_slot.vol_staging_r & 0xFFFF,
			})
			d_slot.walker_flag_word |= _SS.WALKER_FLAG_VOL_LR_RAW

		if (s1 & _SS.CHAN1_PITCH_PRESTAGE) != 0:
			# Compute pitch via dispatcher's existing formula. Mirrors
			# FFT L80017340-L80017370 — sums chan+0x82 baseline,
			# chan+0x86 pitch_bend, chan+0xa2, runs SPU-pitch encode.
			# `_evaluate_pitch_formula` already implements this faithfully.
			var disp = _dispatchers[slot_idx]
			if disp != null:
				d_slot.pitch_staging = (disp as _Dispatcher)._evaluate_pitch_formula(d_channel, d_slot)
			# probe_pitch_inputs (Layer 5 synthesis). Sibling of
			# probe_pitch_staging — same BP @ 0x80017368, but captures
			# the pre-encode formula inputs from chan-state. Emitted
			# BEFORE pitch_staging so call_index ordering pairs
			# 1-for-1 with PCSX (same BP, same fire moment).
			_probe_pitch_inputs_count += 1
			var pitch_base_u16: int = (d_channel.pre_pitch_acc_u32 >> 16) & 0xFFFF
			var pitch_bend_u16: int = d_channel.pitch_bend & 0xFFFF
			var voice_idx: int = _pool.voice_for_slot(slot_idx)
			_Trace.emit("pitch_inputs", {
				"call_index": _probe_pitch_inputs_count,
				"voice":      voice_idx,
				"pitch_base": pitch_base_u16,
				"pitch_bend": pitch_bend_u16,
				"pool_a2":    0,
			})
			# probe_pitch_formula_stages (Layer 5 BISECTION) — five rows
			# per pitch-prestage iteration matching the PCSX-side stages
			# at PC 0x80017344 / 0x80017348 / 0x8001734c / 0x80017354 /
			# 0x8001736c. Cure/reraise have pool_a2 = 0; midi_sum here is
			# the s32 sum (pre-sll/sra; addu can overflow s16 before sign-
			# ext, so we capture as s32 to match PCSX). pitch_result is
			# the final 14-bit masked SPU pitch.
			var pitch_base_s16: int = pitch_base_u16
			if pitch_base_s16 >= 0x8000: pitch_base_s16 -= 0x10000
			var pool_a2_s16: int = 0
			var midi_sum_s32: int = pitch_base_s16 + pitch_bend_u16 + pool_a2_s16
			_emit_pitch_formula_stage(d_slot, "pitch_base",   pitch_base_s16)
			_emit_pitch_formula_stage(d_slot, "pitch_bend",   pitch_bend_u16)
			_emit_pitch_formula_stage(d_slot, "pool_a2",      pool_a2_s16)
			_emit_pitch_formula_stage(d_slot, "midi_sum",     midi_sum_s32)
			_emit_pitch_formula_stage(d_slot, "pitch_result", d_slot.pitch_staging & 0xFFFF)
			# probe_pitch_staging (Layer 5 synthesis). Mirror of FFT
			# BP @ 0x80017368 — SPU pitch committed to chan+0x46.
			_probe_pitch_staging_count += 1
			_Trace.emit("pitch_staging", {
				"call_index": _probe_pitch_staging_count,
				"voice":         voice_idx,
				"pitch_staging": d_slot.pitch_staging & 0xFFFF,
			})
			d_slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH

		# probe_fun80017118_clear (Layer 5 synthesis). Mirror of FFT
		# BP @ 0x800173B8 — per-slot exit-clear that wipes chan_word_1.
		# Emit BEFORE the actual clear so the row captures the pre-
		# clear value (matches PCSX's probe_read16 of s0 prior to the
		# `sh zero, 0x0(s0)` instruction).
		_probe_fun80017118_clear_count += 1
		_Trace.emit("fun80017118_clear", {
			"call_index": _probe_fun80017118_clear_count,
			"chan_word_1_pre_clear": d_channel.channel_word_1 & 0xFFFF,
		})
		d_channel.channel_word_1 = 0


func play_silent_driver_pair(feds: FedsBank, pair_idx: int,
		target_slot_idx: int, start_sub_tick: int = 0,
		sound_id: int = -1) -> bool:
	## Bind a silent-driver feds pair to TWO existing audible voice slots.
	## Allocates 2 new ChannelStates whose target_voice_idx points at the
	## SAME voices the primary pair owns, NOT new pool slots. Each silent-
	## driver dispatcher walks its bytecode independently and ORs flag
	## bits into the shared slot.flag_word. Mirrors FFT's `00 03 / 00 04`
	## sound_channel entries where silent driver overlays the audible
	## voice.
	##
	## start_sub_tick defers the dispatcher start (timeline keyframe
	## activation).
	if feds == null:
		return false
	if pair_idx < 0 or pair_idx >= feds.num_pairs:
		push_warning("EffectPlaySound: silent driver pair %d out of range" % pair_idx)
		return false
	if target_slot_idx < 0 or target_slot_idx + 1 >= _pool.POOL_SLOT_COUNT:
		push_warning("EffectPlaySound: silent target %d out of range" % target_slot_idx)
		return false
	# Verify the target slots are already allocated by a primary pair —
	# otherwise the silent driver has nothing to overlay.
	if _channels[target_slot_idx] == null or _channels[target_slot_idx + 1] == null:
		push_warning("EffectPlaySound: silent target slots %d/%d not bound by primary pair" % [target_slot_idx, target_slot_idx + 1])
		return false

	# Mark the audible-primary channels so their stream-end path does NOT
	# fire KOFF — the overlay will keep driving the shared voice past the
	# audible's bytecode end.
	_channels[target_slot_idx].has_silent_overlay = true
	_channels[target_slot_idx + 1].has_silent_overlay = true

	# Increment per-slot driving_channels counter so the slot knows how
	# many channels need to stream_end before KOFF fires. Each silent
	# driver channel adds 1 to the count; when each channel's bytecode
	# hits stream_end, dispatcher.gd decrements. Final-channel stream_end
	# (count→0) fires the deferred KOFF.
	var slot_a := _pool.get_slot(target_slot_idx)
	var slot_b := _pool.get_slot(target_slot_idx + 1)
	if slot_a != null:
		slot_a.driving_channels += 1
	if slot_b != null:
		slot_b.driving_channels += 1

	var events_a: Array = feds.get_channel_events(pair_idx * 2)
	var events_b: Array = feds.get_channel_events(pair_idx * 2 + 1)

	for off in range(2):
		var sidx: int = target_slot_idx + off
		var events: Array = events_a if off == 0 else events_b
		var disp := _Dispatcher.new()
		disp.bind(events, _waveset)
		var ch := SharedChannelState.new(sidx, _pool.voice_for_slot(sidx))
		ch.opcode_pos = 0
		_apply_chan_92_init(ch, feds, sound_id)
		# Mark this channel as silent-driver so its end-of-stream path
		# doesn't key_off the shared SPU voice that the audible pair is
		# still using. Set BEFORE _apply_lfo_state_seed so the seeder can
		# branch on is_silent_driver (audible primaries get their sub-slot
		# active_dir cleared by FFT play_sound init at PC 0x80013D5C,
		# silent drivers retain savestate sub-slot state).
		ch.is_silent_driver = true
		_apply_lfo_state_seed(ch)
		# Effect-load arming so the first Note dispatches as primary.
		ch.channel_word_0 |= _SS.CHAN0_KON_ARM
		_extra_bindings.append({
			"channel": ch,
			"dispatcher": disp,
			"target_slot_idx": sidx,
			"start_sub_tick": start_sub_tick,
			"started": start_sub_tick == 0,
		})
	return true


func free_pair(slot_idx: int) -> void:
	_dispatchers[slot_idx] = null
	if slot_idx + 1 < _dispatchers.size():
		_dispatchers[slot_idx + 1] = null
	_pool.free_pair(slot_idx)


func is_sequencing_done() -> bool:
	## True once every pair this play dispatched has hit EndBar (its channel's
	## active_word bit-0 cleared) — i.e. the FEDS sequence has played out (voices
	## now in their natural release). False until at least one pair was dispatched.
	## A game engine uses this to reap an ORPHANED cast (whose visual ended) only
	## after its sound finishes, instead of cutting it short.
	var any := false
	for slot_i in range(_pool.POOL_SLOT_COUNT):
		if _dispatchers[slot_i] == null:
			continue
		any = true
		var sl: _SS = _pool.get_slot(slot_i)
		if sl != null and (sl.active_word & 0x1) != 0:
			return false
	return any


func release_and_free() -> void:
	## End this cast cleanly: key-OFF every voice this play has bound (so a held
	## mid-sustain note enters its ADSR release and decays to a natural tail
	## instead of droning forever) and free its pool slots. Other casts' slots
	## are untouched — only slots this play owns (its non-null _dispatchers
	## entries) are released. The release tail finishes on the SPU's own clock.
	for slot_i in range(_pool.POOL_SLOT_COUNT):
		if _dispatchers[slot_i] == null:
			continue
		var sl: _SS = _pool.get_slot(slot_i)
		if sl != null and _flush_tick != null and sl.voice_mask != 0:
			_flush_tick.emit_koff_now(sl.voice_mask)
		_dispatchers[slot_i] = null
		_pool.free_slot(slot_i)
