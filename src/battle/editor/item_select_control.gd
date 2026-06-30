class_name ItemSelectControl
extends Container

@export var item_select_button_container: Container
@export var item_select_button_scene: PackedScene
var item_select_buttons: Array[ItemSelectButton]


func populate_list() -> void:
	for item_name: String in GameData.item_paths.keys():
		var item_data: ItemData = GameData.get_item(item_name)
		var item_select_button: ItemSelectButton = item_select_button_scene.instantiate()
		item_select_button.item_data = item_data
		item_select_button_container.add_child(item_select_button)
	
	item_select_buttons.assign(item_select_button_container.get_children())


func filter_list(items_to_show: Array[ItemData]) -> void:
	for item_select_button: ItemSelectButton in item_select_buttons:
		if items_to_show.has(item_select_button.item_data):
			item_select_button.visible = true
		else:
			item_select_button.visible = false
