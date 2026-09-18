class_name EffectsCastHost
extends ExMateriaEffects.CastHost
## The addon calls these methods to ask about the running battle. They answer in plain
## ints and `Node3D`s, so no TacticsG type (`Unit`, `TerrainTile`, `FftAbilityData`)
## reaches the addon.
##
## The inherited stage reference is WEAK — keeping one of these will not keep a finished
## battle alive.

## The addon wants a charge-pose number; the ROM's tables give a handler number. This
## converts one to the other:
##   handler  4 -> spell charge lines   (pose 1)
##   handler 22 -> orbital summon orbs  (pose 2)
##   anything else -> standard charge particles (pose 0 -> handler 8)
## Charge+N needs no entry — those are matched on ability id before this is consulted.
const HANDLER_TO_CHARGING_POSE: Dictionary = {
	4: 1,
	22: 2,
}


func _battle() -> Node:
	var s := stage()
	return s if is_instance_valid(s) else null


## Vacant slots must stay null. The addon remembers a cast by its position in this array,
## so closing the gaps would re-point every cast after the gap.
func actors() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var battle := _battle()
	if battle == null:
		return result
	for unit in battle.units:
		# `char_body`, not the Unit: a `Unit` never moves, and the lookup below has to
		# match whatever the cast sites passed in.
		if not is_instance_valid(unit):
			result.append(null)
			continue
		# Duck-typed: a `Unit` answers with its body, a stage of plain Node3Ds with itself.
		var body: Node3D = unit.get("char_body") as Node3D
		result.append(body if body != null else unit as Node3D)
	return result


## Recomputed from the live tiles rather than stored, so a rebuilt map cannot leave a
## stale rect behind. An empty rect makes the addon centre effects by map size alone.
func arena_bounds() -> Rect2i:
	var battle := _battle()
	if battle == null or battle.total_map_tiles.is_empty():
		return Rect2i()
	var min_x: int = 1 << 30
	var min_y: int = 1 << 30
	var max_x: int = -(1 << 30)
	var max_y: int = -(1 << 30)
	for location: Vector2i in battle.total_map_tiles.keys():
		min_x = mini(min_x, location.x)
		min_y = mini(min_y, location.y)
		max_x = maxi(max_x, location.x)
		max_y = maxi(max_y, location.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## How ability `ability_id` should look. `ELEMENT_TO_TRAP_ID` turns the
## `Action.ElementTypes` bitfield into the 1-8 the addon expects (FIRE=1 … DARK=8).
func ability_visual(ability_id: int) -> ExMateriaEffects.AbilityVisual:
	if ability_id < 0 or ability_id >= RomReader.fft_abilities.size():
		return ExMateriaEffects.AbilityVisual.absent()
	var data: FftAbilityData = RomReader.fft_abilities[ability_id]
	if data == null:
		return ExMateriaEffects.AbilityVisual.absent()
	var handler_id: int = 0
	if data.ability_action != null:
		handler_id = data.ability_action.user_shared_vfx_handler_id
	return ExMateriaEffects.AbilityVisual.of(
		data.display_name,
		data.formula_id,
		TrapEffectData.element_type_to_trap_id(data.element_type),
		int(HANDLER_TO_CHARGING_POSE.get(handler_id, 0)),
	)


## A per-unit override for the charge-line colour. 0 means "no override" — the addon then
## uses the ability's own element. TacticsG has nothing to put here: a unit's elemental
## affinities are a damage rule, not a colour.
func actor_element_id(_actor: Node3D) -> int:
	return 0


## Called once per cast, so it is off by default. Do not read it as "the cast worked":
## a spell call can arrive before initialization has failed.
static var log_casts: bool = false

var casts: Array = []


func note_cast(caster_idx: int, target_idx: int, effect_name: String) -> void:
	casts.append([caster_idx, target_idx, effect_name])
	if log_casts:
		print("[TTG_CAST] caster=%d target=%d %s" % [caster_idx, target_idx, effect_name])


func diagnostic_label() -> String:
	var battle := _battle()
	return "TacticsG" if battle != null else ""
