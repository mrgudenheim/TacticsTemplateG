class_name FftJobImporter
extends RefCounted


static func create_from_rom(
	new_job_id: int,
	job_bytes: PackedByteArray,
	rom_reader: RomReader
) -> JobData:
	var job_data: JobData = JobData.new()
	if new_job_id == -1 or job_bytes.is_empty():
		return job_data

	job_data.job_id = new_job_id
	if job_data.job_id < 155:
		job_data.display_name = rom_reader.fft_text.job_names[job_data.job_id]
		job_data.description = rom_reader.fft_text.job_desriptions[job_data.job_id]
	job_data.skillset_id = job_bytes.decode_u8(0)
	job_data.monster_portrait_id = job_bytes.decode_u8(0x2d)
	job_data.monster_palette_id = job_bytes.decode_u8(0x2e)
	job_data.monster_type = job_bytes.decode_u8(0x2f)

	if job_data.job_id < 0x4a: # special units and monsters
		job_data.sprite_id = job_data.job_id
	elif job_data.job_id >= 0x4a and job_data.job_id < 0x5e: # generic humans
		job_data.sprite_id = 0x60 + ((job_data.job_id - 0x4a) * 2) # +1 for female sprite
		if job_data.job_id == 0x5c: # dancer is only 1 above bard since there is no female bard
			job_data.sprite_id = 0x83
		if job_data.job_id == 0x5d: # mime is only 1 above dancer since there is no male dancer
			job_data.sprite_id = 0x84
		job_data.default_palette_idx = -1
	elif job_data.job_id >= 0x5e: # generic and special monsters
		job_data.sprite_id = job_data.monster_portrait_id
		if job_data.monster_type != 0:
			job_data.default_palette_idx = job_data.monster_palette_id

	for innate_slot: int in 4:
		var innate_id: int = job_bytes.decode_u16(0x01 + (2 * innate_slot))
		if innate_id != 0:
			job_data.innate_abilities_ids.append(innate_id)

	# equippable item types
	var equipable_bytes: PackedByteArray = job_bytes.slice(0x09, 0x0d)
	for byte_idx: int in equipable_bytes.size():
		var equipable_byte: int = equipable_bytes.decode_u8(byte_idx)
		for bit_idx: int in 8:
			var reverse_idx: int = 7 - bit_idx
			if (equipable_byte & (1 << reverse_idx)) != 0:
				job_data.equippable_item_types.append(((byte_idx * 8) + bit_idx) as ItemData.ItemType)

	job_data.hp_growth = job_bytes.decode_u8(0x0d)
	job_data.mp_growth = job_bytes.decode_u8(0x0f)
	job_data.speed_growth = job_bytes.decode_u8(0x11)
	job_data.pa_growth = job_bytes.decode_u8(0x13)
	job_data.ma_growth = job_bytes.decode_u8(0x15)

	job_data.hp_multiplier = job_bytes.decode_u8(0x0e)
	job_data.mp_multiplier = job_bytes.decode_u8(0x10)
	job_data.speed_multiplier = job_bytes.decode_u8(0x12)
	job_data.pa_multiplier = job_bytes.decode_u8(0x14)
	job_data.ma_multiplier = job_bytes.decode_u8(0x16)

	job_data.move = job_bytes.decode_u8(0x17)
	job_data.jump = job_bytes.decode_u8(0x18) & 127
	job_data.can_be_walked_on = (job_bytes.decode_u8(0x18) & 128) != 0
	job_data.evade_physical = job_bytes.decode_u8(0x19)
	job_data.evade_datas.append(EvadeData.new(job_data.evade_physical, EvadeData.EvadeSource.JOB, EvadeData.EvadeType.PHYSICAL))

	job_data.passive_effect_names.append("standard_move")
	job_data.passive_effect_names.append("standard_evade")

	var status_effects: Array[StatusEffect] = rom_reader.scus_data.status_effects
	var new_passive_effect: PassiveEffect = PassiveEffect.new()
	new_passive_effect.status_always = FftStatusImporter.decode_status_id_array(job_bytes.slice(0x1a, 0x1f), status_effects)
	new_passive_effect.status_immune = FftStatusImporter.decode_status_id_array(job_bytes.slice(0x1f, 0x24), status_effects)
	new_passive_effect.status_start = FftStatusImporter.decode_status_id_array(job_bytes.slice(0x24, 0x29), status_effects)

	new_passive_effect.element_absorb = Action.get_element_types_array([job_bytes.decode_u8(0x29)])
	new_passive_effect.element_cancel = Action.get_element_types_array([job_bytes.decode_u8(0x2a)])
	new_passive_effect.element_half = Action.get_element_types_array([job_bytes.decode_u8(0x2b)])
	new_passive_effect.element_weakness = Action.get_element_types_array([job_bytes.decode_u8(0x2c)])
	new_passive_effect.added_equipment_types_equipable = job_data.equippable_item_types

	FftRegistryHelper.register_unique(rom_reader.jobs_data, job_data, job_data.display_name, "JobData")

	new_passive_effect.unique_name = job_data.unique_name
	FftRegistryHelper.register_unique(rom_reader.passive_effects, new_passive_effect, "", "PassiveEffect")
	job_data.passive_effect_names.append(new_passive_effect.unique_name)

	return job_data
