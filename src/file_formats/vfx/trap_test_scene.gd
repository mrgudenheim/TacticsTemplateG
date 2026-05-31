class_name TrapTestScene
extends Node3D
## Standalone TRAP effect debug scene — loads a map, spawns a real Squire unit,
## and previews TRAP particle effects via TrapEffectInstance.

@export var camera_controller: CameraController
@export var maps_container: Node3D
@export var target_marker: MeshInstance3D
@export var attacker_marker: MeshInstance3D
@export var units_container: Node3D
@export var anim_preview_container: Node3D

# Left panel
@export var handler_option: OptionButton
@export var element_option: OptionButton
@export var play_button: Button
@export var loop_checkbox: CheckBox
@export var speed_slider: HSlider
@export var speed_label: Label
@export var white_flash_button: Button
@export var direction_slider: HSlider
@export var direction_label: Label
@export var config_label: RichTextLabel

# Right panel
@export var texture_preview: TextureRect
@export var info_label: RichTextLabel
@export var element_color_rect: ColorRect

var target_world_pos: Vector3 = Vector3(2.5, 0, 1.5)
var test_unit: Unit
var _impact_direction: Vector3 = Vector3(1, 0, 0)

var _trap_instance: TrapEffectInstance

var _flash_tween: Tween = null

func _ready() -> void:
	handler_option.item_selected.connect(_on_handler_changed)
	element_option.item_selected.connect(_on_element_changed)
	play_button.pressed.connect(_on_play_pressed)
	speed_slider.value_changed.connect(_on_speed_changed)
	white_flash_button.pressed.connect(_on_white_flash_pressed)
	direction_slider.value_changed.connect(_on_direction_changed)

	if RomReader.is_ready:
		_on_rom_loaded()
	else:
		RomReader.rom_loaded.connect(_on_rom_loaded, CONNECT_ONE_SHOT)


func _on_rom_loaded() -> void:
	_load_map()
	_spawn_squire()
	_setup_trap_instance()
	_populate_ui()
	_update_config_display()
	_update_info_display()


func _load_map() -> void:
	var map_node: MapChunkNodes = VfxTestUtils.load_mirrored_map(116, maps_container)
	if map_node == null:
		return

	var map_data: MapData = map_node.map_data

	# Find tile for placement
	for tile: TerrainTile in map_data.terrain_tiles:
		if tile.location == Vector2i(2, 1):
			target_world_pos = tile.get_world_position()

	# Adjust Y for Y-mirror: vertex transform gives new_y = mesh_aabb.end.y - old_y
	var mesh_aabb: AABB = map_data.mesh.get_aabb()
	target_world_pos.y = mesh_aabb.end.y - target_world_pos.y

	target_marker.position = target_world_pos + Vector3(0, 0.15, 0)
	attacker_marker.position = target_world_pos + Vector3(0, 0.15, 0) - _impact_direction
	camera_controller.position = target_world_pos


func _spawn_squire() -> void:
	test_unit = Unit.instantiate()
	units_container.add_child(test_unit)
	test_unit.initialize_unit()
	test_unit.char_body.global_position = target_world_pos + Vector3(0, 0.25, 0)
	test_unit.stat_basis = Unit.StatBasis.MALE
	test_unit.set_job_id(0x4a) # Squire
	test_unit.set_sprite_palette(0)
	test_unit.update_unit_facing(Vector3.FORWARD)
	camera_controller.rotated.connect(test_unit.char_body.set_rotation_degrees)
	test_unit.char_body.set_rotation_degrees(Vector3(0, camera_controller.rotation_degrees.y, 0))
	test_unit.update_animation_facing(camera_controller.camera_facing_vector)
	test_unit.hide_debug_menu()
	test_unit.stat_bars_container.visible = false


func _setup_trap_instance() -> void:
	_trap_instance = TrapEffectInstance.new()
	_trap_instance.name = "TrapEffectInstance"
	_trap_instance.position = target_world_pos
	anim_preview_container.add_child(_trap_instance)
	_trap_instance.initialize()


func _populate_ui() -> void:
	handler_option.clear()
	handler_option.add_item("All", 0)
	for handler_id: int in TrapEffectData.HANDLER_GROUP_NAMES:
		handler_option.add_item("%d: %s" % [handler_id, TrapEffectData.HANDLER_GROUP_NAMES[handler_id]], handler_id)

	element_option.clear()
	for i: int in TrapEffectData.ELEMENT_NAMES.size():
		element_option.add_item("%d: %s" % [i, TrapEffectData.ELEMENT_NAMES[i]], i)

	var trap_data: TrapEffectData = RomReader.trap_effect_data
	if trap_data.texture != null:
		texture_preview.texture = trap_data.texture


func _update_config_display() -> void:
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	var handler_id: int = handler_option.get_selected_id()

	var emitter_indices: Array
	if handler_id == 0:
		emitter_indices = range(TrapEffectData.NUM_EMITTERS)
	else:
		emitter_indices = TrapEffectData.HANDLER_CONFIGS.get(handler_id, [])

	var dir_names: PackedStringArray = ["NONE", "DIRECTIONAL", "FACING"]
	var vel_names: PackedStringArray = ["SPHERICAL_RANDOM", "SCATTER", "DIRECTIONAL", "FACING_DIR", "ZERO"]

	var text: String = ""
	for idx: int in emitter_indices:
		if idx >= trap_data.emitters.size():
			continue
		var emitter: TrapEffectData.TrapEmitter = trap_data.emitters[idx]
		text += "[b]Emitter %d: %s[/b]\n" % [emitter.index, emitter.name]
		text += "anim_index: %d\n" % emitter.anim_index
		text += "max_particles: %d\n" % emitter.max_particles
		text += "direction: %s\n" % dir_names[emitter.direction_mode]
		text += "velocity_mode: %s\n" % vel_names[emitter.velocity_mode]
		text += "pos_scatter: %s\n" % VfxTestUtils.vec3_str(emitter.pos_scatter)
		text += "velocity: %s\n" % VfxTestUtils.vec3_str(emitter.velocity)
		text += "vel_range: %s\n" % VfxTestUtils.vec3_str(emitter.vel_range)
		text += "scatter_half: %s\n" % VfxTestUtils.vec3_str(emitter.scatter_half_range)
		text += "weight: [%d, %d]\n" % [emitter.weight_min, emitter.weight_max]
		text += "radius: [%d, %d]\n" % [emitter.radius_min, emitter.radius_max]
		text += "lifetime: [%d, %d]\n" % [emitter.lifetime_min, emitter.lifetime_max]
		text += "spawn: rate=%d count=%d\n" % [emitter.spawn_rate, emitter.spawn_count]
		text += "spawn_window: [%d, %d]\n\n" % [emitter.spawn_check_lo, emitter.spawn_check_hi]

	config_label.text = text


func _update_info_display() -> void:
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	var text: String = ""
	text += "[b]TRAP Effect Data[/b]\n"
	text += "emitters: %d\n" % trap_data.emitters.size()
	text += "framesets: %d\n" % trap_data.framesets.size()
	text += "animations: %d\n" % trap_data.animations.size()
	text += "elements: %d\n" % trap_data.element_colors.size()
	text += "texture: %s\n" % ("OK" if trap_data.texture != null else "MISSING")
	text += "gravity: %s\n" % VfxTestUtils.vec3_str(trap_data.gravity)
	text += "gravity_raw: %s\n" % str(trap_data.gravity_raw)
	text += "inertia: %d\n" % trap_data.inertia_threshold

	if not trap_data.element_colors.is_empty():
		text += "\n[b]Element Colors[/b]\n"
		for i: int in trap_data.element_colors.size():
			var c: Color = trap_data.element_colors[i]
			text += "%d %s: (%d, %d, %d)\n" % [i, TrapEffectData.ELEMENT_NAMES[i], c.r8, c.g8, c.b8]

	if not RomReader.battle_bin_data.charging_vfx_ids.is_empty():
		text += "\n[b]Charging VFX IDs[/b]\n"
		for i: int in RomReader.battle_bin_data.charging_vfx_ids.size():
			text += "[%d]: handler %d\n" % [i, RomReader.battle_bin_data.charging_vfx_ids[i]]

	info_label.text = text


# ============================================================
#  UI Callbacks
# ============================================================

func _on_handler_changed(_index: int) -> void:
	_update_config_display()


func _on_element_changed(index: int) -> void:
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	var elem_idx: int = element_option.get_item_id(index)
	if elem_idx >= 0 and elem_idx < trap_data.element_colors.size():
		element_color_rect.color = trap_data.element_colors[elem_idx]


func _on_play_pressed() -> void:
	if _trap_instance == null:
		return

	var handler_id: int = handler_option.get_selected_id()
	var elem_idx: int = element_option.get_selected_id()

	_trap_instance.loop = loop_checkbox.button_pressed

	# Pass target_unit for hit flash (handler 2), spell charge height (handler 4),
	# and all-emitter mode (handler 0)
	var flash_unit: Unit = test_unit if handler_id in [0, 2, 4, 18] else null
	_trap_instance.play(handler_id, elem_idx, _impact_direction, flash_unit)


func _on_speed_changed(value: float) -> void:
	Engine.time_scale = value
	speed_label.text = "%.1fx" % value


func _on_direction_changed(value: float) -> void:
	direction_label.text = "%d deg" % int(value)
	var angle_rad: float = deg_to_rad(value)
	_impact_direction = Vector3(cos(angle_rad), 0, sin(angle_rad))
	attacker_marker.position = target_world_pos + Vector3(0, 0.15, 0) - _impact_direction


func _on_white_flash_pressed() -> void:
	if test_unit == null:
		return
	if _flash_tween:
		_flash_tween.kill()
	test_unit.set_sprite_tint(Vector3.ONE)
	_flash_tween = create_tween()
	_flash_tween.tween_method(
		func(v: float) -> void: test_unit.set_sprite_tint(Vector3(v, v, v)),
		1.0, 0.0, 4.0 / 30.0)
	_flash_tween.tween_callback(test_unit.set_sprite_tint.bind(Vector3.ZERO))
