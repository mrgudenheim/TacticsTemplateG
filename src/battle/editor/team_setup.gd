class_name TeamSetup
extends Container

signal need_new_unit(team: Team)

signal unit_job_select_pressed(unit: Unit)
signal unit_item_select_pressed(unit: Unit, slot: EquipmentSlot)
signal unit_ability_select_pressed(unit: Unit, slot: AbilitySlot)
signal unit_skillset_select_pressed(unit: Unit, skillset_idx: int)

@export var team: Team
@export var unit_list: Container
@export var num_units_spinbox: SpinBox
@export var unit_editor_scene: PackedScene


func _ready() -> void:
	num_units_spinbox.value_changed.connect(on_num_units_changed)


func setup(new_team: Team, is_random: bool = false) -> void:
	team = new_team
	name = team.team_name

	if not is_random:
		for unit: Unit in team.units:
			add_unit_editor(unit)

		num_units_spinbox.value = team.units.size()
	else:
		num_units_spinbox.value = 4 # default to 4 units per team
		on_num_units_changed(roundi(num_units_spinbox.value))


func on_num_units_changed(new_value: int) -> void:
	var delta_units: int = new_value - team.units.size()
	if delta_units > 0:
		for delta: int in delta_units:
			need_new_unit.emit(team)
	elif delta_units < 0:
		var unit_panels: Array[UnitEditor] = []
		unit_panels.assign(unit_list.get_children())
		
		for delta: int in -delta_units:
			team.units[-1].queue_free()
			team.units.remove_at(-1)
			unit_panels[-1].queue_free()
			unit_panels.remove_at(-1)


func add_unit_editor(new_unit: Unit) -> void:
	if new_unit.team != team:
		return
	
	var unit_editor: UnitEditor = unit_editor_scene.instantiate()
	unit_list.add_child(unit_editor)
	unit_editor.setup(new_unit)
	
	unit_editor.job_select_pressed.connect(unit_job_select_pressed.emit)
	unit_editor.item_select_pressed.connect(unit_item_select_pressed.emit)
	unit_editor.ability_select_pressed.connect(unit_ability_select_pressed.emit)
	unit_editor.skillset_select_pressed.connect(unit_skillset_select_pressed.emit)
