class_name SkillsetSelectButton
extends PanelContainer

signal selected(selected_skillset: Skillset)

var skillset: Skillset:
	get: return skillset
	set(value):
		skillset = value
		update_ui(value)

@export var button: Button
@export var display_name: Label
@export var sprite_rect: TextureRect
@export var descrption: Label

@export var action_list: Container


func _ready() -> void:
	button.pressed.connect(on_selected)


func on_selected() -> void:
	selected.emit(skillset)


func update_ui(new_skillset_data: Skillset) -> void:
	display_name.text = new_skillset_data.display_name
	name = new_skillset_data.unique_name
	descrption.text = new_skillset_data.description
