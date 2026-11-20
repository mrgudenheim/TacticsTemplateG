class_name ActionInstance
extends RefCounted

signal action_completed()
signal tile_hovered(tile: TerrainTile, action_instance: ActionInstance)

var action: Action
var user: UnitData
var battle_manager: BattleManager

var potential_targets: Array[TerrainTile]
var potential_targets_highlights: Dictionary[TerrainTile, Node3D]
var preview_targets: Array[TerrainTile]
var preview_targets_highlights: Dictionary[TerrainTile, Node3D]
var submitted_targets: Array[TerrainTile]
var allow_triggering_actions: bool = true
var deduct_action_points: bool = true

var current_tile_hovered: TerrainTile
var potential_targets_are_set: bool = false

var action_preview_scene: PackedScene = preload("uid://c8f4elqq81b37")
var action_previews: Array[ActionPreview] = []

func _init(new_action: Action, new_user: UnitData, new_battle_manager: BattleManager) -> void:
	action = new_action
	user = new_user
	battle_manager = new_battle_manager

	allow_triggering_actions = action.allow_triggered_actions


func duplicate() -> ActionInstance:
	var new_action_instance: ActionInstance = ActionInstance.new(action, user, battle_manager)
	new_action_instance.potential_targets = potential_targets.duplicate()
	new_action_instance.preview_targets = preview_targets.duplicate()
	new_action_instance.submitted_targets = submitted_targets.duplicate()
	new_action_instance.current_tile_hovered = current_tile_hovered
	
	return new_action_instance


func clear() -> void:
	clear_targets(potential_targets_highlights)
	potential_targets.clear()
	
	clear_targets(preview_targets_highlights)
	preview_targets.clear()
	
	submitted_targets.clear()


func clear_targets(target_highlights: Dictionary[TerrainTile, Node3D]) -> void:
	for highlight: Node3D in target_highlights.values():
		highlight.queue_free()
	
	target_highlights.clear()


func is_usable() -> bool:
	var action_is_usable: bool = false
	if action.useable_strategy == null: # default usable check
		var user_has_enough_move_points: bool = (not deduct_action_points) or (user.move_points_remaining >= action.move_points_cost)
		var user_has_enough_action_points: bool = (not deduct_action_points) or (user.action_points_remaining >= action.action_points_cost)
		var user_has_enough_mp: bool = user.stats[UnitData.StatType.MP].current_value >= action.mp_cost
		var user_has_equipment_type: bool = false
		if action.required_equipment_type.is_empty():
			user_has_equipment_type = true
		else:
			for equipment_slot: EquipmentSlot in user.equip_slots:
				if action.required_equipment_type.has(equipment_slot.get_item().item_type): # TODO allow actions that require combination of item types?
					user_has_equipment_type = true
					break
		
		var user_has_equipment: bool = false
		if action.required_equipment_unique_name.is_empty():
			user_has_equipment = true
		else:
			for equipment_slot: EquipmentSlot in user.equip_slots:
				if action.required_equipment_unique_name.has(equipment_slot.item_unique_name): # TODO allow actions that require combination of items
					user_has_equipment = true
					break
		
		var action_not_prevented_by_status: bool = not action.status_prevents_use_any.any(func(status_id: String) -> bool: return user.get_current_status_ids().has(status_id))
		
		action_is_usable = (user_has_enough_move_points 
				and user_has_enough_action_points 
				and user_has_enough_mp
				and action_not_prevented_by_status
				and user_has_equipment_type
				and user_has_equipment)
	else: # custom usable check
		action_is_usable = action.useable_strategy.is_usable(self)
		
	return action_is_usable


func update_potential_targets() -> void:
	clear_targets(potential_targets_highlights)
	potential_targets.clear()
	
	@warning_ignore("redundant_await") # inherited targeting strategies may be coroutines
	potential_targets = await action.targeting_strategy.get_potential_targets(self)
	update_potential_targets_highlights()
	
	potential_targets_are_set = true


func update_potential_targets_highlights() -> void:
	var highlight_material: Material = battle_manager.tile_highlights[Color.WHITE]
	if is_usable():
		highlight_material = battle_manager.tile_highlights[Color.BLUE]
	
	potential_targets_highlights = get_tile_highlights(potential_targets, highlight_material)


func show_potential_targets() -> void:
	if not potential_targets_are_set:
		await update_potential_targets()
	show_targets_highlights(potential_targets_highlights)


func hide_potential_targets() -> void:
	show_targets_highlights(potential_targets_highlights, false)


func show_targets_highlights(targets_highlights: Dictionary[TerrainTile, Node3D], show: bool = true) -> void:
	for highlight: Node3D in targets_highlights.values():
		highlight.visible = show


func get_tile_highlights(tiles: Array[TerrainTile], highlight_material: Material) -> Dictionary[TerrainTile, Node3D]:
	var tile_highlights: Dictionary[TerrainTile, Node3D]
	var highlight_offset: Vector3 = Vector3(0, 0.025, 0)
	for tile: TerrainTile in tiles:
		var new_tile_highlight: MeshInstance3D = tile.get_tile_mesh()
		new_tile_highlight.material_override = highlight_material.duplicate() # use pre-existing materials
		user.unit_actor.tile_highlights.add_child(new_tile_highlight)
		new_tile_highlight.position = tile.get_world_position(true) + highlight_offset
		new_tile_highlight.material_override.set_shader_parameter("depth_position", tile.get_world_position() + highlight_offset)
		new_tile_highlight.visible = false
		tile_highlights[tile] = new_tile_highlight
	
	return tile_highlights


func start_targeting() -> void:
	battle_manager.game_state_label.text = user.job_data.display_name + "-" + user.display_name + " targeting " + action.display_name
	
	# cancel any current targeting
	if is_instance_valid(user.active_action):
		user.active_action.stop_targeting()
	user.active_action = self
	await action.targeting_strategy.start_targeting(self)


func stop_targeting() -> void:
	show_targets_highlights(potential_targets_highlights, false)
	show_targets_highlights(preview_targets_highlights, false)
	clear_targets(preview_targets_highlights)
	
	for preview: ActionPreview in action_previews:
		preview.queue_free()
	action_previews.clear()
	
	action.targeting_strategy.stop_targeting(self)


func get_ai_score() -> int:
	# https://ffhacktics.com/smf/index.php?topic=11590.0
	# Target Value Formula
	# (HP Value[curHP * 128 / maxHP] + Total Status Values + (51 * # of items broken up to 7) + Caster Hate [(curMP% / 16) * # MP using Abilities, 0 if not enough MP] + Golem Fear [CurGolem * 128 / Average Team HP (- 1 if Golem not damaged)]) * (-1 if unit is Enemy, 1 if ally)
	var preview_resolution: ActionResolution = ActionResolver.resolve(self, true)
	return roundi(_score_resolution_tree(preview_resolution, 1.0))


func _score_resolution_tree(resolution: ActionResolution, weight: float) -> float:
	if resolution == null or weight <= 0.0:
		return 0.0

	var effective_weight: float = weight * resolution.get_branch_probability()
	if effective_weight <= 0.0:
		return 0.0

	var total_score: float = 0.0
	for target_result: ActionTargetResult in resolution.target_results:
		var target_unit: UnitData = target_result.target_unit
		if target_unit == null:
			continue

		var hit_probability: float = clampf(float(target_result.hit_chance_percentage) / 100.0, 0.0, 1.0)
		var is_friendly: bool = (target_unit.team == user.team)

		var stat_score: float = 0.0
		if not target_result.was_defeated_before_hit or _result_removes_ko(resolution.action, target_result):
			for stat_type: UnitData.StatType in target_result.stat_deltas.keys():
				var stat_delta: int = target_result.stat_deltas[stat_type]
				stat_score += float(stat_delta if is_friendly else -stat_delta)

		var status_score: float = _score_result_statuses(resolution.action, target_result, target_unit, false)
		total_score += (stat_score + status_score) * hit_probability * effective_weight

		for target_sub_resolution: ActionResolution in target_result.target_sub_resolutions:
			total_score += _score_resolution_tree(target_sub_resolution, effective_weight * hit_probability)

	if resolution.user_result != null and resolution.user_result.target_unit != null:
		var user_stat_score: float = 0.0
		if not resolution.user_result.was_defeated_before_hit or _result_removes_ko(resolution.action, resolution.user_result, true):
			for stat_type: UnitData.StatType in resolution.user_result.stat_deltas.keys():
				user_stat_score += float(resolution.user_result.stat_deltas[stat_type])
		var user_status_score: float = _score_result_statuses(resolution.action, resolution.user_result, resolution.user_result.target_unit, true)
		total_score += (user_stat_score + user_status_score) * effective_weight

		for user_sub_resolution: ActionResolution in resolution.user_result.target_sub_resolutions:
			total_score += _score_resolution_tree(user_sub_resolution, effective_weight)

	for secondary_resolution: ActionResolution in resolution.secondary_resolutions:
		total_score += _score_resolution_tree(secondary_resolution, effective_weight)

	return total_score


func _score_result_statuses(
	action_data: Action,
	target_result: ActionTargetResult,
	target_unit: UnitData,
	is_user_result: bool
) -> float:
	if action_data == null or target_result.eligible_status_ids.is_empty():
		return 0.0

	var status_chance: int = action_data.user_status_chance if is_user_result else action_data.target_status_chance
	var status_list_type: Action.StatusListType = action_data.user_status_list_type if is_user_result else action_data.target_status_list_type
	var will_remove: bool = action_data.will_remove_user_status if is_user_result else action_data.will_remove_target_status
	var status_probability: float = clampf(float(status_chance) / 100.0, 0.0, 1.0)

	var total_status_score: float = 0.0
	for status_id: String in target_result.eligible_status_ids:
		var status_effect: StatusEffect = ActionResolver.lookup_status_effect(status_id)
		if status_effect == null:
			continue
		total_status_score += status_effect.get_ai_score(user, target_unit, will_remove)

	if status_list_type == Action.StatusListType.RANDOM:
		total_status_score = (total_status_score / float(target_result.eligible_status_ids.size())) * status_probability
	else:
		total_status_score = total_status_score * status_probability

	return total_status_score


func _result_removes_ko(action_data: Action, target_result: ActionTargetResult, is_user_result: bool = false) -> bool:
	if target_result.statuses_removed.has("dead"):
		return true
	if action_data != null:
		var will_remove: bool = action_data.will_remove_user_status if is_user_result else action_data.will_remove_target_status
		if will_remove and target_result.eligible_status_ids.has("dead"):
			return true
	return false


func show_result_previews() -> Array[ActionPreview]:
	var preview_resolution: ActionResolution = ActionResolver.resolve(self, true)
	for target: UnitData in preview_resolution.targeted_units:
		if not is_instance_valid(target) or target.unit_actor == null or target.unit_actor.char_body == null:
			continue
		var preview: ActionPreview = action_preview_scene.instantiate()
		preview.unit = target.unit_actor
		preview.set_from_resolution(preview_resolution, target)
		target.unit_actor.char_body.add_child(preview)
		action_previews.append(preview)
	return action_previews


func on_map_input_event(_camera: Camera3D, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	#push_warning(event_position)
	var tile: TerrainTile = battle_manager.get_tile(event_position)
	if tile == null:
		return
	
	tile_hovered.emit(tile, self, event)


func on_unit_hovered(unit: UnitActor, event: InputEvent) -> void:
	var tile: TerrainTile = unit.unit_data.terrain_tile_position
	if tile == null:
		return
	
	tile_hovered.emit(tile, self, event)


func queue_use() -> void:
	battle_manager.game_state_label.text = user.job_data.display_name + "-" + user.display_name + " using " + action.display_name
	battle_manager.safe_to_load_map = false
	
	battle_manager.clear_action_buttons()
	if deduct_action_points:
		pay_action_point_costs()
	face_target()
	
	# TODO check for passive_effects that modify charge time? Or Maybe charge time should be modified earlier than this so AI can consider the modified value
	if action.ticks_charge_time > 0:
		var charging_status: StatusEffect = GameData.get_status_effect("charging").duplicate() # charging
		charging_status.delayed_action = self.duplicate()
		charging_status.duration = action.ticks_charge_time
		charging_status.duration_type = StatusEffect.DurationType.TICKS
		if charging_status.delayed_action.action_completed.is_connected(charging_status.delayed_action.user.update_actions):
			charging_status.delayed_action.action_completed.disconnect(charging_status.delayed_action.user.update_actions)
		user.add_status(charging_status)
		
		stop_targeting()
		action_completed.emit()
	else:
		await use()
	battle_manager.safe_to_load_map = true


func use() -> void:
	if battle_manager == null: # TODO correctly handle updating passive_effects, statuses, etc. outside of battle
		return
	
	stop_targeting()
	
	if action.use_strategy == null: # default use
		await apply_standard()
	else:
		action.use_strategy.use(self)


func pay_action_point_costs() -> void:
	user.move_points_remaining -= action.move_points_cost
	user.action_points_remaining -= action.action_points_cost


func face_target() -> void:
	if submitted_targets.is_empty():
		push_warning(action.display_name + ": no submitted targets")
		return
	
	if submitted_targets[0] != user.terrain_tile_position:
		var direction_to_target: Vector2i = submitted_targets[0].xz_location - user.terrain_tile_position.xz_location
		user.update_unit_facing(Vector3(direction_to_target.x, 0, direction_to_target.y))


func apply_standard() -> void:
	var resolution: ActionResolution = ActionResolver.resolve(self)
	await ActionPresenter.play_resolution(resolution, battle_manager)
	clear()
	if is_instance_valid(user):
		action_completed.emit()
