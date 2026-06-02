class_name JobData
extends Resource

const SAVE_FOLDER: String = "jobs"
const FILE_SUFFIX: String = "job"
@export var unique_name: String = "unique_name" # "ATTACK" and "COPY" are special cases

# Job Data # 800610b8 in RAM
@export var job_id: int = 0
@export var display_name: String = "Job Name"
@export var description: String = "[job description]"
@export var skillset_id: int = 0
@export var skillset_unique_name: String = "[skillset unique name]"
@export var innate_abilities_ids: PackedInt32Array = []
@export var innate_ability_names: PackedStringArray = []
var innate_abilities: Array[Ability] = []
@export var equippable_item_types: Array[ItemData.ItemType] # 4 bytes of bitflags, 32 total
@export var hp_growth: int = 1
@export var mp_growth: int = 1
@export var speed_growth: int = 1
@export var pa_growth: int = 1
@export var ma_growth: int = 1

@export var hp_multiplier: int = 1
@export var mp_multiplier: int = 1
@export var speed_multiplier: int = 1
@export var pa_multiplier: int = 1
@export var ma_multiplier: int = 1

@export var move: int = 3
@export var jump: int = 3
@export var can_be_walked_on: bool = false
@export var evade_physical: int = 0
@export var evade_datas: Array[EvadeData] = []

@export var passive_effect_names: PackedStringArray = []
var passive_effects: Array[PassiveEffect] = [] # TODO job_data move stat modifiers, innate abilities to passive_effects

@export var monster_portrait_id: int = 0
@export var monster_palette_id: int = 0
@export var monster_type: int = 0 # monster type sprite? sprite_id = 0x85 + this
var sprite_id: int = 0
@export var sprite_name: String = ""
@export var default_palette_idx: int = 0 # -1 means to use the team idx


func _init(new_job_id: int = -1, job_bytes: PackedByteArray = []) -> void:
	if new_job_id == -1 or job_bytes.is_empty():
		#push_warning("creating empty job data")
		return
	
	job_id = new_job_id
	if job_id < 155:
		display_name = RomReader.fft_text.job_names[job_id]
		description = RomReader.fft_text.job_desriptions[job_id]
	skillset_id = job_bytes.decode_u8(0)
	monster_portrait_id = job_bytes.decode_u8(0x2d)
	monster_palette_id = job_bytes.decode_u8(0x2e)
	monster_type = job_bytes.decode_u8(0x2f)
	
	if job_id < 0x4a: # special units and monsters
		sprite_id = job_id
	elif job_id >= 0x4a and job_id < 0x5e: # generic humans
		sprite_id = 0x60 + ((job_id - 0x4a) * 2) # +1 for female sprite
		if job_id == 0x5c: # dancer is only 1 above bard since there is no female bard
			sprite_id = 0x83
		if job_id == 0x5d: # mime is only 1 above dancer since there is no male dancer
			sprite_id = 0x84
		default_palette_idx = -1
	elif job_id >= 0x5e: # generic and special monsters
		sprite_id = monster_portrait_id
		if monster_type != 0:
			default_palette_idx = monster_palette_id
	
	for innate_slot: int in 4:
		var innate_id: int = job_bytes.decode_u16(0x01 + (2 * innate_slot))
		if innate_id != 0:
			innate_abilities_ids.append(innate_id)
	
	# equippable item types
	var equipable_bytes: PackedByteArray = job_bytes.slice(0x09, 0x0d)
	for byte_idx: int in equipable_bytes.size():
		var equipable_byte: int = equipable_bytes.decode_u8(byte_idx)
		for bit_idx: int in 8:
			var reverse_idx: int = 7 - bit_idx
			if equipable_byte & (2 ** reverse_idx) == (2 ** reverse_idx):
				equippable_item_types.append((byte_idx * 8) + bit_idx)
	
	hp_growth = job_bytes.decode_u8(0x0d)
	mp_growth = job_bytes.decode_u8(0x0f)
	speed_growth = job_bytes.decode_u8(0x11)
	pa_growth = job_bytes.decode_u8(0x13)
	ma_growth = job_bytes.decode_u8(0x15)

	hp_multiplier = job_bytes.decode_u8(0x0e)
	mp_multiplier = job_bytes.decode_u8(0x10)
	speed_multiplier = job_bytes.decode_u8(0x12)
	pa_multiplier = job_bytes.decode_u8(0x14)
	ma_multiplier = job_bytes.decode_u8(0x16)
	
	move = job_bytes.decode_u8(0x17)
	jump = job_bytes.decode_u8(0x18) & 127
	can_be_walked_on = job_bytes.decode_u8(0x18) & 128
	evade_physical = job_bytes.decode_u8(0x19)
	evade_datas.append(EvadeData.new(evade_physical, EvadeData.EvadeSource.JOB, EvadeData.EvadeType.PHYSICAL))
	
	passive_effect_names.append("standard_move")
	passive_effect_names.append("standard_evade")

	var new_passive_effect: PassiveEffect = PassiveEffect.new()
	new_passive_effect.status_always = StatusEffect.get_status_id_array(job_bytes.slice(0x1a, 0x1f))
	new_passive_effect.status_immune = StatusEffect.get_status_id_array(job_bytes.slice(0x1f, 0x24))
	new_passive_effect.status_start = StatusEffect.get_status_id_array(job_bytes.slice(0x24, 0x29))
	
	new_passive_effect.element_absorb = Action.get_element_types_array([job_bytes.decode_u8(0x29)])
	new_passive_effect.element_cancel = Action.get_element_types_array([job_bytes.decode_u8(0x2a)])
	new_passive_effect.element_half = Action.get_element_types_array([job_bytes.decode_u8(0x2b)])
	new_passive_effect.element_weakness = Action.get_element_types_array([job_bytes.decode_u8(0x2c)])
	# ROM job data does not have any element_strengthen
	# new_passive_effect.element_strengthen = Action.get_element_types_array([job_bytes.decode_u8(___)])

	new_passive_effect.added_equipment_types_equipable = equippable_item_types
	
	add_to_global_list()
	
	new_passive_effect.unique_name = unique_name
	new_passive_effect.add_to_global_list()
	passive_effect_names.append(new_passive_effect.unique_name)


func get_passive_effects() -> Array[PassiveEffect]:
	if passive_effects.is_empty():
		for name: String in passive_effect_names:
			passive_effects.append(GameData.passive_effects[name])
	return passive_effects


func add_to_global_list(will_overwrite: bool = false) -> void:
	if ["", "unique_name"].has(unique_name):
		unique_name = display_name.to_snake_case()
	
	if RomReader.jobs_data.keys().has(unique_name) and will_overwrite:
		push_warning("Overwriting existing JobData: " + unique_name)
	elif RomReader.jobs_data.keys().has(unique_name) and not will_overwrite:
		var num: int = 2
		var formatted_num: String = "%02d" % num
		var new_unique_name: String = unique_name + "_" + formatted_num
		while RomReader.jobs_data.keys().has(new_unique_name):
			num += 1
			formatted_num = "%02d" % num
			new_unique_name = unique_name + "_" + formatted_num
		
		push_warning("JobData list already contains: " + unique_name + ". Incrementing unique_name to: " + new_unique_name)
		unique_name = new_unique_name
	
	# passive_effect_names = unique_name
	# passive_effects.unique_name = unique_name
	RomReader.jobs_data[unique_name] = self


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


static func create_from_json(json_string: String) -> JobData:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_job_data: JobData = create_from_dictonary(property_dict)
	
	return new_job_data


static func create_from_dictonary(property_dict: Dictionary) -> JobData:
	var new_job_data: JobData = JobData.new()
	for property_name: String in property_dict.keys():
		if property_name == "equippable_item_types":
			var array = property_dict[property_name]
			var new_equipable_item_types: Array[ItemData.ItemType] = []
			for type in array:
				new_equipable_item_types.append(ItemData.ItemType[type])
			new_job_data.set(property_name, new_equipable_item_types)
		elif property_name == "evade_datas":
			var new_evade_datas: Array[EvadeData] = []
			var new_evade_datas_array: Array = property_dict[property_name]
			for evade_data_dictionary: Dictionary in new_evade_datas_array:
				var new_evade_data: EvadeData = EvadeData.create_from_dictionary(evade_data_dictionary)
				new_evade_datas.append(new_evade_data)
			new_job_data.set(property_name, new_evade_datas)
		else:
			new_job_data.set(property_name, property_dict[property_name])

	new_job_data.emit_changed()
	return new_job_data
