# ffhacktics.com/wiki/BATTLE.BIN_Data_Tables
class_name BattleBinData

var sounds_whoosh_start: int = 0x2cd40
var sounds_hit_start: int = 0x2cd60
var sounds_deflection_start: int = 0x2cd80


var ability_animation_charging_sets_start: int = 0x2cde8 # 20 entries, 2 bytes each
var ability_animation_start_ids: PackedInt32Array = [] # multiplied by 2 (+1 if unit is backfacing) to get animation_ptr_id
var ability_animation_charging_ids: PackedInt32Array = [] # multiplied by 2 (+1 if unit is backfacing) to get animation_ptr_id

var ability_animation_ids_start: int = 0x2ce10 # 1 byte each, 3 bytes per entry
var ability_animation_charging_set_ids: PackedInt32Array = [] # index into ability_animation_start_ids and ability_animation_charging_ids
var ability_animation_executing_ids: PackedInt32Array = [] # multiplied by 2 (+1 if unit is backfacing) to get animation_ptr_id
var ability_animation_text_ids: PackedInt32Array = [] # index into BATTLE_ACTION_EFFECT text

var weapon_animation_ids_start: int = 0x2d364 # 3 bytes per entry, 1 entry per item type
var weapon_animation_ids: PackedVector3Array = [] # attack high, mid, low - multiplied by 2 (+1 if unit is backfacing) to get true animation, Fists/Unarmed used by MON

var weapon_graphic_data_start: int = 0x2d3e4
var weapon_graphic_palettes: PackedInt32Array = [] # 0xF0 - WEP1 Palette, 0x0F - EFF Palette
var weapon_eff_palettes: PackedInt32Array = [] # 0xF0 - WEP1 Palette, 0x0F - EFF Palette
var weapon_frames_vertical_offsets: PackedInt32Array = [] # WEP.SHP vertical offsets

var animation_layer_priorities_start: int = 0x2d548 # 4 uint32 per entry, 0x1b entries? maybe only 0x17?
var animation_layer_priorities: PackedVector4Array = []

var shp_subframe_sizes_start: int = 0x2d6c8 # 8 bytes each, two uint32 per entry, 16 entries
var shp_subframe_sizes: PackedVector2Array = []

var spritesheet_data_start: int = 0x2d748 # 4 bytes each
var spritesheet_shp_id: PackedInt32Array = [] # Type 1, 2, cyoko, mon, other, ruka, arute, kanzen
var spritesheet_seq_id: PackedInt32Array = [] 
var spritesheet_flying: PackedByteArray = [] # bool
var spritesheet_graphic_height: PackedInt32Array = [] # pixels

var targeted_front_frame_id_start: int = 0x2d9c4 # 0x0c entries, 1 byte each, index is seq type?
var targeted_front_frame_id: PackedInt32Array = []
var targeted_back_frame_id_start: int = 0x2d9d0 # 0x0c entries
var targeted_back_frame_id: PackedInt32Array = []

var ability_vfx_header_offsets_start: int = 0x14d8d0 # 511 entries, 8 bytes each, 2 uint32 each
var ability_vfx_header_offsets: PackedInt32Array = [] 

var ability_vfx_ids_start: int = 0x14f3f0 # 2 bytes each - uint16
var ability_vfx_ids: PackedInt32Array = [] 

# Projectile model offsets in BATTLE.BIN
const PROJECTILE_MODEL_OFFSETS: Dictionary = {
	0: 0x14F9DC,  # Arrow
	1: 0x14FD00,  # Stone
	2: 0x1503B8,  # Special (shuriken)
}
var projectile_model_data: Dictionary = {}  # model_id int -> {"vertices": Array[Vector3], "faces": Array}

# https://ffhacktics.com/wiki/Secondary_effects_by_Charge_Animation
var charging_vfx_ids_start: int = 0x1b84ac - 0x67000 # 1 byte each, 0x13 total
var charging_vfx_ids: PackedInt32Array = []

# https://ffhacktics.com/wiki/Effect_Data
var shared_vfx_handler_data_start: int = 0x1b84dc - 0x67000 # 4 byte each, 0x16 entries
var shared_vfx_handler_ids: PackedInt32Array = [] # 1 byte

var status_image_rects_start: int = 0x14cf68 - 0x67000 # 4 bytes each, 49 entries, mostly text + sword and rod icon
var status_image_rects: Array[Rect2i] = []

var status_bubble_locations_x_start: int = 0x949dc - 0x67000 # 22 bytes long, 1 byte each
var status_bubble_locations_y_start: int = 0x949f4 - 0x67000 # 22 bytes long, 1 byte each
var status_icon_locations: Array[Vector2i] = []
var status_icon_rects: Array[Rect2i] = []

var status_counter_locations_x_start: int = 0x94a0c - 0x67000 # 4 bytes long, 1 byte each
var status_counter_locations_y_start: int = 0x94a24 - 0x67000 # 4 bytes long, 1 byte each
var status_counter_locations: Array[Vector2i] = []
var status_counter_rects: Array[Rect2i] = []

var ai_status_priority_start: int = 0x19f308 - 0x67000 # 40 entries, 2 bytes each, signed int16s
var ai_status_priorities: PackedInt32Array = []

func init_from_battle_bin(rom_reader: RomReader) -> void:
	var battle_bytes: PackedByteArray = rom_reader.get_file_data("BATTLE.BIN")
	
	# ability animation charging sets
	var entry_size: int = 2 # bytes
	var num_entries: int = 20
	var ability_animation_charging_sets_bytes: PackedByteArray = battle_bytes.slice(ability_animation_charging_sets_start, ability_animation_charging_sets_start + (num_entries * entry_size))
	ability_animation_start_ids.resize(num_entries)
	ability_animation_charging_ids.resize(num_entries)
	for set_id: int in num_entries:
		ability_animation_start_ids[set_id] = ability_animation_charging_sets_bytes.decode_u8(set_id * entry_size)
		ability_animation_charging_ids[set_id] = ability_animation_charging_sets_bytes.decode_u8((set_id * entry_size) + 1)
	
	# ability animations
	entry_size = 3 # bytes
	var ability_animation_id_bytes: PackedByteArray = battle_bytes.slice(ability_animation_ids_start, ability_animation_ids_start + (RomReader.NUM_ACTIVE_ABILITIES * entry_size))
	ability_animation_charging_set_ids.resize(RomReader.NUM_ACTIVE_ABILITIES)
	ability_animation_executing_ids.resize(RomReader.NUM_ACTIVE_ABILITIES)
	ability_animation_text_ids.resize(RomReader.NUM_ACTIVE_ABILITIES)
	for ability_id: int in RomReader.NUM_ACTIVE_ABILITIES:
		ability_animation_charging_set_ids[ability_id] = ability_animation_id_bytes.decode_u8(ability_id * entry_size)
		ability_animation_executing_ids[ability_id] = ability_animation_id_bytes.decode_u8((ability_id * entry_size) + 1)
		ability_animation_text_ids[ability_id] = ability_animation_id_bytes.decode_u8((ability_id * entry_size) + 2)

	# charging vfx ids (maps charge animation set to TRAP handler index)
	var num_charge_entries: int = 0x14
	charging_vfx_ids.resize(num_charge_entries)
	var charge_data: PackedByteArray = battle_bytes.slice(charging_vfx_ids_start, charging_vfx_ids_start + num_charge_entries)
	for idx: int in num_charge_entries:
		charging_vfx_ids[idx] = charge_data.decode_u8(idx)

	num_entries = 0x16
	shared_vfx_handler_ids.resize(num_entries)
	var shared_vfx_handler_data: PackedByteArray = battle_bytes.slice(shared_vfx_handler_data_start, shared_vfx_handler_data_start + (num_entries * 4))
	for idx: int in num_entries:
		shared_vfx_handler_ids[idx] = shared_vfx_handler_data.decode_u8(idx * 4) # first byte (out of 4) is the handler id

	# weapon animation ids - low, mid, high
	entry_size = 3
	num_entries = ItemData.ItemType.CLOTH + 1
	weapon_animation_ids.resize(num_entries)
	var data_bytes: PackedByteArray = battle_bytes.slice(weapon_animation_ids_start, weapon_animation_ids_start + (num_entries * entry_size))
	for id: int in num_entries:
		var data_start: int = id * entry_size
		weapon_animation_ids[id] = Vector3(
			data_bytes.decode_u8(data_start),
			data_bytes.decode_u8(data_start + 1),
			data_bytes.decode_u8(data_start + 2)
		)
	
	# ability vfx header offsets
	entry_size = 4
	num_entries = RomReader.NUM_VFX
	data_bytes = battle_bytes.slice(ability_vfx_header_offsets_start, ability_vfx_header_offsets_start + (num_entries * entry_size))
	ability_vfx_header_offsets.resize(RomReader.NUM_VFX)
	for id: int in num_entries:
		ability_vfx_header_offsets[id] = data_bytes.decode_u32(id * entry_size) - 0x801c2500
	
	# ability vfx
	entry_size = 2
	var ability_vfx_id_bytes: PackedByteArray = battle_bytes.slice(ability_vfx_ids_start, ability_vfx_ids_start + (RomReader.NUM_ACTIVE_ABILITIES * entry_size))
	ability_vfx_ids.resize(RomReader.NUM_ACTIVE_ABILITIES)
	for ability_id: int in RomReader.NUM_ACTIVE_ABILITIES:
		ability_vfx_ids[ability_id] = ability_vfx_id_bytes.decode_u16(ability_id * entry_size)
	
	# TODO get vfx_ids for items, reactions (support and movement don't have vfx)
	
	# weapon/shield shp frame vertical offsets and palettes
	entry_size = 2
	num_entries = 0x90
	weapon_graphic_palettes.resize(num_entries) # 0xF0 - WEP1 Palette, 0x0F - WEP2 Palette
	weapon_eff_palettes.resize(num_entries) # 0xF0 - WEP1 Palette, 0x0F - WEP2 Palette
	weapon_frames_vertical_offsets.resize(num_entries)
	data_bytes = battle_bytes.slice(weapon_graphic_data_start, weapon_graphic_data_start + (num_entries * entry_size))
	for id: int in num_entries:
		weapon_graphic_palettes[id] = (data_bytes.decode_u8(id * entry_size) & 0xf0) >> 4
		weapon_eff_palettes[id] = data_bytes.decode_u8(id * entry_size) & 0x0f
		weapon_frames_vertical_offsets[id] = data_bytes.decode_u8((id * entry_size) + 1) * 8
	
	# WEP and EFF subframe sizes
	entry_size = 8 # two uint32
	num_entries = 16
	shp_subframe_sizes.resize(num_entries)
	data_bytes = battle_bytes.slice(shp_subframe_sizes_start, shp_subframe_sizes_start + (num_entries * entry_size))
	for id: int in num_entries:
		shp_subframe_sizes[id] = Vector2(data_bytes.decode_u32(id * entry_size), data_bytes.decode_u32((id * entry_size) + 4)) * 8
	
	# being targeted frame ids
	entry_size = 1
	num_entries = 12
	targeted_front_frame_id.resize(num_entries)
	targeted_back_frame_id.resize(num_entries)
	data_bytes = battle_bytes.slice(targeted_front_frame_id_start, targeted_front_frame_id_start + (num_entries * entry_size * 2)) # *2 to get both front and back tables at once
	for id: int in num_entries:
		targeted_front_frame_id[id] = data_bytes.decode_u8(id * entry_size)
		targeted_back_frame_id[id] = data_bytes.decode_u8((id * entry_size) + (targeted_back_frame_id_start - targeted_front_frame_id_start))
	
	# spritesheet shp, seq, flying, height data
	entry_size = 4
	num_entries = RomReader.NUM_SPRITESHEETS
	spritesheet_shp_id.resize(num_entries) # Type 1, 2, cyoko, mon, other, ruka, arute, kanzen
	spritesheet_seq_id.resize(num_entries) # Type 1, 2, cyoko, mon, other, ruka, arute, kanzen
	spritesheet_flying.resize(num_entries) # bool
	spritesheet_graphic_height.resize(num_entries) # pixels
	data_bytes = battle_bytes.slice(spritesheet_data_start, spritesheet_data_start + (num_entries * entry_size))
	for idx: int in num_entries:
		spritesheet_shp_id[idx] = data_bytes.decode_u8(idx * entry_size)
		spritesheet_seq_id[idx] = data_bytes.decode_u8((idx * entry_size) + 1)
		spritesheet_flying[idx] = data_bytes.decode_u8((idx * entry_size) + 2)
		spritesheet_graphic_height[idx] = data_bytes.decode_u8((idx * entry_size) + 3)
	
	
	# animation layer priority table
	entry_size = 16
	num_entries = 0x1b
	animation_layer_priorities.resize(num_entries)
	data_bytes = battle_bytes.slice(animation_layer_priorities_start, animation_layer_priorities_start + (num_entries * entry_size))
	for idx: int in num_entries:
		animation_layer_priorities[idx].w = data_bytes.decode_u32(idx * entry_size)
		animation_layer_priorities[idx].x = data_bytes.decode_u32((idx * entry_size) + 4)
		animation_layer_priorities[idx].y = data_bytes.decode_u32((idx * entry_size) + 8)
		animation_layer_priorities[idx].z = data_bytes.decode_u32((idx * entry_size) + 12)
	
	_load_battle_bin_sprite_data(rom_reader)
	
	# ai status priority table
	entry_size = 2
	num_entries = 40
	ai_status_priorities.resize(num_entries)
	data_bytes = battle_bytes.slice(ai_status_priority_start, ai_status_priority_start + (num_entries * entry_size))
	for idx: int in num_entries:
		ai_status_priorities[idx] = data_bytes.decode_s16(idx * entry_size)
	
	# status icon locations
	entry_size = 1
	num_entries = 22
	status_icon_locations.resize(num_entries)
	status_icon_rects.resize(num_entries)
	var data_bytes_x: PackedByteArray = battle_bytes.slice(status_bubble_locations_x_start, status_bubble_locations_x_start + (num_entries * entry_size))
	var data_bytes_y: PackedByteArray = battle_bytes.slice(status_bubble_locations_y_start, status_bubble_locations_y_start + (num_entries * entry_size))
	for idx: int in num_entries:
		var x: int = data_bytes_x.decode_u8(idx * entry_size)
		var y: int = data_bytes_y.decode_u8(idx * entry_size)
		status_icon_locations[idx] = Vector2i(x, y)
		status_icon_rects[idx] = Rect2i(Vector2i(x, y + 32), Vector2i(14, 12)) # y + 32 because image is 288 pixels tall (288-256 = 32), TODO KO stars are 16 wide
	
	# status counter locations
	entry_size = 1
	num_entries = 4
	status_counter_locations.resize(num_entries)
	status_counter_rects.resize(num_entries)
	data_bytes_x = battle_bytes.slice(status_counter_locations_x_start, status_counter_locations_x_start + (num_entries * entry_size))
	data_bytes_y = battle_bytes.slice(status_counter_locations_y_start, status_counter_locations_y_start + (num_entries * entry_size))
	for idx: int in num_entries:
		var x: int = data_bytes_x.decode_u8(idx * entry_size)
		var y: int = data_bytes_y.decode_u8(idx * entry_size)
		status_counter_locations[idx] = Vector2i(x, y)
		status_counter_rects[idx] = Rect2i(Vector2i(x, y + 32), Vector2i(14, 12)) # y + 32 because image is 288 pixels tall (288-256 = 32)
	
	# Projectile models
	_parse_projectile_models(battle_bytes)

	# TODO all the other battle.bin data
	


# https://ffhacktics.com/wiki/BATTLE.BIN_Data_Tables#Animation_.26_Display_Related_Data
func _load_battle_bin_sprite_data(rom_reader: RomReader) -> void:
	var battle_bytes: PackedByteArray = rom_reader.get_file_data("BATTLE.BIN")
	
	# look up spr file_name based on LBA
	var spritesheet_file_data_length: int = 8
	for sprite_id: int in RomReader.NUM_SPRITESHEETS:
		var spritesheet_file_data_start: int = 0x2dcd4 + (sprite_id * spritesheet_file_data_length)
		var spritesheet_file_data_bytes: PackedByteArray = battle_bytes.slice(spritesheet_file_data_start, spritesheet_file_data_start + spritesheet_file_data_length)
		var spritesheet_lba: int = spritesheet_file_data_bytes.decode_u32(0)
		var spritesheet_file_name: String = ""
		if spritesheet_lba != 0:
			spritesheet_file_name = rom_reader.lba_to_file_name[spritesheet_lba]
		rom_reader.spr_file_name_to_id[spritesheet_file_name] = sprite_id
		rom_reader.spr_id_file_idxs[sprite_id] = rom_reader.file_records[spritesheet_file_name].type_index


func _parse_projectile_models(battle_bytes: PackedByteArray) -> void:
	for model_id: int in PROJECTILE_MODEL_OFFSETS:
		var offset: int = PROJECTILE_MODEL_OFFSETS[model_id]
		projectile_model_data[model_id] = _parse_projectile_model(battle_bytes, offset)


func _parse_projectile_model(data: PackedByteArray, offset: int) -> Dictionary:
	# Header: vertex_offset at byte 12 (relative), vertex_count at byte 16
	var vertex_offset_rel: int = data.decode_u32(offset + 12)
	var vertex_count: int = data.decode_u32(offset + 16)
	var vertex_offset_abs: int = offset + 12 + vertex_offset_rel

	# Parse vertices (8 bytes each: s16 x, s16 y, s16 z, s16 flags)
	var vertices: Array[Vector3] = []
	for i: int in range(vertex_count):
		var v_off: int = vertex_offset_abs + (i * 8)
		vertices.append(Vector3(data.decode_s16(v_off), data.decode_s16(v_off + 2), data.decode_s16(v_off + 4)))

	# Parse faces (variable size, start after 40-byte header)
	var faces: Array = []
	var face_offset: int = offset + 40
	while face_offset < vertex_offset_abs - 8:
		var face_type: int = data[face_offset]
		var num_verts: int
		var color_start: int
		var index_start: int
		var face_size: int
		var type_str: String

		if face_type == 0x08:  # Quad (28 bytes)
			num_verts = 4
			color_start = face_offset + 4
			index_start = face_offset + 20
			face_size = 28
			type_str = "q"
		elif face_type == 0x06:  # Triangle (24 bytes)
			num_verts = 3
			color_start = face_offset + 4
			index_start = face_offset + 16
			face_size = 24
			type_str = "t"
		elif face_type == 0x09:  # Triangle + normals (36 bytes)
			num_verts = 3
			color_start = face_offset + 16  # After 4-byte header + 12-byte normals
			index_start = face_offset + 28
			face_size = 36
			type_str = "t"
		else:
			break

		var colors: Array = []
		for c: int in range(num_verts):
			var co: int = color_start + (c * 4)
			colors.append([data[co], data[co + 1], data[co + 2]])

		var indices: Array = []
		for idx: int in range(num_verts):
			indices.append(data.decode_u16(index_start + (idx * 2)))

		faces.append([indices, colors, type_str])
		face_offset += face_size

	return {"vertices": vertices, "faces": faces}
