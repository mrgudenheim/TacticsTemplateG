class_name Skillset
extends Resource

const SAVE_FOLDER: String = "skillsets/"
const FILE_SUFFIX: String = ".skillset.tres"

@export var unique_name: String = "[skillset unique name]"
@export var display_name: String = "[Skillset display Name]"
@export var description: String = "[skillset description]"
@export var ability_names: PackedStringArray = []

var action_ability_ids: PackedInt32Array = []
var rsm_ability_ids: PackedInt32Array = []
