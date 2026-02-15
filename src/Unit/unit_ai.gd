#https://ffhacktics.com/wiki/BATTLE.BIN_Routines#AI_Calculations

#https://ffhacktics.com/wiki/AI_Ability_Use_Decisions
#https://ffhacktics.com/wiki/Evaluate_Cancel_Status_Ability_(0019881c)
#https://ffhacktics.com/wiki/Find_Peril_Most_Unit_(00198b04)

class_name UnitAi
extends Resource

var wait_action_instance: ActionInstance
@export var strategy: Strategy = Strategy.END_TURN
var only_end_activation: bool = true
var choose_random_action: bool = false
var choose_best_action: bool = false

@export var action_delay: float = 0.5

var action_eval_data: Array = []

enum Strategy {
	PLAYER,
	END_TURN,
	RANDOM,
	BEST,
	CONFUSED,
	BERSERK,
	FLEE,
}

func choose_action(unit: Unit) -> void:
	unit.global_battle_manager.game_state_label.text = unit.job_nickname + "-" + unit.unit_nickname + " AI choosing action"
	
	if Vector2i(floori(unit.char_body.position.x), floori(unit.char_body.position.z)) != unit.tile_position.location:
		push_error("Unit position not equal to char body position")
	
	wait_action_instance = unit.actions_data[unit.wait_action.unique_name]
	
	if strategy == Strategy.END_TURN:
		await wait_for_delay(unit)
		wait_action_instance.start_targeting()
		await wait_action_instance.action_completed
		return
	
	#if not unit.paths_set:
		#await unit.paths_updated
	
	var eligible_actions: Array[ActionInstance] = unit.actions_data.values().filter(func(action_instance: ActionInstance) -> bool: return action_instance.is_usable() and not action_instance.potential_targets.is_empty())
	if eligible_actions.size() > 1:
		eligible_actions.erase(wait_action_instance) # don't choose to wait if another action is eligible
	else:
		await wait_for_delay(unit)
		wait_action_instance.start_targeting()
		await wait_action_instance.action_completed
		return
	
	if strategy == Strategy.RANDOM:
		var chosen_action: ActionInstance = eligible_actions.pick_random()
		await action_targeted(unit, chosen_action) # random target
	elif strategy == Strategy.BEST: # TODO implement better ai choosing 'best' action
		var move_action_instance: ActionInstance = unit.actions_data[unit.move_action.unique_name]
		var non_move_actions: Array[ActionInstance] = eligible_actions.duplicate()
		non_move_actions.erase(move_action_instance) # TODO evaluate move separately
		
		var start_time: int = Time.get_ticks_msec()
		var max_frame_time_ms: float = 1000.0 / 240.0
		
		var best_action: ActionInstance
		var best_target: TerrainTile
		var best_ai_score: int = 0
		
		var simulated_input: InputEvent = InputEventMouseMotion.new()
		var action_best_targets: Dictionary[ActionInstance, TerrainTile] = {}
		var action_scores: Dictionary[ActionInstance, int] = {}
		for action_instance: ActionInstance in non_move_actions:
			for potential_target: TerrainTile in action_instance.potential_targets: # TODO handle ai score for auto targeting
				#action_instance.tile_hovered.emit(potential_target, action_instance, simulated_input) # set preview targets
				action_instance.preview_targets = action_instance.action.targeting_strategy.get_aoe_targets(action_instance, potential_target)
				var potential_ai_score: int = action_instance.get_ai_score()
				
				if potential_ai_score > best_ai_score:
					best_ai_score = potential_ai_score
					best_action = action_instance
					best_target = potential_target
				
				if action_scores.keys().has(action_instance):
					if action_scores[action_instance] < potential_ai_score:
						action_scores[action_instance] = potential_ai_score
						action_best_targets[action_instance] = potential_target
				else:
					action_best_targets[action_instance] = potential_target
					action_scores[action_instance] = potential_ai_score
				
				if Time.get_ticks_msec() - start_time > max_frame_time_ms: # prevent freezing/lag
					await action_instance.user.get_tree().process_frame
					start_time = Time.get_ticks_msec()
			
			action_instance.stop_targeting()
		
		var best_move: TerrainTile
		if move_action_instance.is_usable() and not move_action_instance.potential_targets.is_empty() and not non_move_actions.is_empty():
			var original_tile: TerrainTile = unit.tile_position
			var original_tile_location: Vector2i = original_tile.location
			for potential_move: TerrainTile in move_action_instance.potential_targets: # TODO handle ai score for auto targeting
				unit.tile_position = potential_move
				
				for action_instance: ActionInstance in non_move_actions:
					action_instance.potential_targets = await action_instance.action.targeting_strategy.get_potential_targets(action_instance)
					for potential_target: TerrainTile in action_instance.potential_targets: # TODO handle ai score for auto targeting
						#action_instance.tile_hovered.emit(potential_target, action_instance, simulated_input) # set preview targets
						#action_instance.action.targeting_strategy.target_tile(potential_target, action_instance, simulated_input)
						action_instance.preview_targets = action_instance.action.targeting_strategy.get_aoe_targets(action_instance, potential_target)
						var potential_ai_score: int = action_instance.get_ai_score()
						
						if potential_ai_score > best_ai_score:
							best_ai_score = potential_ai_score
							best_action = action_instance
							best_target = potential_target
							best_move = potential_move
						
						if Time.get_ticks_msec() - start_time > max_frame_time_ms: # prevent freezing/lag
							await action_instance.user.get_tree().process_frame
							start_time = Time.get_ticks_msec()
					
					action_instance.stop_targeting()
			
			unit.tile_position = original_tile
			if unit.tile_position.location != original_tile_location:
				push_error("Unit position not reset during ai consideration")
			if Vector2i(floori(unit.char_body.position.x), floori(unit.char_body.position.z)) != unit.tile_position.location:
				push_error("Unit position not equal to char body position")
		
		if best_move != null:
			move_action_instance.start_targeting() # TODO refactor using actions with specific target
			await wait_for_delay(unit)
			move_action_instance.tile_hovered.emit(best_move, move_action_instance, simulated_input)
			await wait_for_delay(unit)
			#if not move_action_instance.preview_targets.is_empty(): # TODO fix why move does not have targets sometimes
			var simulated_input_action: InputEventAction = InputEventAction.new()
			simulated_input_action.action = "primary_action"
			simulated_input_action.pressed = true
			move_action_instance.tile_hovered.emit(best_move, move_action_instance, simulated_input_action)
			return
		
		if best_action != null:
			var chosen_action: ActionInstance = best_action
			await action_targeted(unit, chosen_action, best_target)
			return
		
		if move_action_instance.is_usable() and not move_action_instance.potential_targets.is_empty():
			# find closest enemy and move towards
			var shortest_path_cost: int = -1
			var shortest_path_target: TerrainTile
			for other_unit: Unit in unit.global_battle_manager.units:
				if other_unit.team != unit.team and not other_unit.is_defeated: # if enemy
					var other_unit_xy: Vector2i = other_unit.tile_position.location
					var adjacent_tiles: Array[TerrainTile] = []
					var adjacent_directions: Array[Vector2i] = [
						Vector2i.LEFT,
						Vector2i.RIGHT,
						Vector2i.UP,
						Vector2i.DOWN,
					]
					for adjacent_vector: Vector2i in adjacent_directions:
						var adjacent_xy: Vector2i = other_unit_xy + adjacent_vector
						if unit.global_battle_manager.total_map_tiles.keys().has(adjacent_xy):
							adjacent_tiles.append_array(unit.global_battle_manager.total_map_tiles[adjacent_xy])
					
					if adjacent_tiles.has(unit.tile_position): # if already next to enemy, wait
						await action_targeted(unit, wait_action_instance)
						return
					
					for adjacent_tile: TerrainTile in adjacent_tiles:
						if unit.path_costs.keys().has(adjacent_tile):
							if shortest_path_cost == -1:
								shortest_path_cost = unit.path_costs[adjacent_tile]
								shortest_path_target = adjacent_tile
							elif unit.path_costs[adjacent_tile] < shortest_path_cost:
								shortest_path_cost = unit.path_costs[adjacent_tile]
								shortest_path_target = adjacent_tile
			
			var move_target: TerrainTile = shortest_path_target
			var move_cost: int = shortest_path_cost
			if move_target != null:
				while move_cost > unit.move:
					#if unit.path_costs[move_target] > unit.move_current:
						#break
					move_target = unit.map_paths[move_target]
					move_cost = unit.path_costs[move_target]
			
			# move to target or else move randomly is no path to any target
			await action_targeted(unit, move_action_instance, move_target, shortest_path_target)
			return
		
		if best_action == null:
			wait_action_instance.start_targeting()
			await wait_action_instance.action_completed
	elif strategy == Strategy.CONFUSED: # TODO implement confused ai
		push_error("Confused ai not implemented")
		var chosen_action: ActionInstance = eligible_actions.pick_random()
		await action_targeted(unit, chosen_action) # random target
	elif strategy == Strategy.BERSERK: # TODO implement berserk ai
		push_error("Berserk ai not implemented")
		var chosen_action: ActionInstance = eligible_actions.pick_random()
		await action_targeted(unit, chosen_action) # random target
	elif strategy == Strategy.FLEE: # TODO implement flee ai
		push_error("Flee ai not implemented")
		var chosen_action: ActionInstance = eligible_actions.pick_random()
		await action_targeted(unit, chosen_action) # random target

func action_targeted(unit: Unit, chosen_action: ActionInstance, target: TerrainTile = null, hover_target: TerrainTile = null) -> void:
	#chosen_action.show_potential_targets() # TODO fix move targeting when updating paths/pathfinding is takes longer than delay (large maps with 10+ units)
	chosen_action.potential_targets = await chosen_action.action.targeting_strategy.get_potential_targets(chosen_action)
	chosen_action.start_targeting()
	if chosen_action.action.auto_target:
		await chosen_action.action_completed
	else:
		await wait_for_delay(unit)
		if target == null:
			target = chosen_action.potential_targets.pick_random() # random target
		if hover_target == null:
			hover_target = target
		var simulated_input: InputEvent = InputEventMouseMotion.new()
		chosen_action.tile_hovered.emit(hover_target, chosen_action, simulated_input)
		await wait_for_delay(unit)
		if not chosen_action.preview_targets.is_empty(): # TODO fix why move does not have targets sometimes
			var simulated_input_action: InputEventAction = InputEventAction.new()
			simulated_input_action.action = "primary_action"
			simulated_input_action.pressed = true
			chosen_action.tile_hovered.emit(target, chosen_action, simulated_input_action)
		else: # wait if no targets
			chosen_action.stop_targeting()
			wait_action_instance.start_targeting()
			await wait_action_instance.action_completed


func wait_for_delay(unit: Unit) -> void:
	await unit.get_tree().create_timer(action_delay).timeout
