# https://ffhacktics.com/wiki/Status_Effects
# https://ffhacktics.com/wiki/Status_Check_table_-_0x800662d0
class_name StatusEffect
extends Resource

const SAVE_DIRECTORY_PATH: String = "user://overrides/status_effects/"
const FILE_SUFFIX: String = "status_effect"
@export var unique_name: String = "unique_name"

@export var status_id: int = 0
@export var status_effect_name: String = "Status effect name"
@export var description: String = "Status effect description"

var byte_00: int = 0
var byte_01: int = 0
@export var order: int = 0
@export var duration: int = 10
@export_flags("Freeze CT", "(Crystal/Treasure)", "(Defend/Perform)", "(Poison/Regen)", "(Confusion/Transparent/Charm/Sleep)", "(Checks 3)", "(Checks 2)", "Counts as KO") var checks_01: int = 0
@export_flags("Cant React", "Unknown", "Ignore Attcks", "(Checks 10)", "(Checks 9)", "(Checks 8)", "(Checks 7 - Cancelled by Immortal?)", "(Checks 6)") var checks_02: int = 0
var status_cancels_flags: PackedByteArray = [] # 5 bytes of bitflags for up to 40 statuses 
@export var status_cant_stack_flags: PackedByteArray = [] # 5 bytes of bitflags for up to 40 statuses

@export var status_cancels: PackedStringArray = [] 
@export var status_cant_stack: PackedStringArray = [] # TODO use bit index as index into StatusEffect array

enum DurationType {
	TICKS,
	TURNS, # death sentance, dead -> crystal/treasure
	INDEFINITE,
	PERMANENT,
}
@export var duration_type: DurationType = DurationType.TICKS
@export var action_on_turn_start: String = "" # Action.unique_name;
@export var action_on_turn_end: String = "" # Action.unique_name;
@export var action_on_x_ticks: String = "" # Action.unique_name; performing
@export var x_ticks: int = -1
@export var action_on_apply: String = "" # Action.unique_name; dead sets current_hp = 0
# @export var action_on_complete: int = -1 # dead -> crystal/treasure, death sentence, charging?
@export var action_on_complete: String = "" # Action.unique_name; dead -> crystal/treasure, death sentence, charging?
var delayed_action: ActionInstance # charging
@export var num_allowed: int = 1
@export var removed_on_damaged: bool = false # TODO should these statuses instead be included in actions remove_status list? ex. sleep
@export var ai_score_formula: FormulaData = FormulaData.new(FormulaData.Formulas.TARGET_CURRENT_HP_X_V1)

# var visual_effect # TODO icons, sprite coloring, spritesheet, animation (haste, dead, etc.), float, etc.

@export var spritesheet_file_name: String = ""
@export var palette_idx_offset: int = 0
@export var other_type_index: int = 0 # 0 = chicken/chest, 1 = frog, 2 = crystal

@export var shading_color: Color
@export var shading_type: int
@export var modulation_color: Color = Color.BLACK
#@export var status_bubble_texture: Texture2D # from Frame.bin

@export var icon_rects: Array[Rect2i] = []
@export var num_icon_frames: int = 1
@export var duration_icons: Array[Rect2i] = RomReader.battle_bin_data.status_counter_rects

@export var idle_animation_id: int = -1

@export var passive_effect_name: String = ""
var passive_effect: PassiveEffect = PassiveEffect.new()


var counts_as_ko: bool = false:
	get:
		counts_as_ko = checks_01 & 0x01 == 0x01
		return counts_as_ko
var freezes_ct: bool = false:
	get:
		freezes_ct = checks_01 & 0x80 == 0x80
		return freezes_ct


func set_data(status_effect_bytes: PackedByteArray) -> void:
	byte_00 = status_effect_bytes.decode_u8(0)
	byte_01 = status_effect_bytes.decode_u8(1)
	order = status_effect_bytes.decode_u8(2)
	duration = status_effect_bytes.decode_u8(3)
	checks_01 = status_effect_bytes.decode_u8(4)
	checks_02 = status_effect_bytes.decode_u8(5)
	status_cancels_flags = status_effect_bytes.slice(6, 11)
	status_cant_stack_flags = status_effect_bytes.slice(11, 16)
	removed_on_damaged = checks_01 & 0x08 == 0x08 # confusion, transparent, charm, sleep, TODO is this really what this flag does?
	
	if duration == 0:
		duration_type = DurationType.INDEFINITE


func get_icon_rect() -> Rect2i:
	if duration_type == DurationType.TURNS:
		if duration >= duration_icons.size() - 1:
			return duration_icons[-1]
		else:
			return duration_icons[duration]
	elif not icon_rects.is_empty():
		return icon_rects[0]
	else:
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)


# called after all StatusEffects have already been initialized since this indexes into the complete array
func status_flags_to_status_array() -> void:
	status_cancels = get_status_id_array(status_cancels_flags)
	status_cant_stack = get_status_id_array(status_cant_stack_flags)


static func get_status_id_array(status_bitflags: PackedByteArray) -> PackedStringArray:
	var status_array: PackedStringArray = []
	
	#if RomReader.status_effects.is_empty():
		#push_warning("Trying to get StatusEffects before they are loaded")
		#return status_array
	
	for byte_idx: int in status_bitflags.size():
		for bit_idx: int in range(7, -1, -1):
			var byte: int = status_bitflags.decode_u8(byte_idx)
			if byte & (2 ** bit_idx) != 0:
				var status_index: int = (7 - bit_idx) + (byte_idx * 8)
				#status_array.append(RomReader.scus_data.status_effects[status_index])
				status_array.append(RomReader.scus_data.status_effects[status_index].unique_name)
	
	return status_array


func get_ai_score(user: Unit, target: Unit, remove: bool = false) -> float:
	var score: float = 0.0
	if not remove and target.immune_statuses.has(unique_name):
		return 0.0
	
	var current_statuses: Array[StatusEffect] = target.current_statuses.filter(func(status: StatusEffect) -> bool: return status.unique_name == unique_name)
	if remove and current_statuses.all(func(status: StatusEffect) -> bool: return status.duration_type != StatusEffect.DurationType.PERMANENT):
		return 0.0
	
	score = ai_score_formula.get_base_value(user, target)
	if target.team == user.team:
		score = -score
	
	if not remove and current_statuses.size() >= num_allowed: # re-applying existing status
		if current_statuses.all(func(status: StatusEffect) -> bool: return status.duration_type == StatusEffect.DurationType.PERMANENT):
			return 0.0
		
		var ticking_statuses: Array[StatusEffect] = current_statuses.filter(func(status: StatusEffect) -> bool: return status.duration_type == StatusEffect.DurationType.TICKS)
		if not ticking_statuses.is_empty():
			score = score * ticking_statuses[0].duration * duration
	
	return score


func add_to_global_list(will_overwrite: bool = false) -> void:
	if ["", "unique_name"].has(unique_name):
		unique_name = status_effect_name.to_snake_case()
	
	if RomReader.status_effects.keys().has(unique_name) and will_overwrite:
		push_warning("Overwriting existing status effect: " + unique_name)
	elif RomReader.status_effects.keys().has(unique_name) and not will_overwrite:
		var num: int = 2
		var formatted_num: String = "%02d" % num
		var new_unique_name: String = unique_name + "_" + formatted_num
		while RomReader.status_effects.keys().has(new_unique_name):
			num += 1
			formatted_num = "%02d" % num
			new_unique_name = unique_name + "_" + formatted_num
		
		push_warning("StatusEffect list already contains: " + unique_name + ". Incrementing unique_name to: " + new_unique_name)
		unique_name = new_unique_name
	
	RomReader.status_effects[unique_name] = self


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


static func create_from_json(json_string: String) -> StatusEffect:
	var property_dict: Dictionary = JSON.parse_string(json_string)
	var new_status_effect: StatusEffect = create_from_dictionary(property_dict)
	
	return new_status_effect


static func create_from_dictionary(property_dict: Dictionary) -> StatusEffect:
	var new_status_effect: StatusEffect = StatusEffect.new()
	for property_name: String in property_dict.keys():
		if property_name.contains("color"):
			var new_color: Color = Color.BLACK
			var color_rgb_array: Array = property_dict[property_name]
			new_color.r = color_rgb_array[0]
			new_color.g = color_rgb_array[1]
			new_color.b = color_rgb_array[2]
			new_color.a = color_rgb_array[3]

			new_status_effect.set(property_name, new_color)
		elif property_name == "duration_type":
			new_status_effect.duration_type = DurationType[property_dict[property_name]]
		else:
			new_status_effect.set(property_name, property_dict[property_name])

	new_status_effect.emit_changed()
	return new_status_effect


#Status Set 1
#0x80 - 0 
#0x40 - 1 Crystal
#0x20 - 2 Dead
#0x10 - 3 Undead
#0x08 - 4 Charging
#0x04 - 5 Jump
#0x02 - 6 Defending
#0x01 - 7 Performing
#Status Set 2
#0x80 - 8 Petrify
#0x40 - 9 Invite
#0x20 - 10 Darkness
#0x10 - 11 Confusion
#0x08 - 12 Silence
#0x04 - 13 Blood Suck
#0x02 - 14 Cursed
#0x01 - 15 Treasure
#Status Set 3
#0x80 - 16 Oil
#0x40 - 17 Float
#0x20 - 18 Reraise
#0x10 - 19 Transparent
#0x08 - 20 Berserk
#0x04 - 21 Chicken
#0x02 - 22 Frog
#0x01 - 23 Critical
#Status Set 4
#0x80 - 24 Poison
#0x40 - 25 Regen
#0x20 - 26 Protect
#0x10 - 27 Shell
#0x08 - 28 Haste
#0x04 - 29 Slow
#0x02 - 30 Stop
#0x01 - 31 Wall
#Status Set 5
#0x80 - 32 Faith
#0x40 - 33 Innocent
#0x20 - 34 Charm
#0x10 - 35 Sleep
#0x08 - 36 Don't Move
#0x04 - 37 Don't Act
#0x02 - 38 Reflect
#0x01 - 39 Death Sentence
