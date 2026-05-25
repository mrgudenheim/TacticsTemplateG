class_name FftEntdUnit
extends Resource

@export var sprite_set_id: int = 0 # 0x80 = generic male, 0x81 = generic female, 0x82 = monster, <0x80 = special unit

@export var flags1: int = 0 # 0x80 = male, 0x40 = female, 0x20 = monster
@export var gender: int = 0
@export var join_after_event: bool = false # 0x10
@export var load_formation: bool = false # 0x08 looks for unit id in roster to load stats, used for guests?
@export var hide_stats: bool = false # 0x04 shows ??? instead of stat values
@export var flag1_02: int = 0 # 0x02 unknown
@export var join_as_guest: bool = false # 0x01

@export var name_idx: int = 0
@export var level: int = 0 # 0xFE = party_level - random
@export var birthday_month: int = 0
@export var birthday_day: int = 0
@export var brave: int = 0 # 0xFE = random
@export var faith: int = 0 # 0xFE = random
@export var job_unlock: int = 0
@export var job_level: int = 0

@export var main_job: int = 0
@export var secondary_skillset: int = 0  # 0x00 = none
@export var reaction: int = 0 # 0xFE01 = random
@export var support: int = 0 # 0xFE01 = random
@export var movement: int = 0 # 0xFE01 = random

@export var equipment_head: int = 0 # 0xFE = random
@export var equipment_body: int = 0 # 0xFE = random
@export var equipment_accessory: int = 0 # 0xFE = random
@export var equipment_right_hand: int = 0 # 0xFE = random
@export var equipment_left_hand: int = 0 # 0xFE = random

@export var palette: int = 0

@export var flags2: int = 0 # 0x80 = always present, 0x40 = randomly present
@export var always_present: bool = true # always or randomly
@export var randomly_present: bool = false
@export var team_color_idx: int = 0 # 0x30 => 0x00 = blue, 0x01 = red, 0x02 = green, 0x03 = light blue
@export var is_player_controlled: bool = false # 0x08
@export var is_immortal: bool = false # 0x04

@export var position_x: int = 0
@export var position_y: int = 0

@export var flags3: int = 0
@export var upper_level: int = 0 #0x80
@export var initial_direction: int = 0 #0x00 = South, 0x02 = East, 0x02 = North, 0x03 = West

@export var experience: int = 0
@export var primary_skillset: int = 0
@export var reward_money: int = 0 # x100 for actual reward
@export var reward_item: int = 0
@export var unit_id: int = 0
@export var ai_target_x: int = 0
@export var ai_target_y: int = 0

@export var flags4: int = 0
@export var focus_unit: bool = false # 0x40 focused unit id stored in other variable
@export var stay_near_xy: bool = false # 0x20 position stored in other variables
@export var aggressive: bool = false # 0x10 position stored in other variables
@export var defensive: bool = false # 0x08 position stored in other variables

@export var target_unit_id: int = 0
@export var x25: int = 0
@export var flags5: int = 0
@export var conserve_ct: bool = false
@export var x27: int = 0

func _init(bytes: PackedByteArray) -> void:
	sprite_set_id = bytes.decode_u8(0)
	
	flags1 = bytes.decode_u8(1)
	gender = (flags1 & 0xe0) >> 5 # 4 = male, 2 = female, 1 = monster
	join_after_event = (flags1 & 0x10) == 0x10 # 0x10
	load_formation = (flags1 & 0x08) == 0x08 # 0x08 looks for unit id in roster to load stats, used for guests?
	hide_stats = (flags1 & 0x04) == 0x04 # 0x04 shows ??? instead of stat values
	flag1_02 = (flags1 & 0x02) # 0x02 unknown
	join_as_guest = (flags1 & 0x01) == 0x01 # 0x01
	
	name_idx = bytes.decode_u8(2)
	level = bytes.decode_u8(3)
	birthday_month = bytes.decode_u8(4)
	birthday_day = bytes.decode_u8(5)
	brave = bytes.decode_u8(6)
	faith = bytes.decode_u8(7)
	job_unlock = bytes.decode_u8(8)
	job_level = bytes.decode_u8(9)
	
	main_job = bytes.decode_u8(0xa)
	
	secondary_skillset = bytes.decode_u8(0xb)
	reaction = bytes.decode_u16(0xc)
	support = bytes.decode_u16(0xe)
	movement = bytes.decode_u16(0x10)
	
	equipment_head = bytes.decode_u8(0x12)
	equipment_body = bytes.decode_u8(0x13)
	equipment_accessory = bytes.decode_u8(0x14)
	equipment_right_hand = bytes.decode_u8(0x15)
	equipment_left_hand = bytes.decode_u8(0x16)
	
	palette = bytes.decode_u8(0x17)
	
	flags2 = bytes.decode_u8(0x18)
	always_present = (flags2 & 0x80) == 0x80 # always or randomly
	randomly_present = (flags2 & 0x40) == 0x40
	team_color_idx = (flags2 & 0x30) >> 4 # 0x30 => 0x00 = blue, 0x01 = red, 0x02 = green, 0x03 = light blue
	is_player_controlled = (flags2 & 0x08) == 0x08 # 0x08
	is_immortal = (flags2 & 0x04) == 0x04 # 0x04
	
	position_x = bytes.decode_u8(0x19)
	position_y = bytes.decode_u8(0x1a)
	
	flags3 = bytes.decode_u8(0x1b)
	upper_level = (flags3 & 0x80) >> 7 #0x80
	initial_direction = flags3 & 0x03 #0x00 = South, 0x01 = East, 0x02 = North, 0x03 = West
	
	experience = bytes.decode_u8(0x1c)
	primary_skillset = bytes.decode_u8(0x1d)
	reward_item = bytes.decode_u8(0x1e)
	reward_money = bytes.decode_u8(0x1f)
	unit_id = bytes.decode_u8(0x20)
	ai_target_x = bytes.decode_u8(0x21)
	ai_target_y = bytes.decode_u8(0x22)
	
	flags4 = bytes.decode_u8(0x23)
	focus_unit = (flags4 & 0x40) == 0x40 # 0x40 focused unit id stored in other variable
	stay_near_xy = (flags4 & 0x20) == 0x20 # 0x20 position stored in other variables
	aggressive = (flags4 & 0x10) == 0x10 # 0x10 position stored in other variables
	defensive = (flags4 & 0x08) == 0x08 # 0x08 position stored in other variables
	
	target_unit_id = bytes.decode_u8(0x24)
	x25 = bytes.decode_u8(0x25)
	flags5 = bytes.decode_u8(0x26)
	conserve_ct = (flags5 & 0x04) == 0x04
	x27 = bytes.decode_u8(0x27)


func get_unit_data() -> UnitData:
	var unit_data: UnitData = UnitData.new()

	# TODO get name based on special, male, female, or monster
	if name_idx != 0xFF:
		unit_data.display_name = RomReader.fft_text.unit_names_list[name_idx] 
	else:
		var new_name_idx: int = randi_range(0, RomReader.fft_text.unit_names_list_filtered.size() - 1)
		unit_data.display_name = RomReader.fft_text.unit_names_list_filtered[new_name_idx]

	if level <= 99:
		unit_data.level = level
	else: # TODO generate level based on party level
		unit_data.level = randi_range(0, 50)

	if gender == 4:
		unit_data.gender = Unit.Gender.MALE
	elif gender == 2:
		unit_data.gender = Unit.Gender.FEMALE
	elif gender == 1:
		unit_data.gender = Unit.Gender.MONSTER
	
	unit_data.zodiac = "zodiac" # TODO should zodiac be derived from birthday?
	unit_data.job_unique_name = RomReader.jobs_data.keys()[main_job]
	unit_data.team_idx = team_color_idx
	unit_data.controller = 1 if is_player_controlled else 0 # 0 = AI, 1 = Player 1, etc.
	
	var new_sprite_id: int = RomReader.jobs_data[unit_data.job_unique_name].sprite_id
	if sprite_set_id == 0x81:
		new_sprite_id += 1
	var new_sprite_file_name_idx: int = RomReader.spr_file_name_to_id.values().find(new_sprite_id)
	unit_data.spritesheeet_file_name = RomReader.spr_file_name_to_id.keys()[new_sprite_file_name_idx].to_lower().trim_suffix(".spr")
	unit_data.palette_id = palette
	if sprite_set_id < 0x80:
		unit_data.palette_id = 0
	if sprite_set_id == 0x82:
		unit_data.palette_id = RomReader.jobs_data.values()[main_job].monster_palette_id
	
	
	if initial_direction == 0:
		unit_data.facing_direction = Unit.Facings.SOUTH
	elif initial_direction == 1:
		unit_data.facing_direction = Unit.Facings.EAST
	elif initial_direction == 2:
		unit_data.facing_direction = Unit.Facings.NORTH
	elif initial_direction == 3:
		unit_data.facing_direction = Unit.Facings.WEST

	# job levels
	# jp per job
	# abilities learned

	# Stats
	unit_data.stats = {
		Unit.StatType.HP_MAX : StatValue.new(0, 999, 150),
		Unit.StatType.HP : StatValue.new(0, 150, 100),
		Unit.StatType.MP_MAX : StatValue.new(0, 999, 100),
		Unit.StatType.MP : StatValue.new(0, 100, 70),
		Unit.StatType.CT : StatValue.new(0, 999, 25),
		Unit.StatType.MOVE : StatValue.new(0, 100, 3),
		Unit.StatType.JUMP : StatValue.new(0, 100, 3),
		Unit.StatType.SPEED : StatValue.new(0, 100, 10),
		Unit.StatType.PHYSICAL_ATTACK : StatValue.new(0, 100, 11),
		Unit.StatType.MAGIC_ATTACK : StatValue.new(0, 100, 12),
		Unit.StatType.BRAVE : StatValue.new(0, 100, 70),
		Unit.StatType.FAITH : StatValue.new(0, 100, 65),
		Unit.StatType.EXP : StatValue.new(0, 999, 99),
		Unit.StatType.LEVEL : StatValue.new(0, 99, 20),
	}
	unit_data.stats_raw = {
		Unit.StatType.HP_MAX : 0.0, 
		Unit.StatType.MP_MAX : 0.0, 
		Unit.StatType.SPEED : 0.0, 
		Unit.StatType.PHYSICAL_ATTACK : 0.0, 
		Unit.StatType.MAGIC_ATTACK : 0.0, 
	}

	unit_data.stats[Unit.StatType.HP_MAX].value_changed.connect(unit_data.stats[Unit.StatType.HP].update_max_from_clamped_value)
	unit_data.stats[Unit.StatType.MP_MAX].value_changed.connect(unit_data.stats[Unit.StatType.MP].update_max_from_clamped_value)
	# TODO unit_data.stats[Unit.StatType.HP].value_changed.connect(hp_changed)
	# TODO connect stat bars?

	unit_data.stats[Unit.StatType.LEVEL].set_value(unit_data.level)
	Unit.generate_leveled_raw_stats(unit_data.gender as Unit.StatBasis, unit_data.level, RomReader.jobs_data[unit_data.job_unique_name], unit_data.stats_raw, true)
	var use_higher_stat_values: bool = false
	if ["RUKA.SEQ", "KANZEN.SEQ", "ARUTE.SEQ"].has(unit_data.spritesheeet_file_name): # lucavi
		use_higher_stat_values = true
	Unit.calc_battle_stats(RomReader.jobs_data.values()[main_job], unit_data.stats_raw, unit_data.stats, true, use_higher_stat_values)

	unit_data.stats[Unit.StatType.BRAVE].set_value(brave)
	unit_data.stats[Unit.StatType.FAITH].set_value(faith)

	# equipment
	unit_data.equip_slots = [
		EquipmentSlot.new("RH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
		EquipmentSlot.new("LH", [ItemData.SlotType.WEAPON, ItemData.SlotType.SHIELD]),
		EquipmentSlot.new("Head", [ItemData.SlotType.HEADGEAR]),
		EquipmentSlot.new("Body", [ItemData.SlotType.ARMOR]),
		EquipmentSlot.new("Accesory", [ItemData.SlotType.ACCESSORY]),
	]

	# TODO if equipment value == 0xFE, get random leveled equipment
	unit_data.equip_slots[0].item_unique_name = get_item_name(unit_data, 0, equipment_right_hand)
	unit_data.equip_slots[1].item_unique_name = get_item_name(unit_data, 1, equipment_left_hand)
	unit_data.equip_slots[2].item_unique_name = get_item_name(unit_data, 2, equipment_head)
	unit_data.equip_slots[3].item_unique_name = get_item_name(unit_data, 3, equipment_body)
	unit_data.equip_slots[4].item_unique_name = get_item_name(unit_data, 4, equipment_accessory)

	# abilities
	unit_data.ability_slots = [
		AbilitySlot.new("Skillset 1", [Ability.SlotType.SKILLSET]),
		AbilitySlot.new("Skillset 2", [Ability.SlotType.SKILLSET]),
		AbilitySlot.new("Reaction", [Ability.SlotType.REACTION]),
		AbilitySlot.new("Support", [Ability.SlotType.SUPPORT]),
		AbilitySlot.new("Movement", [Ability.SlotType.MOVEMENT]),
	]

	# TODO if ability value == 0x01FE, get random leveled equipment
	# TODO create skillset abilities, set random if secondary_skillset == 0xFE
	# if primary_skillset == 0xFF, ability_slots[0] set by main job
	# unit_data.ability_slots[1] 
	unit_data.ability_slots[2].ability_unique_name = get_ability_name(unit_data, 2, reaction)
	unit_data.ability_slots[3].ability_unique_name = get_ability_name(unit_data, 3, support)
	unit_data.ability_slots[4].ability_unique_name = get_ability_name(unit_data, 4, movement)

	# position
	# TODO account for map being shifted or mirrored?
	unit_data.tile_position = Vector3i(position_x, upper_level, position_y)

	return unit_data


func get_item_name(unit_data: UnitData, slot_idx: int, new_item_idx: int) -> String:
	if new_item_idx < 0xFE:
		return RomReader.items_array[new_item_idx].unique_name
	elif new_item_idx == 0xFF:
		return RomReader.items_array[0].unique_name
	
	# TODO if equipment value == 0xFE, get random leveled equipment
	var filtered_items: Array[ItemData] = []
	filtered_items.assign(RomReader.items_array.filter(func(item: ItemData) -> bool: return unit_data.equip_slots[slot_idx].slot_types.has(item.slot_type)))
	var rand_item_idx: int = randi_range(0, filtered_items.size() - 1)
	return filtered_items[rand_item_idx].unique_name


func get_ability_name(unit_data: UnitData, slot_idx: int, new_ability_idx: int) -> String:
	if new_ability_idx < 0x01FE:
		return RomReader.abilities.values()[new_ability_idx].unique_name
	elif new_ability_idx == 0xFF:
		return RomReader.abilities.values()[0].unique_name
	
	# TODO if ability value == 0x01FE, get random learned ability?
	var filtered_abilities: Array[Ability] = []
	filtered_abilities.assign(RomReader.abilities.values().filter(func(ability: Ability) -> bool: return unit_data.ability_slots[slot_idx].slot_types.has(ability.slot_type)))
	var rand_ability_idx: int = randi_range(0, filtered_abilities.size() - 1)
	return filtered_abilities[rand_ability_idx].unique_name
