class_name ActionResolver
extends RefCounted
## Combat math and logic engine.
## Resolves an ActionInstance into an executable ActionResolution composite tree in zero frames
## using CombatSimulationContext without mutating live UnitData instances or triggering visuals.


static func lookup_action(action_unique_name: String) -> Action:
	if action_unique_name.is_empty():
		return null
	if GameData.actions.has(action_unique_name) or GameData.action_paths.has(action_unique_name):
		return GameData.get_action(action_unique_name)
	if RomReader.actions.has(action_unique_name):
		return RomReader.actions[action_unique_name]
	return null


static func lookup_status_effect(status_unique_name: String) -> StatusEffect:
	if status_unique_name.is_empty():
		return null
	if GameData.status_effects.has(status_unique_name) or GameData.status_effect_paths.has(status_unique_name):
		return GameData.get_status_effect(status_unique_name)
	return null


static func get_evade_direction(origin_tile: TerrainTile, target: UnitData) -> EvadeData.Directions:
	if origin_tile == null or target == null or target.terrain_tile_position == null:
		return EvadeData.Directions.FRONT

	var relative_position: Vector2i = origin_tile.xz_location - target.terrain_tile_position.xz_location
	var relative_facing_position: Vector2i = relative_position
	if target.facing_direction == GameData.Directions.NORTH:
		pass
	elif target.facing_direction == GameData.Directions.EAST:
		relative_facing_position = Vector2i(-relative_position.y, relative_position.x)
	elif target.facing_direction == GameData.Directions.SOUTH:
		relative_facing_position = -relative_position
	elif target.facing_direction == GameData.Directions.WEST:
		relative_facing_position = Vector2i(relative_position.y, -relative_position.x)

	var evade_direction: EvadeData.Directions = EvadeData.Directions.FRONT
	if relative_facing_position.y < 0:
		evade_direction = EvadeData.Directions.BACK
		if absi(relative_facing_position.x) >= absi(relative_facing_position.y):
			evade_direction = EvadeData.Directions.SIDE
	elif absi(relative_facing_position.x) > absi(relative_facing_position.y):
		evade_direction = EvadeData.Directions.SIDE

	return evade_direction


static func get_total_hit_chance(
	action: Action,
	caster: UnitData,
	target: UnitData,
	evade_direction: EvadeData.Directions,
	units_override: Array[UnitData] = []
) -> int:
	var caster_passive_effects: Array[PassiveEffect] = caster.get_all_passive_effects(action.ignore_passives, units_override)
	var target_passive_effects: Array[PassiveEffect] = target.get_all_passive_effects(action.ignore_passives, units_override)

	if not action.required_target_job_uname.is_empty():
		var required_jobs: PackedStringArray = action.required_target_job_uname.duplicate()
		for passive_effect: PassiveEffect in caster_passive_effects:
			required_jobs.append_array(passive_effect.add_applicable_target_jobs)
		if not required_jobs.has(target.job_data.unique_name):
			return 0

	if not action.required_target_status_uname.is_empty():
		var required_statuses: PackedStringArray = action.required_target_status_uname.duplicate()
		for passive_effect: PassiveEffect in caster_passive_effects:
			required_statuses.append_array(passive_effect.add_applicable_target_statuses)
		if not Utilities.has_any_elements(target.get_current_status_ids(), required_statuses):
			return 0

	if not action.required_target_stat_basis.is_empty():
		var required_bases: Array[UnitData.StatBasis] = action.required_target_stat_basis.duplicate()
		for passive_effect: PassiveEffect in caster_passive_effects:
			required_bases.append_array(passive_effect.add_applicable_target_stat_bases)
		if not required_bases.has(target.stat_basis):
			return 0

	var base_hit_chance: float = action.base_hit_formula.get_result(caster, target, action.element)
	var modified_hit_chance: float = base_hit_chance
	if action.passive_power_modifier_applies_to_hit_chance:
		for passive_effect: PassiveEffect in caster_passive_effects:
			modified_hit_chance = passive_effect.power_modifier_user.apply(roundi(modified_hit_chance), caster, target)
		for passive_effect: PassiveEffect in target_passive_effects:
			modified_hit_chance = passive_effect.power_modifier_targeted.apply(roundi(modified_hit_chance), caster, target)
	else:
		for passive_effect: PassiveEffect in caster_passive_effects:
			modified_hit_chance = passive_effect.hit_chance_modifier_user.apply(roundi(modified_hit_chance), caster, target)
		for passive_effect: PassiveEffect in target_passive_effects:
			modified_hit_chance = passive_effect.hit_chance_modifier_targeted.apply(roundi(modified_hit_chance), caster, target)

	var effective_evade_values: Dictionary[EvadeData.EvadeSource, int] = _get_effective_evade_values(
		action,
		caster,
		target,
		evade_direction,
		caster_passive_effects,
		target_passive_effects
	)
	var target_total_evade_factor: float = 1.0
	for evade_source: EvadeData.EvadeSource in effective_evade_values.keys():
		var evade_factor: float = maxf(0.0, 1.0 - (float(effective_evade_values[evade_source]) / 100.0))
		target_total_evade_factor = target_total_evade_factor * evade_factor
	target_total_evade_factor = maxf(0.0, target_total_evade_factor)

	return roundi(modified_hit_chance * target_total_evade_factor)


static func resolve(
	action_instance: ActionInstance,
	is_preview: bool = false,
	random_generator: RandomNumberGenerator = null,
	simulation_context: CombatSimulationContext = null,
	chain_depth: int = 0,
	is_reaction: bool = false,
	is_secondary_action: bool = false,
	play_caster_animation: bool = true,
	roll_hit_chance: bool = true
) -> ActionResolution:
	var active_random_generator: RandomNumberGenerator = random_generator
	if active_random_generator == null:
		active_random_generator = RandomNumberGenerator.new()
		active_random_generator.randomize()

	var active_context: CombatSimulationContext = simulation_context
	if active_context == null:
		active_context = CombatSimulationContext.new()

	var resolution: ActionResolution = ActionResolution.new()
	resolution.action = action_instance.action
	resolution.user = action_instance.user
	resolution.is_preview_only = is_preview
	resolution.is_reaction = is_reaction
	resolution.is_secondary_action = is_secondary_action
	resolution.play_caster_animation = play_caster_animation
	resolution.roll_hit_chance = roll_hit_chance
	resolution.chain_depth = chain_depth
	resolution.rng_seed = active_random_generator.seed
	resolution.rng_initial_state = active_random_generator.state
	resolution.ends_turn = action_instance.action.ends_turn and not is_reaction and not is_secondary_action

	if not is_secondary_action:
		resolution.mp_cost = action_instance.action.mp_cost

	var is_outer_wrapper_action: bool = (
		action_instance.action.target_effects.is_empty()
		and action_instance.action.target_status_list.is_empty()
		and action_instance.action.user_effects.is_empty()
		and action_instance.action.user_status_list.is_empty()
		and not action_instance.action.secondary_actions2.is_empty()
	)
	if is_outer_wrapper_action:
		resolution.settle_delay_seconds = 0.0

	var source_tiles: Array[TerrainTile] = action_instance.preview_targets if is_preview else action_instance.submitted_targets
	if source_tiles.is_empty():
		source_tiles = action_instance.submitted_targets if is_preview else action_instance.preview_targets
	resolution.targeted_tiles = source_tiles.duplicate()

	var battle_manager: BattleManager = action_instance.battle_manager
	if battle_manager == null and action_instance.user != null:
		battle_manager = action_instance.user.battle_manager

	var simulated_caster: UnitData = active_context.get_simulated_unit(action_instance.user)
	resolution.targeted_units = _resolve_target_units(
		action_instance.action,
		resolution.targeted_tiles,
		battle_manager,
		active_context
	)

	var can_trigger_reactions: bool = (
		not is_preview
		and action_instance.allow_triggering_actions
		and action_instance.action.allow_triggered_actions
		and chain_depth < CombatSimulationContext.MAX_CHAIN_DEPTH
	)

	# 1. Pre-Action Reactions (e.g. Hamedo / Counter Grasp)
	if can_trigger_reactions and not is_secondary_action:
		for live_target: UnitData in resolution.targeted_units:
			var pre_reactions: Array[ActionResolution] = _resolve_triggered_actions(
				live_target,
				action_instance.user,
				action_instance.action,
				null,
				TriggeredAction.TriggerTiming.TARGETTED_PRE_ACTION,
				battle_manager,
				active_random_generator,
				active_context,
				chain_depth
			)
			resolution.pre_action_reactions.append_array(pre_reactions)

		if simulated_caster != null and simulated_caster.is_defeated():
			resolution.was_aborted_before_execution = true
			resolution.user_defeated_during_action = true
			resolution.mp_cost = 0
			return resolution

	# 2. Primary Target Outcomes
	var units_override: Array[UnitData] = active_context.get_all_units(battle_manager)
	var on_hit_secondaries: Array[SecondaryAction] = _filter_secondary_actions(action_instance.action.secondary_actions2, true)
	var follow_up_secondaries: Array[SecondaryAction] = _filter_secondary_actions(action_instance.action.secondary_actions2, false)

	for live_target: UnitData in resolution.targeted_units:
		var simulated_target: UnitData = active_context.get_simulated_unit(live_target)
		units_override = active_context.get_all_units(battle_manager)

		var target_result: ActionTargetResult = ActionTargetResult.new()
		target_result.target_unit = live_target
		target_result.target_tile = simulated_target.terrain_tile_position
		target_result.was_defeated_before_hit = simulated_target.is_defeated()

		var evade_direction: EvadeData.Directions = get_evade_direction(simulated_caster.terrain_tile_position, simulated_target)
		target_result.evade_direction = evade_direction

		if roll_hit_chance:
			var total_hit_chance: int = clampi(
				get_total_hit_chance(action_instance.action, simulated_caster, simulated_target, evade_direction, units_override),
				0,
				100
			)
			target_result.hit_chance_percentage = total_hit_chance
			if is_preview:
				target_result.hit_outcome = ActionTargetResult.HitOutcome.HIT if total_hit_chance > 0 else ActionTargetResult.HitOutcome.MISS
			else:
				var hit_roll: int = active_random_generator.randi_range(0, 99)
				if hit_roll < total_hit_chance:
					target_result.hit_outcome = ActionTargetResult.HitOutcome.HIT
				else:
					_populate_miss_or_evade(
						action_instance.action,
						simulated_caster,
						simulated_target,
						evade_direction,
						target_result,
						active_random_generator,
						units_override
					)
		else:
			target_result.hit_chance_percentage = 100
			target_result.hit_outcome = ActionTargetResult.HitOutcome.HIT

		if target_result.did_hit():
			for effect: ActionEffect in action_instance.action.target_effects:
				var effect_value: int = effect.get_modified_value(simulated_caster, simulated_target, action_instance.action, units_override)
				_apply_effect_in_simulation(
					effect,
					effect_value,
					action_instance.user,
					simulated_caster,
					simulated_target,
					target_result,
					resolution
				)

			_resolve_status_list(
				simulated_target,
				target_result,
				action_instance.action.target_status_list,
				action_instance.action.target_status_list_type,
				action_instance.action.target_status_chance,
				action_instance.action.will_remove_target_status,
				is_preview,
				active_random_generator,
				units_override
			)

			_resolve_hp_threshold_statuses(simulated_target, target_result, units_override)

			if not is_preview and chain_depth < CombatSimulationContext.MAX_CHAIN_DEPTH:
				_resolve_status_on_apply_actions(
					live_target,
					simulated_target,
					target_result,
					battle_manager,
					active_random_generator,
					active_context,
					chain_depth
				)

			if not on_hit_secondaries.is_empty() and chain_depth < CombatSimulationContext.MAX_CHAIN_DEPTH:
				var on_hit_tiles: Array[TerrainTile] = []
				if target_result.target_tile != null:
					on_hit_tiles.append(target_result.target_tile)
				var sub_resolutions: Array[ActionResolution] = _resolve_secondary_action_list(
					action_instance,
					on_hit_secondaries,
					on_hit_tiles,
					battle_manager,
					is_preview,
					active_random_generator,
					active_context,
					chain_depth
				)
				target_result.target_sub_resolutions.append_array(sub_resolutions)

		resolution.target_results.append(target_result)

	# 3. User Effects & Statuses
	units_override = active_context.get_all_units(battle_manager)
	var has_user_outcomes: bool = (
		not action_instance.action.user_effects.is_empty()
		or not action_instance.action.user_status_list.is_empty()
		or resolution.user_result != null
	)
	if has_user_outcomes and simulated_caster != null:
		var user_result: ActionTargetResult = _get_or_create_user_result(resolution, action_instance.user, simulated_caster)
		for user_effect: ActionEffect in action_instance.action.user_effects:
			var user_effect_value: int = user_effect.get_modified_value(simulated_caster, simulated_caster, action_instance.action, units_override)
			_apply_single_effect_to_unit(user_effect, user_effect_value, simulated_caster, user_result)

		_resolve_status_list(
			simulated_caster,
			user_result,
			action_instance.action.user_status_list,
			action_instance.action.user_status_list_type,
			action_instance.action.user_status_chance,
			action_instance.action.will_remove_user_status,
			is_preview,
			active_random_generator,
			units_override
		)

		_resolve_hp_threshold_statuses(simulated_caster, user_result, units_override)

		if not is_preview and chain_depth < CombatSimulationContext.MAX_CHAIN_DEPTH:
			_resolve_status_on_apply_actions(
				action_instance.user,
				simulated_caster,
				user_result,
				battle_manager,
				active_random_generator,
				active_context,
				chain_depth
			)

	# 4. Deduct Provisional MP Cost on Simulated Caster
	if not is_preview and resolution.mp_cost != 0 and simulated_caster != null and simulated_caster.stats.has(UnitData.StatType.MP):
		simulated_caster.stats[UnitData.StatType.MP].add_value(-resolution.mp_cost)

	# 5. Follow-Up Secondary Actions (requires_primary_hit == false, e.g. Two Swords)
	if not follow_up_secondaries.is_empty() and simulated_caster != null and not simulated_caster.is_defeated() and chain_depth < CombatSimulationContext.MAX_CHAIN_DEPTH:
		var follow_up_resolutions: Array[ActionResolution] = _resolve_secondary_action_list(
			action_instance,
			follow_up_secondaries,
			resolution.targeted_tiles,
			battle_manager,
			is_preview,
			active_random_generator,
			active_context,
			chain_depth
		)
		resolution.secondary_resolutions.append_array(follow_up_resolutions)

	# 6. Post-Action Reactions (e.g. Counter, Auto-Potion, Counter Magic)
	if can_trigger_reactions:
		for target_result: ActionTargetResult in resolution.target_results:
			if target_result.target_unit == null:
				continue
			var post_reactions: Array[ActionResolution] = _resolve_triggered_actions(
				target_result.target_unit,
				action_instance.user,
				action_instance.action,
				target_result,
				TriggeredAction.TriggerTiming.TARGETTED_POST_ACTION,
				battle_manager,
				active_random_generator,
				active_context,
				chain_depth
			)
			resolution.post_action_reactions.append_array(post_reactions)

	if simulated_caster != null:
		resolution.user_defeated_during_action = simulated_caster.is_defeated()

	return resolution


static func _resolve_target_units(
	action: Action,
	target_tiles: Array[TerrainTile],
	battle_manager: BattleManager,
	simulation_context: CombatSimulationContext
) -> Array[UnitData]:
	var candidate_live_units: Array[UnitData] = []
	if battle_manager != null:
		candidate_live_units = battle_manager.units
	else:
		candidate_live_units.assign(simulation_context.simulated_units.keys())

	var resolved_targets: Array[UnitData] = []
	for target_tile: TerrainTile in target_tiles:
		for live_unit: UnitData in candidate_live_units:
			var check_unit: UnitData = simulation_context.simulated_units.get(live_unit, live_unit)
			if check_unit.terrain_tile_position != target_tile:
				continue
			if resolved_targets.has(live_unit):
				continue

			var nullify_statuses: Array[StatusEffect] = check_unit.get_nullify_statuses()
			if nullify_statuses.is_empty():
				resolved_targets.append(live_unit)
				continue

			var ignores_all_nullify: bool = nullify_statuses.all(
				func(status_effect: StatusEffect) -> bool: return action.ignores_statuses.has(status_effect.unique_name)
			)
			var removes_nullify: bool = nullify_statuses.any(
				func(status_effect: StatusEffect) -> bool: return action.will_remove_target_status and action.target_status_list.has(status_effect.unique_name)
			)
			if ignores_all_nullify or removes_nullify:
				resolved_targets.append(live_unit)

	return resolved_targets


static func _get_effective_evade_values(
	action: Action,
	caster: UnitData,
	target: UnitData,
	evade_direction: EvadeData.Directions,
	caster_passive_effects: Array[PassiveEffect],
	target_passive_effects: Array[PassiveEffect]
) -> Dictionary[EvadeData.EvadeSource, int]:
	var effective_evade_values: Dictionary[EvadeData.EvadeSource, int] = {}
	if action.applicable_evasion_type == EvadeData.EvadeType.NONE:
		return effective_evade_values

	var base_evade_values: Dictionary[EvadeData.EvadeSource, int] = target.get_evade_values(action.applicable_evasion_type, evade_direction)
	for evade_source: EvadeData.EvadeSource in base_evade_values.keys():
		if not target_passive_effects.any(func(passive_effect: PassiveEffect) -> bool: return passive_effect.include_evade_sources.has(evade_source)):
			continue
		var evade_value: int = base_evade_values[evade_source]
		for passive_effect: PassiveEffect in caster_passive_effects:
			if passive_effect.evade_source_modifiers_user.has(evade_source):
				evade_value = passive_effect.evade_source_modifiers_user[evade_source].apply(evade_value, caster, target)
		for passive_effect: PassiveEffect in target_passive_effects:
			if passive_effect.evade_source_modifiers_targeted.has(evade_source):
				evade_value = passive_effect.evade_source_modifiers_targeted[evade_source].apply(evade_value, caster, target)
		effective_evade_values[evade_source] = maxi(0, evade_value)

	return effective_evade_values


static func _populate_miss_or_evade(
	action: Action,
	simulated_caster: UnitData,
	simulated_target: UnitData,
	evade_direction: EvadeData.Directions,
	target_result: ActionTargetResult,
	random_generator: RandomNumberGenerator,
	units_override: Array[UnitData] = []
) -> void:
	if action.applicable_evasion_type == EvadeData.EvadeType.NONE:
		target_result.hit_outcome = ActionTargetResult.HitOutcome.MISS
		return

	var caster_passive_effects: Array[PassiveEffect] = simulated_caster.get_all_passive_effects(action.ignore_passives, units_override)
	var target_passive_effects: Array[PassiveEffect] = simulated_target.get_all_passive_effects(action.ignore_passives, units_override)
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = _get_effective_evade_values(
		action,
		simulated_caster,
		simulated_target,
		evade_direction,
		caster_passive_effects,
		target_passive_effects
	)
	var sum_of_weights: int = 0
	for evade_weight: int in evade_values.values():
		sum_of_weights += evade_weight

	if sum_of_weights <= 0:
		target_result.hit_outcome = ActionTargetResult.HitOutcome.MISS
		return

	target_result.hit_outcome = ActionTargetResult.HitOutcome.EVADED
	var roll_value: int = random_generator.randi_range(0, sum_of_weights - 1)
	for evade_source: EvadeData.EvadeSource in evade_values.keys():
		var evade_weight: int = evade_values[evade_source]
		if roll_value < evade_weight:
			target_result.evade_source = evade_source
			return
		roll_value -= evade_weight


static func _get_or_create_user_result(
	resolution: ActionResolution,
	live_caster: UnitData,
	simulated_caster: UnitData
) -> ActionTargetResult:
	if resolution.user_result == null:
		var user_result: ActionTargetResult = ActionTargetResult.new()
		user_result.target_unit = live_caster
		user_result.target_tile = simulated_caster.terrain_tile_position
		user_result.was_defeated_before_hit = simulated_caster.is_defeated()
		resolution.user_result = user_result
	return resolution.user_result


static func _apply_effect_in_simulation(
	effect: ActionEffect,
	effect_value: int,
	live_caster: UnitData,
	simulated_caster: UnitData,
	simulated_target: UnitData,
	target_result: ActionTargetResult,
	resolution: ActionResolution
) -> void:
	var applied_delta: int = 0
	if effect.apply_to_user:
		var user_result: ActionTargetResult = _get_or_create_user_result(resolution, live_caster, simulated_caster)
		applied_delta = _apply_single_effect_to_unit(effect, effect_value, simulated_caster, user_result)
	else:
		applied_delta = _apply_single_effect_to_unit(effect, effect_value, simulated_target, target_result)

	if effect.transfer_to_user and simulated_caster != null:
		var transfer_user_result: ActionTargetResult = _get_or_create_user_result(resolution, live_caster, simulated_caster)
		_apply_transfer_delta_to_unit(effect, -applied_delta, simulated_caster, transfer_user_result)


static func _apply_single_effect_to_unit(
	effect: ActionEffect,
	effect_value: int,
	simulated_unit: UnitData,
	result_record: ActionTargetResult
) -> int:
	match effect.type:
		ActionEffect.EffectType.UNIT_STAT:
			if not simulated_unit.stats.has(effect.effect_stat_type):
				return 0
			var stat_change: Dictionary[String, int] = CombatSimulationContext.apply_stat_change(
				simulated_unit,
				effect.effect_stat_type,
				effect_value,
				effect.set_value
			)
			var delta: int = stat_change["delta"]
			result_record.stat_deltas[effect.effect_stat_type] = result_record.stat_deltas.get(effect.effect_stat_type, 0) + delta
			result_record.stat_overflows[effect.effect_stat_type] = result_record.stat_overflows.get(effect.effect_stat_type, 0) + stat_change["overflow"]
			result_record.stat_underflows[effect.effect_stat_type] = result_record.stat_underflows.get(effect.effect_stat_type, 0) + stat_change["underflow"]
			return delta
		ActionEffect.EffectType.CURRENCY:
			var currency_change: int = effect_value
			if effect.set_value and simulated_unit.team != null:
				currency_change = maxi(0, effect_value) - simulated_unit.team.currency
			result_record.currency_delta += currency_change
			return currency_change
		ActionEffect.EffectType.INVENTORY:
			var item_index: int = 0
			var inventory_change: int = effect_value
			if effect.set_value and simulated_unit.team != null and item_index < simulated_unit.team.inventory.size():
				inventory_change = maxi(0, effect_value) - simulated_unit.team.inventory[item_index]
			result_record.inventory_deltas[item_index] = result_record.inventory_deltas.get(item_index, 0) + inventory_change
			return inventory_change
		_:
			return 0


static func _apply_transfer_delta_to_unit(
	effect: ActionEffect,
	transfer_delta: int,
	simulated_caster: UnitData,
	user_result: ActionTargetResult
) -> void:
	if transfer_delta == 0:
		return
	match effect.type:
		ActionEffect.EffectType.UNIT_STAT:
			if not simulated_caster.stats.has(effect.effect_stat_type):
				return
			var stat_change: Dictionary[String, int] = CombatSimulationContext.apply_stat_change(
				simulated_caster,
				effect.effect_stat_type,
				transfer_delta,
				false
			)
			user_result.stat_deltas[effect.effect_stat_type] = user_result.stat_deltas.get(effect.effect_stat_type, 0) + stat_change["delta"]
			user_result.stat_overflows[effect.effect_stat_type] = user_result.stat_overflows.get(effect.effect_stat_type, 0) + stat_change["overflow"]
			user_result.stat_underflows[effect.effect_stat_type] = user_result.stat_underflows.get(effect.effect_stat_type, 0) + stat_change["underflow"]
		ActionEffect.EffectType.CURRENCY:
			user_result.currency_delta += transfer_delta
		ActionEffect.EffectType.INVENTORY:
			var item_index: int = 0
			user_result.inventory_deltas[item_index] = user_result.inventory_deltas.get(item_index, 0) + transfer_delta


static func _resolve_hp_threshold_statuses(
	simulated_unit: UnitData,
	result_record: ActionTargetResult,
	units_override: Array[UnitData]
) -> void:
	if not simulated_unit.stats.has(UnitData.StatType.HP):
		return
	var hp_changed: bool = result_record.stat_deltas.get(UnitData.StatType.HP, 0) != 0
	var hp_max_changed: bool = result_record.stat_deltas.get(UnitData.StatType.HP_MAX, 0) != 0
	if not hp_changed and not hp_max_changed:
		return

	var hp_stat: StatValue = simulated_unit.stats[UnitData.StatType.HP]
	@warning_ignore("integer_division")
	var critical_hp_threshold: int = hp_stat.max_value / 5

	if hp_stat.current_value == 0:
		var dead_status: StatusEffect = lookup_status_effect("dead")
		if dead_status != null and not simulated_unit.has_status("dead"):
			if not result_record.statuses_added.has("dead"):
				result_record.statuses_added.append("dead")
			simulated_unit.add_status(dead_status.duplicate(), true, units_override)
	elif hp_stat.current_value < critical_hp_threshold:
		if not simulated_unit.has_status("critical") and _can_apply_status(simulated_unit, "critical"):
			var critical_status: StatusEffect = lookup_status_effect("critical")
			if critical_status != null:
				if not result_record.statuses_added.has("critical"):
					result_record.statuses_added.append("critical")
				simulated_unit.add_status(critical_status.duplicate(), false, units_override)
	elif hp_stat.current_value >= critical_hp_threshold:
		var has_removable_critical: bool = simulated_unit.current_statuses.any(
			func(status_effect: StatusEffect) -> bool: return status_effect.unique_name == "critical" and status_effect.duration_type != StatusEffect.DurationType.PERMANENT
		)
		if has_removable_critical:
			if not result_record.statuses_removed.has("critical"):
				result_record.statuses_removed.append("critical")
			simulated_unit.remove_status_id("critical", units_override)


static func _resolve_status_list(
	simulated_unit: UnitData,
	result_record: ActionTargetResult,
	status_list: PackedStringArray,
	status_list_type: Action.StatusListType,
	status_chance: int,
	will_remove_status: bool,
	is_preview: bool,
	random_generator: RandomNumberGenerator,
	units_override: Array[UnitData]
) -> void:
	if status_list.is_empty():
		return

	var eligible_ids: PackedStringArray = []
	for status_id: String in status_list:
		if will_remove_status:
			var can_remove: bool = simulated_unit.current_statuses.any(
				func(status_effect: StatusEffect) -> bool: return status_effect.unique_name == status_id and status_effect.duration_type != StatusEffect.DurationType.PERMANENT
			)
			if can_remove and not eligible_ids.has(status_id):
				eligible_ids.append(status_id)
		else:
			if _can_apply_status(simulated_unit, status_id) and not eligible_ids.has(status_id):
				eligible_ids.append(status_id)

	result_record.eligible_status_ids.append_array(eligible_ids)

	if is_preview or eligible_ids.is_empty():
		return

	var chosen_ids: PackedStringArray = []
	if status_list_type == Action.StatusListType.ALL:
		if random_generator.randi_range(0, 99) < status_chance:
			chosen_ids = eligible_ids.duplicate()
	elif status_list_type == Action.StatusListType.EACH:
		for status_id: String in eligible_ids:
			if random_generator.randi_range(0, 99) < status_chance:
				chosen_ids.append(status_id)
	elif status_list_type == Action.StatusListType.RANDOM:
		if random_generator.randi_range(0, 99) < status_chance:
			var random_index: int = random_generator.randi_range(0, eligible_ids.size() - 1)
			chosen_ids.append(eligible_ids[random_index])

	for status_id: String in chosen_ids:
		if will_remove_status:
			if not result_record.statuses_removed.has(status_id):
				result_record.statuses_removed.append(status_id)
			simulated_unit.remove_status_id(status_id, units_override)
		else:
			var status_effect: StatusEffect = lookup_status_effect(status_id)
			if status_effect != null:
				if not result_record.statuses_added.has(status_id):
					result_record.statuses_added.append(status_id)
				simulated_unit.add_status(status_effect.duplicate(), false, units_override)


static func _can_apply_status(simulated_unit: UnitData, status_id: String) -> bool:
	if simulated_unit.immune_statuses.has(status_id):
		return false

	var status_effect: StatusEffect = lookup_status_effect(status_id)
	if status_effect == null:
		return false

	for prevented_by_id: String in status_effect.status_cant_stack:
		if simulated_unit.has_status(prevented_by_id):
			return false

	var existing_matching: Array[StatusEffect] = simulated_unit.current_statuses.filter(
		func(existing_status: StatusEffect) -> bool: return existing_status.unique_name == status_effect.unique_name
	)
	if existing_matching.size() >= status_effect.num_allowed:
		var has_replaceable_temp: bool = existing_matching.any(
			func(existing_status: StatusEffect) -> bool: return existing_status.duration_type != StatusEffect.DurationType.PERMANENT
		)
		if not has_replaceable_temp:
			return false

	return true


static func _resolve_status_on_apply_actions(
	live_unit: UnitData,
	simulated_unit: UnitData,
	result_record: ActionTargetResult,
	battle_manager: BattleManager,
	random_generator: RandomNumberGenerator,
	simulation_context: CombatSimulationContext,
	chain_depth: int
) -> void:
	for status_id: String in result_record.statuses_added:
		var status_effect: StatusEffect = lookup_status_effect(status_id)
		if status_effect == null or status_effect.action_on_apply.is_empty():
			continue

		var on_apply_action: Action = lookup_action(status_effect.action_on_apply)
		if on_apply_action == null:
			continue

		var on_apply_instance: ActionInstance = ActionInstance.new(on_apply_action, live_unit, battle_manager)
		on_apply_instance.allow_triggering_actions = false
		on_apply_instance.deduct_action_points = false
		if simulated_unit.terrain_tile_position != null:
			on_apply_instance.submitted_targets = [simulated_unit.terrain_tile_position]

		var on_apply_resolution: ActionResolution = resolve(
			on_apply_instance,
			false,
			random_generator,
			simulation_context,
			chain_depth + 1,
			false,
			true,
			false,
			false
		)
		result_record.target_sub_resolutions.append(on_apply_resolution)


static func _filter_secondary_actions(secondary_actions: Array[SecondaryAction], requires_primary_hit_filter: bool) -> Array[SecondaryAction]:
	var filtered: Array[SecondaryAction] = []
	for secondary_action: SecondaryAction in secondary_actions:
		if secondary_action.requires_primary_hit == requires_primary_hit_filter:
			filtered.append(secondary_action)
	return filtered


static func _resolve_secondary_action_list(
	parent_action_instance: ActionInstance,
	secondary_actions: Array[SecondaryAction],
	target_tiles: Array[TerrainTile],
	battle_manager: BattleManager,
	is_preview: bool,
	random_generator: RandomNumberGenerator,
	simulation_context: CombatSimulationContext,
	chain_depth: int
) -> Array[ActionResolution]:
	var results: Array[ActionResolution] = []
	var list_type: Action.StatusListType = parent_action_instance.action.secondary_action_list_type

	if is_preview:
		var weight_sum: int = 100
		if list_type == Action.StatusListType.RANDOM:
			weight_sum = 0
			for secondary_action: SecondaryAction in secondary_actions:
				weight_sum += maxi(0, secondary_action.chance)
			weight_sum = maxi(1, weight_sum)

		for secondary_action: SecondaryAction in secondary_actions:
			var resolved_action: Action = lookup_action(secondary_action.action_unique_name)
			if resolved_action == null:
				continue

			var is_unconditional: bool = (secondary_action.chance >= 100 and list_type != Action.StatusListType.RANDOM)
			var branch_context: CombatSimulationContext = simulation_context if is_unconditional else simulation_context.clone()
			var secondary_instance: ActionInstance = _build_secondary_action_instance(
				resolved_action,
				parent_action_instance.user,
				target_tiles,
				battle_manager,
				parent_action_instance.allow_triggering_actions,
				true
			)
			var secondary_resolution: ActionResolution = resolve(
				secondary_instance,
				true,
				random_generator,
				branch_context,
				chain_depth + 1,
				false,
				true,
				secondary_action.play_caster_animation,
				secondary_action.roll_hit_chance
			)
			secondary_resolution.branch_chance_percent = secondary_action.chance
			secondary_resolution.branch_list_type = list_type
			secondary_resolution.branch_weight_sum = weight_sum
			results.append(secondary_resolution)
		return results

	var selected_actions: Array[SecondaryAction] = []
	if list_type == Action.StatusListType.RANDOM:
		var total_weight: int = 0
		for secondary_action: SecondaryAction in secondary_actions:
			total_weight += maxi(0, secondary_action.chance)
		if total_weight > 0:
			var weight_roll: int = random_generator.randi_range(0, total_weight - 1)
			for secondary_action: SecondaryAction in secondary_actions:
				var entry_weight: int = maxi(0, secondary_action.chance)
				if weight_roll < entry_weight:
					selected_actions.append(secondary_action)
					break
				weight_roll -= entry_weight
	elif list_type == Action.StatusListType.ALL:
		if not secondary_actions.is_empty():
			var group_chance: int = secondary_actions[0].chance
			if random_generator.randi_range(0, 99) < group_chance:
				selected_actions.append_array(secondary_actions)
	else:
		for secondary_action: SecondaryAction in secondary_actions:
			if random_generator.randi_range(0, 99) < secondary_action.chance:
				selected_actions.append(secondary_action)

	for secondary_action: SecondaryAction in selected_actions:
		var resolved_action: Action = lookup_action(secondary_action.action_unique_name)
		if resolved_action == null:
			continue
		var secondary_instance: ActionInstance = _build_secondary_action_instance(
			resolved_action,
			parent_action_instance.user,
			target_tiles,
			battle_manager,
			parent_action_instance.allow_triggering_actions,
			false
		)
		var secondary_resolution: ActionResolution = resolve(
			secondary_instance,
			false,
			random_generator,
			simulation_context,
			chain_depth + 1,
			false,
			true,
			secondary_action.play_caster_animation,
			secondary_action.roll_hit_chance
		)
		results.append(secondary_resolution)

	return results


static func _build_secondary_action_instance(
	secondary_action_resource: Action,
	live_caster: UnitData,
	target_tiles: Array[TerrainTile],
	battle_manager: BattleManager,
	allow_triggering_actions: bool,
	is_preview: bool
) -> ActionInstance:
	var secondary_instance: ActionInstance = ActionInstance.new(secondary_action_resource, live_caster, battle_manager)
	secondary_instance.allow_triggering_actions = allow_triggering_actions
	secondary_instance.deduct_action_points = false

	var resolved_tiles: Array[TerrainTile] = target_tiles.duplicate()
	if (
		battle_manager != null
		and target_tiles.size() == 1
		and secondary_action_resource.area_of_effect_range > 0
		and secondary_action_resource.targeting_strategy is RangeTargeting
	):
		var range_targeting: RangeTargeting = secondary_action_resource.targeting_strategy as RangeTargeting
		resolved_tiles = range_targeting.get_aoe_targets(secondary_instance, target_tiles[0])

	if is_preview:
		secondary_instance.preview_targets = resolved_tiles
	else:
		secondary_instance.submitted_targets = resolved_tiles

	return secondary_instance


static func _resolve_triggered_actions(
	live_reactor: UnitData,
	live_initiator: UnitData,
	initiating_action: Action,
	target_result: ActionTargetResult,
	timing: TriggeredAction.TriggerTiming,
	battle_manager: BattleManager,
	random_generator: RandomNumberGenerator,
	simulation_context: CombatSimulationContext,
	chain_depth: int
) -> Array[ActionResolution]:
	var reaction_resolutions: Array[ActionResolution] = []
	if not simulation_context.can_unit_react(live_reactor, chain_depth):
		return reaction_resolutions

	var simulated_reactor: UnitData = simulation_context.get_simulated_unit(live_reactor)
	var simulated_initiator: UnitData = simulation_context.get_simulated_unit(live_initiator)
	var units_override: Array[UnitData] = simulation_context.get_all_units(battle_manager)

	for triggered_action: TriggeredAction in simulated_reactor.triggered_actions:
		if triggered_action.trigger_timing != timing:
			continue
		if not simulation_context.can_unit_react(live_reactor, chain_depth):
			break
		if not triggered_action.can_trigger(simulated_reactor, simulated_initiator, initiating_action, target_result, units_override):
			continue

		var reaction_instance: ActionInstance = triggered_action.build_action_instance(
			live_reactor,
			simulated_reactor,
			simulated_initiator,
			initiating_action,
			battle_manager
		)
		if reaction_instance == null:
			continue

		if not triggered_action.roll_trigger_chance(simulated_reactor, simulated_initiator, random_generator, initiating_action.element):
			continue

		simulation_context.record_unit_reaction(live_reactor)
		var reaction_resolution: ActionResolution = resolve(
			reaction_instance,
			false,
			random_generator,
			simulation_context,
			chain_depth + 1,
			true,
			false,
			true,
			true
		)
		reaction_resolutions.append(reaction_resolution)

	return reaction_resolutions
