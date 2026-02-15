class_name MoveTargeting
extends TargetingStrategy


func get_potential_targets(action_instance: ActionInstance) -> Array[TerrainTile]:
	var potential_targets: Array[TerrainTile] = []
	await action_instance.user.update_map_paths(action_instance.battle_manager.total_map_tiles, action_instance.battle_manager.units)
	#await action_instance.user.paths_updated
	
	for tile: TerrainTile in action_instance.user.path_costs.keys():
		if tile == action_instance.user.tile_position:
			continue
		if action_instance.user.path_costs[tile] > action_instance.user.move:
			continue # don't highlight tiles beyond move range
		potential_targets.append(tile)
	
	return potential_targets


func start_targeting(action_instance: ActionInstance) -> void:
	super.start_targeting(action_instance)
	
	if not action_instance.battle_manager.map_input_event.is_connected(action_instance.on_map_input_event):
		action_instance.battle_manager.map_input_event.connect(action_instance.on_map_input_event)
	
	for unit: Unit in action_instance.battle_manager.units:
		if not unit.unit_input_event.is_connected(action_instance.on_unit_hovered):
			unit.unit_input_event.connect(action_instance.on_unit_hovered)
	
	if not action_instance.tile_hovered.is_connected(target_tile):
		action_instance.tile_hovered.connect(target_tile)


func stop_targeting(action_instance: ActionInstance) -> void:
	if action_instance.battle_manager.map_input_event.is_connected(action_instance.on_map_input_event):
		action_instance.battle_manager.map_input_event.disconnect(action_instance.on_map_input_event)
	
	for unit: Unit in action_instance.battle_manager.units:
		if unit.unit_input_event.is_connected(action_instance.on_unit_hovered):
			unit.unit_input_event.disconnect(action_instance.on_unit_hovered)
	
	if action_instance.tile_hovered.is_connected(target_tile):
			action_instance.tile_hovered.disconnect(target_tile)


func clear_path(path_highlight_containers: Array[Node3D]) -> void:
	for container: Node3D in path_highlight_containers:
		if is_instance_valid(container):
			container.queue_free()


func target_tile(tile: TerrainTile, action_instance: ActionInstance, event: InputEvent) -> void:
	if action_instance.battle_manager.active_unit != action_instance.user:
		stop_targeting(action_instance)
		return
	
	# don't update path if hovered tile has not changed or is not valid for moving
	if tile == null or action_instance.user.map_paths.is_empty():
		return
	
	# handle hovering over new tile
	if tile != action_instance.current_tile_hovered:
		action_instance.current_tile_hovered = tile
		
		# show preview path
		var path: Array[TerrainTile] = get_map_path(action_instance.user.tile_position, tile, action_instance.user.map_paths)
		var path_in_range: Array[TerrainTile] = path.filter(func(path_tile: TerrainTile) -> bool: return action_instance.user.path_costs[path_tile] <= action_instance.user.move) # TODO allow parameter instead of move_current
		var path_out_of_range: Array[TerrainTile] = path.filter(func(path_tile: TerrainTile) -> bool: return action_instance.user.path_costs[path_tile] > action_instance.user.move) # TODO allow parameter instead of move_current
		
		action_instance.clear_targets(action_instance.preview_targets_highlights)
		action_instance.preview_targets.clear()
		
		action_instance.preview_targets.append(tile)
		
		action_instance.preview_targets_highlights.merge(action_instance.get_tile_highlights(path_in_range, action_instance.battle_manager.tile_highlights[Color.BLUE]))
		action_instance.preview_targets_highlights.merge(action_instance.get_tile_highlights(path_out_of_range, action_instance.battle_manager.tile_highlights[Color.WHITE]))
		action_instance.show_targets_highlights(action_instance.preview_targets_highlights)
	
	# handle clicking tile
	if event.is_action_pressed("primary_action"):
		if action_instance.user.path_costs.has(tile):
			if action_instance.user.path_costs[tile] <= action_instance.user.move: # TODO allow parameter instead of move_current
				action_instance.submitted_targets = get_map_path(action_instance.user.tile_position, tile, action_instance.user.map_paths)
				if action_instance.submitted_targets.is_empty():
					push_error(action_instance.user.unit_nickname + " trying to use Move without any targets")
				
				#action_instance.submitted_targets.append(tile)
				await action_instance.queue_use()
				return

# TODO allow cost based on Unit Move value or action range value, allow vertical jumping or horizontal leapint to use a parameter or unit stat
## map_tiles is Dictionary[Vector2i, Array[TerrainTile]], returns path to every tile
func get_map_paths(user: Unit, map_tiles: Dictionary[Vector2i, Array], units: Array[Unit], max_cost: int = 9999) -> Dictionary[TerrainTile, TerrainTile]:
	user.map_paths.clear()
	user.path_costs.clear()
	
	var start_tile: TerrainTile = user.tile_position
	#var start_tile: TerrainTile = map_tiles[map_position][0]
	#if map_tiles[map_position].size() > 1:
		#for potential_tile in map_tiles[map_position]:
			#
	var frontier: Array[TerrainTile] = [] # TODO use priority_queue for dijkstra's
	frontier.append(start_tile)
	var came_from: Dictionary[TerrainTile, TerrainTile] = {} # path A->B is stored as came_from[B] == A
	var cost_so_far: Dictionary[TerrainTile, float] = {}
	came_from[start_tile] = null
	cost_so_far[start_tile] = 0
	
	var start_time: int = Time.get_ticks_msec()
	var max_frame_time_ms: float = 1000.0 / (units.size() * 60.0)
	
	var current: TerrainTile
	while not frontier.is_empty():
		current = frontier.pop_front()
		
		# break early
		#if current == goal:
			#break 
		
		for next: TerrainTile in get_map_path_neighbors(user, current, map_tiles, units):
			var new_cost: float = cost_so_far[current] + get_move_cost(current, next, user.terrain_costs)
			if new_cost > max_cost:
				continue # break early
			
			if next not in cost_so_far or new_cost < cost_so_far[next]:
				# TODO use a priority_queue
				if next not in cost_so_far:
					cost_so_far[next] = new_cost
					for idx: int in frontier.size(): # TODO use frontier.bsearch_custom(new_cost, func(a, b): return cost_so_far[b] < a)?
						if new_cost < cost_so_far[frontier[idx]]: # assumes frontier is sorted by ascending cost_so_far
							frontier.insert(idx, next)
							break
					frontier.append(next) # add at end if highest cost
				elif new_cost < cost_so_far[next]:
					var current_priority: int = frontier.bsearch(next)
					cost_so_far[next] = new_cost
					if current_priority == 0:
						pass # don't need to change priority
					elif cost_so_far[frontier[current_priority - 1]] < new_cost:
						pass # don't need to change priority
					else: # move position in queue
						frontier.remove_at(current_priority)
						for idx: int in frontier.size(): # TODO use frontier.bsearch_custom(new_cost, func(a, b): return cost_so_far[b] < a)?
							if new_cost < cost_so_far[frontier[idx]]: # assumes frontier is sorted by ascending cost_so_far
								frontier.insert(idx, next)
								break
				
				came_from[next] = current
			
		if Time.get_ticks_msec() - start_time > max_frame_time_ms:
			await user.get_tree().process_frame
			start_time = Time.get_ticks_msec()
			
			if user == null:
				return {}
	
	user.path_costs = cost_so_far
	return came_from


func get_map_path(start_tile: TerrainTile, target_tile_instance: TerrainTile, came_from: Dictionary[TerrainTile, TerrainTile]) -> Array[TerrainTile]:
	if not came_from.has(target_tile_instance):
		#push_warning("No path from " + str(start_tile.location) + " to target: " + str(target_tile_instance.location))
		return []
	
	var current: TerrainTile = target_tile_instance
	var path: Array[TerrainTile] = []
	while current != start_tile: 
		path.append(current)
		current = came_from[current]
	#path.append(start_tile) # optional
	path.reverse() # optional
	
	return path


func get_map_path_neighbors(user: Unit, current_tile: TerrainTile, map_tiles: Dictionary[Vector2i, Array], units: Array[Unit]) -> Array[TerrainTile]:
	var neighbors: Array[TerrainTile]
	const adjacent_offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	# check adjacent tiles
	for offset: Vector2i in adjacent_offsets:
		var potential_xy: Vector2i = current_tile.location + offset
		if map_tiles.has(potential_xy):
			for tile: TerrainTile in map_tiles[potential_xy]:
				if tile.no_walk == 1:
					continue
				elif user.prohibited_terrain.has(tile.surface_type_id): # lava, etc.
					continue
				elif not user.ignore_height and abs(tile.height_mid - current_tile.height_mid) > user.jump: # restrict movement based on current jomp, TODO allow jump height as parameter?
					continue
				elif units.any(func(unit: Unit) -> bool: return unit.tile_position == tile and not unit.is_defeated): # prevent moving on top or through other units
					continue # TODO allow moving through knocked out units
				# TODO prevent trying to move vertically through floors/ceilings
				else:
					neighbors.append(tile)
		
		neighbors.append_array(get_leaping_neighbors(user, current_tile, map_tiles, units, offset, neighbors))
	# TODO check other cases - leaping, teleport, map warps, fly, float, etc.
	# TODO get animations - walking, jumping, etc.
	
	return neighbors


func get_leaping_neighbors(user: Unit, current_tile: TerrainTile, map_tiles: Dictionary[Vector2i, Array], units: Array[Unit], offset_direction: Vector2i, walk_neighbors: Array[TerrainTile]) -> Array[TerrainTile]:
	var leap_neighbors: Array[TerrainTile] = []
	@warning_ignore("integer_division")
	var max_leap_distance: int = user.jump / 2
	
	if max_leap_distance == 0:
		return leap_neighbors
	
	for leap_distance: int in range(1, max_leap_distance + 1):
		var potential_xy: Vector2i = current_tile.location + (offset_direction * (leap_distance + 1))
		if map_tiles.has(potential_xy):
			var intermediate_tiles: Array[TerrainTile] = []
			for intermediate_distance: int in range(1, leap_distance + 1):
				var intermediate_xy: Vector2i = current_tile.location + (offset_direction * intermediate_distance)
				if map_tiles.has(intermediate_xy):
					intermediate_tiles.append_array(map_tiles[intermediate_xy])
			for tile: TerrainTile in map_tiles[potential_xy]:
				if tile.no_walk == 1:
					continue
				elif user.prohibited_terrain.has(tile.surface_type_id): # lava, etc.
					continue
				elif not user.ignore_height and abs(tile.height_mid - current_tile.height_mid) > user.jump: # restrict movement based on current jomp
					continue
				elif tile.height_mid > current_tile.height_mid: # can't leap up
					continue
				# TODO prevent trying to move vertically through floors/ceilings
				elif units.any(func(unit: Unit) -> bool: return unit.tile_position == tile): # prevent moving on top or through other units
					continue # TODO allow moving through knocked out units
				elif intermediate_tiles.any(func(intermediate_tile: TerrainTile) -> bool: return intermediate_tile.height_mid > current_tile.height_mid): # prevent leaping through taller intermediate tiles
					continue # TODO fix leap check for leaping under a bridge/ceiling
				elif intermediate_tiles.any(func(intermediate_tile: TerrainTile) -> bool: 
					var can_leap: bool = true
					if units.any(func(unit: Unit) -> bool: return unit.tile_position == intermediate_tile):
						can_leap = current_tile.height_mid >= intermediate_tile.height_mid + 3 # prevent leaping over units taller than starting height
					return not can_leap): 
					continue
				elif intermediate_tiles.any(func(intermediate_tile: TerrainTile) -> bool: # prevent leaping when walking would be fine
						var intermediate_is_taller_then_final: bool = intermediate_tile.height_mid >= tile.height_mid # TODO more complex check for if there is actually a path from the intermediate tile
						var intermediate_is_walkable: bool = walk_neighbors.has(intermediate_tile) or leap_neighbors.has(intermediate_tile)
						return (intermediate_is_taller_then_final and intermediate_is_walkable)
						): 
					continue
				else:
					leap_neighbors.append(tile)
	
	return leap_neighbors


func get_move_cost(from_tile: TerrainTile, to_tile: TerrainTile, terrain_costs: Dictionary[int, int]) -> float:
	var cost: float = 0
	cost = from_tile.location.distance_to(to_tile.location) # handle leaping cost
	
	if terrain_costs.has(to_tile.surface_type_id):
		cost += terrain_costs[to_tile.surface_type_id] - 1 # subtract 1 because terrain_costs already includes cost for assumed distance of 1
	
	# https://ffhacktics.com/wiki/Movement_modifiers_Table
	# TODO check depth or terrain type?
	
	return cost
