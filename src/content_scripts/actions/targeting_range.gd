class_name RangeTargeting
extends TargetingStrategy
# https://ffhacktics.com/wiki/Targeting_routine

func get_potential_targets(action_instance: ActionInstance) -> Array[TerrainTile]:
	if action_instance.action.use_weapon_targeting:
		var weapon_attack_action_instance: ActionInstance = action_instance.user.actions_data[action_instance.user.get_attack_action().unique_name]
		return weapon_attack_action_instance.action.targeting_strategy.get_potential_targets(weapon_attack_action_instance)
	
	var start_time: int = Time.get_ticks_msec()
	var max_frame_time_ms: float = 1000.0 / 120.0
	
	var potential_targets: Array[TerrainTile] = []
	#action_instance.user.get_map_paths(action_instance.battle_manager.total_map_tiles, action_instance.battle_manager.units)
	
	var min_tile_pos: Vector2i = action_instance.user.tile_position.location - Vector2i(action_instance.action.max_targeting_range, action_instance.action.max_targeting_range)
	var max_tile_pos: Vector2i = action_instance.user.tile_position.location + Vector2i(action_instance.action.max_targeting_range, action_instance.action.max_targeting_range)
	
	for map_x: int in range(min_tile_pos.x, max_tile_pos.x + 1):
		for map_y: int in range(min_tile_pos.y, max_tile_pos.y + 1):
			var map_pos: Vector2i = Vector2i(map_x, map_y)
			if action_instance.battle_manager.total_map_tiles.has(map_pos):
				var relative_pos: Vector2i = map_pos - action_instance.user.tile_position.location
				var distance_xy: int = abs(relative_pos.x) + abs(relative_pos.y)
				
				if action_instance.action.targeting_linear:
					if relative_pos.x != 0 and relative_pos.y != 0:
						continue
				
				var min_height: float = 0
				if action_instance.action.targeting_top_down:
					var map_tiles_at_pos: Array[TileData] = action_instance.battle_manager.total_map_tiles[map_pos].duplicate()
					if map_tiles_at_pos.size() > 1:
						map_tiles_at_pos.sort_custom(func(a: TileData, b: TileData) -> bool: return a.height_mid > b.height_mid)
						min_height = map_tiles_at_pos[0].height_mid
						
				
				for tile: TerrainTile in action_instance.battle_manager.total_map_tiles[map_pos]:
					if action_instance.action.targeting_top_down and tile.height_mid < min_height:
						continue
					
					var distance_vert: float = tile.height_mid - action_instance.user.tile_position.height_mid # TODO should vert tolerance count to top surface of water?
					if action_instance.action.targeting_los:
						var collider = Raycaster.raycast(action_instance.user.tile_position.get_world_position() + Vector3.UP, tile.get_world_position() + Vector3.UP) # TODO adjust for different height sprites: chicken, frog, Altima
						if is_instance_valid(collider):
							if collider is CharacterBody3D:
								var intersected_unit: Unit = collider.get_parent_node_3d()
								if intersected_unit.tile_position != tile:
									continue
						# TODO fix raycast?
					if action_instance.action.cant_target_self and tile == action_instance.user.tile_position:
						continue
					elif distance_xy >= action_instance.action.min_targeting_range and distance_xy <= action_instance.action.max_targeting_range:
						if not action_instance.action.has_vertical_tolerance_from_user:
							potential_targets.append(tile)
						elif abs(distance_vert) <= action_instance.action.vertical_tolerance:
							potential_targets.append(tile)
					
					# TODO arc https://ffhacktics.com/wiki/Arc_Range_Calculation_Routine
			
			if Time.get_ticks_msec() - start_time > max_frame_time_ms: # prevent freezing/lag
				await action_instance.user.get_tree().process_frame
				start_time = Time.get_ticks_msec()
	
	return potential_targets


func start_targeting(action_instance: ActionInstance) -> void:
	if not action_instance.action.auto_target:
		super.start_targeting(action_instance)
		
		if not action_instance.battle_manager.map_input_event.is_connected(action_instance.on_map_input_event):
			action_instance.battle_manager.map_input_event.connect(action_instance.on_map_input_event)
		
		for unit: Unit in action_instance.battle_manager.units:
			if not unit.unit_input_event.is_connected(action_instance.on_unit_hovered):
				unit.unit_input_event.connect(action_instance.on_unit_hovered)
		
		if not action_instance.tile_hovered.is_connected(target_tile):
			action_instance.tile_hovered.connect(target_tile)
		
	else: # TODO auto targeting for reactions and all enimies/allies for dance/sing?
		action_instance.preview_targets.append(action_instance.user.tile_position)
		action_instance.submitted_targets = action_instance.preview_targets
		await action_instance.queue_use()


func stop_targeting(action_instance: ActionInstance) -> void:
	# clear old target previews
	for preview: ActionPreview in action_instance.action_previews:
		preview.queue_free()
	action_instance.action_previews.clear()
	
	if action_instance.battle_manager.map_input_event.is_connected(action_instance.on_map_input_event):
		action_instance.battle_manager.map_input_event.disconnect(action_instance.on_map_input_event)
	
	for unit: Unit in action_instance.battle_manager.units:
		if unit.unit_input_event.is_connected(action_instance.on_unit_hovered):
			unit.unit_input_event.disconnect(action_instance.on_unit_hovered)
	
	if action_instance.tile_hovered.is_connected(target_tile):
			action_instance.tile_hovered.disconnect(target_tile)


func target_tile(tile: TerrainTile, action_instance: ActionInstance, event: InputEvent) -> void:
	if action_instance.battle_manager.active_unit != action_instance.user:
		stop_targeting(action_instance)
		return
	
	if tile != action_instance.current_tile_hovered:
		action_instance.current_tile_hovered = tile
		
		# show preview targets
		action_instance.clear_targets(action_instance.preview_targets_highlights)
		action_instance.preview_targets.clear()
		
		action_instance.preview_targets = get_aoe_targets(action_instance, tile)
		# TODO if targeting_los show line
		
		if action_instance.potential_targets.has(tile):
			action_instance.preview_targets_highlights = action_instance.get_tile_highlights(action_instance.preview_targets, action_instance.battle_manager.tile_highlights[Color.RED])
		else:
			action_instance.preview_targets_highlights = action_instance.get_tile_highlights(action_instance.preview_targets, action_instance.battle_manager.tile_highlights[Color.WHITE])
		
		action_instance.show_targets_highlights(action_instance.preview_targets_highlights)
		
		# clear old target previews
		for preview: ActionPreview in action_instance.action_previews:
			preview.queue_free()
		action_instance.action_previews.clear()
		
		# show target previews
		for preview_tile: TerrainTile in action_instance.preview_targets:
			for unit: Unit in action_instance.battle_manager.units:
				if unit.tile_position == preview_tile and (unit.get_nullify_statuses().is_empty() or unit.get_nullify_statuses().any(
						func(status: StatusEffect) -> bool: return action_instance.action.will_remove_target_status and action_instance.action.target_status_list.has(status.unique_name))): # ignore action unless it would remove nullify
					action_instance.show_result_preview(unit)
					break
	
	if not action_instance.potential_targets.has(tile):
		return
	
	# handle clicking tile
	if event.is_action_pressed("primary_action"):
		action_instance.submitted_targets = action_instance.preview_targets
		#action_instance.submitted_targets.append(tile)
		await action_instance.queue_use()
		return


func get_aoe_targets(action_instance: ActionInstance, tile_target: TerrainTile) -> Array[TerrainTile]:
	# TODO aoe flags: linear, 3 directions, direct, vertical tolerance, top-down
	# TODO fix multiple highlighting?
	var aoe_targets: Array[TerrainTile] = []
	#action_instance.user.get_map_paths(action_instance.battle_manager.total_map_tiles, action_instance.battle_manager.units)
	
	var target_relative_user: Vector2i = tile_target.location - action_instance.user.tile_position.location
	
	if action_instance.action.aoe_targeting_linear:
		if target_relative_user.x != 0 and target_relative_user.y != 0:
			aoe_targets.append(tile_target)
			return aoe_targets
	
	var min_tile_pos: Vector2i = tile_target.location - Vector2i(action_instance.action.area_of_effect_range, action_instance.action.area_of_effect_range)
	var max_tile_pos: Vector2i = tile_target.location + Vector2i(action_instance.action.area_of_effect_range, action_instance.action.area_of_effect_range)
	
	for map_x: int in range(min_tile_pos.x, max_tile_pos.x + 1):
		for map_y: int in range(min_tile_pos.y, max_tile_pos.y + 1):
			var map_pos: Vector2i = Vector2i(map_x, map_y)
			if action_instance.battle_manager.total_map_tiles.has(map_pos):
				var relative_pos_target: Vector2i = map_pos - tile_target.location
				#if action_instance.action.aoe_targeting_linear:
				var relative_pos_user: Vector2i = map_pos - action_instance.user.tile_position.location
				#var target_relative_user: Vector2i = tile_target.location - action_instance.user.tile_position.location
				
				var distance_xy: int = abs(relative_pos_target.x) + abs(relative_pos_target.y)
				
				if action_instance.action.aoe_targeting_linear:
					distance_xy = abs(relative_pos_user.x) + abs(relative_pos_user.y)
					if ((relative_pos_user.x != 0 and relative_pos_user.y != 0)
							or not Vector2(relative_pos_user).normalized().is_equal_approx(Vector2(target_relative_user).normalized())):
						continue
				
				var min_height: float = 0
				if action_instance.action.targeting_top_down:
					var map_tiles_at_pos: Array[TileData] = action_instance.battle_manager.total_map_tiles[map_pos].duplicate()
					if map_tiles_at_pos.size() > 1:
						map_tiles_at_pos.sort_custom(func(a: TileData, b: TileData) -> bool: return a.height_mid > b.height_mid)
						min_height = map_tiles_at_pos[0].height_mid
						
				
				for tile: TerrainTile in action_instance.battle_manager.total_map_tiles[map_pos]:
					if action_instance.action.targeting_top_down and tile.height_mid < min_height:
						continue
					
					var distance_vert: float = tile.height_mid - tile_target.height_mid # TODO should vert tolerance count to top surface of water?
					if action_instance.action.aoe_targeting_los:
						var collider = Raycaster.raycast(tile_target.get_world_position() + Vector3.UP, tile.get_world_position() + Vector3.UP) # TODO adjust for different height sprites: chicken, frog, Altima
						if is_instance_valid(collider):
							if collider is CharacterBody3D:
								var intersected_unit: Unit = collider.get_parent_node_3d()
								if intersected_unit.tile_position != tile:
									continue
						# TODO fix raycast?
					if action_instance.action.cant_hit_user and tile == action_instance.user.tile_position:
						continue
					elif distance_xy <= action_instance.action.area_of_effect_range:
						if not action_instance.action.aoe_has_vertical_tolerance:
							aoe_targets.append(tile)
						elif abs(distance_vert) <= action_instance.action.aoe_vertical_tolerance:
							aoe_targets.append(tile)
	
	return aoe_targets
