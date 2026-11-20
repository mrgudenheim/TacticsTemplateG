class_name ActionPresenter
extends RefCounted
## Asynchronous presentation engine that plays an ActionResolution tree on live UnitActors
## and commits gameplay state mutations in sync with visual impacts.

const KNOCKBACK_SLIDE_DURATION_SECONDS: float = 0.2
const USER_SHARED_VFX_STOP_DELAY_SECONDS: float = 2.0

const COLOR_DAMAGE: Color = Color.WHITE
const COLOR_CRITICAL: Color = Color.GOLD
const COLOR_HEAL: Color = Color.LIGHT_GREEN
const COLOR_MP_DAMAGE: Color = Color.CORNFLOWER_BLUE
const COLOR_MP_HEAL: Color = Color.AQUAMARINE
const COLOR_STAT_BUFF: Color = Color.LIGHT_GREEN
const COLOR_STAT_DEBUFF: Color = Color.SALMON
const COLOR_STATUS_ADDED: Color = Color.GOLD
const COLOR_STATUS_REMOVED: Color = Color.LIGHT_CYAN
const COLOR_MISS: Color = Color.LIGHT_GRAY


static func play_resolution(
	resolution: ActionResolution,
	battle_manager: BattleManager = null
) -> void:
	if resolution == null or resolution.is_preview_only:
		return

	var active_battle_manager: BattleManager = battle_manager
	if active_battle_manager == null and is_instance_valid(resolution.user):
		active_battle_manager = resolution.user.battle_manager

	if active_battle_manager != null and active_battle_manager.skip_action_animations:
		resolution.apply_all_state_changes()
		active_battle_manager.update_units_pathfinding()
		return

	var speed_scale: float = 1.0
	if active_battle_manager != null:
		speed_scale = maxf(0.1, active_battle_manager.action_playback_speed)

	await _play_resolution_node(resolution, active_battle_manager, speed_scale)

	if active_battle_manager != null:
		active_battle_manager.update_units_pathfinding()


static func _play_resolution_node(
	resolution: ActionResolution,
	battle_manager: BattleManager,
	speed_scale: float
) -> void:
	if resolution == null:
		return

	# 1. Pre-Action Reactions (e.g., Hamedo / Counter Grasp)
	for pre_reaction: ActionResolution in resolution.pre_action_reactions:
		await _play_resolution_node(pre_reaction, battle_manager, speed_scale)

	if resolution.was_aborted_before_execution:
		resolution.apply_turn_end_flag()
		return

	var caster: UnitData = resolution.user
	var caster_actor: UnitActor = caster.unit_actor if is_instance_valid(caster) else null
	var action: Action = resolution.action

	# 2. Caster Facing, Shared Trap VFX, Windup, Executing Pose & Projectile / Impact Delay
	if action != null and resolution.play_caster_animation:
		_face_first_target(caster, resolution.targeted_tiles)
		if caster_actor != null:
			if action.user_shared_vfx_handler_id > 0:
				_play_shared_vfx(action.user_shared_vfx_handler_id, action.element, caster_actor, caster_actor, battle_manager)
				if caster_actor.is_inside_tree():
					caster_actor.get_tree().create_timer(USER_SHARED_VFX_STOP_DELAY_SECONDS / speed_scale).timeout.connect(
						func() -> void:
							if is_instance_valid(battle_manager) and is_instance_valid(battle_manager.trap_instance):
								battle_manager.trap_instance.stop(),
						CONNECT_ONE_SHOT
					)

			await caster_actor.animate_start_action(
				action.animation_start_id,
				action.animation_charging_id,
				action.ticks_charge_time,
				speed_scale
			)

			var executing_animation_id: int = _get_executing_animation_id(resolution)
			if executing_animation_id >= 0:
				caster_actor.animate_execute_action(executing_animation_id, false)

	var played_projectile: bool = false
	if action != null and action.projectile_type != ProjectileEffectInstance.ProjectileType.NONE:
		played_projectile = await _play_projectile(resolution, caster_actor, battle_manager)

	if not played_projectile and resolution.play_caster_animation and resolution.impact_delay_seconds > 0.0:
		await Utilities.wait_seconds(resolution.impact_delay_seconds / speed_scale)

	# 3 & 4. Direct Target Impacts, State Commit, Popups, Evade / Flinch / Knockback & User Result
	var waited_for_direct_vfx_or_settle: bool = false
	if resolution.target_results.is_empty():
		if action != null and action.vfx_on_empty and not resolution.targeted_tiles.is_empty():
			var empty_vfx_instances: Array[Node3D] = []
			var empty_tile_position: Vector3 = resolution.targeted_tiles[0].get_world_position()
			var empty_vfx: Node3D = _spawn_vfx(action, caster, empty_tile_position, battle_manager)
			if empty_vfx != null:
				empty_vfx_instances.append(empty_vfx)
			await _wait_for_vfx_or_settle(resolution, empty_vfx_instances, battle_manager, speed_scale)
			waited_for_direct_vfx_or_settle = true
	elif resolution.aoe_presentation_style == ActionResolution.AoePresentation.SEQUENTIAL:
		for target_result: ActionTargetResult in resolution.target_results:
			var target_vfx_instances: Array[Node3D] = []
			var pending_animations: Dictionary[String, int] = {"count": 0}
			_present_target_impact(
				resolution,
				target_result,
				caster_actor,
				battle_manager,
				speed_scale,
				0.0,
				target_vfx_instances,
				pending_animations
			)
			await _wait_for_vfx_or_settle(resolution, target_vfx_instances, battle_manager, speed_scale)
			await _wait_for_pending_animations(pending_animations)
			if is_instance_valid(target_result.target_unit) and target_result.target_unit.unit_actor != null:
				target_result.target_unit.unit_actor.return_to_idle_from_hit()
		waited_for_direct_vfx_or_settle = true
	else:
		var active_vfx_instances: Array[Node3D] = []
		var pending_animations: Dictionary[String, int] = {"count": 0}
		for target_index: int in resolution.target_results.size():
			var target_result: ActionTargetResult = resolution.target_results[target_index]
			var base_popup_delay: float = 0.0
			if resolution.aoe_presentation_style == ActionResolution.AoePresentation.SIMULTANEOUS_STAGGERED:
				base_popup_delay = (float(target_index) * resolution.popup_stagger_seconds) / speed_scale
			_present_target_impact(
				resolution,
				target_result,
				caster_actor,
				battle_manager,
				speed_scale,
				base_popup_delay,
				active_vfx_instances,
				pending_animations
			)

		await _wait_for_vfx_or_settle(resolution, active_vfx_instances, battle_manager, speed_scale)
		await _wait_for_pending_animations(pending_animations)

		for target_result: ActionTargetResult in resolution.target_results:
			if is_instance_valid(target_result.target_unit) and target_result.target_unit.unit_actor != null:
				target_result.target_unit.unit_actor.return_to_idle_from_hit()
		waited_for_direct_vfx_or_settle = true

	if resolution.user_result != null:
		await _present_user_result(resolution, resolution.user_result, caster_actor, speed_scale, not waited_for_direct_vfx_or_settle)
	elif not waited_for_direct_vfx_or_settle and resolution.settle_delay_seconds > 0.0:
		await Utilities.wait_seconds(resolution.settle_delay_seconds / speed_scale)

	# 5. Per-Target Sub-Resolutions, Costs, Secondary Resolutions, Idle Return, Post-Reactions & Turn-End
	for target_result: ActionTargetResult in resolution.target_results:
		for target_sub_resolution: ActionResolution in target_result.target_sub_resolutions:
			await _play_resolution_node(target_sub_resolution, battle_manager, speed_scale)

	if resolution.user_result != null:
		for user_sub_resolution: ActionResolution in resolution.user_result.target_sub_resolutions:
			await _play_resolution_node(user_sub_resolution, battle_manager, speed_scale)

	resolution.apply_costs_to_user()

	for secondary_resolution: ActionResolution in resolution.secondary_resolutions:
		await _play_resolution_node(secondary_resolution, battle_manager, speed_scale)

	if resolution.play_caster_animation and is_instance_valid(caster) and caster.unit_actor != null:
		if caster.current_animation_id_fwd != caster.current_idle_animation_id:
			caster.unit_actor.animate_return_to_idle()

	for post_reaction: ActionResolution in resolution.post_action_reactions:
		await _play_resolution_node(post_reaction, battle_manager, speed_scale)

	resolution.apply_turn_end_flag()


static func _present_target_impact(
	resolution: ActionResolution,
	target_result: ActionTargetResult,
	caster_actor: UnitActor,
	battle_manager: BattleManager,
	speed_scale: float,
	base_popup_delay: float,
	active_vfx_instances: Array[Node3D],
	pending_animations: Dictionary[String, int]
) -> void:
	var action: Action = resolution.action
	var target_unit: UnitData = target_result.target_unit
	var target_actor: UnitActor = target_unit.unit_actor if is_instance_valid(target_unit) else null

	var impact_world_position: Vector3 = Vector3.ZERO
	var has_impact_position: bool = false
	if target_result.target_tile != null:
		impact_world_position = target_result.target_tile.get_world_position()
		has_impact_position = true
	elif is_instance_valid(target_unit) and target_unit.terrain_tile_position != null:
		impact_world_position = target_unit.terrain_tile_position.get_world_position()
		has_impact_position = true

	if action != null and has_impact_position and is_instance_valid(action.vfx_data):
		var vfx_instance: Node3D = _spawn_vfx(action, resolution.user, impact_world_position, battle_manager)
		if vfx_instance != null:
			active_vfx_instances.append(vfx_instance)

	if target_result.did_hit() and action != null and target_actor != null and action.target_shared_vfx_handler_id > 0:
		_play_shared_vfx(action.target_shared_vfx_handler_id, action.element, caster_actor, target_actor, battle_manager)

	target_result.apply_to_unit(false)

	if target_actor != null:
		_schedule_result_popups(target_result, target_actor, resolution.popup_stagger_seconds, speed_scale, base_popup_delay)

		if target_result.did_hit() or target_result.hit_outcome == ActionTargetResult.HitOutcome.ABSORBED:
			_play_target_hit_animation(action, target_result, target_actor)
		elif target_result.hit_outcome in [
			ActionTargetResult.HitOutcome.MISS,
			ActionTargetResult.HitOutcome.EVADED,
			ActionTargetResult.HitOutcome.GUARDED,
		]:
			_run_evade_animation(resolution.user, target_result, target_actor, pending_animations)

	if target_result.knockback_destination_tile != null:
		_run_knockback_slide(target_unit, target_actor, target_result.knockback_destination_tile, speed_scale, pending_animations)


static func _present_user_result(
	resolution: ActionResolution,
	user_result: ActionTargetResult,
	caster_actor: UnitActor,
	speed_scale: float,
	should_wait_settle: bool
) -> void:
	user_result.apply_to_unit(false)

	if caster_actor != null:
		_schedule_result_popups(user_result, caster_actor, resolution.popup_stagger_seconds, speed_scale, 0.0)
		if user_result.statuses_added.has("dead"):
			caster_actor.animate_knock_out()
		elif resolution.target_results.is_empty():
			_play_target_hit_animation(resolution.action, user_result, caster_actor)

	if user_result.knockback_destination_tile != null:
		var pending_knockback: Dictionary[String, int] = {"count": 0}
		_run_knockback_slide(resolution.user, caster_actor, user_result.knockback_destination_tile, speed_scale, pending_knockback)
		await _wait_for_pending_animations(pending_knockback)

	if should_wait_settle and resolution.settle_delay_seconds > 0.0:
		await Utilities.wait_seconds(resolution.settle_delay_seconds / speed_scale)
		if caster_actor != null and resolution.target_results.is_empty():
			caster_actor.return_to_idle_from_hit()


static func _face_first_target(caster: UnitData, targeted_tiles: Array[TerrainTile]) -> void:
	if not is_instance_valid(caster) or caster.terrain_tile_position == null or targeted_tiles.is_empty():
		return
	var primary_tile: TerrainTile = targeted_tiles[0]
	if primary_tile == null or primary_tile == caster.terrain_tile_position:
		return
	var direction_to_target: Vector2i = primary_tile.xz_location - caster.terrain_tile_position.xz_location
	if direction_to_target != Vector2i.ZERO:
		caster.update_unit_facing(Vector3(direction_to_target.x, 0.0, direction_to_target.y))


static func _get_executing_animation_id(resolution: ActionResolution) -> int:
	var action: Action = resolution.action
	if action == null:
		return -1
	var executing_animation_id: int = action.animation_executing_id
	if (
		not resolution.targeted_tiles.is_empty()
		and action.animation_executing_ids_alternate.size() >= 2
		and action.use_weapon_animation
		and is_instance_valid(resolution.user)
		and resolution.user.terrain_tile_position != null
	):
		var primary_tile: TerrainTile = resolution.targeted_tiles[0]
		if primary_tile != null:
			var horizontal_distance: float = (primary_tile.xz_location - resolution.user.terrain_tile_position.xz_location).length()
			if horizontal_distance > 0.0:
				var vertical_slope: float = (primary_tile.height_mid - resolution.user.terrain_tile_position.height_mid) / horizontal_distance
				if vertical_slope > 0.51:
					executing_animation_id = action.animation_executing_ids_alternate[0]
				elif vertical_slope < -0.51:
					executing_animation_id = action.animation_executing_ids_alternate[1]
	return executing_animation_id


static func _play_projectile(
	resolution: ActionResolution,
	caster_actor: UnitActor,
	battle_manager: BattleManager
) -> bool:
	if battle_manager == null or not is_instance_valid(battle_manager.projectile_instance):
		return false
	if caster_actor == null or caster_actor.char_body == null:
		return false

	var destination_position: Vector3 = Vector3.ZERO
	var has_destination: bool = false
	for target_result: ActionTargetResult in resolution.target_results:
		if is_instance_valid(target_result.target_unit) and target_result.target_unit.unit_actor != null and target_result.target_unit.unit_actor.char_body != null:
			destination_position = target_result.target_unit.unit_actor.char_body.global_position
			has_destination = true
			break
	if not has_destination and not resolution.targeted_tiles.is_empty() and resolution.targeted_tiles[0] != null:
		var target_tile: TerrainTile = resolution.targeted_tiles[0]
		destination_position = Vector3(
			target_tile.xz_location.x + 0.5,
			target_tile.get_world_position().y + 0.25,
			target_tile.xz_location.y + 0.5
		)
		has_destination = true

	if not has_destination:
		return false

	var origin_position: Vector3 = caster_actor.char_body.global_position
	var trajectory: ProjectileEffectInstance.Trajectory = ProjectileEffectInstance.Trajectory.LINEAR
	if (
		resolution.action.projectile_type == ProjectileEffectInstance.ProjectileType.ARROW
		and not resolution.action.targeting_los
	):
		trajectory = ProjectileEffectInstance.Trajectory.PARABOLIC

	battle_manager.projectile_instance.play(
		origin_position,
		destination_position,
		resolution.action.projectile_type,
		trajectory
	)
	if battle_manager.projectile_instance.is_playing():
		await battle_manager.projectile_instance.completed
	return true


static func _spawn_vfx(
	action: Action,
	caster: UnitData,
	target_position: Vector3,
	battle_manager: BattleManager
) -> Node3D:
	if action == null or not is_instance_valid(action.vfx_data):
		return null

	var parent_node: Node = null
	if is_instance_valid(caster) and caster.unit_actor != null:
		parent_node = caster.unit_actor.get_parent()
	elif battle_manager != null:
		parent_node = battle_manager.units_container
	if parent_node == null:
		return null

	var vfx_instance: VfxEffectInstance = VfxEffectInstance.new()
	vfx_instance.name = "VfxEffectInstance"
	vfx_instance.position = target_position
	parent_node.add_child(vfx_instance)

	var origin_position: Vector3 = target_position
	if is_instance_valid(caster) and caster.terrain_tile_position != null:
		origin_position = caster.terrain_tile_position.get_world_position()
	vfx_instance.initialize(action.vfx_data, target_position, origin_position)
	return vfx_instance


static func _play_shared_vfx(
	shared_vfx_handler_id: int,
	element: Action.ElementTypes,
	caster_actor: UnitActor,
	target_actor: UnitActor,
	battle_manager: BattleManager
) -> void:
	if shared_vfx_handler_id <= 0 or target_actor == null or target_actor.char_body == null:
		return
	if battle_manager == null or not is_instance_valid(battle_manager.trap_instance):
		return

	var target_position: Vector3 = target_actor.char_body.global_position
	battle_manager.trap_instance.global_position = target_position
	var direction_vector: Vector3 = Vector3.ZERO
	if caster_actor != null and caster_actor.char_body != null:
		direction_vector = (target_position - caster_actor.char_body.global_position).normalized()
	var trap_element: int = TrapEffectData.element_type_to_trap_id(element)
	var flash_unit: UnitActor = target_actor if shared_vfx_handler_id in TrapEffectData.FLASH_HANDLER_IDS else null
	battle_manager.trap_instance.play(shared_vfx_handler_id, trap_element, direction_vector, flash_unit)


static func _play_target_hit_animation(
	action: Action,
	target_result: ActionTargetResult,
	target_actor: UnitActor
) -> void:
	if target_result.statuses_added.has("dead"):
		target_actor.animate_knock_out()
		return
	if action == null or not action.set_target_animation_on_hit:
		return

	var hp_delta: int = target_result.stat_deltas.get(UnitData.StatType.HP, 0)
	var mp_delta: int = target_result.stat_deltas.get(UnitData.StatType.MP, 0)
	if hp_delta < 0 or (hp_delta == 0 and mp_delta < 0):
		target_actor.animate_take_hit()
	elif hp_delta > 0 or (hp_delta == 0 and mp_delta > 0):
		target_actor.animate_recieve_heal()


static func _run_evade_animation(
	caster: UnitData,
	target_result: ActionTargetResult,
	target_actor: UnitActor,
	pending_animations: Dictionary[String, int]
) -> void:
	var target_unit: UnitData = target_result.target_unit
	if not is_instance_valid(target_unit) or not is_instance_valid(target_actor):
		return

	pending_animations["count"] = pending_animations["count"] + 1
	var original_facing: Vector3 = target_unit.get_facing_vector()

	if is_instance_valid(caster) and caster.terrain_tile_position != null and target_unit.terrain_tile_position != null:
		var direction_to_caster: Vector2i = caster.terrain_tile_position.xz_location - target_unit.terrain_tile_position.xz_location
		if direction_to_caster != Vector2i.ZERO:
			target_unit.update_unit_facing(Vector3(direction_to_caster.x, 0.0, direction_to_caster.y).normalized())

	var evade_animation_id: int = EvadeData.animation_ids.get(
		target_result.evade_source,
		EvadeData.animation_ids[EvadeData.EvadeSource.JOB]
	)
	await target_actor.animate_evade(evade_animation_id)

	if is_instance_valid(target_unit):
		target_unit.update_unit_facing(original_facing)
	pending_animations["count"] = maxi(0, pending_animations["count"] - 1)


static func _run_knockback_slide(
	target_unit: UnitData,
	target_actor: UnitActor,
	destination_tile: TerrainTile,
	speed_scale: float,
	pending_animations: Dictionary[String, int]
) -> void:
	if destination_tile == null:
		return

	pending_animations["count"] = pending_animations["count"] + 1
	if is_instance_valid(target_actor) and target_actor.char_body != null and target_actor.is_inside_tree():
		var destination_position: Vector3 = Vector3(
			destination_tile.xz_location.x + 0.5,
			destination_tile.get_world_position().y + 0.25,
			destination_tile.xz_location.y + 0.5
		)
		var slide_tween: Tween = target_actor.create_tween()
		slide_tween.set_trans(Tween.TRANS_QUAD)
		slide_tween.set_ease(Tween.EASE_OUT)
		slide_tween.tween_property(target_actor.char_body, "global_position", destination_position, KNOCKBACK_SLIDE_DURATION_SECONDS / speed_scale)
		await slide_tween.finished

	if is_instance_valid(target_unit):
		target_unit.set_terrain_tile_position(destination_tile)
	pending_animations["count"] = maxi(0, pending_animations["count"] - 1)


static func _schedule_result_popups(
	target_result: ActionTargetResult,
	target_actor: UnitActor,
	popup_stagger_seconds: float,
	speed_scale: float,
	base_delay_seconds: float
) -> void:
	if target_actor == null or target_actor.popup_texts == null:
		return

	var popup_texts: PackedStringArray = []
	var popup_colors: PackedColorArray = []

	if not target_result.did_hit():
		match target_result.hit_outcome:
			ActionTargetResult.HitOutcome.MISS:
				popup_texts.append("Missed!")
				popup_colors.append(COLOR_MISS)
			ActionTargetResult.HitOutcome.EVADED:
				popup_texts.append("Evaded!")
				popup_colors.append(COLOR_MISS)
			ActionTargetResult.HitOutcome.GUARDED:
				popup_texts.append("Guarded!")
				popup_colors.append(COLOR_MISS)
			ActionTargetResult.HitOutcome.NULLIFIED:
				popup_texts.append("Nullified!")
				popup_colors.append(COLOR_MISS)
			ActionTargetResult.HitOutcome.ABSORBED:
				popup_texts.append("Absorbed!")
				popup_colors.append(COLOR_HEAL)

	if target_result.hit_outcome == ActionTargetResult.HitOutcome.CRITICAL:
		popup_texts.append("Critical!")
		popup_colors.append(COLOR_CRITICAL)

	for stat_type: UnitData.StatType in target_result.stat_deltas.keys():
		var delta: int = target_result.stat_deltas[stat_type]
		if delta == 0:
			continue
		if stat_type == UnitData.StatType.HP:
			popup_texts.append(str(absi(delta)))
			if delta > 0:
				popup_colors.append(COLOR_HEAL)
			elif target_result.hit_outcome == ActionTargetResult.HitOutcome.CRITICAL:
				popup_colors.append(COLOR_CRITICAL)
			else:
				popup_colors.append(COLOR_DAMAGE)
		elif stat_type == UnitData.StatType.MP:
			popup_texts.append("%d MP" % absi(delta))
			popup_colors.append(COLOR_MP_HEAL if delta > 0 else COLOR_MP_DAMAGE)
		else:
			var stat_name: String = UnitData.StatType.keys()[stat_type]
			var prefix: String = "+" if delta > 0 else ""
			popup_texts.append("%s%d %s" % [prefix, delta, stat_name])
			popup_colors.append(COLOR_STAT_BUFF if delta > 0 else COLOR_STAT_DEBUFF)

	if target_result.currency_delta != 0:
		var currency_prefix: String = "+" if target_result.currency_delta > 0 else ""
		popup_texts.append("%s%d Gil" % [currency_prefix, target_result.currency_delta])
		popup_colors.append(COLOR_STATUS_ADDED)

	if not target_result.stolen_item_name.is_empty():
		popup_texts.append("Stole %s" % target_result.stolen_item_name)
		popup_colors.append(COLOR_STATUS_ADDED)

	for status_id: String in target_result.statuses_removed:
		popup_texts.append("- %s" % _get_status_display_name(status_id))
		popup_colors.append(COLOR_STATUS_REMOVED)

	for status_id: String in target_result.statuses_added:
		popup_texts.append(_get_status_display_name(status_id))
		popup_colors.append(COLOR_STATUS_ADDED)

	var stagger_step: float = maxf(0.0, popup_stagger_seconds) / speed_scale
	for popup_index: int in popup_texts.size():
		var text: String = popup_texts[popup_index]
		var color: Color = popup_colors[popup_index]
		var delay_seconds: float = base_delay_seconds + (float(popup_index) * stagger_step)
		if delay_seconds <= 0.0 or not target_actor.is_inside_tree():
			target_actor.popup_texts.show_popup_text(text, color)
		else:
			target_actor.get_tree().create_timer(delay_seconds).timeout.connect(
				func() -> void:
					if is_instance_valid(target_actor) and is_instance_valid(target_actor.popup_texts):
						target_actor.popup_texts.show_popup_text(text, color),
				CONNECT_ONE_SHOT
			)


static func _get_status_display_name(status_id: String) -> String:
	var status_effect: StatusEffect = ActionResolver.lookup_status_effect(status_id)
	if status_effect != null and not status_effect.status_effect_name.is_empty():
		return status_effect.status_effect_name
	return status_id.capitalize()


static func _wait_for_vfx_or_settle(
	resolution: ActionResolution,
	active_vfx_instances: Array[Node3D],
	battle_manager: BattleManager,
	speed_scale: float
) -> void:
	if battle_manager != null and is_instance_valid(battle_manager.game_state_label) and resolution.action != null:
		battle_manager.game_state_label.text = "Waiting for " + resolution.action.display_name + " vfx"

	if not active_vfx_instances.is_empty():
		while active_vfx_instances.any(func(vfx_node: Node3D) -> bool: return is_instance_valid(vfx_node)):
			await Utilities.wait_for_frame()
	elif resolution.settle_delay_seconds > 0.0:
		await Utilities.wait_seconds(resolution.settle_delay_seconds / speed_scale)


static func _wait_for_pending_animations(pending_animations: Dictionary[String, int]) -> void:
	while pending_animations["count"] > 0:
		await Utilities.wait_for_frame()
