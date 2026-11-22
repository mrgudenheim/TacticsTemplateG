class_name Ability
extends Resource

enum SlotType {
	# SKILLSET,
	REACTION,
	SUPPORT,
	MOVEMENT,
	ACTION,
}

const SAVE_FOLDER: String = "abilities/"
const FILE_SUFFIX: String = ".ability.tres"

@export var unique_name: String = "unique_name"
@export var display_name: String = "[Ability Name]"
@export var slot_type: SlotType = SlotType.ACTION
@export var description: String = "[ability description]"

@export var jp_cost: int = 0
@export var chance_to_learn: float = 100 # percent
@export var learn_with_jp: bool = true
@export var display_ability_name: bool = true
@export var learn_on_hit: bool = false

@export var passive_effect_name: String = ""
var passive_effect: PassiveEffect = PassiveEffect.new()

@export var triggered_actions_names: PackedStringArray = []
var triggered_actions: Array[TriggeredAction] = []


func get_passive_effect() -> PassiveEffect:
	return GameData.get_passive_effect(passive_effect_name)
