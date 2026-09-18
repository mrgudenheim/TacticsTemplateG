class_name Action
extends Resource

const SAVE_FOLDER: String = "actions"
const FILE_SUFFIX: String = "action"
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
@export var required_target_stat_basis: Array[Unit.StatBasis] = [] # monster, etc.

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

class SecondaryAction:
	var action_idx: int
	var action_unique_name: String
	var chance: int
	
	func _init(new_unique_name: String, new_chance: int) -> void:
		action_unique_name = new_unique_name
		chance = new_chance

# @export var secondary_actions: Array[Action] = [] # skip right to applying ActionEffects to targets, but can use new FormulaData
# @export var secondary_actions: PackedStringArray = [] # list of unique_names
@export var secondary_actions_chances: PackedInt32Array = [100]
@export var secondary_action_list_type: StatusListType = StatusListType.EACH
var secondary_actions2: Array[SecondaryAction] = []

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


static func create_from_json(json_string: String) -> Action:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_action: Action = create_from_dictonary(property_dict)
	
	return new_action


static func create_from_dictonary(property_dict: Dictionary) -> Action:
	var new_action: Action = Action.new()
	for property_name: String in property_dict.keys():
		if ["target_effects", "user_effects"].has(property_name):
			var new_effects: Array[ActionEffect] = []
			for effect: Dictionary in property_dict[property_name]:
				var new_action_effect: ActionEffect = ActionEffect.create_from_dictionary(effect)
				new_effects.append(new_action_effect)
			new_action.set(property_name, new_effects)
		elif property_name == "base_hit_formula":
			var new_formula_data: FormulaData = FormulaData.create_from_dictionary(property_dict[property_name])
			new_action.set(property_name, new_formula_data)
		elif ["action_id", "action_idx"].has(property_name):
			if property_dict[property_name] >= 0: # auto generate action_id if < 0
				new_action.set(property_name, property_dict[property_name])
				# TODO overwrite other Action at index
		elif property_name == "projectile_type":
			new_action.projectile_type = ProjectileEffectInstance.ProjectileType[property_dict[property_name]]
		elif property_name == "applicable_evasion_type":
			new_action.applicable_evasion_type = EvadeData.EvadeType[property_dict[property_name]]
		elif property_name == "element":
			new_action.element = ElementTypes[property_dict[property_name]]
		elif property_name == "target_status_list_type":
			new_action.target_status_list_type = StatusListType[property_dict[property_name]]
		elif property_name == "user_status_list_type":
			new_action.user_status_list_type = StatusListType[property_dict[property_name]]
		elif property_name == "targeting_type":
			new_action.targeting_type = TargetingTypes[property_dict[property_name]]
		elif property_name == "use_type":
			new_action.use_type = UseTypes[property_dict[property_name]]
		else:
			new_action.set(property_name, property_dict[property_name])

	new_action.emit_changed()
	return new_action


static func get_element_types_array(element_bitflags: PackedByteArray) -> Array[ElementTypes]:
	var elemental_types: Array[ElementTypes] = []
	
	for byte_idx: int in element_bitflags.size():
		for bit_idx: int in range(7, -1, -1):
			var byte: int = element_bitflags.decode_u8(byte_idx)
			if byte & (2 ** bit_idx) != 0:
				# var element_index: int = (7 - bit_idx) + (byte_idx * 8)
				elemental_types.append(2 ** bit_idx)
	
	return elemental_types


static func get_modified_action(action_to_modify: Action, user: Unit) -> Action:
	if action_to_modify == null:
		push_error("Action.get_modified_action: null action")
		return null
	var modified_action: Action = action_to_modify.duplicate()
	modified_action.vfx_data = action_to_modify.vfx_data
	modified_action.user_shared_vfx_handler_id = action_to_modify.user_shared_vfx_handler_id
	var all_passive_effects: Array[PassiveEffect] = user.get_all_passive_effects(action_to_modify.ignore_passives)

	for passive_effect: PassiveEffect in all_passive_effects:
		modified_action.ticks_charge_time = passive_effect.action_charge_time_modifier.apply(modified_action.ticks_charge_time)
		modified_action.mp_cost = passive_effect.action_mp_modifier.apply(modified_action.mp_cost)
		modified_action.max_targeting_range = passive_effect.action_max_range_modifier.apply(modified_action.max_targeting_range)

	return modified_action


func _to_string() -> String:
	return display_name


func add_to_global_list(will_overwrite: bool = false) -> void:
	if ["", "unique_name"].has(unique_name):
		unique_name = display_name.to_snake_case()
	
	if RomReader.actions.keys().has(unique_name) and will_overwrite:
		push_warning("Overwriting existing action: " + unique_name)
	elif RomReader.actions.keys().has(unique_name) and not will_overwrite:
		var num: int = 2
		var formatted_num: String = "%02d" % num
		var new_unique_name: String = unique_name + "_" + formatted_num
		while RomReader.actions.keys().has(new_unique_name):
			num += 1
			formatted_num = "%02d" % num
			new_unique_name = unique_name + "_" + formatted_num
		
		push_warning("Action list already contains: " + unique_name + ". Incrementing unique_name to: " + new_unique_name)
		unique_name = new_unique_name
	
	RomReader.actions[unique_name] = self


# TODO set action type directly for each action? maybe as part of action processing per target to check values after formula processing and passive effect modifications
func get_action_types() -> Array[ActionType]:
	var action_types: Array[ActionType] = []
	
	for effect: ActionEffect in target_effects:
		if effect.type == ActionEffect.EffectType.UNIT_STAT:
			if effect.effect_stat_type == Unit.StatType.HP:
				if effect.base_power_formula.values[0] > 0:
					action_types.append(ActionType.HP_RECOVERY)
				elif effect.base_power_formula.values[0] < 0:
					action_types.append(ActionType.HP_DAMAGE)
			if effect.effect_stat_type == Unit.StatType.MP:
				if effect.base_power_formula.values[0] > 0:
					action_types.append(ActionType.MP_RECOVERY)
				elif effect.base_power_formula.values[0] < 0:
					action_types.append(ActionType.MP_DAMAGE)
		if not target_status_list.is_empty():
			action_types.append(ActionType.STATUS_CHANGE)
	
	return action_types


func set_data_from_formula_id(new_formula_id: int) -> void:
	formula_id = new_formula_id
	# ignores_statuses.append_array(["protect", "shell"]) # protect and shell
	ignore_passives = [
		"protect_status",
		"shell_status",
		"attack_up",
		"defense_up",
		"magic_attack_up",
		"magic_defense_up",
		"martial_arts",
		"throw_item",
		"monster_talk",
		"maintenance",
		"finger_guard",
	]
	# https://ffhacktics.com/wiki/Target_XA_affecting_Statuses_(Physical)
	# https://ffhacktics.com/wiki/Target%27s_Status_Affecting_XA_(Magical)
	# https://ffhacktics.com/wiki/Evasion_Changes_due_to_Statuses
	# evade also affected by transparent, concentrate, dark or confuse, on user
	
	match formula_id:
		0:
			use_weapon_damage = true
			target_status_chance = 19
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		1, 5:
			# TODO get reference to weapon effects?
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_BRAVE_X_PA
			target_effects[0].base_power_formula.formula_text = "(user.physical_attack * user.brave / 100.0) * user.physical_attack"
			# target_effects[0].base_power_formula.formula_text = user.primary_weapon.attack_action.target_effects[0].base_power_formula.formula_text
			
			use_weapon_damage = true
			target_status_chance = 19
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		2:
			use_weapon_damage = true
			# secondary_actions.append(RomReader.abilities[inflict_status_id].ability_action)
			target_status_chance = 19
			# secondary_actions_chances = [19]
			secondary_actions2.append(SecondaryAction.new(RomReader.fft_abilities[inflict_status_id].ability_action.unique_name, target_status_chance))
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		3: # weapon_power * weapon_power
			applicable_evasion_type = EvadeData.EvadeType.NONE
			use_weapon_damage = true
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		4:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			var secondary_action_unique_names: PackedStringArray = []
			match element:
				ElementTypes.FIRE:
					secondary_action_unique_names = ["fire", "fire_2", "fire_3"]
				ElementTypes.LIGHTNING:
					secondary_action_unique_names = ["bolt", "bolt_2", "bolt_3"]
				ElementTypes.ICE:
					secondary_action_unique_names = ["ice", "ice_2", "ice_3"]
			
			secondary_actions_chances = [60, 30, 10]
			secondary_action_list_type = StatusListType.RANDOM
			
			for secondary_action_idx: int in secondary_action_unique_names.size():
				# var new_action: Action = RomReader.abilities[secondary_action_ids[secondary_action_idx]].ability_action.duplicate(true) # abilities need to be initialized before items
				var reference_action_unique_name: String = secondary_action_unique_names[secondary_action_idx]
				var new_action: Action = RomReader.actions[reference_action_unique_name].duplicate_deep() # abilities need to be initialized before items
				new_action.display_name = "Magic Gun " + new_action.display_name
				new_action.add_to_global_list()
				new_action.area_of_effect_range = 0
				# new_action.target_effects[0].base_power_formula.formula = FormulaData.Formulas.WP_X_V1
				new_action.target_effects[0].base_power_formula.formula_text = "user.primary_weapon.weapon_power * " + str(new_action.target_effects[0].base_power_formula.values[0])
				new_action.mp_cost = 0
				var chance: int = secondary_actions_chances[secondary_action_idx]
				# secondary_actions.append(new_action)
				secondary_actions2.append(SecondaryAction.new(new_action.unique_name, chance))
			
			# TODO damage formula is WP (instead of MA) * ability Y
			# TODO magic gun should probably use totally new Actions?, with WP*V1 formula, EvadeType.NONE, no costs, animation_ids = 0, etc., but where V1 and vfx are from the original action
			# TODO math skills, charge skills, etc. behave kind of similarly with using partial data from other actions
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		6:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			target_effects[0].transfer_to_user = true # absorb hp
			use_weapon_damage = true
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		7:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			use_weapon_damage = true
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			target_effects[0].base_power_formula.reverse_sign = false # heal
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		8:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			target_status_chance = 19
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			target_effects[0].base_power_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		9:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			target_status_chance = 19
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true

			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x0a:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x0b:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
		0x0c:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			target_effects[0].base_power_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			target_effects[0].base_power_formula.reverse_sign = false
		0x0d:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			target_effects[0].base_power_formula.reverse_sign = false
		0x0e:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# TODO apply status first? if target is immune to status, no damage
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_status_chance = 100
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x0f:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_MP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.mp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x10:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x11:
			pass
		0x12:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.CT))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = "100.0"
			target_effects[0].base_power_formula.values[0] = 100
			target_effects[0].set_value = true
		0x13:
			pass
		0x14:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# TODO set Golem
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
		0x15:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.CT))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = "0.0"
			target_effects[0].base_power_formula.values[0] = 0
			target_effects[0].set_value = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x16:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_MP_MINUS_V1
			target_effects[0].base_power_formula.formula_text = "target.mp"
			target_effects[0].base_power_formula.values[0] = 0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x17:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_HP_MINUS_V1
			target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x18, 0x19:
			pass
		0x1a:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_y)
			base_hit_formula.values[0] = formula_y
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.PHYSICAL_ATTACK)) # TODO MAGICAL_ATTACK or SPEED dependent on ability ID?
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_x)
			target_effects[0].base_power_formula.values[0] = formula_x
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x1b:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_MP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.mp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x1c:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.V1
			base_hit_formula.formula_text = str(formula_x)
			base_hit_formula.values[0] = formula_x
			
			# TODO song effects based on ability ID
		0x1d:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.V1
			base_hit_formula.formula_text = str(formula_x)
			base_hit_formula.values[0] = formula_x
			
			# TODO dance effects based on ability ID
		0x1e:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			target_effects[0].base_power_formula.formula_text = "(user.magical_attack + %.2f) * user.magical_attack / 2.0" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			# TODO random number of hits within AoE
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x1f:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			target_effects[0].base_power_formula.formula_text = "(user.magical_attack + %.2f) * user.magical_attack / 2.0" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.user_faith_modifier = FormulaData.FaithModifier.UNFAITH
			target_effects[0].base_power_formula.target_faith_modifier = FormulaData.FaithModifier.UNFAITH
			# TODO random number of hits within AoE
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")

			target_status_chance = 19
		0x20:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			# TODO chance to decrease inventory
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x21:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			# TODO chance to decrease inventory
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x22:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# TODO chance to decrease inventory
		0x23:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = false # heal
			# TODO chance to decrease inventory
		0x24:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_PLUS_V1_X_MA_DIV_2
			target_effects[0].base_power_formula.formula_text = "(user.physical_attack + %.2f) * user.magical_attack / 2.0" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			# TODO usable based on terrain?
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x25:
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_WP_PLUS_V1
			base_hit_formula.formula_text = "user.physical_attack + user.primary_weapon.weapon_power + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true

			target_effects.append(ActionEffect.new(ActionEffect.EffectType.REMOVE_EQUIPMENT))
			# TODO set equipement slod id based on ability id?
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			ignore_passives.erase("maintenance")
			passive_power_modifier_applies_to_hit_chance = true
		0x26:
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			base_hit_formula.formula_text = "user.speed + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true

			target_effects.append(ActionEffect.new(ActionEffect.EffectType.REMOVE_EQUIPMENT))
			target_effects[0].transfer_to_user = true
			# TODO set equipement slod id based on ability id?
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			ignore_passives.erase("maintenance")
			passive_power_modifier_applies_to_hit_chance = true
		0x27:
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			base_hit_formula.formula_text = "user.speed + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.LVL_X_SP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.level * user.speed"
			target_effects[0].base_power_formula.values[0] = 1
			# TODO add to user currency? user_effects.append(ActionEffect.new(ActionEffect.EffectType.CURRENCY))
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x28:
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			base_hit_formula.formula_text = "user.speed + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.EXP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MIN_TARGET_EXP_OR_SP_PLUS_V1
			target_effects[0].base_power_formula.formula_text = "minf(target.unit_exp, user.speed + %.2f" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x29:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# TODO hit chance based on gender
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
		0x2a:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = false
			# TODO set effects based on ability id

			ignore_passives.erase("finger_guard")
			ignore_passives.erase("monster_talk")

			# only work on non-monsters
			required_target_stat_basis = [
				Unit.StatBasis.MALE,
				Unit.StatBasis.FEMALE,
				Unit.StatBasis.OTHER,
			]
		0x2b:
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			base_hit_formula.formula_text = "user.physical_attack + %.2f" % formula_y
			base_hit_formula.values[0] = formula_y
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.SPEED))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_x)
			target_effects[0].base_power_formula.values[0] = formula_x
			# TODO set effects based on ability id
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x2c:
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			base_hit_formula.formula_text = "user.physical_attack + %.2f" % formula_y
			base_hit_formula.values[0] = formula_y
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = "%.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x2d:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_PLUS_V1
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * (user.primary_weapon.weapon_power + %.2f)" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			
			target_status_chance = 100
			target_status_list_type = StatusListType.RANDOM
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		0x2e:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * user.primary_weapon.weapon_power"
			target_effects[0].base_power_formula.values[0] = 1
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.REMOVE_EQUIPMENT))
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[1].base_power_formula.formula_text = "1.0"
			target_effects[1].base_power_formula.values[0] = 1
			# TODO set equipement slod id based on ability id?
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		0x2f:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * user.primary_weapon.weapon_power"
			target_effects[0].base_power_formula.values[0] = 1
			target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		0x30:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * user.primary_weapon.weapon_power"
			target_effects[0].base_power_formula.values[0] = 1
			target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		0x31:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_PA_PLUS_V1_DIV_2
			target_effects[0].base_power_formula.formula_text = "(user.physical_attack + %.2f) * user.physical_attack / 2.0"
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")

			target_status_chance = 19
		0x32:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.RANDOM_V1_X_PA_X_3_PLUS_V2_DIV_2
			target_effects[0].base_power_formula.formula_text = "randi_range(1, %d) * ((user.physical_attack * 3.0) + %d)" % [formula_x, formula_y]
			target_effects[0].base_power_formula.values[0] = formula_x
			target_effects[0].base_power_formula.values[1] = formula_y
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		0x33:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			base_hit_formula.formula_text = "user.physical_attack + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
		0x34:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * %d" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = false
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			target_effects[1].base_power_formula.formula_text = "user.physical_attack * %.2f" % (formula_y / 2.0)
			target_effects[1].base_power_formula.values[0] = formula_y / 2.0
			target_effects[1].base_power_formula.reverse_sign = false
		0x35:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			base_hit_formula.formula_text = "user.physical_attack + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			target_effects[0].base_power_formula.reverse_sign = false
		0x36:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.PHYSICAL_ATTACK))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = false
		0x37:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.RANDOM_V1_X_PA
			target_effects[0].base_power_formula.formula_text = "randi_range(1, %d) * user.physical_attack" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		0x38:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_status_chance = 100
		0x39:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.SPEED))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = false
		0x3a:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = false
		0x3b:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_x)
			target_effects[0].base_power_formula.values[0] = formula_x
			target_effects[0].base_power_formula.reverse_sign = false
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.SPEED)) # TODO set type based on ability id
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[1].base_power_formula.formula_text = str(formula_y)
			target_effects[1].base_power_formula.values[0] = formula_y
			target_effects[1].base_power_formula.reverse_sign = false
			
		0x3c:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * 0.4"
			target_effects[0].base_power_formula.values[0] = 2.0 / 5.0
			target_effects[0].base_power_formula.reverse_sign = false
			
			user_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP)) # TODO this should be per target
			# user_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			user_effects[0].base_power_formula.formula_text = "target.hp_max * 0.2"
			user_effects[0].base_power_formula.values[0] = 1.0 / 5.0
		0x3d:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x3e:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_HP_MINUS_V1
			target_effects[0].base_power_formula.formula_text = "target.hp - 1"
			target_effects[0].base_power_formula.values[0] = 1
		0x3f:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			base_hit_formula.formula_text = "user.speed + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x40:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			base_hit_formula.formula_text = "user.speed + %.2f" % formula_x
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true

			required_target_status_uname = [
				"undead"
			]
		0x41:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x42:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * %d" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			
			user_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# user_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			user_effects[0].base_power_formula.formula_text = "user.physical_attack * %.2f" % (formula_y / float(formula_x))
			user_effects[0].base_power_formula.values[0] = formula_y / float(formula_x)
		0x43:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_MISSING_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.hp_max - user.hp"
			target_effects[0].base_power_formula.values[0] = 1
		0x44:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_MP_MINUS_V1
			target_effects[0].base_power_formula.formula_text = "target.mp"
			target_effects[0].base_power_formula.values[0] = 0
		0x45:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MISSING_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max - target.hp"
			target_effects[0].base_power_formula.values[0] = 1
		0x46:
			pass
		0x47:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_status_chance = 100
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
		0x48:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_x * 10)
			target_effects[0].base_power_formula.values[0] = formula_x * 10 # maybe should be handled in Item initialization?
			target_effects[0].base_power_formula.reverse_sign = false # heal
		0x49:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_x * 10)
			target_effects[0].base_power_formula.values[0] = formula_x * 10 # maybe should be handled in Item initialization?
			target_effects[0].base_power_formula.reverse_sign = false # heal
		0x4a:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			#target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			#target_effects[0].base_power_formula.formula = FormulaData.Formulas.UNMODIFIED
			#target_effects[0].base_power_formula.value_01 = formula_x * 10 # maybe should be handled in Item initialization?
			#target_effects[0].base_power_formula.reverse_sign = false # heal
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max"
			target_effects[0].base_power_formula.values[0] = 1 # maybe should be handled in Item initialization?
			target_effects[0].base_power_formula.reverse_sign = false # heal
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_MP_X_V1
			target_effects[1].base_power_formula.formula_text = "target.mp_max"
			target_effects[1].base_power_formula.values[0] = 1 # maybe should be handled in Item initialization?
			target_effects[1].base_power_formula.reverse_sign = false # heal
		0x4b:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_status_chance = 100
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.RANDOM_V1_V2
			target_effects[0].base_power_formula.formula_text = "randi_range(1, 9)"
			target_effects[0].base_power_formula.values[0] = 1
			target_effects[0].base_power_formula.values[1] = 9
			target_effects[0].base_power_formula.reverse_sign = false # heal
		0x4c:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = false # heal
		0x4d:
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x4e:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x4f:
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_MISSING_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.hp_max - user.hp"
			target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x50:
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
			passive_power_modifier_applies_to_hit_chance = true
		0x51:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_element = true # TODO only Strengthen element?
			base_hit_formula.is_modified_by_zodiac = true
		0x52:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_status_chance = 100
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_MISSING_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.hp_max - user.hp"
			target_effects[0].base_power_formula.values[0] = 1
			
			user_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# user_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_CURRENT_HP_MINUS_V1
			user_effects[0].base_power_formula.formula_text = "user.hp"
			user_effects[0].base_power_formula.values[0] = 0
		0x53:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true

			target_status_chance = 19
		0x54:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			target_effects[0].base_power_formula.formula_text = "user.magical_attack * " + str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			target_effects[0].base_power_formula.reverse_sign = true
		0x55:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.PHYSICAL_ATTACK))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x56:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.MAGIC_ATTACK))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x57:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.LEVEL))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = "1.0"
			target_effects[0].base_power_formula.values[0] = 1
			target_effects[0].base_power_formula.reverse_sign = false # add

			user_status_list = target_status_list.duplicate()
			user_status_chance = target_status_chance
			user_status_list_type = target_status_list_type
			will_remove_user_status = will_remove_target_status

			target_status_list.clear()
		0x58:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_element = true # TODO element Strengthen only
			base_hit_formula.is_modified_by_zodiac = true
			
			# TODO set MORBOL
		0x59:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.LEVEL))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = "1.0"
			target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x5a:
			target_status_chance = 100
			
			required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5b:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_status_chance = 100
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			target_effects[0].base_power_formula.formula_text = "target.hp_max * %.2f" % (formula_y / 100.0)
			target_effects[0].base_power_formula.values[0] = formula_y

			required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5c:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_x)
			target_effects[0].base_power_formula.values[0] = formula_x
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.SPEED)) # TODO set type based on ability id
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[1].base_power_formula.formula_text = str(formula_y)
			target_effects[1].base_power_formula.values[0] = formula_y
			target_effects[1].base_power_formula.reverse_sign = false
			
			required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5d:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.CT))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = "100.0"
			target_effects[0].base_power_formula.values[0] = 100
			target_effects[0].set_value = true

			required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5e:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			target_status_chance = 19
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			target_effects[0].base_power_formula.formula_text = "(user.magical_attack + %.2f) * user.magical_attack / 2.0" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			# TODO x+1 hits at random target in AoE
		0x5f:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			target_status_chance = 19
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			target_effects[0].base_power_formula.formula_text = "(user.magical_attack + %.2f) * user.magical_attack / 2.0" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x60:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			target_effects[0].base_power_formula.formula_text = "(user.magical_attack + %.2f) * user.magical_attack / 2.0" % formula_y
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x61:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			base_hit_formula.is_modified_by_element = true
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
			passive_power_modifier_applies_to_hit_chance = true
		0x62:
			applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			base_hit_formula.formula_text = "user.magical_attack + " + str(formula_x)
			base_hit_formula.values[0] = formula_x
			base_hit_formula.is_modified_by_zodiac = true
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			target_effects[0].base_power_formula.formula_text = str(formula_y)
			target_effects[0].base_power_formula.values[0] = formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			ignore_passives.erase("shell_status")
			ignore_passives.erase("magic_attack_up")
			ignore_passives.erase("magic_defense_up")
		0x63:
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1 # TODO SPxWP
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * user.primary_weapon.weapon_power"
			target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
		0x64:
			applicable_evasion_type = EvadeData.EvadeType.NONE
			
			target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, Unit.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			target_effects[0].base_power_formula.formula_text = "user.physical_attack * user.primary_weapon.weapon_power"
			target_effects[0].base_power_formula.values[0] = 1 # TODO 1.5 if spear, PAxBRAVE if unarmed, else 1
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			ignore_passives.erase("protect_status")
			ignore_passives.erase("attack_up")
			ignore_passives.erase("defense_up")
			ignore_passives.erase("martial_arts")
	
	emit_changed()


func to_json() -> String:
	var properties_to_exclude: PackedStringArray = [
		"RefCounted",
		"Resource",
		"resource_local_to_scene",
		"resource_path",
		"resource_name",
		"resource_scene_unique_id",
		"script",
	]
	return Utilities.object_properties_to_json(self, properties_to_exclude)
