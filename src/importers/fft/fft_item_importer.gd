class_name FftItemImporter
extends RefCounted


static func create_from_rom(idx: int, rom_reader: RomReader) -> ItemData:
	var item_data: ItemData = ItemData.new()
	if idx == -1:
		return item_data

	var scus_data: ScusData = rom_reader.scus_data
	var battle_bin_data: BattleBinData = rom_reader.battle_bin_data

	item_data.display_name = rom_reader.fft_text.item_names[idx]
	item_data.description = rom_reader.fft_text.item_descriptions[idx]
	item_data.item_idx = idx
	item_data.item_type = scus_data.item_types[idx] as ItemData.ItemType
	item_data.slot_type = (scus_data.item_slot_types[idx] & 0xfc) as ItemData.SlotType # skip rare flag
	if item_data.slot_type == 0:
		item_data.slot_type = ItemData.SlotType.NONE
	item_data.is_rare = (scus_data.item_slot_types[idx] & 0x02) == 0x02 # rare flag

	item_data.item_graphic_id = scus_data.item_sprite_ids[idx]
	item_data.item_palette_id = scus_data.item_palettes[idx]
	item_data.min_level = scus_data.item_min_levels[idx]
	item_data.price = scus_data.item_prices[idx]
	item_data.shop_availability_start = scus_data.item_shop_availability[idx]

	if idx < 0x90: # weapons and shields
		item_data.wep_frame_palette = battle_bin_data.weapon_graphic_palettes[idx]
		item_data.wep_eff_palette = battle_bin_data.weapon_eff_palettes[idx]
		item_data.wep_frame_v_offset = battle_bin_data.weapon_frames_vertical_offsets[idx]

	_apply_item_attributes(item_data, scus_data.item_attributes[scus_data.item_attributes_id[idx]])

	var sub_index: int = idx
	if idx < 0x80: # weapon data
		_populate_weapon_data(item_data, idx, rom_reader)
	elif idx < 0x90: # shield data
		sub_index = idx - 0x80
		item_data.shield_physical_evade = scus_data.shield_physical_evade[sub_index]
		item_data.shield_magical_evade = scus_data.shield_magical_evade[sub_index]

		item_data.evade_datas.append(EvadeData.new(item_data.shield_physical_evade, EvadeData.EvadeSource.SHIELD, EvadeData.EvadeType.PHYSICAL))
		item_data.evade_datas.append(EvadeData.new(item_data.shield_magical_evade, EvadeData.EvadeSource.SHIELD, EvadeData.EvadeType.MAGICAL))
	elif idx < 0xd0: # armour/helm data
		sub_index = idx - 0x90
		item_data.hp_modifier = scus_data.armour_hp_modifier[sub_index]
		item_data.mp_modifier = scus_data.armour_mp_modifier[sub_index]
		item_data.passive_effect.stat_modifiers[UnitData.StatType.HP_MAX] = Modifier.new("value + " + str(item_data.hp_modifier), Modifier.ModifierType.ADD)
		item_data.passive_effect.stat_modifiers[UnitData.StatType.MP_MAX] = Modifier.new("value + " + str(item_data.mp_modifier), Modifier.ModifierType.ADD)
	elif idx < 0xf0: # accessory data
		sub_index = idx - 0xd0
		item_data.accessory_physical_evade = scus_data.accessory_physical_evade[sub_index]
		item_data.accessory_magical_evade = scus_data.accessory_magical_evade[sub_index]

		item_data.evade_datas.append(EvadeData.new(item_data.accessory_physical_evade, EvadeData.EvadeSource.ACCESSORY, EvadeData.EvadeType.PHYSICAL))
		item_data.evade_datas.append(EvadeData.new(item_data.accessory_magical_evade, EvadeData.EvadeSource.ACCESSORY, EvadeData.EvadeType.MAGICAL))
	elif idx < 0xfe: # chemist item data
		sub_index = idx - 0xf0
		item_data.consumable_formula_id = scus_data.chem_item_formula_id[sub_index]
		item_data.consumable_item_z = scus_data.chem_item_z[sub_index]
		item_data.consumable_inflict_status_id = scus_data.chem_item_inflict_status_id[sub_index]

	# remove empty modifiers
	for stat_key: UnitData.StatType in item_data.passive_effect.stat_modifiers.keys():
		if item_data.passive_effect.stat_modifiers[stat_key].formula_text == "value + 0":
			item_data.passive_effect.stat_modifiers.erase(stat_key)

	FftRegistryHelper.register_unique(rom_reader.items, item_data, item_data.display_name, "ItemData")

	item_data.passive_effect_name = item_data.unique_name
	item_data.passive_effect.unique_name = item_data.unique_name
	FftRegistryHelper.register_unique(rom_reader.passive_effects, item_data.passive_effect, "", "PassiveEffect")

	item_data.emit_changed()
	return item_data


static func _populate_weapon_data(item_data: ItemData, idx: int, rom_reader: RomReader) -> void:
	var scus_data: ScusData = rom_reader.scus_data
	var battle_bin_data: BattleBinData = rom_reader.battle_bin_data

	item_data.max_range = scus_data.weapon_range[idx]
	item_data.weapon_formula_id = scus_data.weapon_formula_id[idx]
	item_data.weapon_power = scus_data.weapon_power[idx]
	item_data.weapon_evade = scus_data.weapon_evade[idx]
	item_data.evade_datas.append(EvadeData.new(item_data.weapon_evade, EvadeData.EvadeSource.WEAPON, EvadeData.EvadeType.PHYSICAL))

	item_data.weapon_element = scus_data.weapon_element[idx] as Action.ElementTypes
	item_data.weapon_inflict_status_spell_id = scus_data.weapon_inflict_status_cast_id[idx]

	# weapon targeting types based on weapon_flags
	var weapon_flag_byte: int = scus_data.weapon_flags[idx]
	item_data.weapon_is_striking = (weapon_flag_byte & 0x80) == 0x80
	item_data.weapon_is_lunging = (weapon_flag_byte & 0x40) == 0x40
	item_data.weapon_is_direct = (weapon_flag_byte & 0x20) == 0x20
	item_data.weapon_is_arc = (weapon_flag_byte & 0x10) == 0x10

	item_data.is_dual_wieldable = (weapon_flag_byte & 0x08) == 0x08
	item_data.is_two_handable = (weapon_flag_byte & 0x04) == 0x04
	item_data.is_throwable = (weapon_flag_byte & 0x02) == 0x02
	item_data.takes_both_hands = (weapon_flag_byte & 0x01) == 0x01

	# make attack action
	var attack_action: Action = Action.new()
	attack_action.target_effects.append(ActionEffect.new(ActionEffect.EffectType.UNIT_STAT, UnitData.StatType.HP))
	attack_action.target_effects[0].base_power_formula.values[0] = item_data.weapon_power
	attack_action.element = item_data.weapon_element
	attack_action.use_weapon_animation = true

	attack_action.display_name = "Attack (" + item_data.display_name + ")"
	FftRegistryHelper.register_unique(rom_reader.actions, attack_action, attack_action.display_name, "Action")
	item_data.weapon_attack_action = attack_action
	item_data.weapon_attack_action_name = attack_action.unique_name
	item_data.equipped_action_names.append(item_data.weapon_attack_action_name)

	attack_action.name_will_display = false
	attack_action.min_targeting_range = 0
	attack_action.max_targeting_range = item_data.max_range
	attack_action.area_of_effect_range = 0
	attack_action.has_vertical_tolerance_from_user = true
	attack_action.cant_target_self = true
	attack_action.applicable_evasion_type = EvadeData.EvadeType.PHYSICAL
	attack_action.blocked_by_golem = true
	attack_action.trigger_counter_flood = true
	attack_action.trigger_counter_grasp = true
	attack_action.trigger_types.append(TriggeredAction.TriggerType.PHYSICAL)
	attack_action.trigger_types.append(TriggeredAction.TriggerType.COUNTER_FLOOD)
	attack_action.trigger_types.append(TriggeredAction.TriggerType.MIMIC)
	attack_action.targeting_type = Action.TargetingTypes.RANGE

	match item_data.item_type:
		ItemData.ItemType.BOW, ItemData.ItemType.CROSSBOW, ItemData.ItemType.GUN, ItemData.ItemType.INSTRUMENT, ItemData.ItemType.BOOK:
			attack_action.min_targeting_range = 3

	match item_data.item_type:
		ItemData.ItemType.FISTS:
			attack_action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.stats[user.StatType.BRAVE].get_modified_value() / 100.0) * user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value()"
		ItemData.ItemType.KNIFE, ItemData.ItemType.NINJA_BLADE, ItemData.ItemType.BOW, ItemData.ItemType.SHURIKEN:
			attack_action.target_effects[0].base_power_formula.formula_text = "((user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() + user.stats[user.StatType.SPEED].get_modified_value()) / 2.0) * %d" % item_data.weapon_power
		ItemData.ItemType.SWORD, ItemData.ItemType.ROD, ItemData.ItemType.CROSSBOW, ItemData.ItemType.SPEAR:
			attack_action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * %d" % item_data.weapon_power
		ItemData.ItemType.KNIGHT_SWORD, ItemData.ItemType.KATANA:
			attack_action.target_effects[0].base_power_formula.formula_text = "(user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value() * user.stats[user.StatType.BRAVE].get_modified_value() / 100.0) * %d" % item_data.weapon_power
		ItemData.ItemType.AXE, ItemData.ItemType.FLAIL, ItemData.ItemType.BAG:
			attack_action.target_effects[0].base_power_formula.formula_text = "randi_range(1, user.stats[user.StatType.PHYSICAL_ATTACK].get_modified_value()) * %d" % item_data.weapon_power
		ItemData.ItemType.STAFF, ItemData.ItemType.POLE:
			attack_action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * %d" % item_data.weapon_power
		ItemData.ItemType.GUN:
			attack_action.target_effects[0].base_power_formula.formula_text = "%d * %d" % [item_data.weapon_power, item_data.weapon_power]
			attack_action.has_vertical_tolerance_from_user = false
		ItemData.ItemType.INSTRUMENT, ItemData.ItemType.BOOK, ItemData.ItemType.CLOTH:
			attack_action.target_effects[0].base_power_formula.formula_text = "user.stats[user.StatType.MAGIC_ATTACK].get_modified_value() * %d" % item_data.weapon_power

	if [ItemData.ItemType.BOW, ItemData.ItemType.CROSSBOW].has(item_data.item_type):
		attack_action.projectile_type = ProjectileEffectInstance.ProjectileType.ARROW

	attack_action.description = "Attack Base Damage = " + attack_action.target_effects[0].base_power_formula.formula_text
	attack_action.target_status_chance = 19 # https://ffhacktics.com/wiki/Weapon_Damage_Calculation

	match item_data.weapon_formula_id:
		4: # proc ability for Formula 04 (magic gun)
			attack_action.applicable_evasion_type = EvadeData.EvadeType.NONE
			attack_action.target_effects.clear()
			var secondary_action_unique_names: PackedStringArray = []
			match item_data.weapon_element:
				Action.ElementTypes.FIRE:
					secondary_action_unique_names = ["fire", "fire_2", "fire_3"]
				Action.ElementTypes.LIGHTNING:
					secondary_action_unique_names = ["bolt", "bolt_2", "bolt_3"]
				Action.ElementTypes.ICE:
					secondary_action_unique_names = ["ice", "ice_2", "ice_3"]

			attack_action.secondary_actions_chances = [60, 30, 10]
			attack_action.secondary_action_list_type = Action.StatusListType.RANDOM

			for secondary_action_idx: int in secondary_action_unique_names.size():
				var new_secondary_action: Action = rom_reader.actions[secondary_action_unique_names[secondary_action_idx]].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
				var original_action_effect_power_value: float = new_secondary_action.target_effects[0].base_power_formula.values[0]
				new_secondary_action.display_name = "Magic Gun " + new_secondary_action.display_name
				FftRegistryHelper.register_unique(rom_reader.actions, new_secondary_action, new_secondary_action.display_name, "Action")
				new_secondary_action.area_of_effect_range = 0
				new_secondary_action.target_effects[0].base_power_formula.values[0] = original_action_effect_power_value * item_data.weapon_power
				new_secondary_action.target_effects[0].base_power_formula.formula_text = str(original_action_effect_power_value * item_data.weapon_power)
				new_secondary_action.mp_cost = 0
				var proc_chance: int = attack_action.secondary_actions_chances[secondary_action_idx]
				attack_action.secondary_actions2.append(SecondaryAction.new(new_secondary_action.unique_name, proc_chance, true, false, false))
		6:
			attack_action.target_effects[0].transfer_to_user = true # absorb hp
		7:
			attack_action.applicable_evasion_type = EvadeData.EvadeType.NONE
			attack_action.target_effects[0].base_power_formula.reverse_sign = false # positive action power is healing when false

	if item_data.weapon_formula_id == 2: # proc ability for Formula 02
		attack_action.secondary_actions2.append(SecondaryAction.new(rom_reader.fft_abilities[item_data.weapon_inflict_status_spell_id].ability_action.unique_name, 19, true, false, true))
	else: # inflict status data
		attack_action.inflict_status_id = item_data.weapon_inflict_status_spell_id
		var inflict_status: ScusData.InflictStatus = scus_data.inflict_statuses[item_data.weapon_inflict_status_spell_id]
		attack_action.target_status_list = inflict_status.status_list
		attack_action.will_remove_target_status = inflict_status.will_cancel
		attack_action.target_status_chance = 19

		attack_action.target_status_list_type = Action.StatusListType.ALL
		if inflict_status.is_random:
			attack_action.target_status_list_type = Action.StatusListType.RANDOM
		elif inflict_status.is_separate:
			attack_action.target_status_list_type = Action.StatusListType.EACH
			attack_action.target_status_chance = roundi(attack_action.target_status_chance * 0.24)

	if item_data.weapon_is_striking:
		attack_action.max_targeting_range = 1
		attack_action.vertical_tolerance = 2.5
	elif item_data.weapon_is_lunging:
		attack_action.max_targeting_range = 2
		attack_action.vertical_tolerance = 3.5
		attack_action.targeting_linear = true
		attack_action.targeting_los = true
	elif item_data.weapon_is_direct:
		attack_action.targeting_los = true

	var default_statuses_prevents_weapon_attacks: PackedStringArray = [
		"crystal",
		"dead",
		"petrify",
		"blood_suck",
		"treasure",
		"chicken",
		"frog",
		"stop",
		"don't_act",
	]
	attack_action.status_prevents_use_any.append_array(default_statuses_prevents_weapon_attacks)

	if item_data.weapon_is_arc or item_data.weapon_is_direct:
		attack_action.target_shared_vfx_handler_id = TrapEffectData.HANDLER_HIT_RANGED
	else:
		attack_action.target_shared_vfx_handler_id = TrapEffectData.HANDLER_HIT_MELEE

	if idx < 0x7a:
		attack_action.animation_executing_id = roundi(battle_bin_data.weapon_animation_ids[item_data.item_type].y * 2)
		attack_action.animation_executing_ids_alternate = [
			roundi(battle_bin_data.weapon_animation_ids[item_data.item_type].x * 2),
			roundi(battle_bin_data.weapon_animation_ids[item_data.item_type].z * 2),
		]


static func _apply_item_attributes(item_data: ItemData, item_attribute: ScusData.ItemAttribute) -> void:
	item_data.pa_modifier = item_attribute.pa_modifier
	item_data.ma_modifier = item_attribute.ma_modifier
	item_data.sp_modifier = item_attribute.sp_modifier
	item_data.move_modifier = item_attribute.move_modifier
	item_data.jump_modifier = item_attribute.jump_modifier

	item_data.passive_effect = PassiveEffect.new()

	item_data.passive_effect.stat_modifiers[UnitData.StatType.PHYSICAL_ATTACK] = Modifier.new("value + " + str(item_attribute.pa_modifier), Modifier.ModifierType.ADD)
	item_data.passive_effect.stat_modifiers[UnitData.StatType.MAGIC_ATTACK] = Modifier.new("value + " + str(item_attribute.ma_modifier), Modifier.ModifierType.ADD)
	item_data.passive_effect.stat_modifiers[UnitData.StatType.SPEED] = Modifier.new("value + " + str(item_attribute.sp_modifier), Modifier.ModifierType.ADD)
	item_data.passive_effect.stat_modifiers[UnitData.StatType.MOVE] = Modifier.new("value + " + str(item_attribute.move_modifier), Modifier.ModifierType.ADD)
	item_data.passive_effect.stat_modifiers[UnitData.StatType.JUMP] = Modifier.new("value + " + str(item_attribute.jump_modifier), Modifier.ModifierType.ADD)

	item_data.passive_effect.status_always = item_attribute.status_always
	item_data.passive_effect.status_immune = item_attribute.status_immune
	item_data.passive_effect.status_start = item_attribute.status_start
	item_data.passive_effect.element_absorb = Action.get_element_types_array([item_attribute.elemental_absorb])
	item_data.passive_effect.element_cancel = Action.get_element_types_array([item_attribute.elemental_cancel])
	item_data.passive_effect.element_half = Action.get_element_types_array([item_attribute.elemental_half])
	item_data.passive_effect.element_weakness = Action.get_element_types_array([item_attribute.elemental_weakness])
	item_data.passive_effect.element_strengthen = Action.get_element_types_array([item_attribute.elemental_strengthen])
