class_name UnitActor
extends Node3D

# https://ffhacktics.com/wiki/Miscellaneous_Unit_Data
# https://ffhacktics.com/wiki/Battle_Stats

signal data_updated(unit: UnitActor)

signal primary_weapon_assigned(item_unique_name: String)
signal image_changed(new_image: ImageTexture)
signal spritesheet_changed(new_spritesheet: ImageTexture)
signal unit_input_event(unit_data: UnitActor, event: InputEvent)

const UNIT_SCENE: PackedScene = preload("uid://dkudrb304m7t1")

var battle_manager: BattleManager
var unit_data: UnitData

@export var char_body: CharacterBody3D
@export var animation_manager: UnitAnimationManager
@export var popup_texts: PopupTextContainer
@export var stat_bars_position: Control
@export var stat_bars_container: Container
@export var unit_battle_details_ui: UnitDetailsBattleUi
@export var icon2: Sprite3D
@export var icon_cycle_time: float = 1.25
var is_cycling_status_icons: bool = false

@export var tile_highlights: Node3D
var can_move: bool = true
var is_back_facing: bool = false
var is_in_air: bool = false
var is_traveling_path: bool = false

var hp_stat_bar: StatBar
var mp_stat_bar: StatBar
var ct_stat_bar: StatBar


static func instantiate() -> UnitActor:
	return UNIT_SCENE.instantiate()


func _ready() -> void:
	hp_stat_bar = add_stat_bar()
	hp_stat_bar.show_value = true
	
	mp_stat_bar = add_stat_bar()
	mp_stat_bar.fill_color = Color.INDIAN_RED
	mp_stat_bar.show_value = true

	ct_stat_bar = add_stat_bar()
	ct_stat_bar.visual_max = 100.0
	ct_stat_bar.fill_color = Color.WEB_GREEN
	ct_stat_bar.show_value = true

	start_cycle_status_icons()
	load_game_data()

	if unit_data != null:
		_sync_all_visuals_from_unit_data()
	else:
		bind_unit_data(UnitData.new())


func _process(_delta: float) -> void:
	if not GameData.is_ready:
		return
	
	if char_body.velocity.y != 0 and is_in_air == false:
		is_in_air = true
		unit_data.current_animation_id_fwd = unit_data.mid_jump_animation
	elif char_body.velocity.y == 0 and is_in_air == true:
		is_in_air = false
		unit_data.current_animation_id_fwd = unit_data.current_idle_animation_id
	
	set_base_animation_ptr_id(unit_data.current_animation_id_fwd)


func _physics_process(delta: float) -> void:
	# FFTae (and all non-battles) don't use physics, so this can be turned off
	if battle_manager == null:
		set_physics_process(false)
		return
	
	# Add the gravity.
	if not char_body.is_on_floor():
		char_body.velocity += char_body.get_gravity() * delta
	
	var velocity_horizontal: Vector3 = char_body.velocity
	velocity_horizontal.y = 0
	if velocity_horizontal.length_squared() > 0.01:
		unit_data.update_unit_facing(velocity_horizontal.normalized())
	char_body.move_and_slide()


func bind_unit_data(new_unit_data: UnitData) -> void:	
	if unit_data != new_unit_data and unit_data != null:
		_disconnect_unit_data_signals()
		if unit_data.unit_actor == self:
			unit_data.unit_actor = null
	
	unit_data = new_unit_data
	unit_data.unit_actor = self
	_connect_unit_data_signals()
	
	if is_node_ready():
		_sync_all_visuals_from_unit_data()


func load_game_data() -> void:
	if not GameData.is_ready:
		push_error("GameData is not ready, cannot load unit_actor visuals")
		return
	
	icon2.texture = GameData.get_texture("misc")
	icon2.material_override = icon2.material_override.duplicate()
	icon2.material_override.set_shader_parameter("sprite_texture", GameData.get_texture("misc"))
	icon2.material_override.set_shader_parameter("palette_colors", GameData.palettes["misc"].slice(5 * 16, 6 * 16))
	icon2.material_override.set_shader_parameter("billboard_enabled", true)
	
	animation_manager.wep_texture = GameData.get_texture("wep")
	animation_manager.wep_spritesheet_data = GameData.get_spritesheet_data("wep")
	animation_manager.wep_shp = GameData.get_shp("wep1")
	animation_manager.wep_seq = GameData.get_seq("wep1")
	
	animation_manager.eff_texture = GameData.get_texture("eff")
	animation_manager.eff_spritesheet_data = GameData.get_spritesheet_data("eff")
	animation_manager.eff_shp = GameData.get_shp("eff1")
	animation_manager.eff_seq = GameData.get_seq("eff1")
	
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


func _connect_unit_data_signals() -> void:
	if not unit_data.statuses_updated.is_connected(update_status_visuals):
		unit_data.statuses_updated.connect(update_status_visuals)
	if not unit_data.sprite_changed.is_connected(set_sprite_by_file_name):
		unit_data.sprite_changed.connect(set_sprite_by_file_name)
	if not unit_data.palette_changed.is_connected(_on_palette_changed):
		unit_data.palette_changed.connect(_on_palette_changed)
	if not unit_data.primary_weapon_changed.is_connected(update_primary_weapon_visuals):
		unit_data.primary_weapon_changed.connect(update_primary_weapon_visuals)
	if not unit_data.facing_changed.is_connected(_on_facing_changed):
		unit_data.facing_changed.connect(_on_facing_changed)
	if not unit_data.tile_position_changed.is_connected(_on_tile_position_changed):
		unit_data.tile_position_changed.connect(_on_tile_position_changed)
	if not unit_data.submerged_depth_changed.is_connected(_on_submerged_depth_changed):
		unit_data.submerged_depth_changed.connect(_on_submerged_depth_changed)


func _disconnect_unit_data_signals() -> void:
	if unit_data.statuses_updated.is_connected(update_status_visuals):
		unit_data.statuses_updated.disconnect(update_status_visuals)
	if unit_data.sprite_changed.is_connected(set_sprite_by_file_name):
		unit_data.sprite_changed.disconnect(set_sprite_by_file_name)
	if unit_data.palette_changed.is_connected(_on_palette_changed):
		unit_data.palette_changed.disconnect(_on_palette_changed)
	if unit_data.primary_weapon_changed.is_connected(update_primary_weapon_visuals):
		unit_data.primary_weapon_changed.disconnect(update_primary_weapon_visuals)
	if unit_data.facing_changed.is_connected(_on_facing_changed):
		unit_data.facing_changed.disconnect(_on_facing_changed)
	if unit_data.tile_position_changed.is_connected(_on_tile_position_changed):
		unit_data.tile_position_changed.disconnect(_on_tile_position_changed)
	if unit_data.submerged_depth_changed.is_connected(_on_submerged_depth_changed):
		unit_data.submerged_depth_changed.disconnect(_on_submerged_depth_changed)


func _sync_all_visuals_from_unit_data() -> void:
	if not GameData.is_ready:
		push_error("GameData is not ready, cannot sync visuals from unit_data")
		return
	
	_bind_stat_bars_to_unit_data()
	if unit_battle_details_ui != null:
		unit_battle_details_ui.bind_unit(unit_data)
	
	var sprite_to_load: String = unit_data.spritesheet_file_name
	if sprite_to_load == "" or sprite_to_load == "spritesheet_file_name.spr":
		sprite_to_load = "ramuza"
	set_sprite_by_file_name(sprite_to_load)
	update_primary_weapon_visuals(unit_data.get_primary_weapon())
	update_status_visuals()
	set_position_to_tile()
	_on_facing_changed(unit_data.facing_direction)


func add_stat_bar() -> StatBar:
	var new_stat_bar: StatBar = StatBar.instantiate()
	stat_bars_container.add_child(new_stat_bar)

	return new_stat_bar


func _bind_stat_bars_to_unit_data() -> void:
	_bind_stat_bar(UnitData.StatType.HP, hp_stat_bar)
	_bind_stat_bar(UnitData.StatType.MP, mp_stat_bar)
	_bind_stat_bar(UnitData.StatType.CT, ct_stat_bar)


func _bind_stat_bar(stat_type: UnitData.StatType, stat_bar: StatBar) -> void:
	if unit_data.stats.has(stat_type):
		stat_bar.bind_stat(stat_type, unit_data.stats[stat_type])
	else:
		push_error("unit_data.stats does not have stat_type: " + str(stat_type))


func set_stat_bar_visiblity(new_is_visible: bool, stat_bar_idx: int = -1) -> void:
	if stat_bar_idx == -1:
		stat_bars_position.visible = new_is_visible
		return
	
	stat_bars_container.get_child(stat_bar_idx).visible = new_is_visible


func update_stat_bars_scale(camera_zoom: float) -> void:
	stat_bars_position.scale = Vector2.ONE * 3.775 / camera_zoom


func update_status_visuals() -> void:
	var anim_priority: int = 0
	var shading_priority: int = 0
	var other_type_priority: int = 0
	var spritesheet_priority: int = 0

	var anim_status: StatusEffect
	var current_anim: int = unit_data.current_animation_id_fwd
	var other_type_status: StatusEffect
	var spritesheet_status: StatusEffect
	if unit_data.current_statuses.is_empty():
		if unit_data.current_animation_id_fwd == unit_data.current_idle_animation_id:
			unit_data.current_idle_animation_id = unit_data.idle_walk_animation_id
			set_base_animation_ptr_id(unit_data.current_idle_animation_id)
		else:
			unit_data.current_idle_animation_id = unit_data.idle_walk_animation_id
		
		icon2.region_rect = Rect2i(Vector2i.ZERO, Vector2i.ONE)
		animation_manager.unit_sprites_manager.sprite_primary.modulate = Color.WHITE
		animation_manager.other_type_index = 0
		unit_data.set_sprite_palette_override(-1)
		set_sprite_by_job(unit_data.job_unique_name)
	else:
		for status: StatusEffect in unit_data.current_statuses:
			if status.order >= anim_priority and status.idle_animation_id != -1:
				anim_priority = status.order
				anim_status = status
			
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
			unit_data.palette_id_override = -1
		else:
			animation_manager.other_type_index = other_type_status.other_type_index
		
		# if spritesheet is changing
		if spritesheet_priority == 0 and unit_data.spritesheet_file_name != unit_data.job_data.sprite_name:
			set_base_animation_ptr_id(0) # prevent out of bounds error in case SEQ is also changing
			set_sprite_by_job(unit_data.job_unique_name)
		elif spritesheet_priority != 0:
			set_base_animation_ptr_id(0) # prevent out of bounds error in case SEQ is also changing
			set_sprite_by_file_name(spritesheet_status.spritesheet_file_name)
		
		if anim_priority == 0: # if no statuses set the idle animation (may happen when status is removed)
			if current_anim == unit_data.current_idle_animation_id:
				unit_data.current_idle_animation_id = unit_data.idle_walk_animation_id
				set_base_animation_ptr_id(unit_data.current_idle_animation_id)
			else:
				unit_data.current_idle_animation_id = unit_data.idle_walk_animation_id
		else:
			if current_anim == unit_data.current_idle_animation_id:
				unit_data.current_idle_animation_id = anim_status.idle_animation_id
				set_base_animation_ptr_id(anim_status.idle_animation_id)
			else:
				unit_data.current_idle_animation_id = anim_status.idle_animation_id

		# palette update must come after spritesheet change to make sure palettes are taken from correct spritesheet
		if other_type_priority != 0:
			unit_data.set_sprite_palette_override(unit_data.palette_id + other_type_status.palette_idx_offset)


func animate_start_action(animation_start_id: int, animation_charging_id: int) -> void:
	if animation_start_id != 0:
		set_base_animation_ptr_id(animation_start_id)
		await animation_manager.animation_completed
	
	if animation_charging_id != 0:
		set_base_animation_ptr_id(animation_charging_id)
		var charge_ticks: int = 0
		if unit_data.active_action != null:
			charge_ticks = unit_data.active_action.action.ticks_charge_time
		var charge_time: float = 0.1 + (charge_ticks * 0.1)
		await Utilities.wait_seconds(charge_time) # TODO allow looping until changed, ie. charging a spell


func animate_execute_action(animation_executing_id: int) -> void:
	if animation_executing_id < 0: # no animation
		push_error("animate_execute_action called with invalid animation_executing_id: " + str(animation_executing_id))
		return
	
	var ability_animation_executing_id: int = animation_executing_id
	if unit_data.is_lucavi():
		ability_animation_executing_id = 0x2c * 2 # https://ffhacktics.com/wiki/Set_attack_animation_flags_and_facing_3
	set_base_animation_ptr_id(ability_animation_executing_id)
	
	await animation_manager.animation_completed # TODO change based on vfx timing data?
	
	var current_animation: int = unit_data.current_animation_id_fwd
	if current_animation == animation_executing_id:
		animate_return_to_idle()


func animate_take_hit() -> void:
	var hit_anim_id: int = unit_data.taking_damage_animation_id
	set_base_animation_ptr_id(hit_anim_id)


func animate_recieve_heal() -> void:
	var heal_anim_id: int = unit_data.heal_animation_id
	set_base_animation_ptr_id(heal_anim_id)


func return_to_idle_from_hit() -> void:
	var hit_anim_id: int = unit_data.taking_damage_animation_id
	var heal_anim_id: int = unit_data.heal_animation_id
	var current_animation: int = unit_data.current_animation_id_fwd
	if [hit_anim_id, heal_anim_id].has(current_animation):
		animate_return_to_idle()


func animate_evade(evade_animation_fwd_id: int) -> void:
	set_base_animation_ptr_id(evade_animation_fwd_id)
	
	await animation_manager.animation_completed
	
	var current_animation: int = unit_data.current_animation_id_fwd
	if current_animation == evade_animation_fwd_id:
		animate_return_to_idle()


func animate_knock_out() -> void:
	unit_data.current_idle_animation_id = unit_data.knocked_out_animation_id
	set_base_animation_ptr_id(unit_data.knocked_out_animation_id)


func animate_return_to_idle() -> void:
	# add random delay to prevent unit animations from syncing
	var desync_delay: float = randf_range(0.0, 0.25)
	await Utilities.wait_seconds(desync_delay)
	
	var idle_anim_id: int = unit_data.current_idle_animation_id
	set_base_animation_ptr_id(idle_anim_id)


func set_base_animation_ptr_id(ptr_id: int) -> void:
	unit_data.current_animation_id_fwd = ptr_id
	var new_ptr: int = ptr_id
	if is_back_facing and new_ptr > 5:
		new_ptr = ptr_id + 1
	elif is_back_facing and new_ptr > 0: # handle facing frames 
		new_ptr = ptr_id + 2
	else:
		new_ptr = ptr_id # null animation
	
	if animation_manager.global_animation_ptr_id != new_ptr:
		animation_manager.global_animation_ptr_id = new_ptr


func update_animation_facing(camera_facing_vector: Vector3) -> void:
	var unit_facing_vector: Vector3 = unit_data.get_facing_vector()
	
	var unit_facing_angle: float = fposmod(rad_to_deg(atan2(unit_facing_vector.z, unit_facing_vector.x)), 359.99)
	var camera_facing_angle: float = fposmod(rad_to_deg(atan2(-camera_facing_vector.z, -camera_facing_vector.x)), 359.99)
	var facing_difference_angle: float = fposmod(camera_facing_angle - unit_facing_angle, 359.99)
	
	var new_is_right_facing: bool = false
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
			if animation_manager.global_animation_ptr_id < 5:
				back_facing_offset = 2 # there are 5 directions of facing animations, so diagonal front facing id=2 and diagonal back facing id=4
				# TODO utilize the extra facing frames

			if is_back_facing == true:
				animation_manager.global_animation_ptr_id += back_facing_offset
			else:
				animation_manager.global_animation_ptr_id -= back_facing_offset


func _on_palette_changed(_new_palette_id: int, _new_palette_override_id: int) -> void:
	update_spritesheet_grid_texture()


func _on_facing_changed(_new_facing: GameData.Directions) -> void:
	if battle_manager != null and battle_manager.camera_controller != null:
		update_animation_facing(battle_manager.camera_controller.camera_facing_vector)


func _on_tile_position_changed(_new_tile: TerrainTile) -> void:
	set_position_to_tile()


func update_primary_weapon_visuals(primary_weapon: ItemData) -> void:
	if primary_weapon == null:
		animation_manager.unit_sprites_manager.set_weapon_texture(null)
		primary_weapon_assigned.emit("")
		return
	
	var weapon_palette_id: int = primary_weapon.wep_frame_palette
	var weapon_eff_id: int = primary_weapon.wep_eff_palette
	var weapon_grid_texture: ImageTexture = animation_manager.wep_spritesheet_data.create_frame_grid_texture(
		0, 0, primary_weapon.wep_frame_v_offset, 0, animation_manager.wep_shp.file_name
	)
	animation_manager.unit_sprites_manager.set_weapon_texture(weapon_grid_texture)
	animation_manager.unit_sprites_manager.sprite_weapon.material_override.set_shader_parameter(
		"palette_colors", GameData.get_spritesheet_data("wep").color_palette.slice(weapon_palette_id * 16, (weapon_palette_id + 1) * 16)
	)
	animation_manager.unit_sprites_manager.sprite_effect.material_override.set_shader_parameter(
		"palette_colors", GameData.get_spritesheet_data("eff").color_palette.slice(weapon_eff_id * 16, (weapon_eff_id + 1) * 16)
	)
	primary_weapon_assigned.emit(primary_weapon.unique_name)


func start_cycle_status_icons() -> void:
	var status_idx: int = 0
	is_cycling_status_icons = true
	while is_cycling_status_icons:
		if unit_data != null:
			var status: StatusEffect = null
			if not unit_data.current_statuses.is_empty():
				status_idx = (status_idx + 1) % unit_data.current_statuses.size()
				status = unit_data.current_statuses[status_idx]
				var rect: Rect2i = status.get_icon_rect()
				icon2.region_rect = rect
			else:
				status_idx = 0
		
		await Utilities.wait_seconds(icon_cycle_time)


func set_sprite_by_file_idx(new_sprite_file_idx: int) -> void:
	var spr: Spr = RomReader.sprs[new_sprite_file_idx]
	var spr_name: String = spr.file_name.to_lower().trim_suffix(".spr")
	unit_data.set_sprite_by_file_name(spr_name)


func set_sprite_by_file_name(new_spritesheet_name: String) -> void:
	unit_data.spritesheet_file_name = new_spritesheet_name
	var shp: Shp = GameData.get_spritesheet_data(new_spritesheet_name).get_shp()
	var animation_changed: bool = false
	if shp.file_name == "type2":
		if animation_manager.wep_shp.file_name != "wep2":
			animation_manager.wep_shp = GameData.get_shp("wep2")
			var current_weapon: ItemData = unit_data.get_primary_weapon()
			update_primary_weapon_visuals(current_weapon)
			animation_changed = true
		animation_manager.wep_seq = GameData.get_seq("wep2")
	
	var seq: Seq = GameData.get_spritesheet_data(new_spritesheet_name).get_seq()
	if shp != animation_manager.global_shp or seq != animation_manager.global_seq:
		animation_changed = true
	
	# animation_manager.global_spr = spr
	var new_spritesheet_data: UnitSpritesheetData = GameData.get_spritesheet_data(new_spritesheet_name)
	if animation_manager.global_spritesheet_data == null:
		animation_changed = true
	elif new_spritesheet_data.is_flying != animation_manager.global_spritesheet_data.is_flying:
		animation_changed = true
	animation_manager.global_spritesheet_data = new_spritesheet_data
	animation_manager.global_shp = shp
	animation_manager.global_seq = seq

	if animation_manager.global_spritesheet_data.is_flying:
		unit_data.idle_walk_animation_id = 0x0c
		unit_data.walk_to_animation_id = 0x1e
	else:
		unit_data.idle_walk_animation_id = 0x06
		unit_data.walk_to_animation_id = 0x18
	
	var num_sp2s: int = min(0, (GameData.get_texture(new_spritesheet_name).get_height() - 488)) / 256
	if new_spritesheet_name == "wep":
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 32
	else:
		animation_manager.unit_sprites_manager.sprite_primary.vframes = 16 + (16 * num_sp2s)
	update_spritesheet_grid_texture()

	if animation_changed:
		animation_manager.on_animation_changed()


func set_sprite_by_id(new_sprite_id: int) -> void:
	var new_sprite_file_idx: int = RomReader.spr_id_file_idxs[new_sprite_id]
	set_sprite_by_file_idx(new_sprite_file_idx)


func set_sprite_by_job(new_job_name: String) -> void:
	if not GameData.job_paths.has(new_job_name):
		push_warning("set_sprite_by_job called with invalid job name: " + new_job_name)
		return

	var new_job_data: JobData = GameData.get_job(new_job_name)
	
	var sprite_name: String = new_job_data.sprite_name
	var stat_basis: UnitData.StatBasis = unit_data.stat_basis
	if (new_job_data.job_id >= 0x4a and new_job_data.job_id <= 0x5a or new_job_data.job_id == 0x5d) and stat_basis == UnitData.StatBasis.FEMALE:
		sprite_name = sprite_name.replace("_m", "_w")
	set_sprite_by_file_name(sprite_name)

	var new_palette_idx: int = new_job_data.default_palette_idx
	if new_job_data.default_palette_idx == -1: # get random team palette if job doesn't have a default palette
		new_palette_idx = randi_range(0, 4)

	unit_data.set_sprite_palette(new_palette_idx)


func modulate_sprite_color(new_modulate_color: Color) -> void:
	animation_manager.unit_sprites_manager.sprite_primary.modulate = new_modulate_color


func set_sprite_tint(tint: Vector3) -> void:
	animation_manager.unit_sprites_manager.set_tint(tint)


func _on_submerged_depth_changed(_new_depth: int) -> void:
	update_spritesheet_grid_texture()


func update_spritesheet_grid_texture() -> void:
	var sprite_name: String = unit_data.spritesheet_file_name
	if sprite_name == "" or sprite_name == "spritesheet_file_name.spr":
		sprite_name = "ramuza"
	var new_spritesheet_data: UnitSpritesheetData = GameData.get_spritesheet_data(sprite_name)
	var palette_idx_final: int = unit_data.palette_id_override
	if unit_data.palette_id_override < 0:
		palette_idx_final = unit_data.palette_id
	var depth: int = unit_data.submerged_depth
	var new_grid_texture: Texture2D = new_spritesheet_data.create_frame_grid_texture(
		0, animation_manager.other_type_index, 0, depth
	)
	animation_manager.unit_sprites_manager.set_primary_texture(new_grid_texture)
	animation_manager.unit_sprites_manager.sprite_primary.material_override.set_shader_parameter(
		"palette_colors", new_spritesheet_data.color_palette.slice(palette_idx_final * 16, (palette_idx_final + 1) * 16)
	)

	spritesheet_changed.emit(new_grid_texture)


func set_position_to_tile() -> void:
	var map_tile: TerrainTile = unit_data.terrain_tile_position
	if map_tile == null:
		push_warning("unit_data.terrain_tile_position is null, cannot set unit_actor position for unit: " + str(unit_data.unit_unique_name))
		return
	char_body.global_position = Vector3(
		map_tile.xz_location.x + 0.5,
		map_tile.get_world_position().y + 0.25,
		map_tile.xz_location.y + 0.5
	)


func _on_character_body_3d_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	unit_input_event.emit(self, event)

	# show UnitActor preview ui - hp, mp, evade, equipment, statuses, status immunities, element affinity, etc. portrait/mini sprite?
	if Input.is_action_just_pressed("secondary_action"):
		unit_battle_details_ui.visible = !unit_battle_details_ui.visible
