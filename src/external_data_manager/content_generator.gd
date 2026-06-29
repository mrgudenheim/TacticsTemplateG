class_name ContentGenerator

static func get_predefined_passive_effects() -> Dictionary[String, PassiveEffect]:
	var predefined_passive_effects: Dictionary[String, PassiveEffect] = {}

	var new_passive_effect: PassiveEffect

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "attack_up"
	new_passive_effect.power_modifier_user = Modifier.new("value * 1.33", Modifier.ModifierType.MULT)
	# new_passive_effect.power_modifier_user = Modifier.new(1.33, Modifier.ModifierType.MULT)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "magic_attack_up"
	new_passive_effect.power_modifier_user = Modifier.new("value * 1.33", Modifier.ModifierType.MULT)
	# new_passive_effect.power_modifier_user = Modifier.new(1.33, Modifier.ModifierType.MULT)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "martial_arts"
	new_passive_effect.power_modifier_user = Modifier.new("value * 1.5", Modifier.ModifierType.MULT)
	# new_passive_effect.power_modifier_user = Modifier.new(1.5, Modifier.ModifierType.MULT)
	new_passive_effect.requires_user_item_type = ["FIST"]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "defense_up"
	new_passive_effect.power_modifier_user = Modifier.new("value * 0.66", Modifier.ModifierType.MULT)
	# new_passive_effect.power_modifier_targeted = Modifier.new(0.66, Modifier.ModifierType.MULT)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "magic_defense_up"
	new_passive_effect.power_modifier_user = Modifier.new("value * 0.66", Modifier.ModifierType.MULT)
	# new_passive_effect.power_modifier_targeted = Modifier.new(0.66, Modifier.ModifierType.MULT)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "concentrate"
	var evade_modifier_dict: Dictionary[EvadeData.EvadeSource, Modifier] = {
		EvadeData.EvadeSource.JOB: Modifier.new("0.0", Modifier.ModifierType.SET),
		EvadeData.EvadeSource.SHIELD: Modifier.new("0.0", Modifier.ModifierType.SET),
		EvadeData.EvadeSource.ACCESSORY: Modifier.new("0.0", Modifier.ModifierType.SET),
		EvadeData.EvadeSource.WEAPON: Modifier.new("0.0", Modifier.ModifierType.SET),
	}
	new_passive_effect.evade_source_modifiers_user = evade_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()
	
	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "monster_talk"
	new_passive_effect.add_applicable_target_stat_bases = [Unit.StatBasis.MONSTER]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "maintenance"
	new_passive_effect.hit_chance_modifier_targeted = Modifier.new("0.0", Modifier.ModifierType.SET)
	# new_passive_effect.hit_chance_modifier_targeted = Modifier.new(0, Modifier.ModifierType.SET)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "defend"
	new_passive_effect.added_actions_names = ["defend"]
	# TODO create defend action
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "half_of_mp"
	new_passive_effect.action_mp_modifier = Modifier.new("value * 0.5", Modifier.ModifierType.MULT)
	# new_passive_effect.action_mp_modifier = Modifier.new(0.5, Modifier.ModifierType.MULT)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "throw_item"
	new_passive_effect.action_max_range_modifier = Modifier.new("value + 3", Modifier.ModifierType.ADD)
	# new_passive_effect.action_max_range_modifier = Modifier.new(3, Modifier.ModifierType.ADD)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "short_charge"
	new_passive_effect.action_charge_time_modifier = Modifier.new("value * 0.5", Modifier.ModifierType.MULT)
	# new_passive_effect.action_charge_time_modifier = Modifier.new(0.5, Modifier.ModifierType.MULT)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "non_charge"
	new_passive_effect.action_charge_time_modifier = Modifier.new("0.0", Modifier.ModifierType.SET)
	# new_passive_effect.action_charge_time_modifier = Modifier.new(0.0, Modifier.ModifierType.SET)
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_change"
	new_passive_effect.added_actions_names = ["equip_change"]
	# TODO create equip_change action
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "monster_skill"
	new_passive_effect.effect_range = 3
	new_passive_effect.unit_basis_filter = [Unit.StatBasis.MONSTER]
	new_passive_effect.added_actions_names = ["choco_ball"] # TODO change to 'learned' flag for each job's unique action?
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move+1"
	var stat_modifier_dict: Dictionary[Unit.StatType, Modifier] = {
		Unit.StatType.MOVE: Modifier.new("value + 1", Modifier.ModifierType.ADD),
	}
	new_passive_effect.stat_modifiers = stat_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move+2"
	stat_modifier_dict = {
		Unit.StatType.MOVE: Modifier.new("value + 2", Modifier.ModifierType.ADD),
	}
	new_passive_effect.stat_modifiers = stat_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move+3"
	stat_modifier_dict = {
		Unit.StatType.MOVE: Modifier.new("value + 3", Modifier.ModifierType.ADD),
	}
	new_passive_effect.stat_modifiers = stat_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "jump+1"
	stat_modifier_dict = {
		Unit.StatType.JUMP: Modifier.new("value + 1", Modifier.ModifierType.ADD),
	}
	new_passive_effect.stat_modifiers = stat_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "jump+2"
	stat_modifier_dict = {
		Unit.StatType.JUMP: Modifier.new("value + 2", Modifier.ModifierType.ADD),
	}
	new_passive_effect.stat_modifiers = stat_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "jump+3"
	stat_modifier_dict = {
		Unit.StatType.JUMP: Modifier.new("value + 3", Modifier.ModifierType.ADD),
	}
	new_passive_effect.stat_modifiers = stat_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "ignore_height"
	new_passive_effect.ignore_height = true
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "ignore_terrain"
	var terrain_modifier_dict: Dictionary[int, Modifier] = {
		0x0e: Modifier.new("1", Modifier.ModifierType.SET),
		0x0f: Modifier.new("1", Modifier.ModifierType.SET),
		0x10: Modifier.new("1", Modifier.ModifierType.SET),
		0x11: Modifier.new("1", Modifier.ModifierType.SET),
		0x2d: Modifier.new("1", Modifier.ModifierType.SET),
	}
	new_passive_effect.terrain_cost_modifiers = terrain_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "walk_on_water"
	# TODO handle depth
	new_passive_effect.terrain_cost_modifiers = terrain_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "swim"
	# TODO handle depth
	new_passive_effect.terrain_cost_modifiers = terrain_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move_underwater"
	# TODO handle depth
	new_passive_effect.terrain_cost_modifiers = terrain_modifier_dict
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "walk_on_lava"
	new_passive_effect.remove_prohibited_terrain = [0x12]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	# new_passive_effect = PassiveEffect.new()
	# new_passive_effect.unique_name = "ignore_weather"
	# Utilities.save_json(new_passive_effect)

	# new_passive_effect = PassiveEffect.new()
	# new_passive_effect.unique_name = "cant_enter_depth"
	# Utilities.save_json(new_passive_effect)

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "float"
	new_passive_effect.status_always = ["float"]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "fly"
	new_passive_effect.added_actions_names = ["fly"]
	# TODO create fly action
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "teleport"
	new_passive_effect.added_actions_names = ["teleport"]
	# TODO create teleport action
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "teleport_2"
	new_passive_effect.added_actions_names = ["teleport_2"]
	# TODO create teleport_2 action
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "reflect"
	new_passive_effect.status_always = ["reflect"]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	# TODO define TwoSords, GainedJpUp,
	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "two_swords"
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "gained_jp_up"
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()
	
	# TODO define Train and Secret Hunt passive_effects? could be triggered actions? timing = POST_ACTION?
	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "train"
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "secret_hunt"
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move_find_item"
	new_passive_effect.added_triggered_actions_names = [new_passive_effect.unique_name]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move_get_exp"
	new_passive_effect.added_triggered_actions_names = [new_passive_effect.unique_name]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move_get_jp"
	new_passive_effect.added_triggered_actions_names = [new_passive_effect.unique_name]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move_get_hp"
	new_passive_effect.added_triggered_actions_names = [new_passive_effect.unique_name]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "move_get_mp"
	new_passive_effect.added_triggered_actions_names = [new_passive_effect.unique_name]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "standard_move"
	new_passive_effect.add_prohibited_terrain = [
		18,
		25,
		28,
		63,
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "standard_evade"
	new_passive_effect.include_evade_sources = [
		EvadeData.EvadeSource.JOB,
		EvadeData.EvadeSource.SHIELD,
		EvadeData.EvadeSource.ACCESSORY,
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_armor"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.ARMOR
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_axe"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.AXE
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_crossbow"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.CROSSBOW
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_gun"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.GUN
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_katana"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.KATANA
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_shield"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.SHIELD
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_spear"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.SPEAR
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	new_passive_effect = PassiveEffect.new()
	new_passive_effect.unique_name = "equip_sword"
	new_passive_effect.added_equipment_types_equipable = [
		ItemData.ItemType.SWORD
	]
	predefined_passive_effects[new_passive_effect.unique_name] = new_passive_effect.duplicate_deep()

	return predefined_passive_effects


static func get_predefined_actions(abilities: Dictionary[String, Ability]) -> Dictionary[String, Action]:
	var predefined_actions: Dictionary[String, Action] = {}

	var standard_status_prevents_use: Array[String] = [
		"crystal",
		"dead",
		"petrify",
		"blood_suck",
		"treasure",
		"berserk",
		"chicken",
		"frog",
		"stop",
		"don't_act",
	]

	var standard_ignore_passives: Array[String] = [
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

	var standard_action: Action = Action.new()
	standard_action.applicable_evasion_type = EvadeData.EvadeType.NONE
	standard_action.auto_target = true
	standard_action.max_targeting_range = 0
	standard_action.status_prevents_use_any = standard_status_prevents_use
	standard_action.ignore_passives = standard_ignore_passives
	standard_action.base_hit_formula.formula_text = "100.0"

	var new_action: Action = standard_action.duplicate_deep()
	new_action.display_name = "Move"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Walk to target tile"
	new_action.targeting_type = Action.TargetingTypes.MOVE
	new_action.use_type = Action.UseTypes.MOVE
	new_action.move_points_cost = 1
	new_action.action_points_cost = 0
	standard_action.auto_target = false
	new_action.status_prevents_use_any = [
		"crystal",
		"dead",
		"petrify",
		"treasure",
		"stop",
		"don't_move",
	]
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Wait"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_action.action_points_cost = 0
	new_action.allow_triggered_actions = false
	new_action.animation_executing_id = -1
	new_action.set_target_animation_on_hit = false
	new_action.ends_turn = true
	var new_effect: ActionEffect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.CT
	new_effect.base_power_formula = FormulaData.new("(target.action_points_remaining * 10) + (target.move_points_remaining * 10)", [3], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()
	
	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Defend"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_action.target_status_chance = 100
	new_action.target_status_list = ["defending"]
	new_action.target_status_list_type = Action.StatusListType.ALL
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	# TODO equip_change Action

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Absorb Used MP"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.MP
	# TODO get mp used based off of action? Maybe from TriggeredAction data?
	new_effect.base_power_formula = FormulaData.new("10.0", [10], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Brave Up"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.BRAVE
	new_effect.base_power_formula = FormulaData.new("3.0", [3], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	# Caution TiggeredAction should trigger defend action
	# new_action = Action.new()
	# new_action.display_name = "Caution"
	# new_action.unique_name = new_action.display_name.to_snake_case()
	# new_action.description = abilities[new_action.unique_name].description
	# new_action.target_status_chance = 100
	# new_action.target_status_list = ["defending"]
	# new_action.target_status_list_type = Action.StatusListType.ALL
	# new_action.auto_target = true
	# new_action.max_targeting_range = 0
	# new_action.status_prevents_use_any = standard_status_prevents_use
	# new_action.ignore_passives = standard_ignore_passives
	# new_action.base_hit_formula.formula_text = "100.0"
	# Utilities.save_json(new_action, save_path)

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Counter Tackle"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_action.applicable_evasion_type = EvadeData.EvadeType.PHYSICAL
	new_action.ignore_passives.erase("protect")
	new_action.ignore_passives.erase("attack_up")
	new_action.ignore_passives.erase("defense_up")
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	# TODO use correct formula for Counter Tackle
	new_effect.base_power_formula = FormulaData.new("user.hp_max * 0.04", [4.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, true, true)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Critical Quick"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.CT
	new_effect.base_power_formula = FormulaData.new("100.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Dead Damage"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Removes remaining HP from target when Dead status is added"
	new_action.status_prevents_use_any = []
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("target.hp", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Dead to Cyrstal Treasure"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Adds Crystal or Treasure status to unit"
	new_action.target_status_chance = 100
	new_action.target_status_list = ["crystal", "treasure"]
	new_action.target_status_list_type = Action.StatusListType.RANDOM
	new_action.status_prevents_use_any.erase("dead")
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Death Sentence to Dead"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Add Dead status to unit at end of Death Sentence"
	new_action.target_status_chance = 100
	new_action.target_status_list = ["dead"]
	new_action.target_status_list_type = Action.StatusListType.ALL
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Dragon Spirit"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_action.target_status_chance = 100
	new_action.target_status_list = ["reraise"]
	new_action.target_status_list_type = Action.StatusListType.ALL
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Faith Up"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.FAITH
	new_effect.base_power_formula = FormulaData.new("3.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Gilgame Heart"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description	
	new_effect = ActionEffect.new()
	new_effect.type = ActionEffect.EffectType.CURRENCY
	# TODO use correct formula for Gilgame Heart
	new_effect.base_power_formula = FormulaData.new("50.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "HP Restore"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description	
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("target.hp_max", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "MA Save"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description	
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.MAGIC_ATTACK
	new_effect.base_power_formula = FormulaData.new("1.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Meatbone Slash"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_action.applicable_evasion_type = EvadeData.EvadeType.PHYSICAL
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("user.hp_max", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Move Get EXP"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.EXP
	new_effect.base_power_formula = FormulaData.new("12.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Move Get HP"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("target.hp_max * 0.1", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Move Get JP"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.EXP # TODO move get jp - implement jp
	new_effect.base_power_formula = FormulaData.new("8.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Move Get MP"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.MP
	new_effect.base_power_formula = FormulaData.new("target.mp_max * 0.1", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "MP Restore"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.MP
	new_effect.base_power_formula = FormulaData.new("target.mp_max", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "PA Save"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.PHYSICAL_ATTACK
	new_effect.base_power_formula = FormulaData.new("1.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Poison Damage"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Applies damage from Poison status"
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("target.hp_max * 0.1", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Regeneration Heal"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Heals HP from Regeneration status"
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("target.hp_max * 0.1", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Regenerator"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_action.target_status_chance = 100
	new_action.target_status_list = ["regen"]
	new_action.target_status_list_type = Action.StatusListType.ALL
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Reraise Remove Dead"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Reraise removes Dead status"
	new_action.target_status_chance = 100
	new_action.target_status_list = ["dead"]
	new_action.target_status_list_type = Action.StatusListType.ALL
	new_action.will_remove_target_status = true
	new_action.status_prevents_use_any.erase("dead")
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("target.hp_max * 0.1", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Speed Save"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.SPEED
	new_effect.base_power_formula = FormulaData.new("1.0", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Sunken State"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = abilities[new_action.unique_name].description
	new_action.target_status_chance = 100
	new_action.target_status_list = ["transparent"]
	new_action.target_status_list_type = Action.StatusListType.ALL
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	new_action = standard_action.duplicate_deep()
	new_action.display_name = "Undead Remove Dead"
	new_action.unique_name = new_action.display_name.to_snake_case()
	new_action.description = "Undead has chance to remove Dead status"
	new_action.target_status_chance = 100
	new_action.target_status_list = ["dead"]
	new_action.target_status_list_type = Action.StatusListType.ALL
	new_action.will_remove_target_status = true
	new_action.status_prevents_use_any.erase("dead")
	new_effect = ActionEffect.new()
	new_effect.effect_stat_type = Unit.StatType.HP
	new_effect.base_power_formula = FormulaData.new("target.hp_max * 0.1", [100.0], FormulaData.FaithModifier.NONE, FormulaData.FaithModifier.NONE, false, false, false)
	new_action.target_effects.append(new_effect)
	predefined_actions[new_action.unique_name] = new_action.duplicate_deep()

	return predefined_actions


static func get_predefined_triggered_actions() -> Dictionary[String, TriggeredAction]:
	var predefined_triggered_actions: Dictionary[String, TriggeredAction] = {}

	var new_triggered_action: TriggeredAction = TriggeredAction.new()
	new_triggered_action.display_name = "Absorb Used MP"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.action_mp_cost_threshold = 1
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Auto Potion"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Brave Up"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Caution"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Counter Attack"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = "ATTACK"
	new_triggered_action.targeting = TriggeredAction.TargetingTypes.INITIATOR
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Counter Geomancy"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.targeting = TriggeredAction.TargetingTypes.INITIATOR
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Counter Magic"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = "COPY"
	new_triggered_action.targeting = TriggeredAction.TargetingTypes.INITIATOR
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Counter Tackle"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.targeting = TriggeredAction.TargetingTypes.INITIATOR
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Critical Quick"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.required_status_id = ["critical"]
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Dragon Spirit"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Faith Up"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.action_mp_cost_threshold = 1
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Gilgame Heart"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Hamedo"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = "ATTACK"
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.TARGETTED_PRE_ACTION
	new_triggered_action.targeting = TriggeredAction.TargetingTypes.INITIATOR
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "HP Restore"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.required_status_id = ["critical"]
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "MP Restore"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.required_status_id = ["critical"]
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "MA Save"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()
	
	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "PA Save"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Speed Save"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Meatbone Slash"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.required_status_id = ["critical"]
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Move Find Item"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.MOVED
	new_triggered_action.trigger_chance_formula.formula_text = "100.0"
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Move Get EXP"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.MOVED
	new_triggered_action.trigger_chance_formula.formula_text = "100.0"
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Move Get JP"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.MOVED
	new_triggered_action.trigger_chance_formula.formula_text = "100.0"
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Move Get HP"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.MOVED
	new_triggered_action.trigger_chance_formula.formula_text = "100.0"
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Move Get MP"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.MOVED
	new_triggered_action.trigger_chance_formula.formula_text = "100.0"
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Regenerator"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.requries_hit = TriggeredAction.HitRequirement.HIT
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Sunken State"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Reflect"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = "COPY"
	new_triggered_action.targeting = TriggeredAction.TargetingTypes.REFLECT
	new_triggered_action.trigger_chance_formula.formula_text = "100.0"
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Reraise Remove Dead"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.TURN_START
	new_triggered_action.trigger_chance_formula.formula_text = "100.0"
	new_triggered_action.required_status_id = ["dead"]
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	new_triggered_action = TriggeredAction.new()
	new_triggered_action.display_name = "Undead Remove Dead"
	new_triggered_action.unique_name = new_triggered_action.display_name.to_snake_case()
	new_triggered_action.action_unique_name = new_triggered_action.unique_name
	new_triggered_action.trigger_timing = TriggeredAction.TriggerTiming.TURN_START
	new_triggered_action.trigger_chance_formula.formula_text = "50.0"
	new_triggered_action.required_status_id = ["dead"]
	predefined_triggered_actions[new_triggered_action.unique_name] = new_triggered_action.duplicate_deep()

	return predefined_triggered_actions


static func get_predefined_abilities() -> Dictionary[String, Ability]:
	var predefined_abilities: Dictionary[String, Ability] = {}

	return predefined_abilities