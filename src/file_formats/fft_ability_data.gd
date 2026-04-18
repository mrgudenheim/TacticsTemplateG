class_name FftAbilityData

# https://ffhacktics.com/wiki/Ability_Data
# https://ffhacktics.com/wiki/BATTLE.BIN_Data_Tables#Animation_.26_Display_Related_Data
# https://ffhacktics.com/wiki/Abilities

enum AbilityType {
	NONE,
	NORMAL,
	ITEM,
	THROWING,
	JUMPING,
	AIM,
	MATH_SKILL,
	REACTION,
	SUPPORT,
	MOVEMENT,
	UNKNOWN1,
	UNKNOWN2,
	UNKNOWN3,
	UNKNOWN4,
	UNKNOWN5,
	UNKNOWN6,
}

var id: int = 0
var display_name: String = "ability display_name"
var spell_quote: String = "spell quote"
var description: String = "[ability descirption]"
var jp_cost: int = 0
var chance_to_learn: float = 100 # percent
var ability_type: AbilityType = AbilityType.NORMAL
var learn_with_jp: bool = true
var display_ability_name: bool = true
var learn_on_hit: bool = false
var bit_0x10: bool = false
var ai_flags_1: int = 0
var ai_flags_2: int = 0
var ai_flags_3: int = 0
var ai_flags_4: int = 0

var formula_id: int = 0
var formula_x: int = 0
var formula_y: int = 0
var max_targeting_range: int = 4
var area_of_effect_radius: int = 1
var vertical_tolerance: int = 2
var inflict_status_id: int = 0 # https://ffhacktics.com/wiki/Inflict_Status
var ticks_charge_time: int = 0
var mp_cost: int = 0

var normal_flags_1: int = 0
var force_self_target_1: bool = false
var force_self_target_2: bool = false
var use_weapon_range: bool = false
var linear_range: bool = false
var vertical_tolerance_from_user: bool = false
var weapon_strike: bool = false
var auto_target: bool = false
var cant_target_self: bool = false

var normal_flags_2: int = 0
var cant_hit_enemies: bool = false
var cant_hit_allies: bool = false
var top_down_targeting: bool = false
var cant_follow_target: bool = false
var random_target: bool = false
var linear_aoe: bool = false
var three_direction_aoe: bool = false
var cant_hit_user: bool = false

var normal_flags_3: int = 0
var is_reflectable: bool = false
var usable_by_math: bool = false
var affected_by_silence: bool = false
var cant_mimic: bool = false
var blocked_by_golem: bool = false
var performing: bool = false
var show_quote: bool = false
var animate_on_miss: bool = false

var normal_flags_4: int = 0
var trigger_counter_flood: bool = false
var trigger_counter_magic: bool = false
var stop_at_obstacle: bool = false
var trigger_counter_grasp: bool = false
var require_sword: bool = false
var require_materia_blade: bool = false
var is_evadeable: bool = false
var no_targeting: bool = false

var element_type: Action.ElementTypes = Action.ElementTypes.NONE

var used_item_id: int = -1
var thrown_item_type: int = -1
var jump_range: int = 0
var jump_vert: int = 0
var charge_ct: int = 0
var charge_power: int = 0 # archer charge skills
var math1: int = -1 # 0x80 - CT, 0x40 - Level, 0x20 - Exp, 0x10 - Height
var math2: int = -1 # 0x08 - Prime Number, 0x04 - 5, 0x02 - 4, 0x01 - 3
var rsm_id: int = -1 # RSM Ability ID (numbered from 0x00-0x59)

var animation_charging_set_id: int # BATTLE.BIN offset="2ce10" - table of animations IDs used by Ability ID - byte 1
var animation_start_id: int
var animation_charging_id: int
var animation_executing_id: int # BATTLE.BIN offset="2ce10" - table of animations IDs used by Ability ID - byte 2
var animation_text_id: int # BATTLE.BIN offset="2ce10" - table of animations IDs used by Ability ID - byte 3
var effect_text: String = "ability effect"

var vfx_data: VisualEffectData # BATTLE.BIN offset="14F3F0" - table of Effect IDs used by Ability ID
var vfx_id: int = 0

var animation_speed: float = 59 # frames per second

var ability_action: Action = Action.new()

func _init(new_id: int = 0) -> void:
	id = new_id
	
	display_name = RomReader.fft_text.ability_names[id]
	spell_quote = RomReader.fft_text.spell_quotes[id]
	description = RomReader.fft_text.ability_descriptions[id]
	
	if new_id <= 0x1c5:
		animation_charging_set_id = RomReader.battle_bin_data.ability_animation_charging_set_ids[new_id]
		animation_start_id = RomReader.battle_bin_data.ability_animation_start_ids[animation_charging_set_id] * 2
		animation_charging_id = RomReader.battle_bin_data.ability_animation_charging_ids[animation_charging_set_id] * 2
		animation_executing_id = RomReader.battle_bin_data.ability_animation_executing_ids[new_id] * 2
		animation_text_id = RomReader.battle_bin_data.ability_animation_text_ids[new_id]
		effect_text = RomReader.fft_text.battle_effect_text[animation_text_id]
		vfx_id = RomReader.battle_bin_data.ability_vfx_ids[new_id]
		if [0x11d, 0x11f].has(vfx_id): # Ball
			vfx_data = RomReader.vfx[0] # TODO handle special cases without vfx files, 0x11d (Ball), 0x11f (ability 0x2d)
		elif vfx_id < RomReader.NUM_VFX:
			RomReader.vfx[vfx_id].ability_names += display_name + " "
			vfx_data = RomReader.vfx[vfx_id]
		elif vfx_id == 0xffff:
			vfx_data = RomReader.vfx[0] # TODO handle when vfx_id is 0xffff
		else:
			vfx_data = RomReader.vfx[0]
			#push_warning(vfx_id)
	
	jp_cost = RomReader.scus_data.jp_costs[new_id]
	chance_to_learn = RomReader.scus_data.chance_to_learn[new_id]
	ability_type = RomReader.scus_data.ability_types[new_id]

	if ability_type == AbilityType.NORMAL:
		formula_id = RomReader.scus_data.formula_id[new_id]
		formula_x = RomReader.scus_data.formula_x[new_id]
		formula_y = RomReader.scus_data.formula_y[new_id]
		max_targeting_range = RomReader.scus_data.ranges[new_id]
		area_of_effect_radius = RomReader.scus_data.area_of_effect_radius[new_id]
		vertical_tolerance = RomReader.scus_data.vertical_tolerance[new_id]
		inflict_status_id = RomReader.scus_data.ability_inflict_status_id[new_id]
		ticks_charge_time = RomReader.scus_data.ct[new_id]
	
		normal_flags_1 = RomReader.scus_data.flags1[id]
		normal_flags_2 = RomReader.scus_data.flags2[id]
		normal_flags_3 = RomReader.scus_data.flags3[id]
		normal_flags_4 = RomReader.scus_data.flags4[id]
		set_normal_flags([normal_flags_1, normal_flags_2, normal_flags_3, normal_flags_4])


func set_normal_flags(flag_bytes: PackedInt32Array) -> void:
	force_self_target_1 = normal_flags_1 & 0x80 == 0x80
	force_self_target_2 = normal_flags_1 & 0x40 == 0x40
	use_weapon_range = normal_flags_1 & 0x20 == 0x20
	linear_range = normal_flags_1 & 0x10 == 0x10
	vertical_tolerance_from_user = normal_flags_1 & 0x08 == 0x08
	weapon_strike = normal_flags_1 & 0x04 == 0x04
	auto_target = normal_flags_1 & 0x02 == 0x02
	cant_target_self = normal_flags_1 & 0x01 == 0x01
	
	cant_hit_enemies = normal_flags_2 & 0x80 == 0x80
	cant_hit_allies = normal_flags_2 & 0x40 == 0x40
	top_down_targeting = normal_flags_2 & 0x20 == 0x20
	cant_follow_target = normal_flags_2 & 0x10 == 0x10
	random_target = normal_flags_2 & 0x08 == 0x08
	linear_aoe = normal_flags_2 & 0x04 == 0x04
	three_direction_aoe = normal_flags_2 & 0x02 == 0x02
	cant_hit_user = normal_flags_2 & 0x01 == 0x01
	
	is_reflectable = normal_flags_3 & 0x80 == 0x80
	usable_by_math = normal_flags_3 & 0x40 == 0x40
	affected_by_silence = normal_flags_3 & 0x20 == 0x20
	cant_mimic = normal_flags_3  & 0x10 == 0x10
	blocked_by_golem = normal_flags_3 & 0x08 == 0x08
	performing = normal_flags_3 & 0x04 == 0x04
	show_quote = normal_flags_3 & 0x02 == 0x02
	animate_on_miss = normal_flags_3 & 0x01 == 0x01
	
	trigger_counter_flood = normal_flags_4 & 0x80 == 0x80
	trigger_counter_magic = normal_flags_4 & 0x40 == 0x40
	stop_at_obstacle = normal_flags_4 & 0x20 == 0x20
	trigger_counter_grasp = normal_flags_4 & 0x10 == 0x10
	require_sword = normal_flags_4 & 0x08 == 0x08
	require_materia_blade = normal_flags_4 & 0x04 == 0x04
	is_evadeable = normal_flags_4 & 0x02 == 0x02
	no_targeting = normal_flags_4 & 0x01 == 0x01


func set_action() -> void:
	ability_action.display_name = display_name
	ability_action.add_to_global_list()
	ability_action.description = RomReader.fft_text.ability_descriptions[id]
	ability_action.quote = spell_quote
	ability_action.name_will_display = show_quote
	
	ability_action.targeting_type = Action.TargetingTypes.RANGE
	# ability_action.targeting_strategy = Utilities.targeting_strategies[Utilities.TargetingTypes.RANGE]
	
	ability_action.mp_cost = mp_cost
	
	ability_action.formula_x = formula_x
	ability_action.formula_y = formula_y
	ability_action.min_targeting_range = 0
	ability_action.max_targeting_range = max_targeting_range
	ability_action.area_of_effect_range = area_of_effect_radius
	ability_action.vertical_tolerance = vertical_tolerance
	ability_action.inflict_status_id = inflict_status_id # TODO set status effect data
	ability_action.ticks_charge_time = ticks_charge_time
	
	ability_action.has_vertical_tolerance_from_user = vertical_tolerance_from_user # vertical fixed / linear range
	ability_action.use_weapon_range = use_weapon_range
	ability_action.use_weapon_targeting = use_weapon_range
	ability_action.use_weapon_damage = false # weapon_strike?
	ability_action.use_weapon_animation = weapon_strike or animation_executing_id == 0 # weapon_strike?
	ability_action.auto_target = auto_target
	ability_action.cant_target_self = cant_target_self
	ability_action.cant_hit_enimies = cant_hit_enemies
	ability_action.cant_hit_allies = cant_hit_allies
	ability_action.cant_hit_user = cant_hit_user
	ability_action.targeting_top_down = top_down_targeting
	ability_action.cant_follow_target = cant_follow_target
	ability_action.random_fire = random_target
	ability_action.targeting_linear = linear_range
	ability_action.targeting_los = stop_at_obstacle # stop at obstacle
	ability_action.aoe_has_vertical_tolerance = true # always applies in vanilla
	ability_action.aoe_vertical_tolerance = vertical_tolerance
	ability_action.aoe_targeting_three_directions = three_direction_aoe
	ability_action.aoe_targeting_linear = linear_range
	ability_action.aoe_targeting_los = false # stop at obstacle
	
	ability_action.is_reflectable = is_reflectable
	ability_action.is_math_usable = usable_by_math
	ability_action.is_mimicable = not cant_mimic
	ability_action.blocked_by_golem = blocked_by_golem
	ability_action.repeat_use = performing # performing
	ability_action.vfx_on_empty = animate_on_miss
	
	ability_action.trigger_counter_flood = trigger_counter_flood
	ability_action.trigger_counter_magic = trigger_counter_magic
	ability_action.trigger_counter_grasp = trigger_counter_grasp
	if trigger_counter_grasp:
		ability_action.trigger_types.append(TriggeredAction.TriggerType.PHYSICAL)
	if trigger_counter_magic:
		ability_action.trigger_types.append(TriggeredAction.TriggerType.COUNTER_MAGIC)
	if trigger_counter_flood:
		ability_action.trigger_types.append(TriggeredAction.TriggerType.COUNTER_FLOOD)
	if is_reflectable:
		ability_action.trigger_types.append(TriggeredAction.TriggerType.REFLECTABLE)
	if not cant_mimic:
		ability_action.trigger_types.append(TriggeredAction.TriggerType.MIMIC)
	
	ability_action.can_target = not no_targeting
	
	ability_action.element = element_type
	
	
	
	# inflict status data
	var inflict_status_data: ScusData.InflictStatus = RomReader.scus_data.inflict_statuses[inflict_status_id]
	ability_action.target_status_list = inflict_status_data.status_list
	ability_action.target_status_chance = 100
	ability_action.will_remove_target_status = inflict_status_data.will_cancel
	
	ability_action.all_status = inflict_status_data.is_all
	ability_action.random_status = inflict_status_data.is_random
	ability_action.separate_status = inflict_status_data.is_separate
	if inflict_status_data.is_all:
		ability_action.target_status_list_type = Action.StatusListType.ALL
	elif inflict_status_data.is_random:
		ability_action.target_status_list_type = Action.StatusListType.RANDOM
	elif inflict_status_data.is_separate:
		ability_action.target_status_list_type = Action.StatusListType.EACH
	
	#ability_action.status_prevents_use_any = [
		#1, # crystal
		#2, # dead
		#8, # petrify
		#13, # blood suck
		#15, # treasure
		#20, # berserk
		#21, # chicken
		#22, # frog
		#30, # Stop
		#37, # dont act
	#]
	ability_action.status_prevents_use_any = [
		"crystal",
		"dead", # dead
		"petrify", # petrify
		"blood_suck", # blood suck
		"treasure", # treasure
		"berserk", # berserk
		"chicken", # chicken
		"frog", # frog
		"stop", # Stop
		"don't_act", # dont act
	]
	if affected_by_silence:
		ability_action.status_prevents_use_any.append("silence") # silence
	if require_sword:
		ability_action.required_equipment_type = [ItemData.ItemType.SWORD] # sword, gun, etc.
	if require_materia_blade:
		ability_action.required_equipment_unique_name = ["material_blade"] # materia_blade, etc.
	if not is_reflectable:
		# ability_action.ignores_statuses.append("reflect") # ignore reflect # TODO ignoring Reflect is handled within TriggeredAction
		ability_action.ignore_passives.append("reflect_status")
	
	ability_action.set_data_from_formula_id(formula_id)
	if not is_evadeable: # set after formula
		ability_action.applicable_evasion_type = EvadeData.EvadeType.NONE
	
	if inflict_status_data.is_separate:
		ability_action.target_status_chance = roundi(ability_action.target_status_chance * 0.24)
	
	# animation data
	ability_action.animation_start_id = animation_start_id
	ability_action.animation_charging_id = animation_charging_id
	ability_action.animation_executing_id = animation_executing_id
	
	ability_action.vfx_data = vfx_data
	ability_action.vfx_id = vfx_data.vfx_id

	if animation_charging_set_id < RomReader.battle_bin_data.charging_vfx_ids.size():
		ability_action.trap_hit_handler_id = RomReader.battle_bin_data.charging_vfx_ids[animation_charging_set_id]


func create_ability() -> Ability:
	var new_ability: Ability = Ability.new()

	new_ability.display_name = display_name
	new_ability.description = description

	# name changes
	if display_name == "Equip Knife":
		new_ability.display_name = "Equip Katana"
	elif display_name == "A Save":
		new_ability.display_name = "PA Save"
	elif display_name == "Counter":
		new_ability.display_name = "Counter Attack"
	elif display_name == "Counter Flood":
		new_ability.display_name = "Counter Geomancy"
	elif display_name == "Face Up":
		new_ability.display_name = "Faith Up"
	elif display_name == "Magic DefendUP":
		new_ability.display_name = "Magic Defense Up"
	elif display_name == "Move-Get Exp":
		new_ability.display_name = "Move Get Exp"
	elif display_name == "Move-Get Jp":
		new_ability.display_name = "Move Get Jp"
	elif display_name == "Move-HP Up":
		new_ability.display_name = "Move Get HP"
	elif display_name == "Move-MP Up":
		new_ability.display_name = "Move Get MP"
	elif display_name == "Move-Find Item":
		new_ability.display_name = "Move Find Item"
	elif display_name == "Any Weather":
		new_ability.display_name = "Ignore Weather"
	elif display_name == "Any Ground":
		new_ability.display_name = "Ignore Terrain"
	elif display_name == "Move on Lava":
		new_ability.display_name = "Walk on Lava"
	elif display_name == "Move in Water":
		new_ability.display_name = "Walk on Water"
	elif display_name == "Walk on Water":
		new_ability.display_name = "Swim"
	elif display_name == "Move undrwater":
		new_ability.display_name = "Move Underwater"

	if id == 0x1f1:
		display_name = "Cant enter depth"
		new_ability.display_name = display_name
	
	match ability_type:
		AbilityType.REACTION:
			new_ability.slot_type = Ability.SlotType.REACTION
		AbilityType.SUPPORT:
			new_ability.slot_type = Ability.SlotType.SUPPORT
		AbilityType.MOVEMENT:
			new_ability.slot_type = Ability.SlotType.MOVEMENT

	new_ability.jp_cost = jp_cost
	new_ability.chance_to_learn = chance_to_learn
	new_ability.learn_with_jp = learn_with_jp
	new_ability.display_ability_name = display_ability_name
	new_ability.learn_on_hit = learn_on_hit

	return new_ability



func display_stasis_sword_vfx(location: Node3D) -> void:
	if vfx_id != 163: # TODO handle vfx other than stasis sword
		return
	
	var children: Array[Node] = location.get_children()
	for child: Node in children:
		child.queue_free()
	
	var frame_meshes: Array[ArrayMesh] = []
	for frameset_idx: int in [0, 1, 2, 17, 34, 55, 76, 98, 110]:
		frame_meshes.append(vfx_data.get_frame_mesh(frameset_idx))
	
	for frame_mesh_idx: int in range(2, frame_meshes.size() - 2):
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = frame_meshes[frame_mesh_idx]
		location.add_child(mesh_instance)
		
		mesh_instance.position.y += 5
		var target_pos: Vector3 = Vector3.ZERO
		if frame_mesh_idx == 5:
			target_pos.y -= 15 * MapData.SCALE
		
		# https://docs.godotengine.org/en/stable/classes/class_tween.html
		var tween: Tween = location.create_tween()
		tween.tween_property(mesh_instance, "position", target_pos, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		await location.get_tree().create_timer(0.4).timeout
	
	await location.get_tree().create_timer(0.4).timeout
	
	children = location.get_children() # store current children to remove later
	
	for frame_mesh_idx: int in [0, 1]:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = frame_meshes[frame_mesh_idx]
		location.add_child(mesh_instance)
	
	await location.get_tree().create_timer(0.2).timeout
	
	for child: Node in children:
		child.queue_free()
	
	await location.get_tree().create_timer(0.6).timeout
	
	children = location.get_children()
	for child: Node in children:
		child.queue_free()
	location.queue_free()
