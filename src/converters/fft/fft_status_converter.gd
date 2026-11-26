class_name FftStatusConverter
extends RefCounted

const STATUS_ICON_IDS: Dictionary[int, int] = {
	24: 18, # poison
	4: 9, # charging - second frame is 12 pixels lower
	10: 2, # darkness
	11: 12, # confuse
	12: 3, # silence
	13: 13, # blood suck
	16: 19, # oil
	18: 10, # reraise - second frame is 12 pixels lower
	20: 5, # berserk
	26: 16, # protect
	27: 17, # shell
	32: 6, # faith
	33: 7, # innocent
	34: 4, # charm
	35: 1, # sleep
	36: 14, # don't move
	37: 15, # don't act
} # active turn is icon 8 + second frame, ko stars are icons 0, 11

# https://ffhacktics.com/wiki/Set_Idle_Animation_based_on_status_(not_MON)
# https://ffhacktics.com/wiki/More_animation_based_on_status,_death_sound_effects
# https://ffhacktics.com/wiki/Set_Animation_Based_On_Unit_Status
const STATUS_IDLE_ANIMATIONS: Dictionary[int, int] = { # status_id : animation_id
	1: 18, # crystal
	15: 42, # treasure
	2: 52, # dead
	30: 2, # stop TODO facing frames (ptr_id <= 5) need to be handled differently from other animations
	35: 72, # sleep
	8: 2, # petrify TODO facing frames (ptr_id <= 5) need to be handled differently from other animations
	11: 74, # confusion
	7: 0x50, # performing - TODO use ability ID (0x50 singing or 0x52 dancing)
	4: 0x56, # charging - TODO use ability ID (typically 0x54 to 0x56)
	6: 46, # defending
	28: 0x08, # haste - TODO useHeight1 (14 for flying sprites)
	29: 0x0a, # slow - TODO useHeight2 (16 for flying sprites)
	14: 2, # cursed TODO facing frames (ptr_id <= 5) need to be handled differently from other animations
	0: 66, # blank
	23: 72, # critical
}


static func create_from_bytes(status_effect_bytes: PackedByteArray) -> StatusEffect:
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

	_apply_status_visuals_and_animations(status_effects, rom_reader.battle_bin_data)

	for idx: int in status_effects.size():
		var status: StatusEffect = status_effects[idx]
		status.ai_score_formula.values[0] = rom_reader.battle_bin_data.ai_status_priorities[idx] / 128.0
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
			EvadeData.EvadeSource.JOB: Modifier.new("0", Modifier.ModifierOrder.SET),
			EvadeData.EvadeSource.SHIELD: Modifier.new("0", Modifier.ModifierOrder.SET),
			EvadeData.EvadeSource.ACCESSORY: Modifier.new("0", Modifier.ModifierOrder.SET),
			EvadeData.EvadeSource.WEAPON: Modifier.new("0", Modifier.ModifierOrder.SET),
		}

	# user is transparent
	status_effects[19].passive_effect.target_can_react = false
	status_effects[19].passive_effect.evade_source_modifiers_user = {
		EvadeData.EvadeSource.JOB: Modifier.new("0", Modifier.ModifierOrder.SET),
		EvadeData.EvadeSource.SHIELD: Modifier.new("0", Modifier.ModifierOrder.SET),
		EvadeData.EvadeSource.ACCESSORY: Modifier.new("0", Modifier.ModifierOrder.SET),
		EvadeData.EvadeSource.WEAPON: Modifier.new("0", Modifier.ModifierOrder.SET),
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
	status_effects[32].passive_effect.stat_modifiers[UnitData.StatType.FAITH] = Modifier.new("100.0", Modifier.ModifierOrder.SET)
	# innocent
	status_effects[33].passive_effect.stat_modifiers[UnitData.StatType.FAITH] = Modifier.new("0.0", Modifier.ModifierOrder.SET)

	# float
	# TODO handle ignore depth and add height
	status_effects[17].passive_effect.element_cancel = [Action.ElementTypes.EARTH]
	var terrain_modifier_dict: Dictionary[int, Modifier] = {
		0x0e: Modifier.new("1", Modifier.ModifierOrder.SET),
		0x0f: Modifier.new("1", Modifier.ModifierOrder.SET),
		0x10: Modifier.new("1", Modifier.ModifierOrder.SET),
		0x11: Modifier.new("1", Modifier.ModifierOrder.SET),
		0x2d: Modifier.new("1", Modifier.ModifierOrder.SET),
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


static func _apply_status_visuals_and_animations(
	status_effects: Array[StatusEffect],
	battle_bin_data: BattleBinData
) -> void:
	# https://ffhacktics.com/wiki/Palette_mod_by_status
	var status_colors: Dictionary[int, PackedInt32Array] = { # status_id : [R, G, B, Shade type]
		8: PackedInt32Array([0, 0, 0, 6]), # petrify
		13: PackedInt32Array([3, -1, 8, 6]), # blood suck
		20: PackedInt32Array([8, 0, 0, 4]), # berserk
		24: PackedInt32Array([0, 8, 0, 5]), # poison
		25: PackedInt32Array([0, 0, 8, 4]), # regen
		16: PackedInt32Array([-4, -4, -4, 5]), # oil
		14: PackedInt32Array([-8, -8, -8, 5]), # cursed
		3: PackedInt32Array([4, 0, 5, 5]), # undead
	}
	var status_modulate_colors: Dictionary[int, Color] = { # status_id : [R, G, B, A]
		8: Color8(32, 32, 32), # petrify
		13: Color8(84, 87, 255), # blood suck
		20: Color8(255, 128, 128), # berserk
		24: Color8(64, 192, 64), # poison
		25: Color8(21, 150, 231), # regen
		16: Color8(64, 64, 64), # oil
		14: Color8(32, 32, 32), # cursed
		3: Color8(116, 14, 255), # undead
		19: Color8(255, 255, 255, 128), # transparent
	}

	for status_id: int in status_effects.size():
		var status: StatusEffect = status_effects[status_id]
		status.duration_icons = battle_bin_data.status_counter_rects.duplicate()

		if STATUS_ICON_IDS.has(status_id):
			var rect: Rect2i = battle_bin_data.status_icon_rects[STATUS_ICON_IDS[status_id]]
			status.icon_rects.append(rect) # TODO get second frame of status icons

		if status_colors.has(status_id):
			var color_entry: PackedInt32Array = status_colors[status_id]
			status.shading_color = Color8(color_entry[0], color_entry[1], color_entry[2])
			status.shading_type = color_entry[3]

		if status_modulate_colors.has(status_id):
			status.modulation_color = status_modulate_colors[status_id]

		if STATUS_IDLE_ANIMATIONS.has(status_id):
			status.idle_animation_id = STATUS_IDLE_ANIMATIONS[status_id]
