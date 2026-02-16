class_name ActionInstance
extends RefCounted

signal action_completed(battle_manager: BattleManager)
signal tile_hovered(tile: TerrainTile, action_instance: ActionInstance)

var action: Action
var user: Unit
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

var action_preview_scene: PackedScene = preload("res://src/content_scripts/actions/action_preview.tscn")
var action_previews: Array[ActionPreview] = []

func _init(new_action: Action, new_user: Unit, new_battle_manager: BattleManager) -> void:
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
	return action.is_usable(self)


func update_potential_targets() -> void:
	clear_targets(potential_targets_highlights)
	potential_targets.clear()
	
	potential_targets = action.targeting_strategy.get_potential_targets(self)
	update_potential_targets_highlights()
	
	potential_targets_are_set = true


func update_potential_targets_highlights() -> void:
	var highlight_material: Material = battle_manager.tile_highlights[Color.WHITE]
	if is_usable():
		highlight_material = battle_manager.tile_highlights[Color.BLUE]
	
	potential_targets_highlights = get_tile_highlights(potential_targets, highlight_material)


func show_potential_targets() -> void:
	if not potential_targets_are_set:
		update_potential_targets()
	show_targets_highlights(potential_targets_highlights)


func hide_potential_targets() -> void:
	show_targets_highlights(potential_targets_highlights, false)


func show_targets_highlights(targets_highlights: Dictionary[TerrainTile, Node3D], show: bool = true) -> void:
	for highlight: Node3D in targets_highlights.values():
		highlight.visible = show


func get_tile_highlights(tiles: Array[TerrainTile], highlight_material: Material) -> Dictionary[TerrainTile, Node3D]:
	var tile_highlights: Dictionary[TerrainTile, Node3D]
	for tile: TerrainTile in tiles:
		var new_tile_highlight: MeshInstance3D = tile.get_tile_mesh()
		new_tile_highlight.material_override = highlight_material # use pre-existing materials
		user.tile_highlights.add_child(new_tile_highlight)
		new_tile_highlight.position = tile.get_world_position(true) + Vector3(0, 0.025, 0)
		new_tile_highlight.visible = false
		tile_highlights[tile] = new_tile_highlight
	
	return tile_highlights


func start_targeting() -> void:
	user.global_battle_manager.game_state_label.text = user.job_nickname + "-" + user.unit_nickname + " targeting " + action.display_name
	
	# cancel any current targeting
	if is_instance_valid(user.active_action):
		user.active_action.stop_targeting()
	user.active_action = self
	action.targeting_strategy.start_targeting(self)


func stop_targeting() -> void:
	show_targets_highlights(potential_targets_highlights, false)
	show_targets_highlights(preview_targets_highlights, false)
	clear_targets(preview_targets_highlights)
	
	for preview: ActionPreview in action_previews:
		preview.queue_free()
	action_previews.clear()
	
	action.targeting_strategy.stop_targeting(self)


func get_target_units(target_tiles: Array[TerrainTile]) -> Array[Unit]:
	var target_units: Array[Unit] = []
	for target_tile: TerrainTile in target_tiles:
		var units_on_tile: Array[Unit] = battle_manager.units.filter(func(unit: Unit) -> bool: return unit.tile_position == target_tile)
		
		for unit: Unit in units_on_tile:
			if unit.get_nullify_statuses().is_empty(): # TODO check all passives not just statuses
				target_units.append(unit)
				continue
			
			var action_ignores_all_null_statuses: bool = unit.get_nullify_statuses().all(
				func(status: StatusEffect) -> bool: return action.ignores_statuses.has(status.unique_name))
			var action_removes_null_status: bool = unit.get_nullify_statuses().any(
				func(status: StatusEffect) -> bool: return action.will_remove_target_status and action.target_status_list.has(status.unique_name)) # ignore action unless it would remove nullify
		
			if action_ignores_all_null_statuses or action_removes_null_status:
				target_units.append(unit)

		# units_on_tile = units_on_tile.filter(
		# 	func(unit: Unit): return unit.get_nullify_statuses().is_empty() or action_ignores_all_null_statuses(unit) or action_removes_null_status(unit))
		# target_units.append_array(units_on_tile)
		#if unit_index == -1:
			#continue
		#var target_unit: Unit = battle_manager.units[unit_index]
		#target_units.append(target_unit)
	
	return target_units


# func action_ignores_all_null_statuses(unit: Unit) -> bool:
# 	return unit.get_nullify_statuses().all(
# 			func(status: StatusEffect): return action.ignores_statuses.has(status.status_id))


# func action_removes_null_status(unit: Unit) -> bool:
# 	return unit.get_nullify_statuses().any(
# 			func(status: StatusEffect): return action.will_remove_status and action.target_status_list.has(status.status_id)) # ignore action unless it would remove nullify


func get_ai_score() -> int:
	# https://ffhacktics.com/smf/index.php?topic=11590.0
	# Target Value Formula
	# (HP Value[curHP * 128 / maxHP] + Total Status Values + (51 * # of items broken up to 7) + Caster Hate [(curMP% / 16) * # MP using Abilities, 0 if not enough MP] + Golem Fear [CurGolem * 128 / Average Team HP (- 1 if Golem not damaged)]) * (-1 if unit is Enemy, 1 if ally)


	var ai_score: int = 0
	var target_units: Array[Unit] = get_target_units(preview_targets)
	
	for target: Unit in target_units:
		var target_score: float = 0.0
		for action_effect: ActionEffect in action.target_effects:
			var effect_value: int = action_effect.get_ai_value(user, target, action.element)
			target_score += effect_value
		
		var evade_direction: EvadeData.Directions = action.get_evade_direction(user, target)
		var hit_chance_value: int = action.get_total_hit_chance(user, target, evade_direction)
		hit_chance_value = clamp(hit_chance_value, 0, 100)
		target_score = target_score * (hit_chance_value / 100.0)
		
		# status scores
		var total_status_score: float = 0.0
		for status_id: String in action.target_status_list:
			var status: StatusEffect = RomReader.status_effects[status_id]
			var status_score: float = status.get_ai_score(user, target, action.will_remove_target_status)
			if action.target_status_list_type == Action.StatusListType.ALL:
				status_score = status_score * action.target_status_chance
			elif action.target_status_list_type == Action.StatusListType.EACH:
				status_score = status_score * action.target_status_chance
			total_status_score += status_score
		
		if action.target_status_list_type == Action.StatusListType.RANDOM:
			total_status_score = total_status_score / action.target_status_list.size()
		
		ai_score += roundi(target_score) + roundi(total_status_score)
		#push_warning(action.action_name + " " + str(preview_targets) + " " + str(ai_score))
	
	return ai_score


func show_result_preview(target: Unit) -> ActionPreview:
	var hit_chance_text: String = get_hit_chance_text(target)
	var effects_text: String = get_effects_text(target)
	var statuses_text: String = get_statuses_text(target)
	var secondary_actions_text: String = get_secondary_actions_text(target)
	
	var all_text: PackedStringArray = [hit_chance_text, effects_text, statuses_text, secondary_actions_text]
	for text_idx: int in range(all_text.size() - 1, -1, -1):
		if all_text[text_idx] == "":
			all_text.remove_at(text_idx)
	
	var total_preview_text: String = "\n".join(all_text)
	
	var preview: ActionPreview = action_preview_scene.instantiate()
	preview.label.text = total_preview_text
	preview.unit = target
	target.char_body.add_child(preview)
	
	action_previews.append(preview)
	
	return preview


func get_hit_chance_text(target: Unit) -> String:
	# hit chance preview
	var evade_direction: EvadeData.Directions = action.get_evade_direction(user, target)
	var hit_chance_value: int = action.get_total_hit_chance(user, target, evade_direction)
	var hit_chance_text: String = str(hit_chance_value) + "% Hit"
	
	return hit_chance_text


func get_effects_text(target: Unit) -> String:
	# effect preview
	var all_effects_text: PackedStringArray = []
	for action_effect: ActionEffect in action.target_effects:
		var effect_value: int = action_effect.get_value(user, target, action.element)
		var effect_text: String = action_effect.get_text(effect_value)
		all_effects_text.append(effect_text)
	
	var total_effect_text: String = "/n".join(all_effects_text)
	return total_effect_text


func get_statuses_text(target: Unit) -> String:
	# status preview
	if action.target_status_list.is_empty():
		return ""
	
	var status_chance: String = str(action.target_status_chance) + "%"
	var remove_status: String = ""
	if action.will_remove_target_status:
		remove_status = "Remove "
	var status_group_type: String = Action.StatusListType.keys()[action.target_status_list_type] + " "
	if action.target_status_list.size() < 2:
		status_group_type = "" # don't mention group type if 1 or less status
	
	var status_names: PackedStringArray = []
	for status_id: String in action.target_status_list:
		if not action.will_remove_target_status or target.current_status_ids.has(status_id): # don't show removing status the target does not have TODO don't show remove Always statuses
			status_names.append(RomReader.status_effects[status_id].status_effect_name)
	
	if status_names.is_empty() and action.will_remove_target_status:
		status_names = ["[No status to remove]"]
	
	var total_status_text: String = status_chance + " " + remove_status + status_group_type + ", ".join(status_names)
	return total_status_text


func get_secondary_actions_text(_target: Unit) -> String:
	# TODO show effects and statuses from secondary actions?
	if action.secondary_actions2.is_empty():
		return ""
	
	var total_secondary_action_text: String = Action.StatusListType.keys()[action.secondary_action_list_type] + "\n"
	if action.secondary_actions2.size() < 2:
		total_secondary_action_text = "" # don't show list type if only 1 entry in list
	
	var all_secondary_action_text: PackedStringArray = []
	for secondary_action: Action.SecondaryAction in action.secondary_actions2:
		var secondary_action_chance: String = str(secondary_action.chance) + "%"
		#var secondary_action_effect_text: String = secondary_action.ac # TODO get effect text of secondary action?
		var secondary_action_text: String = secondary_action_chance + " " + RomReader.actions[secondary_action.action_unique_name].display_name
		all_secondary_action_text.append(secondary_action_text)
	
	total_secondary_action_text += "\n".join(all_secondary_action_text)
	return total_secondary_action_text


func on_map_input_event(_camera: Camera3D, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	#push_warning(event_position)
	var tile: TerrainTile = battle_manager.get_tile(event_position)
	if tile == null:
		return
	
	tile_hovered.emit(tile, self, event)


func on_unit_hovered(unit: Unit, event: InputEvent) -> void:
	var tile: TerrainTile = unit.tile_position
	if tile == null:
		return
	
	tile_hovered.emit(tile, self, event)


func queue_use() -> void:
	battle_manager.game_state_label.text = user.job_nickname + "-" + user.unit_nickname + " using " + action.display_name
	battle_manager.safe_to_load_map = false
	
	user.clear_action_buttons(battle_manager)
	if deduct_action_points:
		pay_action_point_costs()
	face_target()
	
	# TODO check for passive_effects that modify charge time? Or Maybe charge time should be modified earlier than this so AI can consider the modified value
	if action.ticks_charge_time > 0:
		var charging_status: StatusEffect = RomReader.status_effects["charging"].duplicate() # charging
		charging_status.delayed_action = self.duplicate()
		charging_status.duration = action.ticks_charge_time
		charging_status.duration_type = StatusEffect.DurationType.TICKS
		if charging_status.delayed_action.action_completed.is_connected(charging_status.delayed_action.user.update_actions):
			charging_status.delayed_action.action_completed.disconnect(charging_status.delayed_action.user.update_actions)
		await user.add_status(charging_status)
		
		stop_targeting()
		action_completed.emit(battle_manager)
	else:
		await use()
	battle_manager.safe_to_load_map = true


func use() -> void:
	if battle_manager == null: # TODO correctly handle updating passive_effects, statuses, etc. outside of battle
		return
	
	stop_targeting()
	
	await action.use(self)


func pay_action_point_costs() -> void:
	user.move_points_remaining -= action.move_points_cost
	user.action_points_remaining -= action.action_points_cost


func face_target() -> void:
	if submitted_targets.is_empty():
		push_warning(action.display_name + ": no submitted targets")
		return
	
	if submitted_targets[0] != user.tile_position:
		var direction_to_target: Vector2i = submitted_targets[0].location - user.tile_position.location
		user.update_unit_facing(Vector3(direction_to_target.x, 0, direction_to_target.y))
