class_name Team
extends Resource

var team_name: String = "[Team Name]"

var inventory: PackedInt32Array = []
var currency: int = 100

var units: Array[Unit] = []

#@export var end_conditions: Array[EndCondition] = []
@export var end_conditions: Dictionary[EndCondition, bool] = {}
var state: State = State.ACTIVE

enum State {
	ACTIVE,
	LOST,
	WON,
}


func _init() -> void:
	# TODO set up end conditions based on battle data
	var standard_win: EndCondition = EndCondition.new()
	standard_win.defeat_all_enemies = true
	standard_win.end_type = EndCondition.EndType.WIN
	standard_win.condition_name = "Defeat All Enemies"
	standard_win.pre_battle_message = "Defeat All Enemies!"
	standard_win.post_battle_message = "Defeated all enemies!"
	
	var standard_lose: EndCondition = EndCondition.new()
	standard_lose.target_teams = [self]
	standard_lose.end_type = EndCondition.EndType.LOSE
	standard_lose.condition_name = "Defeated"
	standard_lose.pre_battle_message = ""
	standard_lose.post_battle_message = "Your team was defeated!"
	
	end_conditions[standard_win] = false
	end_conditions[standard_lose] = false


func check_end_conditions(battle_manager: BattleManager) -> State:
	for end_condition: EndCondition in end_conditions.keys():
		end_conditions[end_condition] = end_condition.check_condition(battle_manager, self)
	
	if end_conditions.keys().any(func(end_condition: EndCondition) -> bool: 
			return end_conditions[end_condition] and end_condition.end_type == EndCondition.EndType.LOSE):
		state = State.LOST
		return State.LOST
	elif end_conditions.keys().any(func(end_condition: EndCondition) -> bool: 
			return end_conditions[end_condition] and end_condition.end_type == EndCondition.EndType.WIN):
		state = State.WON
		return State.WON
	else:
		state = State.ACTIVE
		return State.ACTIVE
