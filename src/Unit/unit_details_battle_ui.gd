class_name UnitDetailsBattleUi
extends PanelContainer

@export var portrait_rect: TextureRect
@export var team_label: Label
@export var unit_name_label: Label
@export var job_label: Label
@export var level_label: Label

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
@export var innate_ability_grid: GridContainer

@export var current_status_list: VBoxContainer
@export var immune_status_list: VBoxContainer
# @export var element_affinity_list: VBoxContainer

@export var weak_elements_label: Label
@export var resist_elements_label: Label
@export var immune_elements_label: Label
@export var absorb_elements_label: Label
@export var strengthen_elements_label: Label

func setup(unit: Unit) -> void:
	unit_name_label.text = unit.unit_nickname
	job_label.text = unit.job_data.display_name

	hp_bar.set_stat(str(Unit.StatType.keys()[Unit.StatType.HP]), unit.stats[Unit.StatType.HP])
	hp_bar.name_label.position.x = 5
	hp_bar.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hp_bar.value_label.position.x -= (hp_bar.value_label.size.x + 10)
	hp_bar.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# hp_bar.value_label.grow_horizontal = GrowDirection.GROW_DIRECTION_BEGIN
	
	mp_bar.set_stat(str(Unit.StatType.keys()[Unit.StatType.MP]), unit.stats[Unit.StatType.MP])
	mp_bar.fill_color = Color.INDIAN_RED
	mp_bar.name_label.position.x = 5
	mp_bar.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mp_bar.value_label.position.x -= (mp_bar.value_label.size.x + 10)
	mp_bar.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# mp_bar.value_label.grow_horizontal = GrowDirection.GROW_DIRECTION_BEGIN

	ct_bar.set_stat(str(Unit.StatType.keys()[Unit.StatType.CT]), unit.stats[Unit.StatType.CT])
	ct_bar.fill_color = Color.WEB_GREEN
	ct_bar.name_label.position.x = 5
	ct_bar.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ct_bar.value_label.position.x -= (ct_bar.value_label.size.x + 10)
	ct_bar.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# ct_bar.value_label.grow_horizontal = GrowDirection.GROW_DIRECTION_BEGIN

	update_ui(unit)

	visibility_changed.connect(func() -> void: update_ui(unit))


func update_ui(unit: Unit) -> void:
	update_stat_label(level_label, unit, Unit.StatType.LEVEL)
	
	update_stat_label(pa_label, unit, Unit.StatType.PHYSICAL_ATTACK)
	update_stat_label(ma_label, unit, Unit.StatType.MAGIC_ATTACK)
	update_stat_label(brave_label, unit, Unit.StatType.BRAVE)
	update_stat_label(faith_label, unit, Unit.StatType.FAITH)
	update_stat_label(move_label, unit, Unit.StatType.MOVE)
	update_stat_label(jump_label, unit, Unit.StatType.JUMP)
	update_stat_label(speed_label, unit, Unit.StatType.SPEED)

	# update evade
	var unit_passive_effects: Array[PassiveEffect] = unit.get_all_passive_effects()

	for evade_type: EvadeData.EvadeType in EvadeData.EvadeType.values():
		# skip EvadeType.NONE
		if evade_type == EvadeData.EvadeType.NONE:
			continue
		
		# skip first row of lables (column headers)
		var label_idx: int = evade_type * (EvadeData.Directions.keys().size() + EvadeData.EvadeSource.keys().size() + 2)
		label_idx += 1 # skip first column of labels
		for evade_direction: EvadeData.Directions in EvadeData.Directions.values():
			var evade_factor: int = get_total_evade_factor(unit, unit_passive_effects, evade_type, evade_direction)
			var evade_value_label: Label = evade_grid.get_child(label_idx)
			evade_value_label.text = str(evade_factor) + "%"
			
			label_idx += 1

		label_idx += 1 # skip empty spacer column
		var source_evade_values: Dictionary[EvadeData.EvadeSource, int] = unit.get_evade_values(evade_type, EvadeData.Directions.FRONT)
		for evade_source: EvadeData.EvadeSource in source_evade_values.keys():
			var evade_value_label: Label = evade_grid.get_child(label_idx)
			evade_value_label.text = str(source_evade_values[evade_source]) + "%"
			
			label_idx += 1

	
	# var magic_evade_values: Dictionary[EvadeData.EvadeSource, int] = unit.get_evade_values(EvadeData.EvadeType.MAGICAL, EvadeData.Directions.FRONT)

	# var job_evade_phys: int = unit.get_evade(EvadeData.EvadeSource.JOB, EvadeData.EvadeType.PHYSICAL, EvadeData.Directions.FRONT)
	# var shield_evade_phys: int = unit.get_evade(EvadeData.EvadeSource.SHIELD, EvadeData.EvadeType.PHYSICAL, EvadeData.Directions.FRONT)
	# var accessory_evade_phys: int = unit.get_evade(EvadeData.EvadeSource.ACCESSORY, EvadeData.EvadeType.PHYSICAL, EvadeData.Directions.FRONT)
	# var weapon_evade_phys: int = unit.get_evade(EvadeData.EvadeSource.WEAPON, EvadeData.EvadeType.PHYSICAL, EvadeData.Directions.FRONT)

	# var job_evade_magic: int = unit.get_evade(EvadeData.EvadeSource.JOB, EvadeData.EvadeType.MAGICAL, EvadeData.Directions.FRONT)
	# var shield_evade_magic: int = unit.get_evade(EvadeData.EvadeSource.SHIELD, EvadeData.EvadeType.MAGICAL, EvadeData.Directions.FRONT)
	# var accessory_evade_magic: int = unit.get_evade(EvadeData.EvadeSource.ACCESSORY, EvadeData.EvadeType.MAGICAL, EvadeData.Directions.FRONT)
	# var weapon_evade_magic: int = unit.get_evade(EvadeData.EvadeSource.WEAPON, EvadeData.EvadeType.MAGICAL, EvadeData.Directions.FRONT)

	
	# var target_total_evade_factor: float = 1.0
	# var evade_factors: Dictionary[EvadeData.EvadeSource, float] = {}

	# for evade_source: EvadeData.EvadeSource in physical_evade_values.keys():
	# 	if unit_passive_effects.any(func(passive_effect): return passive_effect.include_evade_sources.has(evade_source)):
	# 		var evade_value: float = physical_evade_values[evade_source]
	# 		for passive_effect: PassiveEffect in unit_passive_effects:
	# 			if passive_effect.evade_source_modifiers_user.has(evade_source):
	# 				evade_value = passive_effect.evade_source_modifiers_targeted[evade_source].apply(evade_value)
			
	# 		var evade_factor: float = max(0.0, 1 - (evade_value / 100.0))

	# 		evade_factors[evade_source] = evade_factor
	# 		target_total_evade_factor = target_total_evade_factor * evade_factor

	# target_total_evade_factor = max(0, target_total_evade_factor) # prevent negative evasion

	# update equipment
	var equipment_labels: Array[Node] = equipment_grid.get_children()
	for child_idx: int in range(0, equipment_labels.size()):
		equipment_labels[child_idx].queue_free()

	for equip_slot: EquipmentSlot in unit.equip_slots:
		var new_slot_label: Label = Label.new()
		new_slot_label.text = equip_slot.equipment_slot_name
		equipment_grid.add_child(new_slot_label)

		var new_item_label: Label = Label.new()
		new_item_label.text = equip_slot.item.display_name
		equipment_grid.add_child(new_item_label)

	# update abilities
	var ability_labels: Array[Node] = ability_grid.get_children()
	for child_idx: int in range(0, ability_labels.size()):
		ability_labels[child_idx].queue_free()

	for ability_slot: AbilitySlot in unit.ability_slots:
		var new_slot_label: Label = Label.new()
		new_slot_label.text = ability_slot.ability_slot_name
		ability_grid.add_child(new_slot_label)

		var new_ability_label: Label = Label.new()
		new_ability_label.text = ability_slot.ability.display_name
		ability_grid.add_child(new_ability_label)

	# update innate abilities
	var innate_ability_labels: Array[Node] = innate_ability_grid.get_children()
	for child_idx: int in range(0, innate_ability_labels.size()):
		innate_ability_labels[child_idx].queue_free()

	for ability: Ability in unit.job_data.innate_abilities:
		var new_ability_label: Label = Label.new()
		new_ability_label.text = ability.display_name
		innate_ability_grid.add_child(new_ability_label)

	# update statuses
	var current_status_labels: Array[Node] = current_status_list.get_children()
	for child_idx: int in range(1, current_status_labels.size()):
		current_status_labels[child_idx].queue_free()

	for status: StatusEffect in unit.current_statuses:
		var new_status_label: Label = Label.new()
		new_status_label.text = status.status_effect_name
		if status.duration_type == StatusEffect.DurationType.PERMANENT:
			new_status_label.text += " (Permanent)"
		current_status_list.add_child(new_status_label)
	
	# update immune statuses
	var immune_statuses_labels: Array[Node] = immune_status_list.get_children()
	for child_idx: int in range(1, immune_statuses_labels.size()):
		immune_statuses_labels[child_idx].queue_free()

	for status_name: String in unit.immune_statuses:
		var new_status_label: Label = Label.new()
		new_status_label.text = status_name
		immune_status_list.add_child(new_status_label)
	
	# update element affinities
	update_element_list(weak_elements_label, "Weak: ", unit.elemental_weakness)
	update_element_list(resist_elements_label, "Resist: ", unit.elemental_half)
	update_element_list(immune_elements_label, "Immune: ", unit.elemental_cancel)
	update_element_list(absorb_elements_label, "Absorb: ", unit.elemental_absorb)
	update_element_list(strengthen_elements_label, "Strengthen: ", unit.elemental_strengthen)


func update_element_list(affinity_list_label: Label, label_start: String, affinity_list: Array[Action.ElementTypes]) -> void:
	affinity_list_label.text = label_start
	var elements_list: PackedStringArray = []
	for element: Action.ElementTypes in affinity_list:
		elements_list.append(Action.ElementTypes.find_key(element).to_pascal_case())
	affinity_list_label.text += ", ".join(elements_list)


func update_stat_label(stat_label: Label, unit: Unit, stat_type: Unit.StatType) -> void:
	var stat_name: String = Unit.StatType.find_key(stat_type).to_pascal_case()
	var stat: StatValue = unit.stats[stat_type]
	var stat_value: int = stat.get_modified_value()
	# stat_label.text = stat_name + ": " + str(roundi(stat_value)) + "/" + str(roundi(stat.max_value))
	stat_label.text = stat_name + ": " + str(roundi(stat_value)) # + "/" + str(roundi(stat.max_value))


func get_total_evade_factor(unit: Unit, unit_passive_effects: Array[PassiveEffect], evade_type: EvadeData.EvadeType, evade_direction: EvadeData.Directions) -> int:
	var evade_values: Dictionary[EvadeData.EvadeSource, int] = unit.get_evade_values(evade_type, evade_direction)

	var total_evade_factor: float = 1.0
	var evade_factors: Dictionary[EvadeData.EvadeSource, float] = {}

	for evade_source: EvadeData.EvadeSource in evade_values.keys():
		if unit_passive_effects.any(func(passive_effect: PassiveEffect) -> void: return passive_effect.include_evade_sources.has(evade_source)):
			var evade_value: float = evade_values[evade_source]
			for passive_effect: PassiveEffect in unit_passive_effects:
				if passive_effect.evade_source_modifiers_targeted.has(evade_source):
					evade_value = passive_effect.evade_source_modifiers_targeted[evade_source].apply(roundi(evade_value))
			
			var evade_factor: float = max(0.0, 1 - (evade_value / 100.0))

			evade_factors[evade_source] = evade_factor
			total_evade_factor = total_evade_factor * evade_factor

	total_evade_factor = max(0, total_evade_factor) # prevent negative evasion
	var total_evade_value: int = roundi((1 - total_evade_factor) * 100)

	return total_evade_value
