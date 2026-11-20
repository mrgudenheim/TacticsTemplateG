class_name ActionResolution
extends RefCounted
## Uniform non-visual structure representing an action execution, secondary action, or reaction.
## Produced by ActionResolver; consumed by ActionPresenter, ActionPreview, and ActionInstance.get_ai_score().

enum AoePresentation {
	SIMULTANEOUS_STAGGERED,
	SEQUENTIAL,
	SIMULTANEOUS_EXACT,
}

# --- Context & Role Flags ---
var action: Action = null
var user: UnitData = null
var targeted_tiles: Array[TerrainTile] = []
var targeted_units: Array[UnitData] = []
var is_preview_only: bool = false
var is_reaction: bool = false
var is_secondary_action: bool = false
var play_caster_animation: bool = true
var roll_hit_chance: bool = true
var chain_depth: int = 0

# --- Secondary Branch Probability Metadata (used in preview/AI mode on child ActionResolutions) ---
var branch_chance_percent: int = 100
var branch_list_type: Action.StatusListType = Action.StatusListType.EACH
var branch_weight_sum: int = 100

# --- Deterministic RNG Metadata ---
var rng_seed: int = 0
var rng_initial_state: int = 0

# --- Execution-Time Costs (turn move/action points are deducted on queue_use, not here) ---
var mp_cost: int = 0
var consumable_item_index: int = -1

# --- Timing & AOE Presentation ---
var impact_delay_seconds: float = 0.2
var settle_delay_seconds: float = 0.4
var popup_stagger_seconds: float = 0.1
var aoe_presentation_style: AoePresentation = AoePresentation.SIMULTANEOUS_STAGGERED

# --- Direct Target & Self Outcomes ---
var target_results: Array[ActionTargetResult] = []
var user_result: ActionTargetResult = null

# --- Ordered Child ActionResolution Lists ---
var pre_action_reactions: Array[ActionResolution] = []
var secondary_resolutions: Array[ActionResolution] = []
var post_action_reactions: Array[ActionResolution] = []

# --- Outcome Flags ---
var was_aborted_before_execution: bool = false
var user_defeated_during_action: bool = false
var ends_turn: bool = false


func is_probabilistic_branch() -> bool:
	return is_preview_only and (branch_chance_percent < 100 or branch_list_type == Action.StatusListType.RANDOM)


func get_branch_probability() -> float:
	if not is_probabilistic_branch():
		return 1.0
	if branch_list_type == Action.StatusListType.RANDOM:
		return float(branch_chance_percent) / float(maxi(1, branch_weight_sum))
	return clampf(branch_chance_percent / 100.0, 0.0, 1.0)


func get_direct_target_result(target_unit: UnitData) -> ActionTargetResult:
	for target_result: ActionTargetResult in target_results:
		if target_result.target_unit == target_unit:
			return target_result
	return null


func apply_costs_to_user() -> void:
	if is_preview_only or was_aborted_before_execution or not is_instance_valid(user):
		return
	if mp_cost != 0 and user.stats.has(UnitData.StatType.MP):
		user.stats[UnitData.StatType.MP].add_value(-mp_cost)
	if consumable_item_index >= 0 and user.team != null and consumable_item_index < user.team.inventory.size():
		user.team.inventory[consumable_item_index] = maxi(0, user.team.inventory[consumable_item_index] - 1)


func apply_turn_end_flag() -> void:
	if is_preview_only or is_reaction or is_secondary_action or not is_instance_valid(user):
		return
	if ends_turn:
		user.is_ending_turn = true


func apply_all_state_changes() -> void:
	## Instantly applies all state mutations across a resolved live/replay tree (headless tests or skip_action_animations).
	for pre_reaction: ActionResolution in pre_action_reactions:
		pre_reaction.apply_all_state_changes()

	if not was_aborted_before_execution:
		for target_result: ActionTargetResult in target_results:
			target_result.apply_to_unit(true)
			for target_sub_resolution: ActionResolution in target_result.target_sub_resolutions:
				target_sub_resolution.apply_all_state_changes()
		if user_result != null:
			user_result.apply_to_unit(true)
			for user_sub_resolution: ActionResolution in user_result.target_sub_resolutions:
				user_sub_resolution.apply_all_state_changes()
		apply_costs_to_user()

	for secondary_resolution: ActionResolution in secondary_resolutions:
		secondary_resolution.apply_all_state_changes()

	for post_reaction: ActionResolution in post_action_reactions:
		post_reaction.apply_all_state_changes()

	apply_turn_end_flag()


func get_execution_order() -> Array[ActionResolution]:
	var execution_order: Array[ActionResolution] = []
	for pre_reaction: ActionResolution in pre_action_reactions:
		execution_order.append_array(pre_reaction.get_execution_order())
	if not was_aborted_before_execution:
		execution_order.append(self)
		for target_result: ActionTargetResult in target_results:
			for target_sub_resolution: ActionResolution in target_result.target_sub_resolutions:
				execution_order.append_array(target_sub_resolution.get_execution_order())
		if user_result != null:
			for user_sub_resolution: ActionResolution in user_result.target_sub_resolutions:
				execution_order.append_array(user_sub_resolution.get_execution_order())
	for secondary_resolution: ActionResolution in secondary_resolutions:
		execution_order.append_array(secondary_resolution.get_execution_order())
	for post_reaction: ActionResolution in post_action_reactions:
		execution_order.append_array(post_reaction.get_execution_order())
	return execution_order
