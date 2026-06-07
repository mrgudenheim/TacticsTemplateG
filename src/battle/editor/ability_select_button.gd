class_name AbilitySelectButton
extends PanelContainer

signal selected(ability_data: Ability)

var ability_data: Ability:
	get: return ability_data
	set(value):
		ability_data = value
		update_ui(value)

@export var button: Button
@export var display_name: Label
@export var sprite_rect: TextureRect
@export var descrption: Label

@export var action_list: Container


func _ready() -> void:
	button.pressed.connect(on_selected)


func on_selected() -> void:
	selected.emit(ability_data)


func update_ui(new_ability_data: Ability) -> void:
	display_name.text = new_ability_data.display_name
	name = new_ability_data.unique_name
	descrption.text = new_ability_data.description
	
	## TODO update passive effects
	## update action list
	#var action_labels: Array[Node] = action_list.get_children()
	#for child_idx: int in range(1, action_labels.size()):
		#action_labels[child_idx].queue_free()
	#
	#for ability_id: int in RomReader.scus_data.skillsets_data[job_data.skillset_id].action_ability_ids:
		#if ability_id != 0:
			#var new_action: Action = RomReader.fft_abilities[ability_id].ability_action
			#var new_action_name: Label = Label.new()
			#new_action_name.text = new_action.display_name
			#action_list.add_child(new_action_name)
