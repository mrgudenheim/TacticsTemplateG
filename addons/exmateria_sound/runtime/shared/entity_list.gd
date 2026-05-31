class_name SharedEntityList
## Shared sound-entity LIFO. Port of FFT's DAT_80032A50 linked-list head.
##
## FFT analog:
##   DAT_80032A50               — global ptr, head of the LIFO
##   FUN_80014024 entity_ll_push(e)    — *e = head; head = e; (LIFO insert)
##   FUN_80014078 entity_ll_unlink(e)  — walk head→tail, splice out
##
## The same list holds music entities (one per loaded .SMD) AND effect-sound
## entities (one per active effect slot). FFT's spu_updater_tick walks
## DAT_80032A50 for the per-IRQ outer loop at PC 0x80014BCC; it dispatches
## the per-channel chain (per-tick handler / opcode interpreter / LFO / SPU
## flush) regardless of music-vs-SFX origin.
##
## In Godot we'd lose the in-band pointer convention (Godot uses Object refs,
## not raw struct pointers), so the LIFO is implemented as a typed Array.
## Pushing prepends; walk() iterates head→tail; unlink() is O(N) linear-
## scan + erase. Expected list size is small (max ~32: 1 music entity + 8
## SFX entities + a handful of silent-driver entities).
##
## Consumers (Pass 6+):
##   - MusicEntityState   — pushed by Sequencer.load_smd; unlinked by stop.
##   - EffectSoundPool    — wired in Pass 8 to push each EffectEntityCatchupState.
##   - per-IRQ walker     — wired in Pass 8; iterates walk() instead of
##                          EffectSoundPool._slots and Sequencer.tracks
##                          separately.
##
## Until Pass 8 wires consumers the LIFO is a self-contained shape;
## `_smoke_self_test()` exercises push / walk / unlink semantics so the
## abstraction is verifiable on its own.

var _entries: Array = []

# Pass 8 phase 1 — class-level singleton accessor. Music's Sequencer
# pushes its music_entity here at load_smd; SFX's EffectPlaySound
# will push its EffectEntityCatchupState in a follow-up phase. Until
# Pass 8 phase 3 wires the unified driver loop, no consumer walks the
# list — this is foundation plumbing only.
#
# Untyped to avoid the self-class-reference compile error GDScript
# trips on when a class names itself inside its own body. The
# Sequencer-side preload (const _SharedEntityList = preload(...))
# binds the type for callers.
static var _singleton = null


static func get_singleton():
	if _singleton == null:
		_singleton = load("res://addons/exmateria_sound/runtime/shared/entity_list.gd").new()
	return _singleton


func push(entity) -> void:
	## FFT FUN_80014024: *entity_next = head; head = entity.
	## LIFO insert at head — newest pushed walks first.
	if entity == null:
		push_warning("SharedEntityList.push(null) ignored")
		return
	_entries.push_front(entity)


func register_at_tail(entity) -> void:
	## Append at the LL tail. Used by render_music_wav.gd to register a
	## secondary music entity AFTER the primary so iteration order
	## matches PCSX's runtime walk (primary → secondary).
	##
	## Per MUSIC_ITER30_SECOND_MUSIC_ENTITY_REFACTOR.md §1.4: PCSX's
	## probe_pitch_register evidence on MUSIC_34 voice 11 shows the
	## later-write-wins value matches the SECOND entity's slot 12, which
	## means the second entity is processed AFTER the primary in the
	## per-IRQ entity walk. Calling push() would prepend the secondary
	## (making it walk first), so we expose a tail-append explicitly.
	if entity == null:
		push_warning("SharedEntityList.register_at_tail(null) ignored")
		return
	_entries.append(entity)


func unlink(entity) -> bool:
	## FFT FUN_80014078: walk from head, splice out entity.
	## Returns true if entity was present, false if not in list.
	var idx := _entries.find(entity)
	if idx < 0:
		return false
	_entries.remove_at(idx)
	return true


func walk() -> Array:
	## FFT spu_updater_tick outer loop @ PC 0x80014BCC:
	##   for (e = DAT_80032A50; e != null; e = *e) { … }
	## Returns the live Array — caller may iterate but must not mutate
	## during iteration. The returned reference is the internal storage,
	## intentionally — mirrors FFT's direct pointer walk.
	return _entries


func size() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()


func contains(entity) -> bool:
	return _entries.find(entity) >= 0
