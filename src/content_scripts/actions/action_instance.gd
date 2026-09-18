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

var action_preview_scene: PackedScene = preload("uid://c8f4elqq81b37")
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
	var action_is_usable: bool = false
	if action.useable_strategy == null: # default usable check
		var user_has_enough_move_points: bool = user.move_points_remaining >= action.move_points_cost
		var user_has_enough_action_points: bool = user.action_points_remaining >= action.action_points_cost
		var user_has_enough_mp: bool = user.mp >= action.mp_cost
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
		
		var action_not_prevented_by_status: bool = not action.status_prevents_use_any.any(func(status_id: String) -> bool: return user.current_status_ids.has(status_id))
		
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
		user.tile_highlights.add_child(new_tile_highlight)
		new_tile_highlight.position = tile.get_world_position(true) + highlight_offset
		new_tile_highlight.material_override.set_shader_parameter("depth_position", tile.get_world_position() + highlight_offset)
		new_tile_highlight.visible = false
		tile_highlights[tile] = new_tile_highlight
	
	return tile_highlights


func start_targeting() -> void:
	battle_manager.game_state_label.text = user.job_nickname + "-" + user.unit_nickname + " targeting " + action.display_name
	
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
		
		var evade_direction: EvadeData.Directions = get_evade_direction(user.tile_position, target)
		var hit_chance_value: int = action.get_total_hit_chance(user, target, evade_direction)
		hit_chance_value = clamp(hit_chance_value, 0, 100)
		target_score = target_score * (hit_chance_value / 100.0)
		
		# status scores
		var total_status_score: float = 0.0
		for status_id: String in action.target_status_list:
			var status: StatusEffect = GameData.get_status_effect(status_id)
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
	var evade_direction: EvadeData.Directions = get_evade_direction(user.tile_position, target)
	var hit_chance_value: int = get_total_hit_chance(target, evade_direction)
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
			status_names.append(GameData.get_status_effect(status_id).status_effect_name)
	
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
		var charging_status: StatusEffect = GameData.get_status_effect("charging").duplicate() # charging
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
	
	if submitted_targets[0] != user.tile_position:
		var direction_to_target: Vector2i = submitted_targets[0].location - user.tile_position.location
		user.update_unit_facing(Vector3(direction_to_target.x, 0, direction_to_target.y))


func get_total_hit_chance(target: Unit, evade_direction: EvadeData.Directions) -> int:
	var user_passive_effects: Array[PassiveEffect] = user.get_all_passive_effects(action.ignore_passives)
	var target_passive_effects: Array[PassiveEffect] = target.get_all_passive_effects(action.ignore_passives)
	
	if not action.required_target_job_uname.is_empty():
		var required_jobs: PackedStringArray = action.required_target_job_uname.duplicate()
		for passive_effect: PassiveEffect in user_passive_effects:
			required_jobs.append_array(passive_effect.add_applicable_target_jobs)

		if not required_jobs.has(target.job_data.unique_name):
			return 0
	
	if not action.required_target_status_uname.is_empty():
		var required_status: PackedStringArray = action.required_target_status_uname.duplicate()
		for passive_effect: PassiveEffect in user_passive_effects:
			required_status.append_array(passive_effect.add_applicable_target_statuses)
		
		if not Utilities.has_any_elements(target.current_status_ids, required_status):
			return 0

	if not action.required_target_stat_basis.is_empty():
		var required_basis: Array[Unit.StatBasis] = action.required_target_stat_basis.duplicate()
		for passive_effect: PassiveEffect in user_passive_effects:
			required_basis.append_array(passive_effect.add_applicable_target_stat_bases)

		if not required_basis.has(target.stat_basis):
			return 0
	
	var base_hit_chance: float = action.base_hit_formula.get_result(user, target, action.element)
	var modified_hit_chance: float = base_hit_chance
	if action.passive_power_modifier_applies_to_hit_chance:
		for passive_effect: PassiveEffect in user_passive_effects:
			modified_hit_chance = passive_effect.power_modifier_user.apply(roundi(modified_hit_chance), user)
		for passive_effect: PassiveEffect in target_passive_effects:
			modified_hit_chance = passive_effect.power_modifier_targeted.apply(roundi(modified_hit_chance), target)
	else:
		for passive_effect: PassiveEffect in user_passive_effects:
			modified_hit_chance = passive_effect.hit_chance_modifier_user.apply(roundi(modified_hit_chance), user)
		for passive_effect: PassiveEffect in target_passive_effects:
			modified_hit_chance = passive_effect.hit_chance_modifier_targeted.apply(roundi(modified_hit_chance), target)

	var evade_values: Dictionary[EvadeData.EvadeSource, int] = target.get_evade_values(action.applicable_evasion_type, evade_direction)
	
	var target_total_evade_factor: float = 1.0
	var evade_factors: Dictionary[EvadeData.EvadeSource, float] = {}
	if action.applicable_evasion_type != EvadeData.EvadeType.NONE:
		for evade_source: EvadeData.EvadeSource in evade_values.keys():
			if target_passive_effects.any(func(passive_effect: PassiveEffect) -> bool: return passive_effect.include_evade_sources.has(evade_source)):
				var evade_value: float = evade_values[evade_source]
				for passive_effect: PassiveEffect in user_passive_effects:
					if passive_effect.evade_source_modifiers_user.has(evade_source):
						evade_value = passive_effect.evade_source_modifiers_user[evade_source].apply(roundi(evade_value))
				
				for passive_effect: PassiveEffect in target_passive_effects:
					if passive_effect.evade_source_modifiers_targeted.has(evade_source):
						evade_value = passive_effect.evade_source_modifiers_targeted[evade_source].apply(roundi(evade_value))
				
				var evade_factor: float = max(0.0, 1 - (evade_value / 100.0))

				evade_factors[evade_source] = evade_factor
				target_total_evade_factor = target_total_evade_factor * evade_factor

		target_total_evade_factor = max(0, target_total_evade_factor) # prevent negative evasion
	
	var total_hit_chance: int = roundi(modified_hit_chance * target_total_evade_factor)
	
	return roundi(total_hit_chance)


func get_evade_direction(origin_tile: TerrainTile, target: Unit) -> EvadeData.Directions:
	var relative_position: Vector2i = origin_tile.location - target.tile_position.location
	var relative_facing_position: Vector2i = relative_position
	if target.facing == Unit.Facings.NORTH:
		pass # relative position is already correct for North facing
	elif target.facing == Unit.Facings.EAST:
		relative_facing_position = Vector2i(-relative_position.y, relative_position.x)
	elif target.facing == Unit.Facings.SOUTH:
		relative_facing_position = -relative_position
	elif target.facing == Unit.Facings.WEST:
		relative_facing_position = Vector2i(relative_position.y, -relative_position.x)
	
	# check target facing, check x>y
	var evade_direction: EvadeData.Directions = EvadeData.Directions.FRONT
	if relative_facing_position.y < 0:
		evade_direction = EvadeData.Directions.BACK
		if abs(relative_facing_position.x) >= abs(relative_facing_position.y):
			evade_direction = EvadeData.Directions.SIDE
	elif abs(relative_facing_position.x) > abs(relative_facing_position.y):
		evade_direction = EvadeData.Directions.SIDE
	
	return evade_direction


func get_evade_values(target: Unit, evade_direction: EvadeData.Directions) -> Dictionary[EvadeData.EvadeSource, int]:
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = {}
	for evade_source: int in EvadeData.EvadeSource.size():
		var evade_value: int = target.get_evade(evade_source, action.applicable_evasion_type, evade_direction)
		evade_values[evade_source] = evade_value
	
	return evade_values


func animate_evade(target_unit: Unit, evade_direction: EvadeData.Directions, user_pos: Vector2i) -> void:
	var target_original_facing: Vector3 = target_unit.facing_vector
	
	var dir_to_target: Vector2i = user_pos - target_unit.tile_position.location
	var temp_facing: Vector3 = Vector3(dir_to_target.x, 0, dir_to_target.y).normalized()
	target_unit.update_unit_facing(temp_facing)
	
	# var evade_anim_id: int = -1
	var sum_of_weight: int = 0
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = target_unit.get_evade_values(action.applicable_evasion_type, evade_direction)
	for evade_source_value: int in evade_values.values():
		sum_of_weight += evade_source_value
	
	if sum_of_weight <= 0: # missed due to action base hit chance
		await target_unit.animate_evade(EvadeData.animation_ids[0])
	else:
		var rnd: int = randi_range(0, sum_of_weight)
		for evade_source_idx: int in evade_values.size():
			var evade_source_value: int = evade_values[evade_source_idx]
			if rnd < evade_source_value:
				await target_unit.animate_evade(EvadeData.animation_ids[evade_source_idx])
				break
			rnd -= evade_source_value
	
	target_unit.update_unit_facing(target_original_facing)


## This action's ability effect on `target_unit`, drawn by
## `addons/exmateria_effects`. Returns the cast so the caller can time against it, or
## null when this action has no effect or playback is unavailable.
##
## `char_body`, never the `Unit` node — a `Unit` sits at the world origin for the whole
## battle (see `EffectsPlayback.play_action_vfx`, which refuses one). It is also the node
## that moves when a unit walks, so an effect following it stays on the unit.
func show_vfx(target_unit: Unit) -> Node3D:
	var playback: EffectsPlayback = _effects_playback()
	if playback == null or not is_instance_valid(target_unit):
		return null
	if user.char_body == null or target_unit.char_body == null:
		return null
	return playback.play_action_vfx(user.char_body, target_unit.char_body, action)


## The TRAP handlers (hit clouds, knight break, charge poses). The handler id and element
## come from this action's own ROM tables — see `EffectsPlayback.play_shared_vfx` for why
## they are passed rather than derived from an ability id.
func show_shared_vfx(shared_vfx_handler_id: int, target_unit: Unit) -> void:
	var playback: EffectsPlayback = _effects_playback()
	if playback == null or shared_vfx_handler_id <= 0 or not is_instance_valid(target_unit):
		return
	playback.play_shared_vfx(
		shared_vfx_handler_id,
		TrapEffectData.element_type_to_trap_id(action.element),
		user.char_body.global_position,
		target_unit.char_body,
		shared_vfx_handler_id in TrapEffectData.FLASH_HANDLER_IDS,
		action.projectile_type == ProjectileEffectInstance.ProjectileType.NONE)


func _effects_playback() -> EffectsPlayback:
	if battle_manager == null or not is_instance_valid(battle_manager.effects_playback):
		return null
	return battle_manager.effects_playback


func show_projectile(target_unit: Unit, new_projectile_type: ProjectileEffectInstance.ProjectileType) -> void:
	if new_projectile_type == ProjectileEffectInstance.ProjectileType.NONE:
		return
	
	if battle_manager == null or battle_manager.projectile_instance == null:
		push_warning("[Action.show_projectile] battle_manager or projectile_instance is null")
		return
	var origin: Vector3 = user.char_body.global_position
	var target: Vector3 = target_unit.char_body.global_position
	battle_manager.projectile_instance.play(origin, target, new_projectile_type)


func apply_status(unit: Unit, status_list: Array[String], status_list_type: Action.StatusListType, status_list_chance: int, will_remove_status: bool) -> void:
	if status_list_type == Action.StatusListType.ALL:
		var status_success: bool = randi_range(0, 99) < status_list_chance
		if status_success:
			for status_id: String in status_list:
				var status_effect: StatusEffect = GameData.get_status_effect(status_id)
				if will_remove_status and unit.current_statuses.any(func(status: StatusEffect) -> bool: return status.unique_name == status_id):
					unit.remove_status_id(status_id)
					unit.show_popup_text(status_effect.status_effect_name) # TODO different text for removing status
				elif not will_remove_status:
					unit.show_popup_text(status_effect.status_effect_name)
					await unit.add_status(status_effect.duplicate())
	elif status_list_type == Action.StatusListType.EACH:
		for status_id: String in status_list:
			var status_success: bool = randi_range(0, 99) < status_list_chance
			if status_success:
				var status_effect: StatusEffect = GameData.get_status_effect(status_id)
				if will_remove_status and unit.current_statuses.any(func(status: StatusEffect) -> bool: return status.unique_name == status_id):
					unit.remove_status_id(status_id)
					unit.show_popup_text(status_effect.status_effect_name) # TODO different text for removing status
				elif not will_remove_status:
					unit.show_popup_text(status_effect.status_effect_name)
					await unit.add_status(status_effect.duplicate())
	elif status_list_type == Action.StatusListType.RANDOM:
		var status_success: bool = randi_range(0, 99) < status_list_chance
		if status_success:
			if will_remove_status:
				var removable_status_list: Array[String] = status_list.filter(func(status_id: String) -> bool: return unit.current_status_ids.has(status_id))
				if not removable_status_list.is_empty():
					var status_id: String = removable_status_list.pick_random()
					unit.remove_status_id(status_id)
					unit.show_popup_text(GameData.get_status_effect(status_id).status_effect_name) # TODO different text for removing status
			elif not will_remove_status:
				var addable_status_list: Array[String] = status_list.filter(func(status_id: String) -> bool: return not unit.current_status_ids.has(status_id))
				if not addable_status_list.is_empty():
					var status_id: String = addable_status_list.pick_random()
					unit.show_popup_text(GameData.get_status_effect(status_id).status_effect_name)
					await unit.add_status(GameData.get_status_effect(status_id).duplicate())


func apply_standard() -> void:
	var target_units: Array[Unit] = get_target_units(submitted_targets)
	
	if allow_triggering_actions:
		for target: Unit in target_units:
			for connection: Dictionary in target.targeted_pre_action.get_connections():
				await connection["callable"].call(target, self)
	

	# look up animation based on weapon type and vertical angle to target
	var mod_animation_executing_id: int = action.animation_executing_id
	if not submitted_targets.is_empty():
		if action.animation_executing_ids_alternate.size() != 0 and action.use_weapon_animation:
			mod_animation_executing_id = action.animation_executing_id
			var angle_to_target: float = ((submitted_targets[0].height_mid - user.tile_position.height_mid) 
					/ (submitted_targets[0].location - user.tile_position.location).length())
			if angle_to_target > 0.51:
				mod_animation_executing_id = action.animation_executing_ids_alternate[0]
			elif angle_to_target < -0.51:
				mod_animation_executing_id = action.animation_executing_ids_alternate[1]
	
	show_shared_vfx(action.user_shared_vfx_handler_id, user)
	await user.animate_start_action(action.animation_start_id, action.animation_charging_id)
	
	user.animate_execute_action(mod_animation_executing_id)
	
	await user.get_tree().create_timer(0.2).timeout # TODO delay should be based on effect/vfx data? 
	
	# TODO show vfx, including rock, arrow, bolt...
	
	var vfx_casts: Array[Node3D] = []
	# apply effects to targets
	for target_unit: Unit in target_units:
		var cast: Node3D = show_vfx(target_unit)
		if cast != null:
			vfx_casts.append(cast)
		show_projectile(target_unit, action.projectile_type)
		var evade_direction: EvadeData.Directions = get_evade_direction(user.tile_position, target_unit)
		var total_hit_chance: int = get_total_hit_chance(target_unit, evade_direction)
		var hit_success: bool = randi_range(0, 99) < total_hit_chance
		if hit_success:
			show_shared_vfx(action.target_shared_vfx_handler_id, target_unit)

			for effect: ActionEffect in action.target_effects:
				var effect_value: int = roundi(effect.base_power_formula.get_result(user, target_unit, action.element))
				if not action.passive_power_modifier_applies_to_hit_chance:
					# TODO check all passive_effects on user and target
					# TODO check ignores_statuses
					for status: StatusEffect in user.current_statuses:
						effect_value = status.passive_effect.power_modifier_user.apply(effect_value)
					for status: StatusEffect in target_unit.current_statuses:
						effect_value = status.passive_effect.power_modifier_targeted.apply(effect_value)
				
				effect.apply(user, target_unit, effect_value)
				
				if action.set_target_animation_on_hit and [Unit.StatType.HP, Unit.StatType.MP].has(effect.effect_stat_type) and effect_value < 0:
					target_unit.animate_take_hit()
				elif action.set_target_animation_on_hit and [Unit.StatType.HP, Unit.StatType.MP].has(effect.effect_stat_type) and effect_value > 0:
					target_unit.animate_recieve_heal()
			
			# apply status
			await apply_status(target_unit, action.target_status_list, action.target_status_list_type, action.target_status_chance, action.will_remove_target_status)
			
			# TODO apply secondary action
			if action.secondary_action_list_type == Action.StatusListType.RANDOM:
				var sum_weights: int = 0
				for secondary_action: Action.SecondaryAction in action.secondary_actions2:
					sum_weights += secondary_action.chance
				var rng: int = randi_range(0, sum_weights)
				for secondary_action: Action.SecondaryAction in action.secondary_actions2:
					if rng < secondary_action.chance:
						var secondary_action_instance: ActionInstance = self.duplicate()
						secondary_action_instance.action = RomReader.actions[secondary_action.action_unique_name]
						await secondary_action_instance.use() # TODO do not use unit animations, don't check for hit again (when using magic gun)
						break
					else:
						rng -= secondary_action.chance
		else:
			animate_evade(target_unit, evade_direction, user.tile_position.location)
			
			target_unit.show_popup_text("Missed!") # TODO or "Guarded"
			#push_warning(display_name + " missed")
	
	# apply effects to user
	for effect: ActionEffect in action.user_effects:
		var effect_value: int = roundi(effect.base_power_formula.get_result(user, user, action.element))
		effect.apply(user, user, effect_value)
	
	# apply status to user
	await apply_status(user, action.user_status_list, action.user_status_list_type, action.user_status_chance, action.will_remove_user_status)

	# this is needed in case the action causes the user to change animations (or SEQ entirely, ex. new status)
	# TODO correctly time animations with end of action
	if user.current_animation_id_fwd != user.current_idle_animation_id:
		user.animate_return_to_idle()

	# wait for applying effect animation
	battle_manager.game_state_label.text = "Waiting for " + action.display_name + " vfx" 
	# Wait for the real casts, falling back to the flat timer only when there were none.
	# `await_casts` keeps the `any()` shape so multiple targets resolve together.
	var playback: EffectsPlayback = _effects_playback()
	if playback != null:
		await playback.await_casts(vfx_casts)
	else:
		await user.get_tree().create_timer(0.5).timeout
	for target_unit: Unit in target_units:
		if is_instance_valid(target_unit):
			target_unit.return_to_idle_from_hit()
	vfx_casts.clear()

	if not is_instance_valid(user):
		return

	# pay costs
	user.mp -= action.mp_cost

	# wait for triggered actions
	if allow_triggering_actions:
		for target: Unit in target_units:
			if is_instance_valid(target):
				for connection: Dictionary in target.targeted_post_action.get_connections():
					await connection["callable"].call(target, self)

	clear() # clear all highlighting and target data

	if not is_instance_valid(user):
		return

	if action.ends_turn:
		user.is_ending_turn = true
		#action_instance.user.end_turn()

	action_completed.emit(battle_manager)
