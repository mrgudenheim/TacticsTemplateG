extends RefCounted
## Per-battle host contract for EffectManager. No global registration; the
## stage must be in the scene (never the persistent root viewport) and its
## actors share its World3D. The weak reference does not keep the stage alive.

const AbilityVisual = preload("res://addons/exmateria_effects/cast/AbilityVisual.gd")

var _stage_ref: WeakRef


func _init(scene_stage: Node) -> void:
	_stage_ref = weakref(scene_stage) if is_instance_valid(scene_stage) else null


func stage() -> Node:
	return _stage_ref.get_ref() as Node if _stage_ref != null else null


## Live roster in stable slot order. Preserve vacant slots as null; never compact.
## Return a fresh view if the host stores a differently typed collection.
func actors() -> Array[Node3D]:
	return []


## Empty bounds mean unavailable. The manager preserves legacy size-only centering.
func arena_bounds() -> Rect2i:
	return Rect2i()


## Optional actor capability: charge-line color, not the ability's element.
func actor_element_id(_actor: Node3D) -> int:
	return 0


## Optional ability capability: what this battle's ability data says ability
## `ability_id` should LOOK like. The addon's only ability question — it asks
## for a visual, never for a record, a database or a ROM table (ADR-0364).
##
## Absent by default (its semantics: `AbilityVisual.absent`); a host that owns
## ability data overrides this, one that does not gets generic visuals rather
## than a parse error.
func ability_visual(_ability_id: int) -> AbilityVisual:
	return AbilityVisual.absent()


## An observation, not a success notification. Spell/cinematic/item calls can
## precede initialization failure; trap calls follow successful initialization.
## Indices are roster slots; -1 means absent/unknown. Logging is optional.
func note_cast(_caster_idx: int, _target_idx: int, _effect_name: String) -> void:
	pass


## Optional: the for_each LANES of the cast `caster_idx` aims at `target_idx` with
## E`effect_id` — `{units: Array[Node3D], offsets: PackedInt32Array}`, one per unit it hits, in
## the order the host stamps their hits, each lane's start in frames after phase 1 (lane 0's = 0). The
## ROM plays the for_each phase once per target (EffectInstance.set_for_each_lanes); which
## units the cast hits, and when, is the host's to know. Asked after `note_cast`. Empty (the
## default) = one lane, on the target.
func for_each_lanes(_caster_idx: int, _target_idx: int, _effect_id: int) -> Dictionary:
	return {}


func diagnostic_label() -> String:
	return ""


func diagnostic_tick() -> int:
	return 0
