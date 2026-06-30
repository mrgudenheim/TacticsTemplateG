class_name AbilitySelectControl
extends Container

@export var ability_select_button_container: Container
@export var ability_select_button_scene: PackedScene
var ability_select_buttons: Array[AbilitySelectButton]


func populate_list() -> void:
	for ability_name: String in GameData.ability_paths.keys():
		var ability_data: Ability = GameData.get_ability(ability_name)
		var ability_select_button: AbilitySelectButton = ability_select_button_scene.instantiate()
		ability_select_button.ability_data = ability_data
		ability_select_button_container.add_child(ability_select_button)
	
	ability_select_buttons.assign(ability_select_button_container.get_children())


func filter_list(abilities_to_show: Array[Ability]) -> void:
	for ability_select_button: AbilitySelectButton in ability_select_buttons:
		if abilities_to_show.has(ability_select_button.ability_data):
			ability_select_button.visible = true
		else:
			ability_select_button.visible = false
