class_name SkillsetSelectControl
extends Container

@export var skillset_select_button_container: Container
@export var skillset_select_button_scene: PackedScene
var skillset_select_buttons: Array[SkillsetSelectButton]


func populate_list() -> void:
	for skillset: Skillset in GameData.skillsets.values():
		var skillset_select_button: SkillsetSelectButton = skillset_select_button_scene.instantiate()
		skillset_select_button.skillset = skillset
		skillset_select_button_container.add_child(skillset_select_button)
	
	skillset_select_buttons.assign(skillset_select_button_container.get_children())


func filter_list(skillsets_to_show: Array[Skillset]) -> void:
	for skillset_select_button: SkillsetSelectButton in skillset_select_buttons:
		if skillsets_to_show.has(skillset_select_button.skillset):
			skillset_select_button.visible = true
		else:
			skillset_select_button.visible = false
