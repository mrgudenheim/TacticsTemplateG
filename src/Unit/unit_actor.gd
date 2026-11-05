class_name UnitActor
extends Node3D

# https://ffhacktics.com/wiki/Miscellaneous_Unit_Data
# https://ffhacktics.com/wiki/Battle_Stats

signal initialized()
signal data_updated(unit: UnitActor)

signal ability_assigned(name: String)
signal primary_weapon_assigned(item_unique_name: String)
signal image_changed(new_image: ImageTexture)
signal spritesheet_changed(new_spritesheet: ImageTexture)
signal unit_input_event(unit_data: UnitActor, event: InputEvent)

static var unit_scene: PackedScene = load("uid://dkudrb304m7t1")

var global_battle_manager: BattleManager
var unit_data: UnitData

@export var char_body: CharacterBody3D
@export var animation_manager: UnitAnimationManager
@export var popup_texts: PopupTextContainer
@export var stat_bars_position: Control
@export var stat_bars_container: Container
@export var unit_battle_details_ui: UnitDetailsBattleUi
@export var icon2: Sprite3D
@export var icon_cycle_time: float = 1.25
@export var icon_id: int = 0:
	get:
		return icon_id
	set(value):
		icon_id = value
		set_icon(icon_id)
@export var debug_menu: UnitDebugMenu

var can_move: bool = true

@export var tile_highlights: Node3D
var is_back_facing: bool = false

var is_in_air: bool = false
var is_traveling_path: bool = false

var active_ability_name: String = ""
var action_data: Action

var active_action: ActionInstance

@export var current_animation_id_fwd: int = 6 # set based on current action
@export var current_idle_animation_id: int = 6 # set based on status (critical, knocked out, etc.)
# constants?
@export var idle_walk_animation_id: int = 6 # 0x0c for flying sprites
@export var walk_to_animation_id: int = 0x18 # 0x1e (30) for flying sprites
@export var evade_animation_id: int = 0x30 # TODO fix for kanzen, arute?
@export var taking_damage_animation_id: int = 0x32
@export var knocked_out_animation_id: int = 0x34
@export var heal_animation_id: int = 0x36
@export var mid_jump_animation: int = 0x3e
var submerged_depth: int = 0


static func instantiate() -> UnitActor:
	return unit_scene.instantiate()


func _ready() -> void:
	var hp_bar: StatBar = add_stat_bar(UnitData.StatType.HP)
	hp_bar.show_value = true
	
	var mp_bar: StatBar = add_stat_bar(UnitData.StatType.MP)
	mp_bar.fill_color = Color.INDIAN_RED
	mp_bar.show_value = true

	var ct_bar: StatBar = add_stat_bar(UnitData.StatType.CT)
	ct_bar.visual_max = 100.0
	ct_bar.update_stat(unit_data.stats[UnitData.StatType.CT])
	ct_bar.fill_color = Color.WEB_GREEN
	ct_bar.show_value = true
	
	icon2.texture = GameData.get_texture("misc")
	icon2.material_override = icon2.material_override.duplicate()
	icon2.material_override.set_shader_parameter("sprite_texture", GameData.get_texture("misc"))
	icon2.material_override.set_shader_parameter("palette_colors", GameData.palettes["misc"].slice(5 * 16, 6 * 16))
	icon2.material_override.set_shader_parameter("billboard_enabled", true)
	cycle_status_icons()
	
	add_to_group("Units")

	if not GameData.is_ready:
		GameData.data_indexed.connect(initialize_unit)
	else:
		initialize_unit()


func bind_unit_data(new_unit_data: UnitData) -> void:
	unit_data = new_unit_data
	unit_data.statuses_updated.connect(update_status_visuals)


func _exit_tree() -> void:
	if global_battle_manager != null and is_queued_for_deletion():
		var unit_index: int = global_battle_manager.units.find(unit_data)
		for action_instance: ActionInstance in unit_data.actions_data.values():
			action_instance.stop_targeting()
		if unit_index != -1: # if the unit is in the battle_manager array
			global_battle_manager.units.remove_at(unit_index)


func add_stat_bar(stat_type: UnitData.StatType) -> StatBar:
	var new_stat_bar: StatBar = StatBar.instantiate()
	new_stat_bar.set_stat(str(UnitData.StatType.keys()[stat_type]), unit_data.stats[stat_type])
	stat_bars_container.add_child(new_stat_bar)

	return new_stat_bar


func set_stat_bar_visiblity(new_is_visible: bool, stat_bar_idx: int = -1) -> void:
	if stat_bar_idx == -1:
		stat_bars_position.visible = new_is_visible
		return
	
	stat_bars_container.get_child(stat_bar_idx).visible = new_is_visible


func update_stat_bars_scale(camera_zoom: float) -> void:
	stat_bars_position.scale = Vector2.ONE * 3.775 / camera_zoom


func initialize_unit() -> void:
	debug_menu.populate_options()
	
	animation_manager.wep_texture = GameData.get_texture("wep")
	animation_manager.wep_spritesheet_data = GameData.get_spritesheet_data("wep")
	animation_manager.wep_shp = GameData.get_shp("wep1")
	animation_manager.wep_seq = GameData.get_seq("wep1")
	
	animation_manager.eff_texture = GameData.get_texture("eff")
	animation_manager.eff_spritesheet_data = GameData.get_spritesheet_data("eff")
	animation_manager.eff_shp = GameData.get_shp("eff1")
	animation_manager.eff_seq = GameData.get_seq("eff1")
	
	#animation_manager.unit_sprites_manager.sprite_effect.texture = animation_manager.eff_spr.create_frame_grid_texture(0, 0, 0, 0, 0)
	var eff_frame_grid: ImageTexture = GameData.get_spritesheet_data("eff").create_frame_grid_texture(0, 0, 0, 0)
	animation_manager.unit_sprites_manager.sprite_effect.texture = eff_frame_grid
	var eff_material: ShaderMaterial = animation_manager.unit_sprites_manager.sprite_effect.material_override.duplicate()
	eff_material.set_shader_parameter("sprite_texture", eff_frame_grid)
	eff_material.set_shader_parameter("palette_colors", GameData.get_spritesheet_data("eff").color_palette.slice(0 * 16, 1 * 16))
	eff_material.set_shader_parameter("depth_mode", VfxConstants.DepthMode.UNIT)
	animation_manager.unit_sprites_manager.sprite_effect.material_override = eff_material

	animation_manager.unit_sprites_manager.sprite_item.texture = GameData.get_texture("items")
	
	animation_manager.other_texture = GameData.get_texture("other")
	animation_manager.other_shp = GameData.get_shp("other")
	
	set_sprite_by_file_name("ramuza")

	initialized.emit()


func _physics_process(delta: float) -> void:
	# FFTae (and all non-battles) don't use physics, so this can be turned off
	if global_battle_manager == null:
		set_physics_process(false)
		return
	
	# Add the gravity.
	if not char_body.is_on_floor():
		char_body.velocity += char_body.get_gravity() * delta
	
	var velocity_horizontal: Vector3 = char_body.velocity
	velocity_horizontal.y = 0
	if velocity_horizontal.length_squared() > 0.01:
		update_unit_facing(velocity_horizontal.normalized())
	char_body.move_and_slide()


func _process(_delta: float) -> void:
	if not GameData.is_ready:
		return
	
	if char_body.velocity.y != 0 and is_in_air == false:
		is_in_air = true
		current_animation_id_fwd = mid_jump_animation
		#debug_menu.anim_id_spin.value = mid_jump_animation
	elif char_body.velocity.y == 0 and is_in_air == true:
		is_in_air = false
		current_animation_id_fwd = current_idle_animation_id
		#debug_menu.anim_id_spin.value = idle_animation
	
	set_base_animation_ptr_id(current_animation_id_fwd)


func get_nullify_statuses() -> Array[StatusEffect]:
	return current_statuses.filter(func(status: StatusEffect) -> bool: return status.passive_effect.nullify_targeted)


func update_status_visuals() -> void:
	var anim_priority: int = 0
	var shading_priority: int = 0
	var other_type_priority: int = 0
	var spritesheet_priority: int = 0

	var anim_status: StatusEffect
	var current_anim: int = current_animation_id_fwd
	var other_type_status: StatusEffect
	var spritesheet_status: StatusEffect
	if current_statuses.is_empty():
		if current_animation_id_fwd == current_idle_animation_id:
			current_idle_animation_id = idle_walk_animation_id
			set_base_animation_ptr_id(current_idle_animation_id)
		else:
			current_idle_animation_id = idle_walk_animation_id
		
		icon2.region_rect = Rect2i(Vector2i.ZERO, Vector2i.ONE)
		animation_manager.unit_sprites_manager.sprite_primary.modulate = Color.WHITE
		animation_manager.other_type_index = 0
		set_sprite_by_job(job_name)
	else:
		for status: StatusEffect in current_statuses:
			if status.order >= anim_priority and status.idle_animation_id != -1:
				anim_priority = status.order
				anim_status = status
				
				# if current_animation_id_fwd == current_idle_animation_id:
				# 	current_idle_animation_id = status.idle_animation_id
				# 	set_base_animation_ptr_id(status.idle_animation_id)
				# else:
				# 	current_idle_animation_id = status.idle_animation_id
			
			if status.order >= shading_priority and status.modulation_color != Color.BLACK:
				shading_priority = status.order
				animation_manager.unit_sprites_manager.sprite_primary.modulate = status.modulation_color
			
			if status.order >= other_type_priority and status.spritesheet_file_name == "other":
				other_type_priority = status.order
				other_type_status = status
			
			if status.order >= spritesheet_priority and status.spritesheet_file_name != "":
				spritesheet_priority = status.order
				spritesheet_status = status
		
		if shading_priority == 0:
			animation_manager.unit_sprites_manager.sprite_primary.modulate = Color.WHITE
		
		if other_type_priority == 0:
			animation_manager.other_type_index = 0
		else:
			animation_manager.other_type_index = other_type_status.other_type_index
		
		# if spritesheet is changing
		if spritesheet_priority == 0 and sprite_file_name != job_data.sprite_name:
			set_base_animation_ptr_id(0) # prevent out of bounds error in case SEQ is also changing
			set_sprite_by_job(job_name)
		elif spritesheet_priority != 0:
			set_base_animation_ptr_id(0) # prevent out of bounds error in case SEQ is also changing
			set_sprite_by_file_name(spritesheet_status.spritesheet_file_name)
		
		if anim_priority == 0: # if no statuses set the idle animation (may happen when status is removed)
			if current_anim == current_idle_animation_id:
				current_idle_animation_id = idle_walk_animation_id
				set_base_animation_ptr_id(current_idle_animation_id)
			else:
				current_idle_animation_id = idle_walk_animation_id
		else:
			if current_anim == current_idle_animation_id:
				current_idle_animation_id = anim_status.idle_animation_id
				set_base_animation_ptr_id(anim_status.idle_animation_id)
			else:
				current_idle_animation_id = anim_status.idle_animation_id

		# palette update must come after spritesheet change to make sure palettes are taken from correct spritesheet
		if other_type_priority != 0:
			set_sprite_palette_override(sprite_palette_id + other_type_status.palette_idx_offset)


func use_attack() -> void:
	can_move = false
	push_warning("using attack: " + primary_weapon.display_name)
	#push_warning("Animations: " + str(PackedInt32Array([action_data.animation_start_id, action_data.animation_charging_id, action_data.animation_executing_id])))
	#if action_data.animation_start_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_start_id + int(is_back_facing)
		#await animation_manager.animation_completed
	#
	#if action_data.animation_charging_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_charging_id + int(is_back_facing)
		#await get_tree().create_timer(0.1 + (action_data.ticks_charge_time * 0.1)).timeout
	
		#animation_executing_id = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#animation_manager.unit_debug_menu.anim_id_spin.value = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
	
	# execute atttack
	#debug_menu.anim_id_spin.value = (RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) + int(is_back_facing) # TODO lookup based on target relative height
	current_animation_id_fwd = roundi(RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) # TODO lookup based on target relative height
	set_base_animation_ptr_id(current_animation_id_fwd)
	
	# TODO implement proper timeout for abilities that execute using an infinite loop animation
	# this implementation can overwrite can_move when in the middle of another ability
	get_tree().create_timer(2).timeout.connect(func() -> void: can_move = true) 
	
	await animation_manager.animation_completed

	#ability_completed.emit()
	animation_manager.reset_sprites()
	#debug_menu.anim_id_spin.value = current_idle_animation_id  + int(is_back_facing)
	current_animation_id_fwd = current_idle_animation_id
	set_base_animation_ptr_id(current_animation_id_fwd)
	can_move = true


func use_ability(pos: Vector3) -> void:
	can_move = false
	print_debug("animating: " + action_data.display_name)
	#push_warning("Animations: " + str(PackedInt32Array([action_data.animation_start_id, action_data.animation_charging_id, action_data.animation_executing_id])))
	if action_data.animation_start_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_start_id + int(is_back_facing)
		current_animation_id_fwd = action_data.animation_start_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		await animation_manager.animation_completed
	
	if action_data.animation_charging_id != 0:
		#debug_menu.anim_id_spin.value = action_data.animation_charging_id + int(is_back_facing)
		current_animation_id_fwd = action_data.animation_charging_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		await get_tree().create_timer(0.1 + (action_data.ticks_charge_time * 0.1)).timeout
	
	#if action_data.animation_executing_id != 0:
	if action_data.animation_executing_id < 0:
		pass
	elif action_data.animation_executing_id == 0:
		#animation_executing_id = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#animation_manager.unit_debug_menu.anim_id_spin.value = 0x3e * 2 # TODO look up based on equiped weapon and target relative height
		#debug_menu.anim_id_spin.value = (RomReader.battle_bin_data.weapon_animation_ids[primary_weapon.item_type].y * 2) + int(is_back_facing) # TODO lookup based on target relative height
		current_animation_id_fwd = get_attack_action().animation_executing_id # TODO lookup based on target relative height
		set_base_animation_ptr_id(current_animation_id_fwd)
	else:
		var ability_animation_executing_id: int = action_data.animation_executing_id
		if ["ruka", "arute", "kanzen"].has(GameData.get_spritesheet_data(sprite_file_name).seq_name):
			ability_animation_executing_id = 0x2c * 2 # https://ffhacktics.com/wiki/Set_attack_animation_flags_and_facing_3
		#debug_menu.anim_id_spin.value = ability_animation_executing_id + int(is_back_facing)
		current_animation_id_fwd = ability_animation_executing_id
		set_base_animation_ptr_id(current_animation_id_fwd)
		
	#var new_vfx_location: Node3D = Node3D.new()
	#new_vfx_location.position = pos
	##new_vfx_location.position.y += 2 # TODO set position dependent on ability vfx data
	#new_vfx_location.name = "VfxLocation"
	#get_parent().add_child(new_vfx_location)
	var action_instance: ActionInstance = ActionInstance.new(action_data, self, global_battle_manager)
	if is_instance_valid(action_instance.action.vfx_data):
		action_instance.show_vfx(pos)
	
	# TODO implement proper timeout for abilities that execute using an infinite loop animation
	# this implementation can overwrite can_move when in the middle of another ability
	get_tree().create_timer(2).timeout.connect(func() -> void: can_move = true) 
		
	await animation_manager.animation_completed

	ability_completed.emit()
	animation_manager.reset_sprites()
	#debug_menu.anim_id_spin.value = current_idle_animation_id  + int(is_back_facing)
	current_animation_id_fwd = current_idle_animation_id
	set_base_animation_ptr_id(current_animation_id_fwd)
	can_move = true


func animate_start_action(animation_start_id: int, animation_charging_id: int) -> void:
	if animation_start_id != 0:
		set_base_animation_ptr_id(animation_start_id)
		await animation_manager.animation_completed
	
	if animation_charging_id != 0:
		set_base_animation_ptr_id(animation_charging_id)
		await get_tree().create_timer(0.1 + (action_data.ticks_charge_time * 0.1)).timeout # TODO allow looping until changed, ie. charging a spell


func animate_execute_action(animation_executing_id: int) -> void:
	if animation_executing_id < 0: # no animatione
		return
	
	var ability_animation_executing_id: int = animation_executing_id
	if ["ruka", "arute", "kanzen"].has(GameData.get_spritesheet_data(sprite_file_name).seq_name):
		ability_animation_executing_id = 0x2c * 2 # https://ffhacktics.com/wiki/Set_attack_animation_flags_and_facing_3
	#debug_menu.anim_id_spin.value = ability_animation_executing_id + int(is_back_facing)
	set_base_animation_ptr_id(ability_animation_executing_id)
	
	await animation_manager.animation_completed # TODO change based on vfx timing data?
	
	if current_animation_id_fwd == animation_executing_id:
		animate_return_to_idle()


func animate_take_hit() -> void:
	set_base_animation_ptr_id(taking_damage_animation_id)
	
	#if vfx != null:
		#await vfx.vfx_completed
	#else:
		#await get_tree().create_timer(0.5).timeout # TODO show based on vfx timing data?
	#
	#if current_animation_id_fwd == taking_damage_animation_id:
		#animate_return_to_idle()


func animate_recieve_heal() -> void:
	set_base_animation_ptr_id(heal_animation_id)
	
	#if vfx != null:
		#await vfx.vfx_completed
	#else:
		#await get_tree().create_timer(1).timeout # TODO show based on vfx timing data?
	#
	#if current_animation_id_fwd == heal_animation_id:
		#animate_return_to_idle()


func return_to_idle_from_hit() -> void:
	if [taking_damage_animation_id, heal_animation_id].has(current_animation_id_fwd):
		animate_return_to_idle()


func animate_evade(evade_animation_fwd_id: int) -> void:
	set_base_animation_ptr_id(evade_animation_fwd_id)
	
	await animation_manager.animation_completed
	
	if current_animation_id_fwd == evade_animation_fwd_id:
		animate_return_to_idle()


func animate_knock_out() -> void:
	current_idle_animation_id = knocked_out_animation_id
	set_base_animation_ptr_id(knocked_out_animation_id)
	
	knocked_out.emit(self)


func animate_return_to_idle() -> void:
	# add random delay to prevent unit animations from syncing
	# Talcall: if changing animation to one of the walking animations (anything less than 0xC) it checks the unit ID && 0x3 against the event timer. if they are equal, start animating the unit. else... don't animate the unit.
	var desync_delay: float = randf_range(0.0, 0.25)
	await get_tree().create_timer(desync_delay).timeout 
	
	set_base_animation_ptr_id(current_idle_animation_id)


func set_base_animation_ptr_id(ptr_id: int) -> void:
	current_animation_id_fwd = ptr_id
	var new_ptr: int = ptr_id
	if is_back_facing and new_ptr > 5:
		new_ptr = ptr_id + 1
	elif is_back_facing and new_ptr > 0: # handle facing frames 
		new_ptr = ptr_id + 2
	else:
		new_ptr = ptr_id # null animation
	
	#if is_back_facing:
		#debug_menu.anim_id_spin.value = ptr_id + 1
		##animation_manager.global_animation_ptr_id = ptr_id + 1
	#else:
		#debug_menu.anim_id_spin.value = ptr_id
		##animation_manager.global_animation_ptr_id = ptr_id
	
	if animation_manager.global_animation_ptr_id != new_ptr:
		debug_menu.anim_id_spin.value = new_ptr # TODO the debug ui should not be the primary path to changing he animation
		#animation_manager.global_animation_ptr_id = new_ptr


func update_unit_facing(dir: Vector3) -> void:
	var angle_deg: float = rad_to_deg(atan2(dir.z, dir.x))
	angle_deg = fposmod(angle_deg, 359.99) + 45 # add 45 so EAST is just < 90 instead of < 45 and > 315
	angle_deg = fposmod(angle_deg, 359.99) # correction for values over 360 due to adding 45
	var new_facing: GameData.Directions = unit_data.facing
	if angle_deg < 90:
		new_facing = GameData.Directions.EAST
	elif angle_deg < 180:
		new_facing = GameData.Directions.NORTH
	elif angle_deg < 270:
		new_facing = GameData.Directions.WEST
	elif angle_deg < 360:
		new_facing = GameData.Directions.SOUTH
	
	if new_facing != unit_data.facing:
		unit_data.facing = new_facing
		if global_battle_manager != null:
			update_animation_facing(global_battle_manager.camera_controller.camera_facing_vector)


func update_animation_facing(camera_facing_vector: Vector3) -> void:
	var unit_facing_vector: Vector3 = UnitData.FACING_VECTORS[unit_data.facing]
	#var camera_facing_vector: Vector3 = UnitControllerRT.CameraFacingVectors[controller.camera_facing]
	#var facing_difference: Vector3 = camera_facing_vector - unt_facing_vectorwad
	
	var unit_facing_angle: float = fposmod(rad_to_deg(atan2(unit_facing_vector.z, unit_facing_vector.x)), 359.99)
	var camera_facing_angle: float = fposmod(rad_to_deg(atan2(-camera_facing_vector.z, -camera_facing_vector.x)), 359.99)
	var facing_difference_angle: float = fposmod(camera_facing_angle - unit_facing_angle, 359.99)
		
	#push_warning("Difference: " + str(facing_difference) + ", UnitFacing: " + str(unit_facing_vector) + ", CameraFacing: " + str(camera_facing_vector))
	#push_warning("Difference: " + str(facing_difference_angle) + ", UnitFacing: " + str(unit_facing_angle) + ", CameraFacing: " + str(camera_facing_angle))
	#push_warning(rad_to_deg(atan2(facing_difference.z, facing_difference.x)))
	
	var new_is_right_facing: bool = false
	#is_back_facing: bool = false
	if facing_difference_angle < 90:
		new_is_right_facing = true
		is_back_facing = false
	elif facing_difference_angle < 180:
		new_is_right_facing = true
		is_back_facing = true
	elif facing_difference_angle < 270:
		new_is_right_facing = false
		is_back_facing = true
	elif facing_difference_angle < 360:
		new_is_right_facing = false
		is_back_facing = false
	
	if (animation_manager.is_right_facing != new_is_right_facing
			or animation_manager.is_back_facing != is_back_facing):
		animation_manager.set_face_right(new_is_right_facing)
		
		# TODO when changing fwd/back animations, retain the current step of the animation
		# Talcall: the direction the unit is facing gets updated on every parse of the routine, but unless the animation is changing, 
		# the instruction pointer byte doesn't get refreshed every vanilla animation is coded such that this swapping between front and back works flawlessly.
		if animation_manager.is_back_facing != is_back_facing:
			animation_manager.is_back_facing = is_back_facing
			var back_facing_offset: int = 1
			if debug_menu.anim_id_spin.value < 5:
				back_facing_offset = 2 # there are 5 directions of facing animations, so diagonal front facing id=2 and diagonal back facing id=4
				# TODO utilize the extra facing frames

			if is_back_facing == true:
				debug_menu.anim_id_spin.value += back_facing_offset
			else:
				debug_menu.anim_id_spin.value -= back_facing_offset


func toggle_debug_menu() -> void:
	debug_menu.visible = not debug_menu.visible


func hide_debug_menu() -> void:
	debug_menu.visible = false


func set_job(new_job_name: String) -> void:
	job_name = new_job_name
	job_data = GameData.get_job(new_job_name)
	set_sprite_by_job(new_job_name)
	
	# skillsets_names.fill("")
	equip_skillset(0, GameData.get_skillset(job_data.skillset_unique_name))
	
	job_nickname = job_data.display_name
	
	if animation_manager.global_spritesheet_data.is_flying:
		idle_walk_animation_id = 0x0c
		walk_to_animation_id = 0x1e
		current_idle_animation_id = idle_walk_animation_id
		set_base_animation_ptr_id(idle_walk_animation_id)
	else:
		idle_walk_animation_id = 0x06
		walk_to_animation_id = 0x18
		current_idle_animation_id = idle_walk_animation_id
		set_base_animation_ptr_id(idle_walk_animation_id)
	
	update_passive_effects()


func set_primary_weapon(new_weapon_unique_name: String) -> void:
	equip_slots[0].item_unique_name = new_weapon_unique_name
	primary_weapon = GameData.get_item(new_weapon_unique_name)
	#animation_manager.weapon_id = new_weapon_id
	var weapon_palette_id: int = primary_weapon.wep_frame_palette
	var weapon_eff_id: int = primary_weapon.wep_eff_palette
	var weapon_grid_texture: ImageTexture = animation_manager.wep_spritesheet_data.create_frame_grid_texture(
		0, 0, primary_weapon.wep_frame_v_offset, 0, animation_manager.wep_shp.file_name)
	animation_manager.unit_sprites_manager.set_weapon_texture(weapon_grid_texture)
	animation_manager.unit_sprites_manager.sprite_weapon.material_override.set_shader_parameter("palette_colors", GameData.get_spritesheet_data("wep").color_palette.slice(weapon_palette_id * 16, (weapon_palette_id + 1) * 16))
	animation_manager.unit_sprites_manager.sprite_effect.material_override.set_shader_parameter("palette_colors", GameData.get_spritesheet_data("eff").color_palette.slice(weapon_eff_id * 16, (weapon_eff_id + 1) * 16))

	# attack_action = primary_weapon.weapon_attack_action
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects()
	set_available_actions(all_passive_effects)
	primary_weapon_assigned.emit(new_weapon_unique_name)


# https://ffhacktics.com/wiki/Determine_Status_Bubble_Parameters
# https://ffhacktics.com/wiki/Display_Status_Bubble
func set_icon(new_icon_id: int) -> void:
	icon2.region_rect = RomReader.battle_bin_data.status_icon_rects[new_icon_id]


func set_status_icon_rect(rect: Rect2i) -> void:
	icon2.region_rect = rect


func cycle_status_icons() -> void:
	var status_idx: int = 0
	while true:
		var status: StatusEffect = null
		if not current_statuses.is_empty():
			status_idx = (status_idx + 1) % current_statuses.size()
			status = current_statuses[status_idx]
			var rect: Rect2i = status.get_icon_rect()
			set_status_icon_rect(rect)
		else:
			status_idx = 0
		
		await get_tree().create_timer(icon_cycle_time).timeout
			
		#if current_statuses2.keys().all(func(status: StatusEffect): return status.status_icon_rects.is_empty()):
			#set_status_icon_rect(Rect2i(Vector2i.ZERO, Vector2i.ONE))
			#await get_tree().create_timer(icon_cycle_time).timeout
		#elif current_statuses2.keys()[status_idx].status_icon_rects.size() > 0:
			#var rect: Rect2i = current_statuses2.keys()[status_idx].status_icon_rects[0]
			##var rect: Rect2i = status.get_icon_rect()
			#set_status_icon_rect(rect)
			#await get_tree().create_timer(icon_cycle_time).timeout
			#
			#if current_statuses2.keys().size() > 0:
				#status_idx = (status_idx + 1) % current_statuses2.keys().size()
			#else:
				#status_idx = 0
		#else:
			#if current_statuses2.keys().size() > 0:
				#status_idx = (status_idx + 1) % current_statuses2.keys().size()
			#else:
				#status_idx = 0


func show_popup_text(text: String) -> void:
	popup_texts.show_popup_text(text)


func set_sprite_by_file_idx(new_sprite_file_idx: int) -> void:
	if sprite_file_idx == new_sprite_file_idx:
		return # do nothing if no change
	
	sprite_file_idx = new_sprite_file_idx
	var spr: Spr = RomReader.sprs[new_sprite_file_idx]
	sprite_file_name = spr.file_name
	if RomReader.spr_file_name_to_id.has(spr.file_name):
		sprite_id = RomReader.spr_file_name_to_id[spr.file_name]
	debug_menu.sprite_options.select(new_sprite_file_idx)
	#on_sprite_selected(new_sprite_file_idx)
	if spr.file_name == "WEP.SPR":
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 32
	else:
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 16 + (16 * spr.sp2s.size())
	update_spritesheet_grid_texture()
	
	debug_menu.anim_id_spin.value = current_idle_animation_id


func set_sprite_by_file_name(new_sprite_file_name: String) -> void:
	#var new_sprite_file_idx: int = RomReader.file_records[new_sprite_file_name].type_index
	#set_sprite_by_file_idx(new_sprite_file_idx)
	
	sprite_file_name = new_sprite_file_name
	#debug_menu.sprite_options.select(new_sprite_file_idx)
	on_sprite_selected(new_sprite_file_name)
	var num_sp2s: int = min(0, (GameData.get_texture(new_sprite_file_name).get_height() - 488)) / 256
	if new_sprite_file_name == "wep":
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 32
	else:
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 16 + (16 * num_sp2s)
	update_spritesheet_grid_texture()
	
	debug_menu.anim_id_spin.value = current_idle_animation_id


func set_sprite_by_id(new_sprite_id: int) -> void:
	var new_sprite_file_idx: int = RomReader.spr_id_file_idxs[new_sprite_id]
	set_sprite_by_file_idx(new_sprite_file_idx)


func set_sprite_by_job(new_job_name: String) -> void:
	var new_job_data: JobData = GameData.get_job(new_job_name)
	
	# TODO get different sprite_name for female generic jobs
	var sprite_name: String = new_job_data.sprite_name
	if (new_job_data.job_id >= 0x4a and new_job_data.job_id <= 0x5a or new_job_data.job_id == 0x5d) and stat_basis == StatBasis.FEMALE:
		sprite_name = sprite_name.replace("_m", "_w")
	set_sprite_by_file_name(sprite_name)
	if job_data.default_palette_idx != -1:
		set_sprite_palette(job_data.default_palette_idx)
	else:
		set_sprite_palette(randi_range(0, 4))


func set_sprite_palette(new_palette_id: int) -> void:
	if new_palette_id == sprite_palette_id:
		return
	
	sprite_palette_id = new_palette_id
	if sprite_palette_id_override == -1: # don't update grid texture if palette is still being overridden
		update_spritesheet_grid_texture()


func set_sprite_palette_override(new_palette_id: int) -> void:
	if new_palette_id == sprite_palette_id_override:
		return
	
	sprite_palette_id_override = new_palette_id
	update_spritesheet_grid_texture()


func modulate_sprite_color(new_modulate_color: Color) -> void:
	animation_manager.unit_sprites_manager.sprite_primary.modulate = new_modulate_color


func set_sprite_tint(tint: Vector3) -> void:
	animation_manager.unit_sprites_manager.set_tint(tint)


func set_submerged_depth(new_depth: int) -> void:
	if new_depth == submerged_depth:
		return
	
	submerged_depth = new_depth
	update_spritesheet_grid_texture()


func update_spritesheet_grid_texture() -> void:
	var new_spritesheet_data: UnitSpritesheetData = GameData.get_spritesheet_data(sprite_file_name)
	var palette_idx_final: int = sprite_palette_id_override
	if sprite_palette_id_override < 0:
		palette_idx_final = sprite_palette_id
	var new_grid_texture: Texture2D = new_spritesheet_data.create_frame_grid_texture(
		0, animation_manager.other_type_index, 0, submerged_depth
	)
	animation_manager.unit_sprites_manager.set_primary_texture(new_grid_texture)
	animation_manager.unit_sprites_manager.sprite_primary.material_override.set_shader_parameter("palette_colors", new_spritesheet_data.color_palette.slice(palette_idx_final * 16, (palette_idx_final + 1) * 16))

	spritesheet_changed.emit(new_grid_texture)


func on_sprite_selected(new_spritesheet_name: String) -> void:
	# var spr: Spr = RomReader.sprs[index]
	# if not spr.is_initialized:
	# 	spr.set_data()
	# 	if RomReader.spr_file_name_to_id.keys().has(spr.file_name):
	# 		spr.set_spritesheet_data(RomReader.spr_file_name_to_id[spr.file_name])
	# 	else:
	# 		spr.set_spritesheet_data(-1) # get data for OTHER.SPR
	
	# animation_manager.global_spr = spr
	
	# var shp: Shp = RomReader.shps_array[RomReader.file_records[spr.shp_name].type_index]
	# if not shp.is_initialized:
	# 	shp.set_data_from_shp_bytes(RomReader.get_file_data(shp.file_name))
	
	# var seq: Seq = RomReader.seqs_array[RomReader.file_records[spr.seq_name].type_index]
	# if not seq.is_initialized:
	# 	seq.set_data_from_seq_bytes(RomReader.get_file_data(seq.file_name))
	
	var shp: Shp = GameData.get_spritesheet_data(new_spritesheet_name).get_shp()
	var animation_changed: bool = false
	if shp.file_name == "type2":
		if animation_manager.wep_shp.file_name != "wep2":
			animation_manager.wep_shp = GameData.get_shp("wep2")
			set_primary_weapon(primary_weapon.unique_name) # get new texture based on wep2.shp
			animation_changed = true
		animation_manager.wep_seq = GameData.get_seq("wep2")
	
	var seq: Seq = GameData.get_spritesheet_data(new_spritesheet_name).get_seq()
	if shp != animation_manager.global_shp or seq != animation_manager.global_seq:
		animation_changed = true
	
	# animation_manager.global_spr = spr
	animation_manager.global_spritesheet_data = GameData.get_spritesheet_data(new_spritesheet_name)
	animation_manager.global_shp = shp
	animation_manager.global_seq = seq
	
	
	#spritesheet_changed.emit(animation_manager.unit_sprites_manager.sprite_item.texture) # TODO hook up to sprite for debug purposes
	#spritesheet_changed.emit(ImageTexture.create_from_image(spr.spritesheet)) # TODO hook up to sprite for debug purposes
	#spritesheet_changed.emit(animation_manager.unit_sprites_manager.sprite_weapon.texture) # TODO hook up to sprite for debug purposes
	if animation_changed:
		# if animation_manager.global_animation_id >= animation_manager.global_seq.sequences.size():
		# 	set_base_animation_ptr_id(6) # triggers on_animation_changed
		# else:
		animation_manager.on_animation_changed()


func set_position_to_tile() -> void:
	char_body.global_position = Vector3(tile_position.location.x + 0.5, tile_position.get_world_position().y + 0.25, tile_position.location.y + 0.5)


func update_map_paths(map_tiles: Dictionary[Vector2i, Array], units: Array[UnitActor], max_cost: int = 9999) -> void:
	paths_set = false
	var all_passive_effects: Array[PassiveEffect] = get_all_passive_effects()
	update_prohibited_terrain(all_passive_effects)
	update_terrain_costs(all_passive_effects)
	ignore_height = all_passive_effects.any(func(passive_effect: PassiveEffect) -> bool: return passive_effect.ignore_height)
	
	if move_action.targeting_strategy.has_method("get_map_paths"):
		map_paths = await move_action.targeting_strategy.get_map_paths(self, map_tiles, units, max_cost)
		paths_set = true
		paths_updated.emit()


func _on_character_body_3d_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	unit_input_event.emit(self, event)

	# show UnitActor preview ui - hp, mp, evade, equipment, statuses, status immunities, element affinity, etc. portrait/mini sprite?
	if Input.is_action_just_pressed("secondary_action"):
		unit_battle_details_ui.visible = !unit_battle_details_ui.visible
