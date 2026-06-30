class_name UnitDebugMenu
extends Control

signal spritesheet_changed(new_image: ImageTexture)

@export var unit: Unit
@export var unit_char_body: CharacterBody3D
@export var animation_manager: UnitAnimationManager

@export var sprite_options: OptionButton
@export var anim_id_spin: SpinBox

@export var weapon_options: OptionButton
@export var item_options: OptionButton
@export var other_type_options: OptionButton

@export var ability_id_spin: SpinBox
@export var ability_name_line: LineEdit

#@export var sprite_viewer: Sprite3D
var camera: Camera3D


func _ready() -> void:
	camera = get_viewport().get_camera_3d()
	
	sprite_options.item_selected.connect(_on_sprite_option_selected)
	anim_id_spin.value_changed.connect(_on_anim_id_spin_value_changed)
	weapon_options.item_selected.connect(unit.set_primary_weapon)
	item_options.item_selected.connect(animation_manager.set_item)
	
	ability_id_spin.value_changed.connect(_on_ability_id_value_changed)
	# unit.ability_assigned.connect(func(action_name: String) -> void: ability_id_spin.value = GameData.actions.keys().find(action_name))
	
	unit.primary_weapon_assigned.connect(func(weapon_unique_name: String) -> void: weapon_options.select(RomReader.items.keys().find(weapon_unique_name)))
	# unit.primary_weapon_assigned.connect(weapon_options.select)

func _process(delta: float) -> void:
	if camera != null:
		var camera_right: Vector3 = camera.basis * Vector3.RIGHT
		position = camera.unproject_position(unit_char_body.position + (Vector3.UP * 1.0) + (camera_right * 0.35))


func populate_options() -> void:
	weapon_options.clear()
	item_options.clear()
	#for weapon_index: int in RomReader.NUM_WEAPONS:
		#var equipment_type_name: String = ""
		#if RomReader.items_array[weapon_index].item_type < RomReader.fft_text.equipment_types.size():
			#equipment_type_name = " (" + RomReader.fft_text.equipment_types[RomReader.items_array[weapon_index].item_type] + ")"
		#weapon_options.add_item(str(weapon_index) + " - " + RomReader.items_array[weapon_index].display_name + equipment_type_name
	
	#item_options.clear()
	#for item_index: int in RomReader.NUM_ITEMS:
		#var type_name: String = ""
		#if RomReader.items_array[item_index].item_type < RomReader.fft_text.equipment_types.size():
			#type_name = " (" + RomReader.fft_text.equipment_types[RomReader.items_array[item_index].item_type] + ")"
		#item_options.add_item(str(item_index) + " - " + RomReader.items_array[item_index].display_name + type_name )
	
	for item_name: String in GameData.item_paths.keys():
		var item: ItemData = GameData.get_item(item_name)
		var item_type_name: String = " (" + ItemData.ItemType.keys()[item.item_type] + ")"
		if range(0, 20).has(item.item_type):
			weapon_options.add_item(item.display_name + item_type_name)
		item_options.add_item(item.display_name + item_type_name)
	
	
	sprite_options.clear()
	for unit_spritesheet_name: String in GameData.unit_spritesheet_data_paths.keys():
		sprite_options.add_item(unit_spritesheet_name)


func populate_sprite_options() -> void:
	sprite_options.clear()
	for spr: Spr in RomReader.sprs:
		sprite_options.add_item(spr.file_name)


func enable_ui() -> void:
	weapon_options.disabled = false
	item_options.disabled = false
	other_type_options.disabled = false


func _on_sprite_option_selected(index: int) -> void:
	unit.on_sprite_selected(sprite_options.get_item_text(index))


func _on_anim_id_spin_value_changed(value: int) -> void:
	animation_manager.global_animation_ptr_id = value


func _on_ability_id_value_changed(ability_id: int) -> void:
	# var ability_name: String = GameData.actions.keys()[ability_id]
	# unit.set_ability(ability_name)
	# ability_name_line.text = ability_name
	ability_name_line.text = "Ability id: " + str(ability_id)
