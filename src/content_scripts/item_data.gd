class_name ItemData
extends Resource

# https://ffhacktics.com/wiki/Item_Data

const SAVE_FOLDER: String = "items/"
const FILE_SUFFIX: String = ".item.tres"

@export var unique_name: String = "unique_name"
@export var display_name: String = "Item display_name"
@export var description: String = "[item description]"
@export var item_idx: int = 0
@export var item_graphic_id: int = 0
@export var item_palette_id: int = 0
@export var min_level: int = 0
@export var slot_type: SlotType = SlotType.NONE
@export var is_rare: bool = false
@export var item_type: ItemType = ItemType.FISTS
var item_attribute_id: int = 0 # https://ffhacktics.com/wiki/Item_Attribute stat modifiers, always/start/immune statuses, elemental interaction
@export var price: int = 100
@export var shop_availability_start: int = 0

@export var wep_frame_v_offset: int = 0
@export var wep_frame_palette: int = 0
@export var wep_eff_palette: int = 0

# weapon data
# ROM data for debug mostly, equivalent data is stored in weapon_attack_action
var max_range: int = 1
var weapon_formula_id: int = 1
@export var weapon_power: int = 1
var weapon_evade: int = 0
var weapon_element: Action.ElementTypes = Action.ElementTypes.NONE
var weapon_inflict_status_spell_id: int = 0
var weapon_is_striking: bool = true
var weapon_is_lunging: bool = false
var weapon_is_direct: bool = false
var weapon_is_arc: bool = false
#@export var weapon_targeting_strategy: TargetingStrategy

@export var equipped_action_names: PackedStringArray = []
@export var weapon_attack_action_name: String = ""
var weapon_attack_action: Action
@export var is_dual_wieldable: bool = false
@export var is_two_handable: bool = false
@export var is_throwable: bool = false
@export var takes_both_hands: bool = false

#@export var weapon_add_status_chance: int = 100
#@export var weapon_add_statuses: Array[StatusEffect] = []
#@export var weapon_other_effect_chance: int = 100
#@export var weapon_other_effects: Array = [] # TODO create data structure for other effects

# shield data
var shield_physical_evade: int = 0
var shield_magical_evade: int = 0

# accessory data
var accessory_physical_evade: int = 0
var accessory_magical_evade: int = 0

# armour/helm data
var hp_modifier: int = 0
var mp_modifier: int = 0

# attribute data
var pa_modifier: int = 0
var ma_modifier: int = 0
var sp_modifier: int = 0
var move_modifier: int = 0
var jump_modifier: int = 0

# chemist item data
var consumable_formula_id: int = 0
var consumable_item_z: int = 0
var consumable_inflict_status_id: int = 0

#@export var actions_granted: Array[Action] = []

@export var evade_datas: Array[EvadeData] = []

@export var passive_effect_name: String = ""
var passive_effect: PassiveEffect

enum SlotType {
	WEAPON = 0x80,
	SHIELD = 0x40,
	HEADGEAR = 0x20,
	ARMOR = 0x10,
	ACCESSORY = 0x08,
	NONE = 0x04,
}

enum ItemType {
	FISTS = 0,
	KNIFE = 1,
	NINJA_BLADE = 2,
	SWORD = 3,
	KNIGHT_SWORD = 4,
	KATANA = 5,
	AXE = 6,
	ROD = 7,
	STAFF = 8,
	FLAIL = 9,
	GUN = 10,
	CROSSBOW = 11,
	BOW = 12,
	INSTRUMENT = 13,
	BOOK = 14,
	SPEAR = 15,
	POLE = 16,
	BAG = 17,
	CLOTH = 18,
	SHIELD = 19,
	HELMET = 20,
	HAT = 21,
	HAIR_ADORNMENT = 22,
	ARMOR = 23,
	CLOTHING = 24,
	ROBE = 25,
	SHOES = 26,
	ARMGUARD = 27,
	RING = 28,
	ARMLET = 29,
	CLOAK = 30,
	PERFUME = 31,
	SHURIKEN = 32,
	BALL = 33,
	CONSUMABLE_ITEM = 34,
}


func get_equipped_actions() -> Array[Action]:
	var action_list: Array[Action] = []
	for action_name: String in equipped_action_names:
		action_list.append(GameData.get_action(action_name))

	return action_list


func get_passive_effect() -> PassiveEffect:
	return GameData.get_passive_effect(passive_effect_name)
