class_name FftActionConverter
extends RefCounted


static func apply_formula_id(action: Action, new_formula_id: int, rom_reader: RomReader) -> void:
	action.formula_id = new_formula_id
	# ignores_statuses.append_array(["protect", "shell"]) # protect and shell
	action.ignore_passives = [
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
	
	match action.formula_id:
		0:
			action.use_weapon_damage = true
			action.target_status_chance = 19
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		1, 5:
			# TODO get reference to weapon effects?
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_BRAVE_X_PA
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.stats[user.StatType.BRAVE].get_modified_value() / 100.0) * user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value()"
			# target_effects[0].base_power_formula.formula_text = user.primary_weapon.attack_action.target_effects[0].base_power_formula.formula_text
			
			action.use_weapon_damage = true
			action.target_status_chance = 19
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		2:
			action.use_weapon_damage = true
			# secondary_actions.append(RomReader.abilities[inflict_status_id].ability_action)
			action.target_status_chance = 19
			# secondary_actions_chances = [19]
			action.secondary_actions2.append(SecondaryAction.new(rom_reader.fft_abilities[action.inflict_status_id].ability_action.unique_name, action.target_status_chance, true, false, true))
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		3: # weapon_power * weapon_power
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			action.use_weapon_damage = true
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		4:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			var secondary_action_unique_names: PackedStringArray = []
			match action.element:
				Action.ElementTypes.FIRE:
					secondary_action_unique_names = ["fire", "fire_2", "fire_3"]
				Action.ElementTypes.LIGHTNING:
					secondary_action_unique_names = ["bolt", "bolt_2", "bolt_3"]
				Action.ElementTypes.ICE:
					secondary_action_unique_names = ["ice", "ice_2", "ice_3"]
			
			action.secondary_actions_chances = [60, 30, 10]
			action.secondary_action_list_type = Action.StatusListType.RANDOM
			
			for secondary_action_idx: int in secondary_action_unique_names.size():
				# var new_action: Action = RomReader.abilities[secondary_action_ids[secondary_action_idx]].ability_action.duplicate(true) # abilities need to be initialized before items
				var reference_action_unique_name: String = secondary_action_unique_names[secondary_action_idx]
				var new_action: Action = rom_reader.actions[reference_action_unique_name].duplicate_deep() # abilities need to be initialized before items
				new_action.display_name = "Magic Gun " + new_action.display_name
				FftRegistryHelper.register_unique(rom_reader.actions, new_action, new_action.display_name, "Action")
				new_action.area_of_effect_range = 0
				# new_action.target_effects[0].base_power_formula.formula = FormulaData.Formulas.WP_X_V1
				new_action.target_effects[0].base_power_formula.formula_text = "user.get_primary_weapon().weapon_power * " + str(new_action.target_effects[0].base_power_formula.values[0])
				new_action.mp_cost = 0
				var chance: int = action.secondary_actions_chances[secondary_action_idx]
				# secondary_actions.append(new_action)
				action.secondary_actions2.append(SecondaryAction.new(new_action.unique_name, chance, true, false, false))
			
			# TODO damage formula is WP (instead of MA) * ability Y
			# TODO magic gun should probably use totally new Actions?, with WP*V1 formula, EvadeType.NONE, no costs, animation_ids = 0, etc., but where V1 and vfx are from the original action
			# TODO math skills, charge skills, etc. behave kind of similarly with using partial data from other actions
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		6:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			action.target_effects[0].transfer_to_user = true # absorb hp
			action.use_weapon_damage = true
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		7:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			action.use_weapon_damage = true
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			action.target_effects[0].base_power_formula.reverse_sign = false # heal
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		8:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			action.target_status_chance = 19
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.target_effects[0].base_power_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		9:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			action.target_status_chance = 19
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true

			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x0a:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x0b:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
		0x0c:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.target_effects[0].base_power_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.target_effects[0].base_power_formula.reverse_sign = false
		0x0d:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			action.target_effects[0].base_power_formula.reverse_sign = false
		0x0e:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# TODO apply status first? if target is immune to status, no damage
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_status_chance = 100
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x0f:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_MP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.MP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			action.target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x10:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			action.target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x11:
			pass
		0x12:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.CT))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = "100.0"
			action.target_effects[0].base_power_formula.values[0] = 100
			action.target_effects[0].set_value = true
		0x13:
			pass
		0x14:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# TODO set Golem
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
		0x15:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.CT))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = "0.0"
			action.target_effects[0].base_power_formula.values[0] = 0
			action.target_effects[0].set_value = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x16:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_MP_MINUS_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.MP].current_value"
			action.target_effects[0].base_power_formula.values[0] = 0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x17:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_HP_MINUS_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP].current_value - 1"
			action.target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x18, 0x19:
			pass
		0x1a:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_y)
			action.base_hit_formula.values[0] = action.formula_y
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.PHYSICAL_ATTACK)) # TODO MAGICAL_ATTACK or SPEED dependent on ability ID?
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_x)
			action.target_effects[0].base_power_formula.values[0] = action.formula_x
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x1b:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_MP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.MP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x1c:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.V1
			action.base_hit_formula.formula_text = str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			
			# TODO song effects based on ability ID
		0x1d:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.V1
			action.base_hit_formula.formula_text = str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			
			# TODO dance effects based on ability ID
		0x1e:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + %.2f) * user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() / 2.0" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			# TODO random number of hits within AoE
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x1f:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + %.2f) * user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() / 2.0" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.user_faith_modifier = FormulaData.FaithModifier.UNFAITH
			action.target_effects[0].base_power_formula.target_faith_modifier = FormulaData.FaithModifier.UNFAITH
			# TODO random number of hits within AoE
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")

			action.target_status_chance = 19
		0x20:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			# TODO chance to decrease inventory
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x21:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			# TODO chance to decrease inventory
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x22:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# TODO chance to decrease inventory
		0x23:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = false # heal
			# TODO chance to decrease inventory
		0x24:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_PLUS_V1_X_MA_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + %.2f) * user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() / 2.0" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			# TODO usable based on terrain?
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x25:
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_WP_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + user.get_primary_weapon().weapon_power + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true

			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.REMOVE_EQUIPMENT))
			# TODO set equipement slod id based on ability id?
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.ignore_passives.erase("maintenance")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x26:
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.SPEED].get_modified_value() + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true

			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.REMOVE_EQUIPMENT))
			action.target_effects[0].transfer_to_user = true
			# TODO set equipement slod id based on ability id?
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.ignore_passives.erase("maintenance")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x27:
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.SPEED].get_modified_value() + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.LVL_X_SP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.LEVEL].current_value * user.stats[user.StatType.SPEED].get_modified_value()"
			action.target_effects[0].base_power_formula.values[0] = 1
			# TODO add to user currency? user_effects.append(ActionEffect.new(ActionEffect.EffectType.CURRENCY))
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x28:
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.SPEED].get_modified_value() + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.EXP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MIN_TARGET_EXP_OR_SP_PLUS_V1
			action.target_effects[0].base_power_formula.formula_text = "minf(target.stats[target.StatType.EXP].current_value, user.stats[user.StatType.SPEED].get_modified_value() + %.2f)" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x29:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# TODO hit chance based on gender
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
		0x2a:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = false
			# TODO set effects based on ability id

			action.ignore_passives.erase("finger_guard")
			action.ignore_passives.erase("monster_talk")

			# only work on non-monsters
			action.required_target_stat_basis = [
				UnitData.StatBasis.MALE,
				UnitData.StatBasis.FEMALE,
				UnitData.StatBasis.OTHER,
			]
		0x2b:
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + %.2f" % action.formula_y
			action.base_hit_formula.values[0] = action.formula_y
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.SPEED))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_x)
			action.target_effects[0].base_power_formula.values[0] = action.formula_x
			# TODO set effects based on ability id
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x2c:
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + %.2f" % action.formula_y
			action.base_hit_formula.values[0] = action.formula_y
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = "%.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x2d:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_PLUS_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * (user.get_primary_weapon().weapon_power + %.2f)" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			action.target_status_chance = 100
			action.target_status_list_type = Action.StatusListType.RANDOM
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		0x2e:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.get_primary_weapon().weapon_power"
			action.target_effects[0].base_power_formula.values[0] = 1
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.REMOVE_EQUIPMENT))
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[1].base_power_formula.formula_text = "1.0"
			action.target_effects[1].base_power_formula.values[0] = 1
			# TODO set equipement slod id based on ability id?
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		0x2f:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.get_primary_weapon().weapon_power"
			action.target_effects[0].base_power_formula.values[0] = 1
			action.target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		0x30:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.get_primary_weapon().weapon_power"
			action.target_effects[0].base_power_formula.values[0] = 1
			action.target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		0x31:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_PA_PLUS_V1_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + %.2f) * user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() / 2.0" % float(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")

			action.target_status_chance = 19
		0x32:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.RANDOM_V1_X_PA_X_3_PLUS_V2_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "randi_range(1, %d) * ((user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * 3.0) + %d)" % [action.formula_x, action.formula_y]
			action.target_effects[0].base_power_formula.values[0] = action.formula_x
			action.target_effects[0].base_power_formula.values[1] = action.formula_y
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		0x33:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
		0x34:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * %d" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = false
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			action.target_effects[1].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * %.2f" % (action.formula_y / 2.0)
			action.target_effects[1].base_power_formula.values[0] = action.formula_y / 2.0
			action.target_effects[1].base_power_formula.reverse_sign = false
		0x35:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.PA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			action.target_effects[0].base_power_formula.reverse_sign = false
		0x36:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.PHYSICAL_ATTACK))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = false
		0x37:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.RANDOM_V1_X_PA
			action.target_effects[0].base_power_formula.formula_text = "randi_range(1, %d) * user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value()" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		0x38:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_status_chance = 100
		0x39:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.SPEED))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = false
		0x3a:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = false
		0x3b:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_x)
			action.target_effects[0].base_power_formula.values[0] = action.formula_x
			action.target_effects[0].base_power_formula.reverse_sign = false
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.SPEED)) # TODO set type based on ability id
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[1].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[1].base_power_formula.values[0] = action.formula_y
			action.target_effects[1].base_power_formula.reverse_sign = false
			
		0x3c:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * 0.4"
			action.target_effects[0].base_power_formula.values[0] = 2.0 / 5.0
			action.target_effects[0].base_power_formula.reverse_sign = false
			
			action.user_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP)) # TODO this should be per target
			# user_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.user_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * 0.2"
			action.user_effects[0].base_power_formula.values[0] = 1.0 / 5.0
		0x3d:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x3e:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_HP_MINUS_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP].current_value - 1"
			action.target_effects[0].base_power_formula.values[0] = 1
		0x3f:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.SPEED].get_modified_value() + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x40:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.SP_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.SPEED].get_modified_value() + %.2f" % action.formula_x
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true

			action.required_target_status_uname = [
				"undead"
			]
		0x41:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x42:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * %d" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			action.user_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# user_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_V1
			action.user_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * %.2f" % (action.formula_y / float(action.formula_x))
			action.user_effects[0].base_power_formula.values[0] = action.formula_y / float(action.formula_x)
		0x43:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_MISSING_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.HP_MAX].get_modified_value() - user.stats[user.StatType.HP].current_value"
			action.target_effects[0].base_power_formula.values[0] = 1
		0x44:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_CURRENT_MP_MINUS_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.MP].current_value"
			action.target_effects[0].base_power_formula.values[0] = 0
		0x45:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MISSING_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() - target.stats[target.StatType.HP].current_value"
			action.target_effects[0].base_power_formula.values[0] = 1
		0x46:
			pass
		0x47:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_status_chance = 100
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
		0x48:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_x * 10)
			action.target_effects[0].base_power_formula.values[0] = action.formula_x * 10 # maybe should be handled in Item initialization?
			action.target_effects[0].base_power_formula.reverse_sign = false # heal
		0x49:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_x * 10)
			action.target_effects[0].base_power_formula.values[0] = action.formula_x * 10 # maybe should be handled in Item initialization?
			action.target_effects[0].base_power_formula.reverse_sign = false # heal
		0x4a:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			#target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			#target_effects[0].base_power_formula.formula = FormulaData.Formulas.UNMODIFIED
			#target_effects[0].base_power_formula.value_01 = formula_x * 10 # maybe should be handled in Item initialization?
			#target_effects[0].base_power_formula.reverse_sign = false # heal
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value()"
			action.target_effects[0].base_power_formula.values[0] = 1 # maybe should be handled in Item initialization?
			action.target_effects[0].base_power_formula.reverse_sign = false # heal
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_MP_X_V1
			action.target_effects[1].base_power_formula.formula_text = "target.stats[target.StatType.MP_MAX].get_modified_value()"
			action.target_effects[1].base_power_formula.values[0] = 1 # maybe should be handled in Item initialization?
			action.target_effects[1].base_power_formula.reverse_sign = false # heal
		0x4b:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_status_chance = 100
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.RANDOM_V1_V2
			action.target_effects[0].base_power_formula.formula_text = "randi_range(1, 9)"
			action.target_effects[0].base_power_formula.values[0] = 1
			action.target_effects[0].base_power_formula.values[1] = 9
			action.target_effects[0].base_power_formula.reverse_sign = false # heal
		0x4c:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = false # heal
		0x4d:
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			action.target_effects[0].transfer_to_user = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x4e:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x4f:
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_MISSING_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.HP_MAX].get_modified_value() - user.stats[user.StatType.HP].current_value"
			action.target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x50:
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken, hit chance
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x51:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_element = true # TODO only Strengthen element?
			action.base_hit_formula.is_modified_by_zodiac = true
		0x52:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_status_chance = 100
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_MISSING_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.HP_MAX].get_modified_value() - user.stats[user.StatType.HP].current_value"
			action.target_effects[0].base_power_formula.values[0] = 1
			
			action.user_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# user_effects[0].base_power_formula.formula = FormulaData.Formulas.USER_CURRENT_HP_MINUS_V1
			action.user_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.HP].current_value"
			action.user_effects[0].base_power_formula.values[0] = 0
		0x53:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y / 100.0
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true

			action.target_status_chance = 19
		0x54:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * " + str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			action.target_effects[0].base_power_formula.reverse_sign = true
		0x55:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.PHYSICAL_ATTACK))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x56:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.MAGIC_ATTACK))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x57:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.LEVEL))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = "1.0"
			action.target_effects[0].base_power_formula.values[0] = 1
			action.target_effects[0].base_power_formula.reverse_sign = false # add
 
			action.user_status_list = action.target_status_list.duplicate()
			action.user_status_chance = action.target_status_chance
			action.user_status_list_type = action.target_status_list_type
			action.will_remove_user_status = action.will_remove_target_status
 
			action.target_status_list.clear()
		0x58:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_element = true # TODO element Strengthen only
			action.base_hit_formula.is_modified_by_zodiac = true
			
			# TODO set MORBOL
		0x59:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.LEVEL))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = "1.0"
			action.target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x5a:
			action.target_status_chance = 100
			
			action.required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5b:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_status_chance = 100
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.TARGET_MAX_HP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "target.stats[target.StatType.HP_MAX].get_modified_value() * %.2f" % (action.formula_y / 100.0)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y

			action.required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5c:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_x)
			action.target_effects[0].base_power_formula.values[0] = action.formula_x
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.SPEED)) # TODO set type based on ability id
			# target_effects[1].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[1].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[1].base_power_formula.values[0] = action.formula_y
			action.target_effects[1].base_power_formula.reverse_sign = false
			
			action.required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5d:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.CT))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = "100.0"
			action.target_effects[0].base_power_formula.values[0] = 100
			action.target_effects[0].set_value = true

			action.required_target_job_uname = [
				"dragon",
				"blue_dragon",
				"red_dragon",
				"hyudra",
				"hydra",
				"tiamat",
			]
		0x5e:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			action.target_status_chance = 19
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + %.2f) * user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() / 2.0" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			# TODO x+1 hits at random target in AoE
		0x5f:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			action.target_status_chance = 19
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + %.2f) * user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() / 2.0" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x60:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.MA_PLUS_V1_X_MA_DIV_2
			action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + %.2f) * user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() / 2.0" % action.formula_y
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x61:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.user_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.target_faith_modifier = FormulaData.FaithModifier.FAITH
			action.base_hit_formula.is_modified_by_element = true
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
			action.passive_power_modifier_applies_to_hit_chance = true
		0x62:
			action.applicable_evasion_type = EvadeData.EvadeType.MAGICAL
			
			# base_hit_formula.formula = FormulaData.Formulas.MA_PLUS_V1
			action.base_hit_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() + " + str(action.formula_x)
			action.base_hit_formula.values[0] = action.formula_x
			action.base_hit_formula.is_modified_by_zodiac = true
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.BRAVE))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.V1
			action.target_effects[0].base_power_formula.formula_text = str(action.formula_y)
			action.target_effects[0].base_power_formula.values[0] = action.formula_y
			
			# ignores_statuses.erase(27) # affected by shell, frog, chicken, hit chance
			action.ignore_passives.erase("shell_status")
			action.ignore_passives.erase("magic_attack_up")
			action.ignore_passives.erase("magic_defense_up")
		0x63:
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1 # TODO SPxWP
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.get_primary_weapon().weapon_power"
			action.target_effects[0].base_power_formula.values[0] = 1
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
		0x64:
			action.applicable_evasion_type = EvadeData.EvadeType.NONE
			
			action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
			# target_effects[0].base_power_formula.formula = FormulaData.Formulas.PA_X_WP_X_V1
			action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.get_primary_weapon().weapon_power"
			action.target_effects[0].base_power_formula.values[0] = 1 # TODO 1.5 if spear, PAxBRAVE if unarmed, else 1
			
			# ignores_statuses.erase(26) # affected by protect, sleeping, charging, frog, chicken
			action.ignore_passives.erase("protect_status")
			action.ignore_passives.erase("attack_up")
			action.ignore_passives.erase("defense_up")
			action.ignore_passives.erase("martial_arts")
	
	action.emit_changed()
