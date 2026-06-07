class_name UnitEditor
extends Container

signal job_select_pressed(unit: Unit)
signal item_select_pressed(unit: Unit, slot: EquipmentSlot)
signal ability_select_pressed(unit: Unit, slot: AbilitySlot)
signal skillset_select_pressed(unit: Unit, skillset_slot_idx: int)

@export var sprite_rect: TextureRect
@export var sprite_button: TextureButton
@export var unit_name_line_edit: LineEdit
@export var gender_option_button: OptionButton
@export var job_button: Button
@export var level_spinbox: SpinBox

@export var team_option_button: OptionButton
@export var controller_option_button: OptionButton
@export var palette_option_button: OptionButton
@export var zodiac_option_button: OptionButton

@export var hp_bar: StatBar
@export var mp_bar: StatBar
@export var ct_bar: StatBar

@export var pa_label: Label
@export var ma_label: Label
@export var brave_label: Label
@export var faith_label: Label
@export var move_label: Label
@export var jump_label: Label
@export var speed_label: Label

@export var evade_grid: GridContainer

@export var equipment_grid: GridContainer
@export var ability_grid: GridContainer

@export var passive_effect_container: Container
@export var innate_ability_container: Container
@export var status_affinity_container: Container
# @export var element_affinity_list: VBoxContainer

@export var weak_elements_label: Label
@export var resist_elements_label: Label
@export var immune_elements_label: Label
@export var absorb_elements_label: Label
@export var strengthen_elements_label: Label

@export var unit_scene: PackedScene
var unit: Unit


func _ready() -> void:
	sprite_button.material = sprite_button.material.duplicate() # duplicate becaues each sprite needs its own unique shader parameter for color palette


func setup(new_unit: Unit) -> void:
	if unit != null:
		if unit.data_updated.is_connected(update_ui):
			unit.data_updated.disconnect(update_ui)

	unit = new_unit
	if new_unit.job_data == null:
		new_unit.set_job_id(0x01) # TODO set initial job correctly
	
	unit_name_line_edit.text = new_unit.unit_nickname
	job_button.text = new_unit.job_data.display_name
	
	palette_option_button.clear()
	@warning_ignore("integer_division")
	for palette_idx: int in GameData.unit_spritesheets_data[new_unit.sprite_file_name].color_palette.size() / 16:
		palette_option_button.add_item(str(palette_idx))
	palette_option_button.select(new_unit.sprite_palette_id)

	if new_unit.is_ai_controlled:
		controller_option_button.select(0)
	else:
		controller_option_button.select(1)

	hp_bar.set_stat(str(Unit.StatType.keys()[Unit.StatType.HP]), new_unit.stats[Unit.StatType.HP])
	hp_bar.name_label.position.x = 5
	hp_bar.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hp_bar.value_label.position.x = hp_bar.size.x - hp_bar.value_label.size.x - 5
	hp_bar.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# hp_bar.value_label.grow_horizontal = GrowDirection.GROW_DIRECTION_BEGIN
	
	mp_bar.set_stat(str(Unit.StatType.keys()[Unit.StatType.MP]), new_unit.stats[Unit.StatType.MP])
	mp_bar.fill_color = Color.INDIAN_RED
	mp_bar.name_label.position.x = 5
	mp_bar.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mp_bar.value_label.position.x = mp_bar.size.x - mp_bar.value_label.size.x - 5
	mp_bar.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# mp_bar.value_label.grow_horizontal = GrowDirection.GROW_DIRECTION_BEGIN

	ct_bar.set_stat(str(Unit.StatType.keys()[Unit.StatType.CT]), new_unit.stats[Unit.StatType.CT])
	ct_bar.fill_color = Color.WEB_GREEN
	ct_bar.name_label.position.x = 5
	ct_bar.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ct_bar.value_label.position.x = ct_bar.size.x - ct_bar.value_label.size.x - 5
	ct_bar.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# ct_bar.value_label.grow_horizontal = GrowDirection.GROW_DIRECTION_BEGIN

	# clear connections for when panel is reused
	# hook up buttons to update Unit data
	Utilities.disconnect_all_connections(unit_name_line_edit.text_submitted)
	unit_name_line_edit.text_submitted.connect(func(new_name: String) -> void: new_unit.unit_nickname = new_name)
	
	Utilities.disconnect_all_connections(level_spinbox.value_changed)
	level_spinbox.value_changed.connect(func(new_value: int) -> void: update_level(new_unit, new_value))
	# TODO update gender - sprite and stats

	Utilities.disconnect_all_connections(job_button.pressed)
	job_button.pressed.connect(func() -> void: job_select_pressed.emit(new_unit))
	
	Utilities.disconnect_all_connections(palette_option_button.item_selected)
	palette_option_button.item_selected.connect(set_palette)

	Utilities.disconnect_all_connections(team_option_button.item_selected)
	team_option_button.item_selected.connect(set_team)

	Utilities.disconnect_all_connections(controller_option_button.item_selected)
	controller_option_button.item_selected.connect(set_controller)
	
	# on unit data changed:
	# TODO remove invalid equipment?
	new_unit.data_updated.connect(update_ui)

	update_ui(new_unit)


func update_ui(new_unit: Unit) -> void:
	# update_stat_label(level_label, unit, Unit.StatType.LEVEL)
	var atlas_texture: AtlasTexture = sprite_button.texture_normal
	var unit_sprite: Sprite3D = new_unit.animation_manager.unit_sprites_manager.sprite_primary
	atlas_texture.atlas = unit_sprite.texture
	var spritesheet_data: UnitSpritesheetData = GameData.unit_spritesheets_data[new_unit.sprite_file_name]

	sprite_button.material.set_shader_parameter("palette_colors", spritesheet_data.color_palette.slice(new_unit.sprite_palette_id * 16, (new_unit.sprite_palette_id + 1) * 16))

	job_button.text = new_unit.job_data.display_name
	level_spinbox.value = new_unit.stats[Unit.StatType.LEVEL].get_modified_value()

	team_option_button.select(new_unit.team_id)
	
	update_stat_label(pa_label, new_unit, Unit.StatType.PHYSICAL_ATTACK)
	update_stat_label(ma_label, new_unit, Unit.StatType.MAGIC_ATTACK)
	update_stat_label(brave_label, new_unit, Unit.StatType.BRAVE)
	update_stat_label(faith_label, new_unit, Unit.StatType.FAITH)
	update_stat_label(move_label, new_unit, Unit.StatType.MOVE)
	update_stat_label(jump_label, new_unit, Unit.StatType.JUMP)
	update_stat_label(speed_label, new_unit, Unit.StatType.SPEED)

	# update evade
	var unit_passive_effects: Array[PassiveEffect] = new_unit.get_all_passive_effects()

	for evade_type: EvadeData.EvadeType in EvadeData.EvadeType.values():
		# skip EvadeType.NONE
		if evade_type == EvadeData.EvadeType.NONE:
			continue
		
		# skip first row of lables (column headers)
		var label_idx: int = evade_type * (EvadeData.Directions.keys().size() + EvadeData.EvadeSource.keys().size() + 2)
		label_idx += 1 # skip first column of labels
		for evade_direction: EvadeData.Directions in EvadeData.Directions.values():
			var evade_factor: int = get_total_evade_factor(new_unit, unit_passive_effects, evade_type, evade_direction)
			var evade_value_label: Label = evade_grid.get_child(label_idx)
			evade_value_label.text = str(evade_factor) + "%"
			
			label_idx += 1

		label_idx += 1 # skip empty spacer column
		var source_evade_values: Dictionary[EvadeData.EvadeSource, int] = new_unit.get_evade_values(evade_type, EvadeData.Directions.FRONT)
		for evade_source: EvadeData.EvadeSource in source_evade_values.keys():
			var evade_value_label: Label = evade_grid.get_child(label_idx)
			evade_value_label.text = str(source_evade_values[evade_source]) + "%"
			
			label_idx += 1

	# update equipment
	var equipment_labels: Array[Node] = equipment_grid.get_children()
	for child_idx: int in range(0, equipment_labels.size()):
		equipment_labels[child_idx].queue_free()

	for equip_slot: EquipmentSlot in new_unit.equip_slots:
		var new_slot_label: Label = Label.new()
		new_slot_label.text = equip_slot.equipment_slot_name
		equipment_grid.add_child(new_slot_label)

		var new_item_button: Button = Button.new()
		new_item_button.text = equip_slot.get_item().display_name
		new_item_button.pressed.connect(func() -> void: item_select_pressed.emit(new_unit, equip_slot))
		new_item_button.custom_minimum_size = Vector2(60, 0)
		equipment_grid.add_child(new_item_button)

	# update abilities and skillsets
	var ability_labels: Array[Node] = ability_grid.get_children()
	for child_idx: int in range(0, ability_labels.size()):
		ability_labels[child_idx].queue_free()

	# update skillsets
	for skillset_slot_idx: int in new_unit.skillsets_names.size():
		var new_slot_label: Label = Label.new()
		new_slot_label.text = "Skillset " + str(skillset_slot_idx + 1)
		ability_grid.add_child(new_slot_label)

		var skillset_display_name: String = ""
		var skillset_uname: String = new_unit.skillsets_names[skillset_slot_idx]
		if not skillset_uname.is_empty():
			if GameData.skillsets.has(skillset_uname):
				skillset_display_name = GameData.skillsets[skillset_uname].display_name
			else:
				push_warning("GameData does not have skillset: " + skillset_uname)

		var new_skillset_button: Button = Button.new()
		new_skillset_button.text = skillset_display_name
		new_skillset_button.pressed.connect(func() -> void: skillset_select_pressed.emit(new_unit, skillset_slot_idx))
		ability_grid.add_child(new_skillset_button)

	# update abilities
	for ability_slot: AbilitySlot in new_unit.ability_slots:
		var new_slot_label: Label = Label.new()
		new_slot_label.text = ability_slot.ability_slot_name
		ability_grid.add_child(new_slot_label)

		var new_ability_button: Button = Button.new()
		new_ability_button.text = ability_slot.get_ability().display_name
		new_ability_button.pressed.connect(func() -> void: ability_select_pressed.emit(new_unit, ability_slot))
		# TODO implement ability select buttons
		ability_grid.add_child(new_ability_button)
	
	# update passive effects
	var passive_effect_labels: Array[Node] = passive_effect_container.get_children()
	for child_idx: int in range(1, passive_effect_labels.size()):
		passive_effect_labels[child_idx].queue_free()
	
	# update innate abilities
	var innate_abilities_names: PackedStringArray = []
	for ability: Ability in new_unit.job_data.innate_abilities:
		innate_abilities_names.append(ability.display_name)
	#for passive_effect: PassiveEffect in unit.get_all_passive_effects(): # TODO allow giving innate abilities from passive effects?
		#innate_abilities_names.append(passive_effect.innate_abilities)
	
	update_passive_effect_list_label("Innate: ", innate_abilities_names)
	
	update_passive_effect_list_label("Weak: ", get_elements_text(new_unit.elemental_weakness))
	update_passive_effect_list_label("Resist: ", get_elements_text(new_unit.elemental_half))
	update_passive_effect_list_label("Immune: ", get_elements_text(new_unit.elemental_cancel))
	update_passive_effect_list_label("Absorb: ", get_elements_text(new_unit.elemental_absorb))
	update_passive_effect_list_label("Strengthen: ", get_elements_text(new_unit.elemental_strengthen))
	
	update_passive_effect_list_label("Always: ", new_unit.always_statuses)
	update_passive_effect_list_label("Starting: ", new_unit.start_statuses)
	update_passive_effect_list_label("Immune: ", new_unit.immune_statuses)
	
	
	# update innate abilities
	var innate_ability_labels: Array[Node] = innate_ability_container.get_children()
	for child_idx: int in range(0, innate_ability_labels.size()):
		innate_ability_labels[child_idx].queue_free()

	for ability: Ability in new_unit.job_data.innate_abilities:
		var new_ability_label: Label = Label.new()
		new_ability_label.text = ability.display_name
		innate_ability_container.add_child(new_ability_label)

	# update status affinity
	var current_status_labels: Array[Node] = status_affinity_container.get_children()
	for child_idx: int in range(1, current_status_labels.size()):
		current_status_labels[child_idx].queue_free()

	for status_name: String in new_unit.always_statuses:
		var new_status_label: Label = Label.new()
		new_status_label.text = "Always " + status_name
		status_affinity_container.add_child(new_status_label)
	
	for status_name: String in new_unit.start_statuses:
		var new_status_label: Label = Label.new()
		new_status_label.text = "Start " + status_name
		status_affinity_container.add_child(new_status_label)
	
	for status_name: String in new_unit.immune_statuses:
		var new_status_label: Label = Label.new()
		new_status_label.text = "Immune " + status_name
		status_affinity_container.add_child(new_status_label)
	
	# update element affinities
	update_element_list(weak_elements_label, "Weak: ", new_unit.elemental_weakness)
	update_element_list(resist_elements_label, "Resist: ", new_unit.elemental_half)
	update_element_list(immune_elements_label, "Immune: ", new_unit.elemental_cancel)
	update_element_list(absorb_elements_label, "Absorb: ", new_unit.elemental_absorb)
	update_element_list(strengthen_elements_label, "Strengthen: ", new_unit.elemental_strengthen)


func update_element_list(affinity_list_label: Label, label_start: String, affinity_list: Array[Action.ElementTypes]) -> void:
	affinity_list_label.text = label_start
	var elements_list: PackedStringArray = get_elements_text(affinity_list)
	affinity_list_label.text += ", ".join(elements_list)


func get_elements_text(element_list: Array[Action.ElementTypes]) -> PackedStringArray:
	var elements_text: PackedStringArray = []
	for element: Action.ElementTypes in element_list:
		elements_text.append(Action.ElementTypes.find_key(element).to_pascal_case())
	
	return elements_text


func update_passive_effect_list_label(starting_text: String, text_list: PackedStringArray) -> void:
	if not text_list.is_empty():
		var new_label: Label = Label.new()
		new_label.name = starting_text.to_pascal_case()
		new_label.text = starting_text + ", ".join(text_list)
		new_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		passive_effect_container.add_child(new_label)


func update_stat_label(stat_label: Label, new_unit: Unit, stat_type: Unit.StatType) -> void:
	var stat_name: String = Unit.StatType.find_key(stat_type).to_pascal_case()
	var stat: StatValue = new_unit.stats[stat_type]
	var stat_value: int = stat.get_modified_value()
	# stat_label.text = stat_name + ": " + str(roundi(stat_value)) + "/" + str(roundi(stat.max_value))
	stat_label.text = stat_name + ": " + str(roundi(stat_value)) # + "/" + str(roundi(stat.max_value))


func get_total_evade_factor(new_unit: Unit, unit_passive_effects: Array[PassiveEffect], evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> int:
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = new_unit.get_evade_values(evade_type, evade_direction)

	var total_evade_factor: float = 1.0
	var evade_factors: Dictionary[EvadeData.EvadeSource, float] = {}

	for evade_source: EvadeData.EvadeSource in evade_values.keys():
		if unit_passive_effects.any(func(passive_effect: PassiveEffect) -> bool: return passive_effect.include_evade_sources.has(evade_source)):
			var evade_value: int = evade_values[evade_source]
			for passive_effect: PassiveEffect in unit_passive_effects:
				if passive_effect.evade_source_modifiers_targeted.has(evade_source):
					evade_value = passive_effect.evade_source_modifiers_targeted[evade_source].apply(evade_value)
			
			var evade_factor: float = max(0.0, 1 - (evade_value / 100.0))

			evade_factors[evade_source] = evade_factor
			total_evade_factor = total_evade_factor * evade_factor

	total_evade_factor = max(0, total_evade_factor) # prevent negative evasion
	var total_evade_value: int = roundi((1 - total_evade_factor) * 100)

	return total_evade_value


func set_palette(new_palette_idx: int) -> void:
	if unit != null:
		unit.set_sprite_palette(new_palette_idx)
		unit.data_updated.emit(unit)


func set_team(new_team_idx: int) -> void:
	unit.team_id = new_team_idx
	
	if new_team_idx >= unit.global_battle_manager.teams.size():
		unit.global_battle_manager.teams.resize(new_team_idx + 1)
	
	if unit.global_battle_manager.teams[new_team_idx] == null:
		var new_team: Team = Team.new()
		new_team.team_name = "Team" + str(new_team_idx + 1)
		unit.global_battle_manager.teams[new_team_idx] = new_team
	
	unit.team = unit.global_battle_manager.teams[new_team_idx]


func set_controller(new_controller_idx: int) -> void:
	if new_controller_idx == 0:
		unit.is_ai_controlled = true
	else:
		unit.is_ai_controlled = false
		# TODO handle multiple player teams


func update_level(new_unit: Unit, new_level: int) -> void:
	new_unit.stats[Unit.StatType.LEVEL].set_value(new_level)
	Unit.generate_leveled_raw_stats(new_unit.stat_basis, new_level, new_unit.job_data, new_unit.stats_raw)
	
	var use_higher_stat_values: bool = false
	if ["RUKA.SEQ", "KANZEN.SEQ", "ARUTE.SEQ"].has(new_unit.animation_manager.global_seq.file_name): # lucavi
		use_higher_stat_values = true
	Unit.calc_battle_stats(new_unit.job_data, new_unit.stats_raw, new_unit.stats, true, use_higher_stat_values)
