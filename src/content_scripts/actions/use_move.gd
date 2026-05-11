class_name MoveUse
extends UseStrategy

func use(action_instance: ActionInstance) -> void:
	var map_path: Array[TerrainTile] = action_instance.submitted_targets.duplicate()
	
	action_instance.clear() # clear all highlighting and target data
	await travel_path(action_instance.user, map_path)
	
	action_instance.battle_manager.update_units_pathfinding()
	action_instance.action_completed.emit(action_instance.battle_manager)


func walk_to_tile(user: Unit, to_tile: TerrainTile) -> void:
	var distance_to_move: float = user.tile_position.location.distance_to(to_tile.location)
	var immediate_path: Vector3 = to_tile.get_world_position() - user.tile_position.get_world_position()
	if distance_to_move > 1.1: # TODO is leaping the only case where moving more than 1 distance at a time?
		user.char_body.velocity.y = 1.1 * distance_to_move # hop over intermediate tiles
	elif to_tile.height_mid - user.tile_position.height_mid >= 3:
		user.update_unit_facing(immediate_path)
		var vert_distance: float = (to_tile.height_mid - user.tile_position.height_mid) * FftMapData.HEIGHT_SCALE
		user.char_body.velocity.y = sqrt(vert_distance) * 4.5 # jump for steep changes in height, to get to bridges that don't have walls
		await user.get_tree().create_timer(vert_distance * 0.19).timeout
	else:
		user.current_animation_id_fwd = user.walk_to_animation_id
	await process_physics_move(user, to_tile.get_world_position())
	user.tile_position = to_tile
	
	while not user.char_body.is_on_floor():
		await user.get_tree().process_frame
	
	user.tile_position = to_tile
	user.reached_tile.emit()


func process_physics_move(user: Unit, target_position: Vector3) -> void:
	var speed: float = 4.0
	var current_xy: Vector2 = Vector2(user.char_body.global_position.x, user.char_body.global_position.z)
	var target_xy: Vector2 = Vector2(target_position.x, target_position.z)
	var distance_left: float = current_xy.distance_to(target_xy)
	
	while distance_left > 0.05: # char_body.position is about 0.25 off the ground
		current_xy = Vector2(user.char_body.global_position.x, user.char_body.global_position.z)
		var direction: Vector2 = current_xy.direction_to(target_xy)
		#direction.y = 0
		var velocity_2d: Vector2 = direction * speed
		distance_left = current_xy.distance_to(target_xy)
		velocity_2d = velocity_2d.limit_length(distance_left / user.get_physics_process_delta_time())
		user.char_body.velocity.x = velocity_2d.x
		user.char_body.velocity.z = velocity_2d.y
		if (user.char_body.is_on_wall() # TODO implement jumping and leaping correctly
				and target_position.y + 0.25 > user.char_body.global_position.y
				and user.char_body.velocity.y <= 0.1): # TODO fix comparing target position to charbody, char_body's position is offset from the ground
			user.char_body.velocity.y = sqrt((target_position.y + 0.25) - user.char_body.global_position.y) * 4.5
		await user.get_tree().physics_frame
	
	#char_body.velocity = Vector3.ZERO
	user.char_body.velocity.x = 0
	user.char_body.velocity.z = 0


#func sort_ascending(a_idx: int, b_idx: int):
	#if a.cost < b.cost:
		#return true
	#return false


func travel_path(user: Unit, path: Array[TerrainTile]) -> void:
	user.is_traveling_path = true
	var initial_pos: Vector2i = user.tile_position.location
	for tile: TerrainTile in path:
		await walk_to_tile(user, tile) # TODO handle movement types other than walking
	
	await user.get_tree().process_frame # wait one extra frame to allow for landing
	#animation_manager.global_animation_ptr_id = current_idle_animation_id
	#user.current_animation_id_fwd = user.current_idle_animation_id
	user.set_base_animation_ptr_id(user.current_idle_animation_id)
	user.is_traveling_path = false
	var distance_moved: Vector2i = (user.tile_position.location - initial_pos).abs()
	var tiles_moved: int = distance_moved.x + distance_moved.y
	# user.completed_move.emit(user, tiles_moved)
	for connection in user.completed_move.get_connections():
		await connection["callable"].call(user, tiles_moved)
