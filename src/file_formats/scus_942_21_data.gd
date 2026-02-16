class_name ScusData

# https://ffhacktics.com/wiki/SCUS_942.21_Data_Tables#MURATA_Main_Program_Data

class SkillsetData:
	var skillset_name: String = ""
	var action_ability_ids: PackedInt32Array = []
	var rsm_ability_ids: PackedInt32Array = []


var jobs_start: int = 0x518b8 # 0x30 byte long entries
var jobs_data: Array[JobData] = [] # special jobs 0x01 - 0x49, generics are 0x4a - 0x5d, generic monsters 0x5e - 0x8d, special monsters 0x8e+

var skillsets_start: int = 0x55294 # 0x55311 start of 05 Basic Skill, 0x19 bytes long
var skillsets_data: Array[SkillsetData] = []

# https://ffhacktics.com/wiki/Ability_Data
var ability_data_all_start: int = 0x4f3f0 # 0x200 entries, 0x08 bytes each
var jp_costs: PackedInt32Array = []
var chance_to_learn: PackedInt32Array = []
var ability_types: Array[FftAbilityData.AbilityType] = [] # FftAbilityData.AbilityType.NORMAL

var ability_data_normal_start: int = 0x503f0 # ids 0x000 - 0x16f, 0x170 entries, 0x0e bytes each
var ranges: PackedInt32Array = []
var area_of_effect_radius: PackedInt32Array = []
var vertical_tolerance: PackedInt32Array = []
var flags1: PackedInt32Array = []
var flags2: PackedInt32Array = []
var flags3: PackedInt32Array = []
var flags4: PackedInt32Array = []
var element_flags: PackedInt32Array = []
var formula_id: PackedInt32Array = []
var formula_x: PackedInt32Array = []
var formula_y: PackedInt32Array = []
var ability_inflict_status_id: PackedInt32Array = []
var ct: PackedInt32Array = []
var mp_cost: PackedInt32Array = []

var ability_data_item_start: int = 0x503f0 # ids 0x170 - 0x17d, 0x0e entries, 0x01 bytes each
var ability_data_throw_start: int = 0x503f0 # ids 0x17e - 0x189, 0x0c entries, 0x01 bytes each
var ability_data_jump_start: int = 0x503f0 # ids 0x18a - 0x195, 0x0c entries, 0x02 bytes each
var ability_data_charge_start: int = 0x503f0 # ids 0x196 - 0x19d, 0x08 entries, 0x02 bytes each
var ability_data_math_start: int = 0x503f0 # ids 0x19e - 0x1a5, 0x08 entries, 0x02 bytes each
var ability_data_rsm_start: int = 0x503f0 # ids 0x1a6 - 0x1ff, 0x5a entries, 0x01 bytes each

# Item data
# https://ffhacktics.com/wiki/Item_Data
var item_data_base_start: int = 0x536b8 # 0xfd entries, 0x0c bytes each
var item_entries: int = 0xfe
var item_entry_length: int = 0x0c
var item_palettes: PackedInt32Array = []
var item_sprite_ids: PackedInt32Array = []
var item_min_levels: PackedInt32Array = []
var item_slot_types: PackedInt32Array = []
var item_types: PackedInt32Array = []
var item_attributes_id: PackedInt32Array = [] # TODO item attributes https://ffhacktics.com/wiki/Item_Attribute
var item_prices: PackedInt32Array = []
var item_shop_availability: PackedInt32Array = []

# item weapon data https://ffhacktics.com/wiki/Weapon_Secondary_Data
var weapon_data_start: int = 0x542b8 # 0x80 entries, 0x08 bytes each
var weapon_entries: int = 0x80
var weapon_entry_length: int = 0x08
var weapon_range: PackedInt32Array = []
var weapon_flags: PackedInt32Array = []
var weapon_formula_id: PackedInt32Array = []
var weapon_power: PackedInt32Array = []
var weapon_evade: PackedInt32Array = []
var weapon_element: PackedInt32Array = []
var weapon_inflict_status_cast_id: PackedInt32Array = []

# item shield data https://ffhacktics.com/wiki/Shield_Secondary_Data
var shield_data_start: int = 0x63eb8-0xf800
var shield_entries: int = 0x90 - 0x80
var shield_entry_length: int = 0x02
var shield_physical_evade: PackedInt32Array = []
var shield_magical_evade: PackedInt32Array = []

# item helm/armour data https://ffhacktics.com/wiki/Helm/Armor_Secondary_Data
var armour_data_start: int = 0x63ed8-0xf800
var armour_entries: int = 0xd0 - 0x90
var armour_entry_length: int = 0x02
var armour_hp_modifier: PackedInt32Array = []
var armour_mp_modifier: PackedInt32Array = []

# item accessory data https://ffhacktics.com/wiki/Accessory_Secondary_Data
var accessory_data_start: int = 0x63f58-0xf800
var accessory_entries: int = 0xf0 - 0xd0
var accessory_entry_length: int = 0x02
var accessory_physical_evade: PackedInt32Array = []
var accessory_magical_evade: PackedInt32Array = []

# item chemist item data https://ffhacktics.com/wiki/Item_Secondary_Data
var chem_item_data_start: int = 0x63f98-0xf800
var chem_item_entries: int = 0xfe - 0xf0
var chem_item_entry_length: int = 0x03
var chem_item_formula_id: PackedInt32Array = []
var chem_item_z: PackedInt32Array = []
var chem_item_inflict_status_id: PackedInt32Array = []

# item attribute data https://ffhacktics.com/wiki/Item_Attribute
class ItemAttribute:
	var pa_modifier: int = 0
	var ma_modifier: int = 0
	var sp_modifier: int = 0
	var move_modifier: int = 0
	var jump_modifier: int = 0
	var status_always: PackedStringArray = [] # 5 bytes of bitflags for up to 40 statuses # TODO use bit index as index into StatusEffect array
	var status_immune: PackedStringArray = [] # 5 bytes of bitflags for up to 40 statuses # TODO use bit index as index into StatusEffect array
	var status_start: PackedStringArray = [] # 5 bytes of bitflags for up to 40 statuses # TODO use bit index as index into StatusEffect array
	var elemental_absorb: int = 0 # 1 byte of bitflags, elemental types
	var elemental_cancel: int = 0 # 1 byte of bitflags, elemental types
	var elemental_half: int = 0 # 1 byte of bitflags, elemental types
	var elemental_weakness: int = 0 # 1 byte of bitflags, elemental types
	var elemental_strengthen: int = 0 # 1 byte of bitflags, elemental types
	
	func set_data(item_attribute_bytes: PackedByteArray) -> void:
		pa_modifier = item_attribute_bytes.decode_u8(0)
		ma_modifier = item_attribute_bytes.decode_u8(1)
		sp_modifier = item_attribute_bytes.decode_u8(2)
		move_modifier = item_attribute_bytes.decode_u8(3)
		jump_modifier = item_attribute_bytes.decode_u8(4)
		status_always = StatusEffect.get_status_id_array(item_attribute_bytes.slice(5, 10))
		status_immune = StatusEffect.get_status_id_array(item_attribute_bytes.slice(10, 15))
		status_start = StatusEffect.get_status_id_array(item_attribute_bytes.slice(15, 20))
		elemental_absorb = item_attribute_bytes.decode_u8(20)
		elemental_cancel = item_attribute_bytes.decode_u8(21)
		elemental_half = item_attribute_bytes.decode_u8(22)
		elemental_weakness = item_attribute_bytes.decode_u8(23)
		elemental_strengthen = item_attribute_bytes.decode_u8(24)


var item_attribute_data_start: int = 0x642c4 - 0xf800
var item_attribute_entries: int = 0x50
var item_attribute_entry_length: int = 0x19
var item_attributes: Array[ItemAttribute] = []

# Status Effect data https://ffhacktics.com/wiki/Status_Effects
var status_effect_data_start: int = 0x565e4
var status_effect_entries: int = 40
var status_effect_entry_length: int = 0x10
var status_effects: Array[StatusEffect] = []

class InflictStatus:
	var is_all: bool = false
	var is_random: bool = false
	var is_separate: bool = false
	var will_cancel: bool = false
	var status_flags: PackedByteArray = []
	var status_list: PackedStringArray = []
	
	func set_data(inflict_status_bytes: PackedByteArray) -> void:
		is_all = inflict_status_bytes.decode_u8(0) & 0x80 == 0x80
		is_random = inflict_status_bytes.decode_u8(0) & 0x40 == 0x40
		is_separate = inflict_status_bytes.decode_u8(0) & 0x20 == 0x20
		will_cancel = inflict_status_bytes.decode_u8(0) & 0x10 == 0x10
		status_flags = inflict_status_bytes.slice(1)
		status_list = StatusEffect.get_status_id_array(status_flags)

# Inflict Status data https://ffhacktics.com/wiki/Inflict_Statuses
var inflict_status_data_start: int = 0x63fc4 - 0xf800
var inflict_status_entries: int = 0x80
var inflict_status_entry_length: int = 0x06
var inflict_statuses: Array[InflictStatus] = []

# unit base data https://ffhacktics.com/wiki/Out_of_Battle_Unit_Generation
var unit_base_data_start: int = 0x5e90c - 0xf800
var unit_base_data_entries: int = 4 # male, female, Ramza, monster
var unit_base_data_length: int = 12 # hp, mp, sp, pa, ma, helmet, armor, accessory, RH weapon, RH shield, LH weapon, LH shield
var unit_base_datas: Array[PackedInt32Array] = []
# unit base stat random mod
var unit_base_stats_mod_start: int = 0x5e93c - 0xf800
var unit_base_stats_mod_entries: int = 4
var unit_base_stats_mod_length: int = 0x05 # hp, mp, sp, pa, ma
var unit_base_stats_mods: Array[PackedInt32Array] = []

# terrain geomancy type https://ffhacktics.com/wiki/Geomancy_tiles_type_to_ability_table
var terrain_geomancy_start: int = 0x4f1d0
var terrain_geomancy_entries: int = 0x2f # number of terrain types
var terrain_geomancy_length: int = 0x01 # geomancy ability id
var terrain_geomancy: Array[int] = [] # idx is terrain type, entry is ability id


func init_from_scus() -> void:
	var scus_bytes: PackedByteArray = RomReader.get_file_data("SCUS_942.21")
	
	# status effect data https://ffhacktics.com/wiki/SCUS_942.21_Data_Tables
	# status effects need to be loaded first to be referenced by other data
	var status_effect_data_bytes: PackedByteArray = scus_bytes.slice(status_effect_data_start, status_effect_data_start + (status_effect_entries * status_effect_entry_length))
	status_effects.resize(status_effect_entries)
	for id: int in status_effect_entries:
		var new_status_effect_bytes: PackedByteArray = status_effect_data_bytes.slice(id * status_effect_entry_length, (id + 1) * status_effect_entry_length)
		var new_status_effect: StatusEffect = StatusEffect.new()
		new_status_effect.set_data(new_status_effect_bytes)
		new_status_effect.status_effect_name = RomReader.fft_text.status_names[id]
		new_status_effect.add_to_global_list()
		new_status_effect.status_id = id
		status_effects[id] = new_status_effect
		
		if RomReader.battle_bin_data.status_colors.has(id):
			var r: int = RomReader.battle_bin_data.status_colors[id][0]
			var g: int = RomReader.battle_bin_data.status_colors[id][1]
			var b: int = RomReader.battle_bin_data.status_colors[id][2]
			new_status_effect.shading_color = Color8(r, g, b)
			new_status_effect.shading_type = RomReader.battle_bin_data.status_colors[id][3]
		
		if RomReader.battle_bin_data.status_modulate_colors.has(id):
			new_status_effect.modulation_color = RomReader.battle_bin_data.status_modulate_colors[id]
		
		if RomReader.battle_bin_data.status_idle_animations.has(id):
			new_status_effect.idle_animation_id = RomReader.battle_bin_data.status_idle_animations[id]
		
		
	
	for status_effect: StatusEffect in status_effects:
		status_effect.status_flags_to_status_array() # called after all StatusEffects have already been initialized since this indexes into the complete array
	
	# Inflict Status data https://ffhacktics.com/wiki/Inflict_Statuses
	# inflict status data needs to be loaded before abilities and items that reference the array
	var inflict_status_data_bytes: PackedByteArray = scus_bytes.slice(inflict_status_data_start, inflict_status_data_start + (inflict_status_entries * inflict_status_entry_length))
	inflict_statuses.resize(inflict_status_entries)
	for id: int in inflict_status_entries:
		var new_inflict_status_bytes: PackedByteArray = inflict_status_data_bytes.slice(id * inflict_status_entry_length, (id + 1) * inflict_status_entry_length)
		var new_inflict_status: InflictStatus = InflictStatus.new()
		new_inflict_status.set_data(new_inflict_status_bytes)
		inflict_statuses[id] = new_inflict_status
	
	
	# job data
	var entry_size: int = 0x30 # bytes
	var num_entries: int = RomReader.NUM_JOBS
	var job_bytes: PackedByteArray = scus_bytes.slice(jobs_start, jobs_start + (num_entries * entry_size))
	jobs_data.resize(num_entries)
	for job_id: int in num_entries:
		var job_entry_bytes: PackedByteArray = job_bytes.slice(job_id * entry_size, (job_id * entry_size) + entry_size)
		var job_data: JobData = JobData.new(job_id, job_entry_bytes)
		#job_data.job_name = RomReader.fft_text.job_names[job_id]
		#job_data.skillset_id = job_bytes.decode_u8(job_id * entry_size)
		#job_data.monster_type = job_bytes.decode_u8((job_id * entry_size) + 0x2f)
		jobs_data[job_id] = job_data
	
	# unit skillset data
	skillsets_data.resize(RomReader.NUM_SKILLSETS)
	
	entry_size = 0x19 # bytes
	num_entries = RomReader.NUM_UNIT_SKILLSETS
	var unit_skillsets_bytes: PackedByteArray = scus_bytes.slice(skillsets_start, skillsets_start + (num_entries * entry_size))
	for skillset_id: int in num_entries:
		var skillset_data: SkillsetData = SkillsetData.new()
		skillset_data.skillset_name = RomReader.fft_text.skillset_names[skillset_id]
		skillset_data.action_ability_ids.resize(16)
		skillset_data.rsm_ability_ids.resize(6)
		for skill_slot: int in 16: # action abilities
			var ability_id: int = unit_skillsets_bytes.decode_u8((skillset_id * entry_size) + 3 + skill_slot)
			var flag: int = 2**(7 - (skill_slot % 8)) # add 0x100 to ability ID if bit is 1 for each ability, 0x80 = Ability 1 (eg. Item ability, etc)
			if skill_slot < 8:
				ability_id += 0x100 if unit_skillsets_bytes.decode_u8((skillset_id * entry_size)) & flag != 0 else 0
			elif skill_slot < 16:
				ability_id += 0x100 if unit_skillsets_bytes.decode_u8((skillset_id * entry_size) + 1) & flag != 0 else 0
			
			skillset_data.action_ability_ids[skill_slot] = ability_id
			
		for skill_slot: int in 6: # rsm abilities
			var ability_id: int = unit_skillsets_bytes.decode_u8((skillset_id * entry_size) + 3 + 16 + skill_slot)
			var flag: int = 2**(7 - (skill_slot % 8)) # add 0x100 to ability ID if bit is 1 for each ability, 0x80 = RSM Ability 1 (rightmost 2 bits unused)
			ability_id += 0x100 if unit_skillsets_bytes.decode_u8((skillset_id * entry_size) + 2) & flag != 0 else 0
			skillset_data.rsm_ability_ids[skill_slot] = ability_id
		
		skillsets_data[skillset_id] = skillset_data
	
	# monster skillset data
	var monster_skillsets_start: int = skillsets_start + (RomReader.NUM_UNIT_SKILLSETS * entry_size)
	entry_size = 0x05 # bytes
	num_entries = RomReader.NUM_MONSTER_SKILLSETS
	var monster_skillsets_bytes: PackedByteArray = scus_bytes.slice(monster_skillsets_start, monster_skillsets_start + (num_entries * entry_size))
	for skillset_id: int in num_entries:
		var skillset_data: SkillsetData = SkillsetData.new()
		skillset_data.action_ability_ids.resize(4)
		for skill_slot: int in 4: # action abilities
			var ability_id: int = monster_skillsets_bytes.decode_u8((skillset_id * entry_size) + 1 + skill_slot)
			var flag: int = 2**(7 - (skill_slot % 8)) # add 0x100 to ability ID if bit is 1 for each ability, 0x80 = Ability 1 (eg. Item ability, etc)
			ability_id += 0x100 if monster_skillsets_bytes.decode_u8(skillset_id * entry_size) & flag != 0 else 0
			skillset_data.action_ability_ids[skill_slot] = ability_id
		
		skillsets_data[skillset_id + RomReader.NUM_UNIT_SKILLSETS] = skillset_data
	
	# ability data all
	jp_costs.resize(RomReader.NUM_ABILITIES)
	chance_to_learn.resize(RomReader.NUM_ABILITIES)
	ability_types.resize(RomReader.NUM_ABILITIES)
	
	entry_size = 0x08 # bytes
	num_entries = RomReader.NUM_ABILITIES
	var ability_data_bytes: PackedByteArray = scus_bytes.slice(ability_data_all_start, ability_data_all_start + (num_entries * entry_size))
	for id: int in num_entries:
		jp_costs[id] = ability_data_bytes.decode_u16(id * entry_size)
		chance_to_learn[id] = ability_data_bytes.decode_u8((id * entry_size) + 2)
		ability_types[id] = FftAbilityData.AbilityType.values()[ability_data_bytes.decode_u8((id * entry_size) + 3) % 16]
	
	# ability data normal
	ranges.resize(RomReader.NUM_ABILITIES)
	area_of_effect_radius.resize(RomReader.NUM_ABILITIES)
	vertical_tolerance.resize(RomReader.NUM_ABILITIES)
	flags1.resize(RomReader.NUM_ABILITIES)
	flags2.resize(RomReader.NUM_ABILITIES)
	flags3.resize(RomReader.NUM_ABILITIES)
	flags4.resize(RomReader.NUM_ABILITIES)
	element_flags.resize(RomReader.NUM_ABILITIES)
	formula_id.resize(RomReader.NUM_ABILITIES)
	formula_x.resize(RomReader.NUM_ABILITIES)
	formula_y.resize(RomReader.NUM_ABILITIES)
	ability_inflict_status_id.resize(RomReader.NUM_ABILITIES)
	ct.resize(RomReader.NUM_ABILITIES)
	mp_cost.resize(RomReader.NUM_ABILITIES)
	
	entry_size = 0x0e # bytes
	num_entries = 0x170
	ability_data_bytes = scus_bytes.slice(ability_data_normal_start, ability_data_normal_start + (num_entries * entry_size))
	for id: int in num_entries:
		ranges[id] = ability_data_bytes.decode_u8(id * entry_size)
		area_of_effect_radius[id] = ability_data_bytes.decode_u8((id * entry_size) + 1)
		vertical_tolerance[id] = ability_data_bytes.decode_u8((id * entry_size) + 2)
		flags1[id] = ability_data_bytes.decode_u8((id * entry_size) + 3)
		flags2[id] = ability_data_bytes.decode_u8((id * entry_size) + 4)
		flags3[id] = ability_data_bytes.decode_u8((id * entry_size) + 5)
		flags4[id] = ability_data_bytes.decode_u8((id * entry_size) + 6)
		element_flags[id] = ability_data_bytes.decode_u8((id * entry_size) + 7)
		formula_id[id] = ability_data_bytes.decode_u8((id * entry_size) + 8)
		formula_x[id] = ability_data_bytes.decode_u8((id * entry_size) + 9)
		formula_y[id] = ability_data_bytes.decode_u8((id * entry_size) + 10)
		ability_inflict_status_id[id] = ability_data_bytes.decode_u8((id * entry_size) + 11)
		ct[id] = ability_data_bytes.decode_u8((id * entry_size) + 12)
		mp_cost[id] = ability_data_bytes.decode_u8((id * entry_size) + 13)
	
	# item data base
	item_palettes.resize(item_entries)
	item_sprite_ids.resize(item_entries)
	item_min_levels.resize(item_entries)
	item_slot_types.resize(item_entries)
	item_types.resize(item_entries)
	item_attributes_id.resize(item_entries)
	item_prices.resize(item_entries)
	item_shop_availability.resize(item_entries)
	
	var item_data_bytes: PackedByteArray = scus_bytes.slice(item_data_base_start, item_data_base_start + (item_entries * item_entry_length))
	for id: int in item_entries:
		item_palettes[id] = item_data_bytes.decode_u8(id * item_entry_length)
		item_sprite_ids[id] = item_data_bytes.decode_u8((id * item_entry_length) + 1)
		item_min_levels[id] = item_data_bytes.decode_u8((id * item_entry_length) + 2)
		item_slot_types[id] = item_data_bytes.decode_u8((id * item_entry_length) + 3)
		item_types[id] = item_data_bytes.decode_u8((id * item_entry_length) + 5)
		item_attributes_id[id] = item_data_bytes.decode_u8((id * item_entry_length) + 7)
		item_prices[id] = item_data_bytes.decode_u16((id * item_entry_length) + 8)
		item_shop_availability[id] = item_data_bytes.decode_u8((id * item_entry_length) + 10)
	
	# item weapon data https://ffhacktics.com/wiki/Weapon_Secondary_Data
	var weapon_data_bytes: PackedByteArray = scus_bytes.slice(weapon_data_start, weapon_data_start + (weapon_entries * weapon_entry_length))
	weapon_range.resize(weapon_entries)
	weapon_flags.resize(weapon_entries)
	weapon_formula_id.resize(weapon_entries)
	weapon_power.resize(weapon_entries)
	weapon_evade.resize(weapon_entries)
	weapon_element.resize(weapon_entries)
	weapon_inflict_status_cast_id.resize(weapon_entries)
	for id: int in weapon_entries:
		weapon_range[id] = weapon_data_bytes.decode_u8(id * weapon_entry_length)
		weapon_flags[id] = weapon_data_bytes.decode_u8((id * weapon_entry_length) + 1)
		weapon_formula_id[id] = weapon_data_bytes.decode_u8((id * weapon_entry_length) + 2)
		weapon_power[id] = weapon_data_bytes.decode_u8((id * weapon_entry_length) + 4)
		weapon_evade[id] = weapon_data_bytes.decode_u8((id * weapon_entry_length) + 5)
		weapon_element[id] = weapon_data_bytes.decode_u8((id * weapon_entry_length) + 6)
		weapon_inflict_status_cast_id[id] = weapon_data_bytes.decode_u8((id * weapon_entry_length) + 7)
	
	# item shield data https://ffhacktics.com/wiki/Shield_Secondary_Data
	var shield_data_bytes: PackedByteArray = scus_bytes.slice(shield_data_start, shield_data_start + (shield_entries * shield_entry_length))
	shield_physical_evade.resize(shield_entries)
	shield_magical_evade.resize(shield_entries)
	for id: int in shield_entries:
		shield_physical_evade[id] = shield_data_bytes.decode_u8(id * shield_entry_length)
		shield_magical_evade[id] = shield_data_bytes.decode_u8((id * shield_entry_length) + 1)
	
	# item helm/armour data https://ffhacktics.com/wiki/Helm/Armor_Secondary_Data
	var armour_data_bytes: PackedByteArray = scus_bytes.slice(armour_data_start,armour_data_start + (armour_entries * armour_entry_length))
	armour_hp_modifier.resize(armour_entries)
	armour_mp_modifier.resize(armour_entries)
	for id: int in armour_entries:
		armour_hp_modifier[id] = armour_data_bytes.decode_u8(id * armour_entry_length)
		armour_mp_modifier[id] = armour_data_bytes.decode_u8((id * armour_entry_length) + 1)
	
	# item accessory data https://ffhacktics.com/wiki/Accessory_Secondary_Data
	var accessory_data_bytes: PackedByteArray = scus_bytes.slice(accessory_data_start, accessory_data_start + (accessory_entries * accessory_entry_length))
	accessory_physical_evade.resize(accessory_entries)
	accessory_magical_evade.resize(accessory_entries)
	for id: int in accessory_entries:
		accessory_physical_evade[id] = accessory_data_bytes.decode_u8(id * accessory_entry_length)
		accessory_magical_evade[id] = accessory_data_bytes.decode_u8((id * accessory_entry_length) + 1)
	
	# item chemist item data https://ffhacktics.com/wiki/Item_Secondary_Data
	var chem_item_data_bytes: PackedByteArray = scus_bytes.slice(chem_item_data_start, chem_item_data_start + (chem_item_entries * chem_item_entry_length))
	chem_item_formula_id.resize(chem_item_entries)
	chem_item_z.resize(chem_item_entries)
	chem_item_inflict_status_id.resize(chem_item_entries)
	for id: int in chem_item_entries:
		chem_item_formula_id[id] = chem_item_data_bytes.decode_u8(id * chem_item_entry_length)
		chem_item_z[id] = chem_item_data_bytes.decode_u8((id * chem_item_entry_length) + 1)
		chem_item_inflict_status_id[id] = chem_item_data_bytes.decode_u8((id * chem_item_entry_length) + 2)
	
	# item attribute data https://ffhacktics.com/wiki/Item_Attribute
	var item_attribute_data_bytes: PackedByteArray = scus_bytes.slice(item_attribute_data_start, item_attribute_data_start + (item_attribute_entries * item_attribute_entry_length))
	item_attributes.resize(item_attribute_entries)
	for id: int in item_attribute_entries:
		var new_item_attribute_bytes: PackedByteArray = item_attribute_data_bytes.slice(id * item_attribute_entry_length, (id + 1) * item_attribute_entry_length)
		var new_item_attribute: ItemAttribute = ItemAttribute.new()
		new_item_attribute.set_data(new_item_attribute_bytes)
		item_attributes[id] = new_item_attribute
	
	# unit base data https://ffhacktics.com/wiki/Out_of_Battle_Unit_Generation
	# https://ffhacktics.com/wiki/Generate_Unit%27s_Base_Raw_Stats
	var unit_base_data_bytes: PackedByteArray = scus_bytes.slice(unit_base_data_start, unit_base_data_start + (unit_base_data_entries * unit_base_data_length))
	unit_base_datas.resize(unit_base_data_entries)
	for idx: int in unit_base_data_entries:
		var unit_base_data: PackedInt32Array = []
		unit_base_data.resize(unit_base_data_length)
		for byte_idx: int in unit_base_data_length:
			unit_base_data[byte_idx] = unit_base_data_bytes.decode_u8(byte_idx + (idx * unit_base_data_length))
		unit_base_datas[idx] = unit_base_data
	
	var unit_base_stats_mod_bytes: PackedByteArray = scus_bytes.slice(unit_base_stats_mod_start, unit_base_stats_mod_start + (unit_base_stats_mod_entries * unit_base_stats_mod_length))
	unit_base_stats_mods.resize(unit_base_stats_mod_entries)
	for idx: int in unit_base_stats_mod_entries:
		var unit_stat_mods_data: PackedInt32Array = []
		unit_stat_mods_data.resize(unit_base_stats_mod_length)
		for byte_idx: int in unit_base_stats_mod_length:
			unit_stat_mods_data[byte_idx] = unit_base_stats_mod_bytes.decode_u8((idx * unit_base_stats_mod_length) + byte_idx)
		unit_base_stats_mods[idx] = unit_stat_mods_data
	
	var terrain_geomancy_bytes: PackedByteArray = scus_bytes.slice(terrain_geomancy_start, terrain_geomancy_start + (terrain_geomancy_entries * terrain_geomancy_length))
	terrain_geomancy.resize(terrain_geomancy_entries)
	for byte_idx: int in terrain_geomancy_bytes.size():
		terrain_geomancy.append(terrain_geomancy_bytes.decode_u8(byte_idx))


func init_statuses() -> void:
	# https://ffhacktics.com/wiki/Target_XA_affecting_Statuses_(Physical)
	# https://ffhacktics.com/wiki/Target%27s_Status_Affecting_XA_(Magical)
	# https://ffhacktics.com/wiki/Evasion_Changes_due_to_Statuses
	# evade also affected by transparent, concentrate, dark or confuse, on user

	for idx: int in status_effects.size():
		status_effects[idx].ai_score_formula.values[0] = RomReader.battle_bin_data.ai_status_priorities[idx] / 128.0
	
	# haste
	# status_effects[28].passive_effect.ct_gain_modifier.value_formula.values = [1.5]
	status_effects[28].passive_effect.ct_gain_modifier.formula_text = "value * 1.5"
	# slow
	# status_effects[29].passive_effect.ct_gain_modifier.value_formula.values = [0.5]
	status_effects[29].passive_effect.ct_gain_modifier.formula_text = "value * 0.5"
	
	# freeze ct flag
	for status: StatusEffect in status_effects:
		if status.freezes_ct:
			# status.passive_effect.ct_gain_modifier.value_formula.values = [0.0]
			status.passive_effect.ct_gain_modifier.formula_text = "value * 0.0"
		status.passive_effect.can_react = not (status.checks_02 & 0x80 == 0x80) # cant react flag
		status.passive_effect.nullify_targeted = status.checks_02 & 0x20 == 0x20 # ignore attacks flag
	
	# reflect - handled as a triggered action
	# status_effects[38].passive_effect.hit_chance_modifier_targeted.value = 0.0
	
	# defending
	# status_effects[6].passive_effect.hit_chance_modifier_targeted.value_formula.values = [0.5]
	status_effects[6].passive_effect.hit_chance_modifier_targeted.formula_text = "value * 0.5"
	
	# protect, shell
	for idx: int in [26, 27]:
		# status_effects[idx].passive_effect.hit_chance_modifier_targeted.value_formula.values = [0.66]
		# status_effects[idx].passive_effect.power_modifier_targeted.value_formula.values = [0.66]
		status_effects[idx].passive_effect.power_modifier_targeted.formula_text = "value * 0.66"
	
	# chicken, frog, sleeping, charging
	for idx: int in [21, 22, 35, 4]:
		#status_effects[idx].passive_effect.hit_chance_modifier_targeted.value_formula.values = [1.5]
		# status_effects[idx].passive_effect.power_modifier_targeted.value_formula.values = [1.5]
		status_effects[idx].passive_effect.power_modifier_targeted.formula_text = "value * 1.5"
	
	# dark, confuse
	for idx: int in [10, 11]:
		# status_effects[idx].passive_effect.hit_chance_modifier_user.value_formula.values = [0.5]
		status_effects[idx].passive_effect.hit_chance_modifier_user.formula_text = "value * 0.5"
	
	# dont act, sleep, stop, confuse, charging, performing
	for idx: int in [37, 35, 30, 11, 4, 7]:
		# status_effects[idx].passive_effect.evade_modifier_targeted.type = Modifier.ModifierType.SET
		# status_effects[idx].passive_effect.evade_modifier_targeted.value = 1.0
		status_effects[idx].passive_effect.evade_source_modifiers_targeted = {
			EvadeData.EvadeSource.JOB: Modifier.new("0", Modifier.ModifierType.SET),
			EvadeData.EvadeSource.SHIELD: Modifier.new("0", Modifier.ModifierType.SET),
			EvadeData.EvadeSource.ACCESSORY: Modifier.new("0", Modifier.ModifierType.SET),
			EvadeData.EvadeSource.WEAPON: Modifier.new("0", Modifier.ModifierType.SET),
		}
	
	# user is transparent
	status_effects[19].passive_effect.target_can_react = false
	# status_effects[19].passive_effect.evade_modifier_user.type = Modifier.ModifierType.SET
	# status_effects[19].passive_effect.evade_modifier_user.value = 1.0
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
	status_effects[21].spritesheet_file_name = "OTHER.SPR"
	status_effects[21].palette_idx_offset = 0 # TODO chicken is actually palettes 0-4 depending on original palette
	status_effects[1].other_type_index = 0
	# blood suck
	status_effects[13].passive_effect.ai_strategy = UnitAi.Strategy.BEST
	status_effects[13].passive_effect.added_actions = [RomReader.fft_abilities[0x0c8].ability_action] # blood suck action
	RomReader.fft_abilities[0x0c8].ability_action.status_prevents_use_any.erase("blood_suck") # can use blood suck
	
	# faith
	status_effects[32].passive_effect.stat_modifiers[Unit.StatType.FAITH] = Modifier.new("100.0", Modifier.ModifierType.SET)
	# innocent
	status_effects[33].passive_effect.stat_modifiers[Unit.StatType.FAITH] = Modifier.new("0.0", Modifier.ModifierType.SET)
	
	# float
	# TODO handle ignore depth and add height
	status_effects[17].passive_effect.element_cancel = [Action.ElementTypes.EARTH]
	var terrain_modifier_dict: Dictionary[int, Modifier] = {
		0x0e : Modifier.new("1", Modifier.ModifierType.SET),
		0x0f: Modifier.new("1", Modifier.ModifierType.SET),
		0x10 : Modifier.new("1", Modifier.ModifierType.SET),
		0x11 : Modifier.new("1", Modifier.ModifierType.SET),
		0x2d : Modifier.new("1", Modifier.ModifierType.SET),
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
	status_effects[22].passive_effect.added_actions = [RomReader.fft_abilities[0x16f].ability_action] # frog attack action
	status_effects[22].spritesheet_file_name = "OTHER.SPR"
	status_effects[22].palette_idx_offset = 5 # frog is actually palettes 5-9 depending on original palette
	status_effects[22].other_type_index = 1
	RomReader.fft_abilities[0x16f].ability_action.status_prevents_use_any.erase("frog") # can use frog attack
	RomReader.fft_abilities[0x01d].ability_action.status_prevents_use_any.erase("frog") # can use Frog
	
	# crystal
	status_effects[1].spritesheet_file_name = "OTHER.SPR"
	status_effects[1].palette_idx_offset = 10 # crystal is actually palettes 10-14 depending on original palette
	status_effects[1].other_type_index = 2

	# treasure
	status_effects[15].spritesheet_file_name = "OTHER.SPR"
	status_effects[15].palette_idx_offset = 16 # treasure is actually palettes 16-20 depending on original palette
	status_effects[15].other_type_index = 0

	# death sentence, dead
	for idx: int in [39, 2]:
		status_effects[idx].duration = 3
		status_effects[idx].duration_type = StatusEffect.DurationType.TURNS
	
	# dead actions
	status_effects[2].action_on_apply = "dead_damage" # dead damage
	status_effects[2].action_on_complete = "dead_to_crystal" # dead to crystal/treasure

	# poison action
	status_effects[24].action_on_turn_end = "poison_damage"

	# regen action
	status_effects[25].action_on_turn_end = "regen_heal"

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

	#for status: StatusEffect in status_effects:
		#if status.passive_effect != null:
			#status.passive_effect.unique_name = status.unique_name
			#Utilities.save_json(status.passive_effect)

	# var default_passive_json: String = PassiveEffect.new().to_json()
	# # Utilities.save_json(PassiveEffect.new())
	# for idx: int in status_effects.size():
	# 	var status_passive_json: String = status_effects[idx].passive_effect.to_json()
	# 	if not status_passive_json == default_passive_json:
	# 		status_effects[idx].passive_effect.unique_name = status_effects[idx].unique_name + "_status"
	# 		status_effects[idx].passive_effect_name = status_effects[idx].passive_effect.unique_name
	# 		status_effects[idx].passive_effect.add_to_global_list()
	# 		Utilities.save_json(status_effects[idx].passive_effect)
		
	# 	Utilities.save_json(status_effects[idx])
