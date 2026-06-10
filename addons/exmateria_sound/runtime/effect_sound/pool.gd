class_name EffectSoundPool
## Effect-sound voice pool — port of FFT's effect-channel pool.
##
## Mirrors the 8-slot effect pool walked by FUN_80017118 (per-tick SPU flush).
## Each pool slot is deterministically bound to one SPU voice:
##   slot_idx N (0..7) → SPU voice (16 + N)
##
## In FFT, each slot is a 0x160-byte struct walked at stride 0x160. We don't
## need byte-accurate layout — slot state lives in _SS.
##
## Allocation: port of FFT's `play_sound_callee_12d40` (0x80012D40).
## Starting at slot_idx = `6 - pair_size` (= 4 for stereo pair), search
## DOWNWARD in pair-sized strides for a pair whose slots are both free.
## First-fit wins. Empirically: cure_no_music's single sound lands at
## slot 4 (matches our prior hardcoded value); cure_4_no_music's three
## sounds fire to slots 4, 2, 0 in firing order.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")

# FFT-faithful defaults: 8 slots, SFX voices start at 16, slots 0-5 usable
# (6-7 reserved for music). `_Pool.new()` with no args reproduces these exactly,
# so the parity harness is unchanged. The game's EffectSfxEngine constructs an
# "unlocked" pool (e.g. new(24, 0, 24)) to use all 24 voices of its dedicated
# SFX SPU. Kept as class consts (capitalised) so static reads like
# `_SfxPoolInner.SPU_VOICE_BASE_DEFAULT` still resolve.
const POOL_SLOT_COUNT_DEFAULT := 8
const SPU_VOICE_BASE_DEFAULT := 16
const USABLE_SLOTS_DEFAULT := 6

# Per-instance config (UPPER-cased so existing `_pool.SPU_VOICE_BASE` /
# `_pool.POOL_SLOT_COUNT` instance reads in flush_tick/walker keep working).
var POOL_SLOT_COUNT: int = POOL_SLOT_COUNT_DEFAULT
var SPU_VOICE_BASE: int = SPU_VOICE_BASE_DEFAULT
var _usable_slots: int = USABLE_SLOTS_DEFAULT

var _slots: Array = []                            # Array[_SS]
var _slot_free: PackedByteArray = PackedByteArray()  # 1 = free, 0 = in use

# Monotonic counter — bumped on every allocate_pair and stamped onto both
# allocated slots' bind_tick. LRU proxy for FFT's entity+0x10 preempt
# priority: smaller bind_tick = older bind = lower priority = preempt
# candidate. See DISILLUSIONMENT_PAIR_SLOT_PREEMPT_DEFICIT.md Phase 1.
var _bind_tick_counter: int = 0

# SharedFlushTick ref. Untyped to avoid the preload cycle (flush_tick.gd
# already preloads pool.gd). When non-null, allocate_pair emits a pre-bind
# KOFF on the prior tenant's voice mask via flush_tick.emit_koff_now —
# mirrors FFT feds_channel_resolver (0x80013B20) at the JAL to
# FUN_8001ACF0(0, voice_mask). Wired by render_effect_sound.gd; legacy
# callers / unit tests that leave it null skip the emit.
var _flush_tick = null


func _init(p_slot_count: int = POOL_SLOT_COUNT_DEFAULT,
		p_voice_base: int = SPU_VOICE_BASE_DEFAULT,
		p_usable_slots: int = -1) -> void:
	POOL_SLOT_COUNT = p_slot_count
	SPU_VOICE_BASE = p_voice_base
	# Default usable = all slots (use the whole pool); FAITHFUL passes 6 to keep
	# slots 6-7 reserved for the music sequencer.
	_usable_slots = p_usable_slots if p_usable_slots >= 0 else p_slot_count
	_slots.resize(POOL_SLOT_COUNT)
	_slot_free.resize(POOL_SLOT_COUNT)
	for i in range(POOL_SLOT_COUNT):
		_slots[i] = _SS.new(i)
		_slot_free[i] = 1


func set_flush_tick(flush_tick) -> void:
	_flush_tick = flush_tick


func voice_for_slot(slot_idx: int) -> int:
	## Pool slot N is bound to SPU voice SPU_VOICE_BASE + N (deterministic).
	return SPU_VOICE_BASE + slot_idx


func is_free(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= POOL_SLOT_COUNT:
		return false
	return _slot_free[slot_idx] == 1


func get_slot(slot_idx: int) -> _SS:
	if slot_idx < 0 or slot_idx >= POOL_SLOT_COUNT:
		return null
	return _slots[slot_idx]


func find_free_pair_slot(pair_size: int = 2) -> Dictionary:
	## Port of FFT play_sound_callee_12d40 (0x80012D40, scus_decompilation.c:816).
	##
	## Pass 2a — free-pair downward scan (lines 848-867):
	##   start_slot = 6 - pair_size                       (= 4 for stereo pair)
	##   mask = (1 << pair_size) - 1                      (= 0x3 for pair)
	##   bits_at_slot = mask << start_slot                (= 0x30 initially)
	##   while bits_at_slot >= mask:
	##       if no busy bit overlaps bits_at_slot: return start_slot
	##       bits_at_slot >>= pair_size                   (walk down)
	##       start_slot -= pair_size
	##
	## Pass 2b — preempt-candidate scan (PC 0x80012E08..0x80012E70):
	## walks the same high-to-low pair-stride sweep and picks the slot
	## whose `entity+0x10` (priority/lifetime metric) is the smallest seen
	## so far AND whose `entity+0xd` (release-state byte) is `< 0x21`. We
	## proxy entity+0x10 with `SlotState.bind_tick` (smallest bind_tick =
	## oldest = lowest priority — equivalent ordering since every FFT
	## slot starts at the same init value and decrements per tick). The
	## entity+0xd `< 0x21` gate is dropped from this Phase 1 LRU proxy —
	## see DISILLUSIONMENT_PAIR_SLOT_PREEMPT_DEFICIT.md Phase 2 for the
	## true field instrumentation.
	##
	## Returns {slot_idx: int, preempted: bool}. slot_idx == -1 only when
	## pair_size is out of range OR the pool is exhausted and no candidate
	## slot has ever been bound (= initial state; should not occur in
	## practice).
	if pair_size <= 0 or pair_size > POOL_SLOT_COUNT:
		return {"slot_idx": -1, "preempted": false}
	# FFT magic constant: `6 - pair_size`. The effect pool occupies slots 0-5
	# (6 slots); slots 6-7 are reserved for the music sequencer. So the
	# highest valid stereo-pair-start is slot 4 (slots 4+5). Verified at
	# scus_decompilation.c:848 (FUN_80012D40 line `uVar4 = 6 - param_2`).
	# `_usable_slots` defaults to 6 (FAITHFUL); an unlocked pool sets it to the
	# full slot count to hand out every pair (e.g. 24 -> highest start = 22).
	var start_slot_init: int = _usable_slots - pair_size
	# Build a bitmap of busy slots. A slot is "busy" iff
	#   _slot_free[i] == 0  AND  slot.active_word & 1 != 0
	# Mirrors FFT play_sound_callee_12d40 Pass 2 (PC 0x80012E04):
	# `~killed_mask & *(global_active_mask) & pair_bitmask`. The
	# global active mask is updated when a chan's word_0 bit 0 is
	# cleared — i.e., when the chan's bytecode terminates. In Godot,
	# the dispatcher clears `slot.active_word & 1` at stream-end
	# (dispatcher.gd:392) and EndBar-no-loop (dispatcher.gd:1869),
	# making the slot reusable for the next allocation without
	# disturbing the slot's post-EndBar release-decay state (which
	# active_slots() / flush_tick still process via _slot_free).
	var busy: int = 0
	for i in range(POOL_SLOT_COUNT):
		var s: _SS = _slots[i]
		var word0_alive: bool = s != null and (s.active_word & 0x1) != 0
		if _slot_free[i] == 0 and word0_alive:
			busy |= 1 << i
	var mask: int = (1 << pair_size) - 1

	# Pass 2a — free-pair search.
	var start_slot: int = start_slot_init
	var bits_at_slot: int = mask << start_slot
	while bits_at_slot >= mask:
		if (busy & bits_at_slot) == 0:
			return {"slot_idx": start_slot, "preempted": false}
		bits_at_slot >>= pair_size
		start_slot -= pair_size

	# Pass 2b — preempt search (LRU proxy). Walk the same high-to-low pair-
	# stride sweep; pick the busy slot with the smallest bind_tick. Slots
	# with bind_tick == -1 (never bound) are not preempt candidates.
	var best_bind_tick: int = 0x7FFFFFFF
	var best_slot: int = -1
	start_slot = start_slot_init
	while start_slot >= 0:
		var ps: _SS = _slots[start_slot]
		if ps != null and ps.bind_tick >= 0 and ps.bind_tick < best_bind_tick:
			best_bind_tick = ps.bind_tick
			best_slot = start_slot
		start_slot -= pair_size
	return {"slot_idx": best_slot, "preempted": best_slot >= 0}


func allocate_pair(start_slot_idx: int) -> Array:
	## Reserve slots [start_slot_idx, start_slot_idx + 1] atomically.
	## Returns [slot_a, slot_b] (_SS) on success, or [] if
	## either slot is out of range or already in use.
	##
	## In FFT, the resolver always allocates two adjacent slots (a "pair")
	## per config, mapping to a stereo voice pair (e.g. voices 20, 21).
	if start_slot_idx < 0 or start_slot_idx + 1 >= POOL_SLOT_COUNT:
		push_warning("EffectSoundPool: pair start %d out of range" % start_slot_idx)
		return []
	# Match find_free_pair_slot's busy criterion: a slot is "busy" only
	# if it was previously allocated AND its chan word_0 bit 0 is still
	# set (i.e., the chan hasn't terminated). Slots whose dispatchers
	# have fired stream-end (active_word & 1 cleared) are reusable.
	var sa: _SS = _slots[start_slot_idx]
	var sb: _SS = _slots[start_slot_idx + 1]
	var a_busy: bool = _slot_free[start_slot_idx] == 0 and sa != null and (sa.active_word & 0x1) != 0
	var b_busy: bool = _slot_free[start_slot_idx + 1] == 0 and sb != null and (sb.active_word & 0x1) != 0
	if a_busy or b_busy:
		push_warning("EffectSoundPool: pair %d/%d busy" % [start_slot_idx, start_slot_idx + 1])
		return []
	# FFT feds_channel_resolver (0x80013B20) emits FUN_8001ACF0(0,
	# voice_mask) on the prior tenant's voice mask BEFORE rebinding
	# chan_word_0+0x1. Mirror that here so probe_kon_koff_mask pairs
	# cad-by-cad: the slot allocator's pre-bind KOFF emit at cad 1212 /
	# 1343 (zombie_no_music BATTLE.BIN-driven status-effect re-tenants)
	# is observable on PCSX even when the SPU voice has already been
	# released by the prior tenant's bytecode-driven stream-end. When
	# voice_mask is 0 (slot has never been allocated), there is nothing
	# to release and the emit is skipped. See
	# research/effect_sound/working_documents/
	# ZOMBIE_CATALOG_REPLAY_SILENT_FIX_PLAN.md Stage C-1.
	var prior_voice_mask: int = 0
	if sa != null:
		prior_voice_mask |= sa.voice_mask
	if sb != null:
		prior_voice_mask |= sb.voice_mask
	if prior_voice_mask != 0 and _flush_tick != null:
		_flush_tick.emit_koff_now(prior_voice_mask)
	_slot_free[start_slot_idx] = 0
	_slot_free[start_slot_idx + 1] = 0
	var a: _SS = _slots[start_slot_idx]
	var b: _SS = _slots[start_slot_idx + 1]
	a.reset()
	b.reset()
	a.voice_mask = 1 << voice_for_slot(start_slot_idx)
	b.voice_mask = 1 << voice_for_slot(start_slot_idx + 1)
	# Mirror FFT FUN_800137d8's slot+0x6c=0 (noise) / +0x68 (fmod) clear at slot
	# allocation: a reused voice must not carry the prior effect's noise/pitch-mod
	# mode into this fresh sound. A bytecode 0xB4 (Noise) re-enables it if needed.
	if _flush_tick != null:
		_flush_tick.reset_voice_routing(a.voice_mask | b.voice_mask)
	_bind_tick_counter += 1
	a.bind_tick = _bind_tick_counter
	b.bind_tick = _bind_tick_counter
	return [a, b]


func free_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= POOL_SLOT_COUNT:
		return
	_slot_free[slot_idx] = 1
	(_slots[slot_idx] as _SS).reset()


func mark_free(slot_idx: int) -> void:
	## Flip _slot_free to 1 WITHOUT resetting the slot state. Used by
	## play_sound.tick_all_dispatchers post-tick sync to mirror FFT's
	## "chan_word_0 & 1 == 0 → slot is free" semantics without wiping
	## the slot fields that the SPU mixer still consumes (ADSR release
	## decay, sample_start_addr, etc.). The next allocate_pair will
	## reset() the slot itself before binding new events.
	if slot_idx < 0 or slot_idx >= POOL_SLOT_COUNT:
		return
	_slot_free[slot_idx] = 1


func free_pair(start_slot_idx: int) -> void:
	free_slot(start_slot_idx)
	free_slot(start_slot_idx + 1)


func active_slots() -> Array:
	## Returns slots currently in use (in slot_idx order). Used by the
	## per-tick flush (Layer 3) to walk the pool.
	var out: Array = []
	for i in range(POOL_SLOT_COUNT):
		if _slot_free[i] == 0:
			out.append(_slots[i])
	return out


func reset() -> void:
	for i in range(POOL_SLOT_COUNT):
		_slot_free[i] = 1
		(_slots[i] as _SS).reset()
