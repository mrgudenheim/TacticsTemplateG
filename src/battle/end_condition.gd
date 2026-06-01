class_name EndCondition
extends Resource

@export var condition_name: String = "[End Condition Name]"
@export var pre_battle_message: String = "[pre_battle_message]"
@export var post_battle_message: String = "[post_batle_message]"

var defeat_all_enemies: bool = false
var target_teams: Array[Team] = []
var target_units: Array[Unit] = []
var list_type: ListType = ListType.ANY
var end_type: EndType = EndType.WIN

enum EndType {
	WIN,
	LOSE,
}

enum ListType {
	ANY,
	ALL,
}


func check_condition(battle_manager: BattleManager, this_team: Team) -> bool:
	if defeat_all_enemies:
		return all_enemies_defeated(battle_manager, this_team)
	elif not target_teams.is_empty():
		if list_type == ListType.ALL:
			return all_teams_defeated(target_teams)
		else: # ListType.ANY:
			return any_teams_defeated(target_teams)
	elif not target_units.is_empty():
		if list_type == ListType.ALL:
			return all_units_defeated(target_units)
		else: # ListType.ANY:
			return any_units_defeated(target_units)
	
	push_warning("End condition defaulting to false: " + condition_name)
	return false


func all_enemies_defeated(battle_manager: BattleManager, this_team: Team) -> bool:
	for team: Team in battle_manager.teams:
		if team == this_team:
			continue
		elif not all_units_defeated(team.units):
			return false
	
	return true


func all_teams_defeated(teams: Array[Team]) -> bool:
	return teams.all(func(team: Team) -> bool: return all_units_defeated(team.units)) # returns true if teams is empty


func any_teams_defeated(teams: Array[Team]) -> bool:
	return teams.any(func(team: Team) -> bool: return all_units_defeated(team.units)) # returns false if teams is empty


func all_units_defeated(units: Array[Unit]) -> bool:
	return units.all(func(unit: Unit) -> bool: return unit.is_defeated) # returns true if units is empty


func any_units_defeated(units: Array[Unit]) -> bool:
	return units.any(func(unit: Unit) -> bool: return unit.is_defeated) # returns false if units is empty


# TODO check if all units (from all teams) are permanently frozen to prevent infinite loop
func all_units_frozen(units: Array[Unit]) -> bool:
	return units.all(func(unit: Unit) -> bool: return unit.current_statuses.any(func(status: StatusEffect) -> bool: return status.freezes_ct and status.duration_type == StatusEffect.DurationType.INDEFINITE)) # returns true if units is empty
