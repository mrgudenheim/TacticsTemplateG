class_name PreviewManager
extends PanelContainer

@export var ui_manager: UiManager
#@export var preview_viewport: PreviewSubViewportContainer
@export var preview_viewport2: SubViewport
@export var preview_rect: TextureRect
@export var unit_tscn: PackedScene
@export var unit: UnitActor

@export var weapon_options: OptionButton
@export var item_options: OptionButton
@export var other_type_options: OptionButton
@export var submerged_depth_options: OptionButton
@export var face_right_check: CheckBox
@export var is_playing_check: CheckBox
@export var is_back_facing_check: CheckBox

@export var animation_is_playing: bool = true
@export var animation_speed: float = 59 # frames per sec
@export var animation_slider: Slider
@export var opcode_text: LineEdit
var opcode_frame_offset: int = 0
var weapon_sheathe_check1_delay: int = 0
var weapon_sheathe_check2_delay: int = 10
var wait_for_input_delay: int = 10


#func _ready() -> void:
	#RomReader.rom_loaded.connect(initialize)


func initialize() -> void:
	add_unit()
	
	weapon_options.clear()
	for weapon_index: int in 0x90: # weapons + throwables (shuriken, ball) +  shields
		var equipment_type_name: String = ""
		if RomReader.items_array[weapon_index].item_type < RomReader.fft_text.equipment_types.size():
			equipment_type_name = " (" + RomReader.fft_text.equipment_types[RomReader.items_array[weapon_index].item_type] + ")"
		weapon_options.add_item(RomReader.items_array[weapon_index].unique_name + equipment_type_name)
	
	weapon_options.select(unit.primary_weapon.item_idx)
	
	item_options.clear()
	for item_index: int in RomReader.NUM_ITEMS:
		var type_name: String = ""
		if RomReader.items_array[item_index].item_type < RomReader.fft_text.equipment_types.size():
			type_name = " (" + RomReader.fft_text.equipment_types[RomReader.items_array[item_index].item_type] + ")"
		item_options.add_item(str(item_index) + " - " + RomReader.items_array[item_index].display_name + type_name)
	item_options.item_selected.connect(unit.animation_manager.set_item)
	
	is_playing_check.button_pressed = true
	#unit.animation_manager.animation_frame_loaded.connect(update_preview_render)


func add_unit() -> void:
	if is_instance_valid(unit):
		unit.queue_free()
	
	var new_unit: UnitActor = unit_tscn.instantiate()
	#preview_viewport.subviewport.add_child(new_unit)
	preview_viewport2.add_child(new_unit)
	new_unit.initialize_unit()
	new_unit.facing = GameData.Directions.SOUTH
	new_unit.position += Vector3.DOWN * 0.5
	#new_unit.char_body.rotation_degrees = Vector3.ZERO
	new_unit.animation_manager.rotation_degrees = Vector3.ZERO
	unit = new_unit
	#preview_viewport.camera_control.sprite = unit.animation_manager.unit_sprites_manager.sprite_primary
	
	new_unit.spritesheet_changed.connect(func(new_texture: ImageTexture) -> void: preview_rect.texture = new_texture)
	unit.animation_manager.processing_opcode.connect(update_preview_slider)
	ui_manager.pointer_index_spinbox.value_changed.connect(func(ptr_idx: int) -> void: unit.animation_manager.global_animation_ptr_id = ptr_idx)


func enable_ui() -> void:
	weapon_options.disabled = false
	item_options.disabled = false
	other_type_options.disabled = false
	submerged_depth_options.disabled = false
	face_right_check.disabled = false
	is_playing_check.disabled = false


#func update_preview_render() -> void:
	#preview_viewport2.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_weapon_options_item_selected(index: int) -> void:
	#unit.animation_manager._on_weapon_options_item_selected(index)
	#unit.animation_manager.weapon_id = index
	unit.set_primary_weapon(weapon_options.get_item_text(index))
	#unit.debug_menu.weapon_options.select(index)


func _on_other_type_selected(index: int) -> void:
	#unit.animation_manager._on_weapon_options_item_selected(index)
	#unit.animation_manager.weapon_id = index
	unit.animation_manager.other_type_index = index # TODO other_type_index should probably be var on UnitActor, set by status?
	#unit.debug_menu.weapon_options.select(index)


func _on_is_playing_check_box_toggled(toggled_on: bool) -> void:
	animation_slider.editable = !toggled_on
	
	if (!toggled_on):
		animation_slider.value = 0
	
	unit.animation_manager._on_is_playing_check_box_toggled(toggled_on)


func _on_animation_id_spin_box_value_changed(value: int) -> void:
	#global_animation_id = value
	unit.animation_manager._on_animation_id_spin_box_value_changed(value)
	#unit.debug_menu.anim_id_spin.value = value
	
	var num_parts: int = unit.animation_manager.global_fft_animation.sequence.seq_parts.size()
	animation_slider.tick_count = num_parts
	animation_slider.max_value = num_parts - 1


func _on_animation_h_slider_value_changed(value: int) -> void:
	opcode_text.text = unit.animation_manager.global_fft_animation.sequence.seq_parts[value].to_string()
	if(unit.animation_manager.animation_is_playing):
		return
	
	unit.animation_manager.process_seq_part(unit.animation_manager.global_fft_animation, value, unit.animation_manager.unit_sprites_manager.sprite_primary)


func _on_submerged_options_item_selected(index: int) -> void:
	unit.animation_manager._on_submerged_options_item_selected(index)


func _on_face_right_check_toggled(toggled_on: bool) -> void:
	if toggled_on:
		unit.facing = GameData.Directions.EAST
		unit.update_animation_facing(Vector3(-1, 0, -1))
	else:
		unit.facing = GameData.Directions.SOUTH
		unit.update_animation_facing(Vector3(-1, 0, -1))
	#unit.animation_manager._on_face_right_check_toggled(toggled_on)


func _on_palette_spin_box_value_changed(value: float) -> void:
	unit.animation_manager._on_palette_spin_box_value_changed(roundi(value))


func update_preview_slider(index: int) -> void:
	animation_slider.value = index
