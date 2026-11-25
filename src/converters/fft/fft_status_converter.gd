class_name FftStatusConverter
extends RefCounted


static func create_from_bytes(status_effect_bytes: PackedByteArray, rom_reader: RomReader) -> StatusEffect:
	var status_effect: StatusEffect = StatusEffect.new()
	status_effect.byte_00 = status_effect_bytes.decode_u8(0)
	status_effect.byte_01 = status_effect_bytes.decode_u8(1)
	status_effect.order = status_effect_bytes.decode_u8(2)
	status_effect.duration = status_effect_bytes.decode_u8(3)
	status_effect.checks_01 = status_effect_bytes.decode_u8(4)
	status_effect.checks_02 = status_effect_bytes.decode_u8(5)
	status_effect.status_cancels_flags = status_effect_bytes.slice(6, 11)
	status_effect.status_cant_stack_flags = status_effect_bytes.slice(11, 16)
	status_effect.removed_on_damaged = status_effect.checks_01 & 0x08 == 0x08 # confusion, transparent, charm, sleep
	status_effect.duration_icons = rom_reader.battle_bin_data.status_counter_rects.duplicate()

	if status_effect.duration == 0:
		status_effect.duration_type = StatusEffect.DurationType.INDEFINITE

	return status_effect


# Called after all StatusEffects have been initialized since this indexes into the complete array.
static func resolve_status_flags(status_effect: StatusEffect, status_effects: Array[StatusEffect]) -> void:
	status_effect.status_cancels = decode_status_id_array(status_effect.status_cancels_flags, status_effects)
	status_effect.status_cant_stack = decode_status_id_array(status_effect.status_cant_stack_flags, status_effects)


static func decode_status_id_array(
	status_bitflags: PackedByteArray,
	status_effects: Array[StatusEffect]
) -> PackedStringArray:
	var status_array: PackedStringArray = []

	for byte_idx: int in status_bitflags.size():
		var byte_value: int = status_bitflags.decode_u8(byte_idx)
		for bit_idx: int in range(7, -1, -1):
			if (byte_value & (1 << bit_idx)) != 0:
				var status_index: int = (7 - bit_idx) + (byte_idx * 8)
				status_array.append(status_effects[status_index].unique_name)

	return status_array


static func configure_statuses(status_effects: Array[StatusEffect], rom_reader: RomReader) -> void:
	# https://ffhacktics.com/wiki/Target_XA_affecting_Statuses_(Physical)
	# https://ffhacktics.com/wiki/Target%27s_Status_Affecting_XA_(Magical)
	# https://ffhacktics.com/wiki/Evasion_Changes_due_to_Statuses
	# evade also affected by transparent, concentrate, dark or confuse, on user

	for idx: int in status_effects.size():
		var status: StatusEffect = status_effects[idx]
		status.ai_score_formula.values[0] = rom_reader.battle_bin_data.ai_status_priorities[idx] / 128.0
		status.duration_icons = rom_reader.battle_bin_data.status_counter_rects.duplicate()
		if status.freezes_ct:
			status.passive_effect.ct_gain_modifier.formula_text = "value * 0.0"
		status.passive_effect.can_react = not (status.checks_02 & 0x80 == 0x80) # cant react flag
		status.passive_effect.nullify_targeted = status.checks_02 & 0x20 == 0x20 # ignore attacks flag
		status.passive_effect_name = status.unique_name + "_status"
		status.passive_effect.unique_name = status.passive_effect_name

	# haste
	status_effects[28].passive_effect.ct_gain_modifier.formula_text = "value * 1.5"
	# slow
	status_effects[29].passive_effect.ct_gain_modifier.formula_text = "value * 0.5"

	# defending
	status_effects[6].passive_effect.hit_chance_modifier_targeted.formula_text = "value * 0.5"

	# protect, shell
	for idx: int in [26, 27]:
		status_effects[idx].passive_effect.power_modifier_targeted.formula_text = "value * 0.66"

	# chicken, frog, sleeping, charging
	for idx: int in [21, 22, 35, 4]:
		status_effects[idx].passive_effect.power_modifier_targeted.formula_text = "value * 1.5"

	# dark, confuse
	for idx: int in [10, 11]:
		status_effects[idx].passive_effect.hit_chance_modifier_user.formula_text = "value * 0.5"

	# dont act, sleep, stop, confuse, charging, performing
	for idx: int in [37, 35, 30, 11, 4, 7]:
		status_effects[idx].passive_effect.evade_source_modifiers_targeted = {
			EvadeData.EvadeSource.JOB: Modifier.new("0", Modifier.ModifierType.SET),
			EvadeData.EvadeSource.SHIELD: Modifier.new("0", Modifier.ModifierType.SET),
			EvadeData.EvadeSource.ACCESSORY: Modifier.new("0", Modifier.ModifierType.SET),
			EvadeData.EvadeSource.WEAPON: Modifier.new("0", Modifier.ModifierType.SET),
		}

	# user is transparent
	status_effects[19].passive_effect.target_can_react = false
	status_effects[19].passive_effect.evade_source_modifiers_user = {
		EvadeData.EvadeSource.JOB: Modifier.new("0", Modifier.ModifierType.SET),
		EvadeData.EvadeSource.SHIELD: Modifier.new("0", Modifier.ModifierType.SET),
		EvadeData.EvadeSource.ACCESSORY: Modifier.new("0", Modifier.ModifierType.SET),
		EvadeData.EvadeSource.WEAPON: Modifier.new("0", Modifier.ModifierType.SET),
	}

	# confuse
	status_effects[11].passive_effect.ai_strategy = UnitAi.Strategy.CONFUSED
	# berserk
	status_effects[20].passive_effect.ai_strategy = UnitAi.Strategy.BEST
	# chicken
	status_effects[21].passive_effect.ai_strategy = UnitAi.Strategy.FLEE
	status_effects[21].spritesheet_file_name = "other"
	status_effects[21].palette_idx_offset = 0 # TODO chicken is actually palettes 0-4 depending on original palette
	status_effects[21].other_type_index = 0
	# blood suck
	status_effects[13].passive_effect.ai_strategy = UnitAi.Strategy.BEST
	status_effects[13].passive_effect.added_actions = [rom_reader.fft_abilities[0x0c8].ability_action] # blood suck action
	rom_reader.fft_abilities[0x0c8].ability_action.status_prevents_use_any.erase("blood_suck") # can use blood suck

	# faith
	status_effects[32].passive_effect.stat_modifiers[UnitData.StatType.FAITH] = Modifier.new("100.0", Modifier.ModifierType.SET)
	# innocent
	status_effects[33].passive_effect.stat_modifiers[UnitData.StatType.FAITH] = Modifier.new("0.0", Modifier.ModifierType.SET)

	# float
	# TODO handle ignore depth and add height
	status_effects[17].passive_effect.element_cancel = [Action.ElementTypes.EARTH]
	var terrain_modifier_dict: Dictionary[int, Modifier] = {
		0x0e: Modifier.new("1", Modifier.ModifierType.SET),
		0x0f: Modifier.new("1", Modifier.ModifierType.SET),
		0x10: Modifier.new("1", Modifier.ModifierType.SET),
		0x11: Modifier.new("1", Modifier.ModifierType.SET),
		0x2d: Modifier.new("1", Modifier.ModifierType.SET),
	}
	status_effects[17].passive_effect.terrain_cost_modifiers = terrain_modifier_dict
	status_effects[17].passive_effect.remove_prohibited_terrain = [
		0x12,
		0x19,
		0x1c,
	]

	# oil
	status_effects[16].passive_effect.element_weakness = [Action.ElementTypes.FIRE] # TODO oil is in addition to fire weakness

	# frog
	status_effects[22].passive_effect.added_actions = [rom_reader.fft_abilities[0x16f].ability_action] # frog attack action
	status_effects[22].spritesheet_file_name = "other"
	status_effects[22].palette_idx_offset = 5 # frog is actually palettes 5-9 depending on original palette
	status_effects[22].other_type_index = 1
	rom_reader.fft_abilities[0x16f].ability_action.status_prevents_use_any.erase("frog") # can use frog attack
	rom_reader.fft_abilities[0x01d].ability_action.status_prevents_use_any.erase("frog") # can use Frog

	# crystal
	status_effects[1].spritesheet_file_name = "other"
	status_effects[1].palette_idx_offset = 10 # crystal is actually palettes 10-14 depending on original palette
	status_effects[1].other_type_index = 2

	# treasure
	status_effects[15].spritesheet_file_name = "other"
	status_effects[15].palette_idx_offset = 16 # treasure is actually palettes 16-20 depending on original palette
	status_effects[15].other_type_index = 0

	# death sentence, dead
	for idx: int in [39, 2]:
		status_effects[idx].duration = 3
		status_effects[idx].duration_type = StatusEffect.DurationType.TURNS

	# dead actions
	status_effects[2].action_on_apply = "dead_damage" # dead damage
	status_effects[2].action_on_complete = "dead_to_crystal_treasure" # dead to crystal/treasure

	# poison action
	status_effects[24].action_on_turn_end = "poison_damage"

	# regen action
	status_effects[25].action_on_turn_end = "regeneration_heal"

	# reraise triggered action
	status_effects[18].passive_effect.added_triggered_actions_names = ["reraise_remove_dead"]

	# undead triggered action
	status_effects[3].passive_effect.added_triggered_actions_names = ["undead_remove_dead"]

	# reflect triggered action
	status_effects[38].passive_effect.added_triggered_actions_names = ["reflect"]

	# death sentence action
	status_effects[39].action_on_complete = "death_sentence_to_dead"

	# TODO Invite, Charm
	# TODO Undead reverse healing -> damage
