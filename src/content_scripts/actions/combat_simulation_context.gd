class_name CombatSimulationContext
extends RefCounted
## Simulation scratchpad managing cloned UnitData resources during ActionResolver chain evaluation.

const MAX_REACTIONS_PER_UNIT: int = 1
const MAX_CHAIN_DEPTH: int = 10

var simulated_units: Dictionary[UnitData, UnitData] = {}
var unit_reaction_counts: Dictionary[UnitData, int] = {}


func get_or_create(live_unit: UnitData) -> UnitData:
	if live_unit == null:
		return null
	if not simulated_units.has(live_unit):
		var simulated_unit: UnitData = live_unit.duplicate_for_simulation()
		simulated_units[live_unit] = simulated_unit
	return simulated_units[live_unit]


func get_units_override(battle_manager: BattleManager) -> Array[UnitData]:
	var combined_units: Array[UnitData] = []
	if battle_manager != null:
		for battle_unit: UnitData in battle_manager.units:
			combined_units.append(simulated_units[battle_unit] if simulated_units.has(battle_unit) else battle_unit)
	else:
		combined_units.assign(simulated_units.values())
	return combined_units


static func apply_stat_change(
	simulated_unit: UnitData,
	stat_type: UnitData.StatType,
	raw_value: int,
	is_set_value: bool
) -> Dictionary[String, int]:
	var stat_value: StatValue = simulated_unit.stats[stat_type]
	var current_value: int = stat_value.current_value
	var min_value: int = stat_value.min_value
	var max_value: int = stat_value.max_value
	var desired_value: int = raw_value if is_set_value else (current_value + raw_value)
	var overflow: int = maxi(0, desired_value - max_value)
	var underflow: int = maxi(0, min_value - desired_value)
	var actual_delta: int = stat_value.set_value(raw_value) if is_set_value else stat_value.add_value(raw_value)
	return {
		"delta": actual_delta,
		"overflow": overflow,
		"underflow": underflow,
	}


func clone() -> CombatSimulationContext:
	var copy: CombatSimulationContext = CombatSimulationContext.new()
	for live_unit: UnitData in simulated_units.keys():
		var cloned_unit: UnitData = simulated_units[live_unit].duplicate_for_simulation()
		copy.simulated_units[live_unit] = cloned_unit
	copy.unit_reaction_counts = unit_reaction_counts.duplicate()
	return copy


func can_unit_react(live_unit: UnitData, chain_depth: int) -> bool:
	if live_unit == null or chain_depth >= MAX_CHAIN_DEPTH:
		return false
	if unit_reaction_counts.get(live_unit, 0) >= MAX_REACTIONS_PER_UNIT:
		return false
	var simulated_unit: UnitData = get_or_create(live_unit)
	return not simulated_unit.is_defeated()


func record_unit_reaction(live_unit: UnitData) -> void:
	unit_reaction_counts[live_unit] = unit_reaction_counts.get(live_unit, 0) + 1
