class_name JobSelectButton
extends PanelContainer

signal selected(job_data: JobData)

var job_data: JobData:
	get: return job_data
	set(value):
		job_data = value
		update_ui(value)

@export var button: Button
@export var display_name: Label
@export var sprite_rect: TextureRect
@export var sprite_rect_on_screen_notifier: VisibleOnScreenNotifier2D
@export var move: Label
@export var jump: Label

# @export var stat_multipleirs_growth_grid: Container

@export var hp_multiplier: Label
@export var mp_multiplier: Label
@export var speed_multiplier: Label
@export var pa_multiplier: Label
@export var ma_multiplier: Label

@export var hp_growth: Label
@export var mp_growth: Label
@export var speed_growth: Label
@export var pa_growth: Label
@export var ma_growth: Label

@export var equipment_hand: Label
@export var equipment_head: Label
@export var equipment_body: Label
@export var equipment_accessory: Label

@export var evade_grid: Container

@export var innate_abilities_list: Container

@export var statuses_always_list: Container
@export var statuses_start_list: Container
@export var statuses_immune_list: Container

@export var element_weak: Label
@export var element_resist: Label
@export var element_immune: Label
@export var element_absorb: Label
@export var element_strengthen: Label

@export var action_list: Container

func _ready() -> void:
	button.pressed.connect(on_selected)
	sprite_rect_on_screen_notifier.screen_entered.connect(set_sprite)


func on_selected() -> void:
	selected.emit(job_data)


func update_ui(new_job_data: JobData) -> void:
	display_name.text = new_job_data.display_name + " (Job ID: " + str(new_job_data.job_id) + ")"
	name = new_job_data.unique_name

	# update stats
	move.text = "Move: " + str(new_job_data.move)
	jump.text = "Jump: " + str(new_job_data.jump)

	hp_multiplier.text = str(new_job_data.hp_multiplier)
	mp_multiplier.text = str(new_job_data.mp_multiplier)
	speed_multiplier.text = str(new_job_data.speed_multiplier)
	pa_multiplier.text = str(new_job_data.pa_multiplier)
	ma_multiplier.text = str(new_job_data.ma_multiplier)

	hp_growth.text = str(new_job_data.hp_growth)
	mp_growth.text = str(new_job_data.mp_growth)
	speed_growth.text = str(new_job_data.speed_growth)
	pa_growth.text = str(new_job_data.pa_growth)
	ma_growth.text = str(new_job_data.ma_growth)

	# TODO update equippable types
	var hand_types: PackedInt32Array = range(1,20)
	var head_types: PackedInt32Array = range(20,23)
	var body_types: PackedInt32Array = range(23,26)
	var accessory_types: PackedInt32Array = range(26,32)

	var equipable_hand_types: PackedStringArray = get_slot_item_type_names(new_job_data.equippable_item_types, hand_types)
	var equipable_head_types: PackedStringArray = get_slot_item_type_names(new_job_data.equippable_item_types, head_types)
	var equipable_body_types: PackedStringArray = get_slot_item_type_names(new_job_data.equippable_item_types, body_types)
	var equipable_accessory_types: PackedStringArray = get_slot_item_type_names(new_job_data.equippable_item_types, accessory_types)
	
	equipment_hand.text = ", ".join(equipable_hand_types)
	equipment_head.text = ", ".join(equipable_head_types)
	equipment_body.text = ", ".join(equipable_body_types)
	equipment_accessory.text = ", ".join(equipable_accessory_types)

	# update evade
	for evade_type: EvadeData.EvadeType in EvadeData.EvadeType.values():
		# skip EvadeType.NONE
		if evade_type == EvadeData.EvadeType.NONE:
			continue
		
		# skip first row of lables (column headers)
		var label_idx: int = evade_type * (EvadeData.EvadeSource.keys().size() + 1)
		label_idx += 1 # skip first column of labels

		var source_evade_values: Dictionary[EvadeData.EvadeSource, int] = get_evade_values(new_job_data.evade_datas, evade_type, EvadeData.Directions.FRONT)
		for evade_source: EvadeData.EvadeSource in source_evade_values.keys():
			var evade_value_label: Label = evade_grid.get_child(label_idx)
			evade_value_label.text = str(source_evade_values[evade_source]) + "%"
			
			label_idx += 1

	# update innate abilities
	var innate_ability_labels: Array[Node] = innate_abilities_list.get_children()
	for child_idx: int in range(1, innate_ability_labels.size()):
		innate_ability_labels[child_idx].queue_free()

	for ability: Ability in job_data.innate_abilities:
		var new_ability_label: Label = Label.new()
		new_ability_label.text = ability.display_name
		innate_abilities_list.add_child(new_ability_label)

	# update statuses	
	var statuses_always: PackedStringArray = []
	var statuses_start: PackedStringArray = []
	var statuses_immune: PackedStringArray = []

	for passive_effect: PassiveEffect in new_job_data.passive_effects:
		statuses_always.append_array(passive_effect.status_always)
		statuses_start.append_array(passive_effect.status_start)
		statuses_immune.append_array(passive_effect.status_immune)
	
	statuses_always = PackedStringArray(Utilities.get_array_unique(statuses_always))
	statuses_start = PackedStringArray(Utilities.get_array_unique(statuses_start))
	statuses_immune = PackedStringArray(Utilities.get_array_unique(statuses_immune))

	update_status_list(statuses_always_list, statuses_always)
	update_status_list(statuses_start_list, statuses_start)
	update_status_list(statuses_immune_list, statuses_immune)
	
	# Update element affinities
	var element_weak_list: Array[Action.ElementTypes] = []
	var element_resist_list: Array[Action.ElementTypes] = []
	var element_immune_list: Array[Action.ElementTypes] = []
	var element_absorb_list: Array[Action.ElementTypes] = []
	var element_strengthen_list: Array[Action.ElementTypes] = []
	
	for passive_effect: PassiveEffect in new_job_data.passive_effects:
		element_weak_list.append_array(passive_effect.element_weakness)
		element_resist_list.append_array(passive_effect.element_half)
		element_immune_list.append_array(passive_effect.element_cancel)
		element_absorb_list.append_array(passive_effect.element_absorb)
		element_strengthen_list.append_array(passive_effect.element_strengthen)
	
	element_weak_list.assign(Utilities.get_array_unique(element_weak_list))
	element_resist_list.assign(Utilities.get_array_unique(element_resist_list))
	element_immune_list.assign(Utilities.get_array_unique(element_immune_list))
	element_absorb_list.assign(Utilities.get_array_unique(element_absorb_list))
	element_strengthen_list.assign(Utilities.get_array_unique(element_strengthen_list))

	update_element_list(element_weak, "Weak: ", element_weak_list)
	update_element_list(element_resist, "Resist: ", element_resist_list)
	update_element_list(element_immune, "Immune: ", element_immune_list)
	update_element_list(element_absorb, "Absorb: ", element_absorb_list)
	update_element_list(element_strengthen, "Strengthen: ", element_strengthen_list)
	
	# update action list
	var action_labels: Array[Node] = action_list.get_children()
	for child_idx: int in range(1, action_labels.size()):
		action_labels[child_idx].queue_free()
	
	for ability_name: String in GameData.skillsets[job_data.skillset_unique_name].ability_names:
		# TODO fix custom ability names
		if ability_name == "counter": ability_name = "counter_tackle"
		elif ability_name == "face_up": ability_name = "faith_up"
		elif ability_name == "a_save": ability_name = "pa_save"
		elif ability_name == "counter_flood": ability_name = "counter_geomancy"
		elif ability_name == "any_ground": ability_name = "ignore_terrain"
		elif ability_name == "move_on_lava": ability_name = "walk_on_lava"
		elif ability_name == "move_hp_up": ability_name = "move_get_hp"
		elif ability_name == "equip_knife": ability_name = "equip_katana"
		
		var new_action_name: Label = Label.new()
		new_action_name.text = GameData.abilities[ability_name].display_name
		action_list.add_child(new_action_name)


func set_sprite() -> void:
	if job_data == null or sprite_rect.texture.atlas != null:
		return

	var spritesheet_data: UnitSpritesheetData = GameData.unit_spritesheets_data[job_data.sprite_name]
	
	var atlas_texture: AtlasTexture = sprite_rect.texture
	atlas_texture.atlas = spritesheet_data.create_frame_grid_texture()
	# atlas_texture.atlas = job_spr.create_frame_grid_texture(0)


func get_evade_values(evade_datas: Array[EvadeData], evade_type: EvadeData.EvadeType, direction: EvadeData.Directions) -> Dictionary[EvadeData.EvadeSource, int]:
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = {
		EvadeData.EvadeSource.JOB: 0,
		EvadeData.EvadeSource.SHIELD: 0,
		EvadeData.EvadeSource.ACCESSORY: 0,
		EvadeData.EvadeSource.WEAPON: 0,
	}
	
	for evade_data: EvadeData in evade_datas:
		if evade_data.directions.has(direction) and evade_data.type == evade_type:
			evade_values[evade_data.source] += evade_data.value
	
	return evade_values


func update_element_list(affinity_list_label: Label, label_start: String, affinity_list: Array[Action.ElementTypes]) -> void:
	affinity_list_label.text = label_start
	var elements_list: PackedStringArray = []
	for element: Action.ElementTypes in affinity_list:
		elements_list.append(Action.ElementTypes.find_key(element).to_pascal_case())
	affinity_list_label.text += ", ".join(elements_list)


func update_status_list(status_container: Node, status_list: PackedStringArray) -> void:
	var status_labels: Array[Node] = status_container.get_children()
	for child_idx: int in range(1, status_labels.size()):
		status_labels[child_idx].queue_free()

	for status_name: String in status_list:
		var new_status_label: Label = Label.new()
		new_status_label.text = status_name
		status_container.add_child(new_status_label)

func get_slot_item_type_names(equippable_item_types: Array[ItemData.ItemType], slot_types: PackedInt32Array) -> PackedStringArray:
	var slot_equipable_types: PackedStringArray = []
	for type: int in equippable_item_types:
		if slot_types.has(type):
			slot_equipable_types.append(ItemData.ItemType.keys()[type].to_snake_case())
	
	return slot_equipable_types
