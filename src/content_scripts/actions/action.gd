class_name Action
extends Resource

const SAVE_FOLDER: String = "actions/"
const FILE_SUFFIX: String = ".action.tres"
# static var current_id: int = 0

@export var unique_name: String = "unique_name" # "ATTACK" and "COPY" are special cases
# @export var action_id: int = 0
# @export var action_idx: int = 0
@export var display_name: String = "Action Name"
@export var description: String = "Action description"
@export var quote: String = "Action quote"
@export var name_will_display: bool = true

@export var useable_strategy: UseableStrategy
@export var targeting_type: TargetingTypes = TargetingTypes.RANGE
var targeting_strategy: TargetingStrategy:
	get:
		return Utilities.targeting_strategies[targeting_type]
@export var use_type: UseTypes = UseTypes.NORMAL
var use_strategy: UseStrategy:
	get:
		return Utilities.use_strategies[use_type]

@export var move_points_cost: int = 0
@export var action_points_cost: int = 1

@export var mp_cost: int = 0

var formula_id: int = 0
var formula_x: int = 0
var formula_y: int = 0
@export var min_targeting_range: int = 0
@export var max_targeting_range: int = 4
@export var area_of_effect_range: int = 0
@export var vertical_tolerance: float = 2.0
var inflict_status_id: int = 0
@export var ticks_charge_time: int = 0

@export var has_vertical_tolerance_from_user: bool = false # vertical fixed / linear range
@export var use_weapon_range: bool = false
@export var use_weapon_targeting: bool = false
@export var use_weapon_damage: bool = false
@export var use_weapon_animation: bool = false
@export var auto_target: bool = false
@export var cant_target_self: bool = false
@export var cant_hit_enimies: bool = false
@export var cant_hit_allies: bool = false
@export var cant_hit_user: bool = false
@export var targeting_top_down: bool = false
@export var cant_follow_target: bool = true
@export var random_fire: bool = false
@export var targeting_linear: bool = false
@export var targeting_los: bool = false # stop at obstacle
@export var aoe_has_vertical_tolerance: bool = true # vertical tolerance
@export var aoe_vertical_tolerance: float = 2.0
@export var aoe_targeting_three_directions: bool = false
@export var aoe_targeting_linear: bool = false
@export var aoe_targeting_los: bool = false # stop at obstacle

@export var target_effects: Array[ActionEffect] = []
@export var user_effects: Array[ActionEffect] = []

#@export var is_evadable: bool = false
@export var applicable_evasion_type: EvadeData.EvadeType = EvadeData.EvadeType.PHYSICAL
@export var is_reflectable: bool = false
@export var is_math_usable: bool = false
@export var is_mimicable: bool = false
@export var blocked_by_golem: bool = false
@export var repeat_use: bool = false # performing
@export var vfx_on_empty: bool = false

@export var allow_triggered_actions: bool = true
@export var trigger_counter_flood: bool = false
@export var trigger_counter_magic: bool = false
@export var trigger_counter_grasp: bool = false

@export var can_target: bool = true

@export var element: ElementTypes = ElementTypes.NONE

@export var base_hit_formula: FormulaData = FormulaData.new("100.0", [100, 0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)

@export var healing_damages_undead: bool = false

# inflict status data
@export var target_status_list: PackedStringArray = []
@export var target_status_chance: int = 100
@export var will_remove_target_status: bool = false
@export var target_status_list_type: StatusListType = StatusListType.EACH
var all_status: bool = false
var random_status: bool = false
var separate_status: bool = false

@export var user_status_list: PackedStringArray = []
@export var user_status_chance: int = 100
@export var will_remove_user_status: bool = false
@export var user_status_list_type: StatusListType = StatusListType.EACH

@export var status_prevents_use_any: Array[String] = [] # silence, dont move, dont act, etc.
@export var required_equipment_type: Array[ItemData.ItemType] = [] # sword, gun, etc.
@export var required_equipment_unique_name: PackedStringArray = [] # materia_blade, etc.

@export var required_target_job_uname: PackedStringArray = [] # dragon, etc.
@export var required_target_status_uname: PackedStringArray = [] # undead
@export var required_target_stat_basis: Array[UnitData.StatBasis] = [] # monster, etc.

# animation data
@export var animation_start_id: int = 0
@export var animation_charging_id: int = 0
@export var animation_executing_id: int = 0
@export var animation_executing_ids_alternate: PackedInt32Array = []

@export var vfx_name: String
@export var vfx_id: int = 0
var vfx_data: VisualEffectData

@export var user_shared_vfx_handler_id: int = 0 # 0 = no shared_vfx, >0 = handler ID from charging_vfx_ids -> shared_vfx_handler_ids
@export var target_shared_vfx_handler_id: int = 0 # 0 = no shared_vfx, >0 = handler ID from charging_vfx_ids -> shared_vfx_handler_ids
@export var projectile_type: ProjectileEffectInstance.ProjectileType = ProjectileEffectInstance.ProjectileType.NONE

# @export var secondary_actions: Array[Action] = [] # skip right to applying ActionEffects to targets, but can use new FormulaData
# @export var secondary_actions: PackedStringArray = [] # list of unique_names
@export var secondary_actions_chances: PackedInt32Array = [100]
@export var secondary_action_list_type: StatusListType = StatusListType.EACH
@export var secondary_actions2: Array[SecondaryAction] = []

@export var set_target_animation_on_hit: bool = true
@export var ends_turn: bool = false

@export var passive_power_modifier_applies_to_hit_chance: bool = false
@export var ignores_statuses: PackedStringArray = [] # unique names
@export var ignore_passives: PackedStringArray = [] # unique names

@export var trigger_types: Array[TriggeredAction.TriggerType] = []

enum ActionType {
	HP_DAMAGE,
	HP_RECOVERY,
	MP_DAMAGE,
	MP_RECOVERY,
	STATUS_CHANGE,
}

enum ElementTypes {
	NONE = 0x00,
	DARK = 0x01,
	HOLY = 0x02,
	WATER = 0x04,
	EARTH = 0x08,
	WIND = 0x10,
	ICE = 0x20,
	LIGHTNING = 0x40,
	FIRE = 0x80,
}

enum StatusListType {
	ALL,
	EACH,
	RANDOM,
}

enum ActionRelativePosition {
	FRONT,
	SIDE,
	BACK,
}

enum TargetingTypes {
	RANGE,
	MOVE,
}

enum UseTypes {
	NORMAL,
	MOVE,
}

# func _init(new_unique_name: String = "unique_name"):
	# unique_name = new_unique_name
	
	# if RomReader.actions.keys().has(new_unique_name):
	# 	push_warning("Overwriting existing action: " + str(new_unique_name))

	# RomReader.actions[unique_name] = self
	# action_id = current_id
	# current_id += 1

	# if new_idx < 0 or new_idx >= RomReader.actions.size():
	# 	if new_idx >= RomReader.actions.size():
	# 		push_warning("Action index (" + str(new_idx) + ") is beyond bounds. Setting action_idx to end of array: " + str(RomReader.actions.size()))
		
	# 	action_idx = RomReader.actions.size()
	# 	RomReader.actions.append(self)
	# else:
	# 	action_idx = new_idx
	# 	RomReader.actions[action_idx] = self
		
	# emit_changed()


static func get_element_types_array(element_bitflags: PackedByteArray) -> Array[ElementTypes]:
	var elemental_types: Array[ElementTypes] = []
	
	for byte_idx: int in element_bitflags.size():
		for bit_idx: int in range(7, -1, -1):
			var byte: int = element_bitflags.decode_u8(byte_idx)
			if byte & (2 ** bit_idx) != 0:
				# var element_index: int = (7 - bit_idx) + (byte_idx * 8)
				elemental_types.append(2 ** bit_idx)
	
	return elemental_types


static func get_modified_action(action_to_modify: Action, user: UnitData, units_override: Array[UnitData] = []) -> Action:
	var modified_action: Action = action_to_modify.duplicate()
	modified_action.vfx_data = action_to_modify.vfx_data
	modified_action.user_shared_vfx_handler_id = action_to_modify.user_shared_vfx_handler_id
	modified_action.secondary_actions2 = action_to_modify.secondary_actions2.duplicate()
	var all_passive_effects: Array[PassiveEffect] = user.get_all_passive_effects(action_to_modify.ignore_passives, units_override)

	var charge_time_modifiers: Array[Modifier] = []
	var mp_modifiers: Array[Modifier] = []
	var max_range_modifiers: Array[Modifier] = []
	for passive_effect: PassiveEffect in all_passive_effects:
		charge_time_modifiers.append(passive_effect.action_charge_time_modifier)
		mp_modifiers.append(passive_effect.action_mp_modifier)
		max_range_modifiers.append(passive_effect.action_max_range_modifier)

	modified_action.ticks_charge_time = Modifier.apply_all(charge_time_modifiers, modified_action.ticks_charge_time)
	modified_action.mp_cost = Modifier.apply_all(mp_modifiers, modified_action.mp_cost)
	modified_action.max_targeting_range = Modifier.apply_all(max_range_modifiers, modified_action.max_targeting_range)

	return modified_action


func _to_string() -> String:
	return display_name


# TODO set action type directly for each action? maybe as part of action processing per target to check values after formula processing and passive effect modifications
func get_action_types() -> Array[ActionType]:
	var action_types: Array[ActionType] = []
	
	for effect: ActionEffect in target_effects:
		if effect.type == ActionEffect.EffectType.UNIT_STAT:
			var effective_sign: float = 1.0
			if effect.base_power_formula.reverse_sign:
				effective_sign = -1.0
			if not effect.base_power_formula.values.is_empty() and effect.base_power_formula.values[0] < 0.0:
				effective_sign = -effective_sign
			if effect.effect_stat_type == UnitData.StatType.HP:
				if effective_sign > 0.0 and not action_types.has(ActionType.HP_RECOVERY):
					action_types.append(ActionType.HP_RECOVERY)
				elif effective_sign < 0.0 and not action_types.has(ActionType.HP_DAMAGE):
					action_types.append(ActionType.HP_DAMAGE)
			elif effect.effect_stat_type == UnitData.StatType.MP:
				if effective_sign > 0.0 and not action_types.has(ActionType.MP_RECOVERY):
					action_types.append(ActionType.MP_RECOVERY)
				elif effective_sign < 0.0 and not action_types.has(ActionType.MP_DAMAGE):
					action_types.append(ActionType.MP_DAMAGE)
	
	if not target_status_list.is_empty():
		action_types.append(ActionType.STATUS_CHANGE)
	
	return action_types
