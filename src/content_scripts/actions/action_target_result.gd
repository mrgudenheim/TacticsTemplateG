class_name ActionTargetResult
extends RefCounted
## Pure gameplay outcome for a targeted UnitData (or empty tile when target_unit == null).

enum HitOutcome {
	HIT,
	CRITICAL,
	MISS,
	EVADED,
	GUARDED,
	NULLIFIED,
	ABSORBED,
}

# --- Identity & Pre-Hit State ---
var target_unit: UnitData = null
var target_tile: TerrainTile = null
var hit_outcome: HitOutcome = HitOutcome.HIT
var hit_chance_percentage: int = 100
var was_defeated_before_hit: bool = false

# --- Evasion Details (read by ActionPresenter for weapon/shield/job evade animations) ---
var evade_source: EvadeData.EvadeSource = EvadeData.EvadeSource.JOB
var evade_direction: EvadeData.Directions = EvadeData.Directions.FRONT

# --- Clamped Stat Mutations ---
var stat_deltas: Dictionary[UnitData.StatType, int] = {}
var stat_underflows: Dictionary[UnitData.StatType, int] = {}
var stat_overflows: Dictionary[UnitData.StatType, int] = {}

# --- Team Resource Mutations ---
var currency_delta: int = 0
var inventory_deltas: Dictionary[int, int] = {}

# --- Status Mutations ---
var statuses_added: PackedStringArray = []
var statuses_removed: PackedStringArray = []
var eligible_status_ids: PackedStringArray = [] # populated in preview/AI and live modes; paired with action's chance/list_type/will_remove

# --- Equipment & Displacement ---
var broken_slot_index: int = -1
var stolen_slot_index: int = -1
var stolen_item_name: String = ""
var knockback_origin_tile: TerrainTile = null
var knockback_destination_tile: TerrainTile = null

# --- Per-Target Cascading Sub-Actions (On-Hit SecondaryActions, status action_on_apply) ---
var target_sub_resolutions: Array[ActionResolution] = []


func did_hit() -> bool:
	return hit_outcome == HitOutcome.HIT or hit_outcome == HitOutcome.CRITICAL


func apply_to_unit(apply_displacement: bool = true) -> void:
	if not is_instance_valid(target_unit):
		return

	# 1. Apply Clamped Stat Changes ("dead" / "critical" are applied in steps 3-4)
	for stat_type: UnitData.StatType in stat_deltas.keys():
		var delta: int = stat_deltas[stat_type]
		if delta != 0 and target_unit.stats.has(stat_type):
			target_unit.stats[stat_type].add_value(delta)

	# 2. Apply Team Currency & Inventory Changes
	if target_unit.team != null:
		if currency_delta != 0:
			target_unit.team.currency = maxi(0, target_unit.team.currency + currency_delta)
		for item_index: int in inventory_deltas.keys():
			if item_index >= 0 and item_index < target_unit.team.inventory.size():
				target_unit.team.inventory[item_index] = maxi(0, target_unit.team.inventory[item_index] + inventory_deltas[item_index])

	# 3. Apply Status Removals
	for status_id: String in statuses_removed:
		target_unit.remove_status_id(status_id)

	# 4. Apply Status Additions (UnitActor updates visuals via statuses_updated; action_on_apply is in target_sub_resolutions)
	for status_id: String in statuses_added:
		var status_effect: StatusEffect = GameData.get_status_effect(status_id)
		if status_effect != null:
			var ignore_immunity: bool = (status_id == "dead")
			target_unit.add_status(status_effect.duplicate(), ignore_immunity)

	# 5. Update Logical Tile Position (ActionPresenter passes false until knockback slide finishes)
	if apply_displacement and knockback_destination_tile != null:
		target_unit.set_terrain_tile_position(knockback_destination_tile)
