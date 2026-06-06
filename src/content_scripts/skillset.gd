class_name Skillset
extends Resource

@export var unique_name: String = "[skillset unique name]"
@export var display_name: String = "[Skillset display Name]"
@export var description: String = "[skillset description]"
@export var ability_names: PackedStringArray = []

var action_ability_ids: PackedInt32Array = []
var rsm_ability_ids: PackedInt32Array = []
