class_name JobData
extends Resource

const SAVE_FOLDER: String = "jobs/"
const FILE_SUFFIX: String = ".job.tres"
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
@export var default_palette_idx: int = 0 # -1 means to use the team idx; TODO should this be defined in UnitSpritesheetData instead of JobData?


func get_passive_effects() -> Array[PassiveEffect]:
	if passive_effects.is_empty():
		for passive_name: String in passive_effect_names:
			passive_effects.append(GameData.get_passive_effect(passive_name))
	return passive_effects
