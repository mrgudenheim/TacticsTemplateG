class_name TrapEffectData

## TRAP particle effect system — melee hit dust, charge shimmer, earth claw, etc.
## 17 emitter configs baked into BATTLE.BIN + texture from WEP.SPR TRAP1 section.

# BATTLE.BIN offsets (RAM addr - 0x67000, matching battle_bin_data.gd pattern)
const FRAMES_OFFSET: int = 0x1b7690 - 0x67000
const ANIMATIONS_OFFSET: int = 0x1b8320 - 0x67000
const ELEMENT_RGB_OFFSET: int = 0x1b84C0 - 0x67000
const PARTICLE_CONFIGS_OFFSET: int = 0x1b8564 - 0x67000
const GRAVITY_OFFSET: int = 0x1b8a40 - 0x67000
const INERTIA_OFFSET: int = 0x1b8a4c - 0x67000

const NUM_EMITTERS: int = 17
const EMITTER_CONFIG_SIZE: int = 0x2E # 46 bytes
const NUM_ANIMATIONS: int = 17
const NUM_ELEMENTS: int = 9

# WEP.SPR TRAP1 texture offsets
const TRAP1_PALETTE_OFFSET: int = 0x10400
const TRAP1_PALETTE_SIZE: int = 512
const TRAP1_PIXEL_OFFSET: int = 0x10600
const TRAP1_PIXEL_SIZE: int = 0x4800

# TRAP1 sits at Y=112 within PSX texture page (256-144), UVs are relative to page origin
const TRAP1_VRAM_Y_OFFSET: int = 112

# BSS (runtime-initialized) fallback values from PSX RAM captures
const BSS_GRAVITY_RAW := Vector3i(0, 4096, 0)
const BSS_INERTIA_THRESHOLD: int = 560

const FRAME_DATA_SIZE: int = 0x18 # 24 bytes per frame

const EMITTER_NAMES: Dictionary = {
	0: "dust",
	1: "flash_throwstone",
	2: "earth_claw",
	3: "pulsing_glow",
	4: "explosion_burst",
	5: "dense_sparkle",
	6: "cloud_puff_alt",
	7: "golden_orbs",
	8: "shimmer_glow",
	9: "flash_melee",
	10: "fast_burst",
	11: "scattered_dots",
	12: "sparse_sparkle",
	13: "small_sparkle",
	14: "pulsing_pair",
	15: "medium_puff",
	16: "beam",
}

# Handler index → config indices (aligned to PSX g_charge_effect_handlers[] func_id)
const HANDLER_CONFIGS: Dictionary = {
	2: [0, 1, 9],               # hit clouds (melee + ranged) — PSX func_id 2
	3: [16],                     # earth claw thing — PSX func_id 3
	# 4: intercepted by HANDLER_SPELL_CHARGE (lines + config 12 sparkles)
	6: [10],                     # Charge+X particles — PSX func_id 6
	8: [6],                      # dust puff
	9: [7],                      # splash — PSX func_id 9
	12: [8],                     # poison bubbles — PSX func_id 12
	13: [5],                     # something sparkles — PSX func_id 13
	15: [4],                     # monster death cloud — PSX func_id 15
	17: [3],                     # rising blue sparkle cluster
	19: [15],                    # teleport
	21: [11],                    # knight break (overbright white triangles, palette 10)
	22: [14],                    # summon charge orbs
}

enum DirectionMode { NONE, DIRECTIONAL, FACING }
enum VelocityMode { SPHERICAL_RANDOM, SCATTER, DIRECTIONAL, FACING_DIRECTIONAL, ZERO }

const HANDLER_GROUP_NAMES: Dictionary = {
	2: "Hit Clouds",
	3: "Earth Claw Thing",
	4: "Spell Charge Lines",
	6: "Charge+X",
	8: "Dust Puff",
	9: "Splash",
	12: "Poison Bubbles",
	13: "Something Sparkles",
	15: "Monster Death Cloud",
	17: "Rising Blue Sparkle Cluster",
	18: "Plain Charge Lines",
	19: "Teleport",
	21: "Knight Break",
	22: "Summon Charge Orbs",
}

const ELEMENT_NAMES: PackedStringArray = [
	"None", "Fire", "Lightning", "Ice", "Wind",
	"Earth", "Water", "Holy", "Dark"
]

# Named handler IDs (sorted by handler ID, each with its palette)
const HANDLER_HIT_MELEE: int = 2
const HANDLER_HIT_RANGED: int = 2   # PSX func_id 2 handles both melee and ranged
const HANDLER_EARTH_CLAW: int = 3
const EARTH_CLAW_PALETTE_ID: int = 13  # CLUT 0x7ACD
const HANDLER_SPELL_CHARGE: int = 4
const HANDLER_CHARGE_X: int = 6     # PSX func_id 6
const CHARGE_X_PALETTE_ID: int = 11  # CLUT 0x7ACB
const HANDLER_DUST_PUFF: int = 8
const DUST_PUFF_PALETTE_ID: int = 9   # CLUT 0x7AC9
const HANDLER_SPLASH: int = 9
const SPLASH_PALETTE_ID: int = 11  # CLUT 0x7ACB
const HANDLER_POISON_BUBBLES: int = 12
const POISON_BUBBLES_PALETTE_ID: int = 12  # CLUT 0x7ACC
const HANDLER_SOMETHING_SPARKLES: int = 13
const SOMETHING_SPARKLES_PALETTE_ID: int = 11  # CLUT 0x7ACB
const HANDLER_DEATH_CLOUD: int = 15
const DEATH_CLOUD_PALETTE_ID: int = 15  # CLUT 0x7ACF
const HANDLER_BLUE_SPARKLE_CLUSTER: int = 17
# Element → palette for handler 17 (PSX DAT_801b88dc + 0x7AC0)
# Elements 1-5 get unique palettes; 6-8 and 0 fall back to palette 0
const ELEMENT_PARTICLE_PALETTES: Dictionary = {
	1: 10,   # Fire → CLUT 0x7ACA
	2: 11,   # Lightning → CLUT 0x7ACB
	3: 12,   # Ice → CLUT 0x7ACC
	4: 13,   # Wind → CLUT 0x7ACD
	5: 14,   # Earth → CLUT 0x7ACE
}
const HANDLER_TELEPORT: int = 19
const TELEPORT_PALETTE_ID: int = 11  # CLUT 0x7ACB
const HANDLER_PLAIN_CHARGE: int = 18
const HANDLER_KNIGHT_BREAK: int = 21
const KNIGHT_BREAK_PALETTE_ID: int = 10  # CLUT 0x7ACA
const HANDLER_ORBITAL: int = 22
const ORBITAL_PALETTE_ID: int = 12  # CLUT 0x7ACC (applied per-emitter, not via HANDLER_PALETTE_OVERRIDES)

# Handlers where ALL emitters use a single palette (overrides element_id)
const HANDLER_PALETTE_OVERRIDES: Dictionary = {
	HANDLER_EARTH_CLAW: EARTH_CLAW_PALETTE_ID,  # 3 -> 13
	HANDLER_CHARGE_X: CHARGE_X_PALETTE_ID,   # 6 -> 11
	HANDLER_DUST_PUFF: DUST_PUFF_PALETTE_ID,   # 8 -> 9
	HANDLER_SPLASH: SPLASH_PALETTE_ID,  # 9 -> 11
	HANDLER_POISON_BUBBLES: POISON_BUBBLES_PALETTE_ID,  # 12 -> 12
	HANDLER_SOMETHING_SPARKLES: SOMETHING_SPARKLES_PALETTE_ID,  # 13 -> 11
	HANDLER_DEATH_CLOUD: DEATH_CLOUD_PALETTE_ID,  # 15 -> 15
	HANDLER_TELEPORT: TELEPORT_PALETTE_ID,  # 19 -> 11
	HANDLER_KNIGHT_BREAK: KNIGHT_BREAK_PALETTE_ID,  # 21 -> 10
}

# Handlers that trigger white flash on the target unit sprite
const FLASH_HANDLER_IDS: PackedInt32Array = [HANDLER_HIT_MELEE]

static func element_type_to_trap_id(el: Action.ElementTypes) -> int:
	match el:
		Action.ElementTypes.FIRE: return 1
		Action.ElementTypes.LIGHTNING: return 2
		Action.ElementTypes.ICE: return 3
		Action.ElementTypes.WIND: return 4
		Action.ElementTypes.EARTH: return 5
		Action.ElementTypes.WATER: return 6
		Action.ElementTypes.HOLY: return 7
		Action.ElementTypes.DARK: return 8
		_: return 0


static func get_element_color(p_element_id: int) -> Color:
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	if p_element_id >= 0 and p_element_id < trap_data.element_colors.size():
		return trap_data.element_colors[p_element_id]
	return Color.WHITE


class TrapEmitter:
	const FLAG_DIRECTIONAL: int = 0x400
	const FLAG_FACING: int = 0x010
	const FLAG_DIRECTIONAL_AND_FACING: int = FLAG_DIRECTIONAL | FLAG_FACING # 0x410
	const FLAG_VELOCITY_ZERO: int = 0x1000

	var index: int = 0
	var name: String = ""
	var anim_index: int = 0
	var spawn_check_lo: int = 0
	var spawn_check_hi: int = 0
	var max_particles: int = 0
	var direction_mode: DirectionMode = DirectionMode.NONE
	var velocity_mode: VelocityMode = VelocityMode.SPHERICAL_RANDOM
	var pos_scatter: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO # spawn ellipsoid
	var vel_range: Vector3 = Vector3.ZERO # radians
	var scatter_half_range: Vector3 = Vector3.ZERO # radians
	var weight_min: int = 0
	var weight_max: int = 0
	var radius_min: int = 0 # signed: negative = fly away
	var radius_max: int = 0
	var spawn_rate: int = 0
	var spawn_count: int = 0
	var lifetime_min: int = 0 # -1 = animation-driven
	var lifetime_max: int = 0

	func _init(config_bytes: PackedByteArray, emitter_index: int) -> void:
		index = emitter_index
		name = EMITTER_NAMES.get(emitter_index, "config_%d" % emitter_index)
		_parse_raw(config_bytes)
		_convert_units(config_bytes)

	func _parse_raw(config_bytes: PackedByteArray) -> void:
		anim_index = config_bytes.decode_u8(0x00)
		spawn_check_lo = config_bytes.decode_u8(0x02)
		spawn_check_hi = config_bytes.decode_u8(0x03)
		max_particles = config_bytes.decode_u8(0x04)

		# Direction flags
		var direction_flags: int = config_bytes.decode_u16(0x06)
		if direction_flags & FLAG_DIRECTIONAL_AND_FACING == FLAG_DIRECTIONAL_AND_FACING:
			direction_mode = DirectionMode.FACING
		elif direction_flags & FLAG_DIRECTIONAL:
			direction_mode = DirectionMode.DIRECTIONAL
		else:
			direction_mode = DirectionMode.NONE

		# Velocity mode flags
		var velocity_mode_flags: int = config_bytes.decode_u16(0x08)
		if velocity_mode_flags & FLAG_VELOCITY_ZERO:
			velocity_mode = VelocityMode.ZERO
		elif velocity_mode_flags & FLAG_DIRECTIONAL_AND_FACING == FLAG_DIRECTIONAL_AND_FACING:
			velocity_mode = VelocityMode.FACING_DIRECTIONAL
		elif velocity_mode_flags & FLAG_DIRECTIONAL:
			velocity_mode = VelocityMode.DIRECTIONAL
		elif velocity_mode_flags & FLAG_FACING:
			velocity_mode = VelocityMode.SCATTER
		else:
			velocity_mode = VelocityMode.SPHERICAL_RANDOM

		weight_min = config_bytes.decode_s16(0x22)
		weight_max = config_bytes.decode_s16(0x24)
		radius_min = config_bytes.decode_s16(0x26)
		radius_max = config_bytes.decode_s16(0x28)
		spawn_rate = config_bytes.decode_u8(0x2A)
		spawn_count = config_bytes.decode_u8(0x2B)
		lifetime_min = config_bytes.decode_s8(0x2C)
		lifetime_max = config_bytes.decode_s8(0x2D)

	func _convert_units(config_bytes: PackedByteArray) -> void:
		# Position scatter (/ POSITION_DIVISOR, Y-flip)
		pos_scatter = Vector3(
			config_bytes.decode_s16(0x0A) / VfxEmitter.POSITION_DIVISOR,
			-config_bytes.decode_s16(0x0C) / VfxEmitter.POSITION_DIVISOR,
			config_bytes.decode_s16(0x0E) / VfxEmitter.POSITION_DIVISOR)

		# Velocity = spawn position ellipsoid (/ POSITION_DIVISOR, Y-flip)
		velocity = Vector3(
			config_bytes.decode_s16(0x10) / VfxEmitter.POSITION_DIVISOR,
			-config_bytes.decode_s16(0x12) / VfxEmitter.POSITION_DIVISOR,
			config_bytes.decode_s16(0x14) / VfxEmitter.POSITION_DIVISOR)

		# Vel range (radians)
		vel_range = Vector3(
			config_bytes.decode_s16(0x16) * VfxEmitter.ANGLE_TO_RADIANS,
			config_bytes.decode_s16(0x18) * VfxEmitter.ANGLE_TO_RADIANS,
			config_bytes.decode_s16(0x1A) * VfxEmitter.ANGLE_TO_RADIANS)

		# Scatter half range (radians, unsigned)
		scatter_half_range = Vector3(
			config_bytes.decode_u16(0x1C) * VfxEmitter.ANGLE_TO_RADIANS,
			config_bytes.decode_u16(0x1E) * VfxEmitter.ANGLE_TO_RADIANS,
			config_bytes.decode_u16(0x20) * VfxEmitter.ANGLE_TO_RADIANS)


# Parsed data
var gravity_raw: Vector3i = Vector3i.ZERO
var gravity: Vector3 = Vector3.ZERO
var inertia_threshold: int = 0
var emitters: Array[TrapEmitter] = []
var framesets: Array[VisualEffectData.VfxFrameSet] = []
var animations: Array[VisualEffectData.VfxAnimation] = []
var element_colors: Array[Color] = []
var texture: Texture2D
var textures_by_palette: Dictionary[int, Texture2D] = {}
var trap_spr: Spr


func init_from_rom() -> void:
	var battle_bytes: PackedByteArray = RomReader.get_file_data("BATTLE.BIN")
	var wep_bytes: PackedByteArray = RomReader.get_file_data("WEP.SPR")

	if battle_bytes.size() == 0 or wep_bytes.size() == 0:
		push_warning("TrapEffectData: missing BATTLE.BIN or WEP.SPR data")
		return

	# 1. Gravity + inertia
	# These values live in BSS (runtime-initialized) memory on PSX — the static
	# BATTLE.BIN file has zeros at these addresses. Hardcode from runtime captures:
	#   gravity = (0, 4096, 0) in PSX coords (Y-down), inertia_threshold = 560
	#   damping factor = (4096 - 560) / 4096 ≈ 0.863
	var file_gravity_raw := Vector3i(
		battle_bytes.decode_s32(GRAVITY_OFFSET),
		battle_bytes.decode_s32(GRAVITY_OFFSET + 4),
		battle_bytes.decode_s32(GRAVITY_OFFSET + 8))
	var file_inertia: int = battle_bytes.decode_s32(INERTIA_OFFSET)

	if file_gravity_raw == Vector3i.ZERO:
		# BSS — use known runtime values
		gravity_raw = BSS_GRAVITY_RAW
		inertia_threshold = BSS_INERTIA_THRESHOLD
	else:
		gravity_raw = file_gravity_raw
		inertia_threshold = file_inertia

	gravity = Vector3(
		gravity_raw.x / VfxEmitter.ACCEL_DIVISOR,
		-gravity_raw.y / VfxEmitter.ACCEL_DIVISOR,
		gravity_raw.z / VfxEmitter.ACCEL_DIVISOR)

	# 2. Emitter configs (17 × 46 bytes)
	emitters.resize(NUM_EMITTERS)
	for i: int in NUM_EMITTERS:
		var cfg_start: int = PARTICLE_CONFIGS_OFFSET + i * EMITTER_CONFIG_SIZE
		var cfg_bytes: PackedByteArray = battle_bytes.slice(cfg_start, cfg_start + EMITTER_CONFIG_SIZE)
		emitters[i] = TrapEmitter.new(cfg_bytes, i)

	# 3. Frames (identical format to E###.BIN)
	var frames_data: PackedByteArray = battle_bytes.slice(FRAMES_OFFSET, ANIMATIONS_OFFSET)
	_parse_frames(frames_data)

	# 4. Animations (17 sequences)
	var anim_section_end: int = ELEMENT_RGB_OFFSET
	var anim_data: PackedByteArray = battle_bytes.slice(ANIMATIONS_OFFSET, anim_section_end)
	_parse_animations(anim_data)

	# 5. Element RGB (9 × 3 bytes)
	element_colors.resize(NUM_ELEMENTS)
	for i: int in NUM_ELEMENTS:
		var offset: int = ELEMENT_RGB_OFFSET + i * 3
		element_colors[i] = Color8(
			battle_bytes.decode_u8(offset),
			battle_bytes.decode_u8(offset + 1),
			battle_bytes.decode_u8(offset + 2))

	# 6. TRAP1 texture from WEP.SPR
	_create_trap_texture(wep_bytes)

	# 7. Normalize frame UVs
	if trap_spr != null:
		for frameset_idx: int in framesets.size():
			for frame_idx: int in framesets[frameset_idx].frameset.size():
				var vfx_frame: VisualEffectData.VfxFrame = framesets[frameset_idx].frameset[frame_idx]
				vfx_frame.quad_uvs.resize(vfx_frame.quad_uvs_pixels.size())
				for vert_idx: int in vfx_frame.quad_uvs_pixels.size():
					vfx_frame.quad_uvs[vert_idx] = Vector2(
						vfx_frame.quad_uvs_pixels[vert_idx].x / float(trap_spr.width),
						vfx_frame.quad_uvs_pixels[vert_idx].y / float(trap_spr.height))


func _parse_frames(data: PackedByteArray) -> void:
	if data.size() < 4:
		return

	var group_count: int = data.decode_u8(0)
	var group_entries_end: int = 4 + group_count * 2

	if group_entries_end >= data.size():
		return

	# First frameset offset tells us where frame data starts
	var first_offset: int = data.decode_u16(group_entries_end)
	var frame_sets_data_start: int = first_offset + 4
	@warning_ignore("integer_division")
	var max_frame_sets: int = (frame_sets_data_start - group_entries_end) / 2

	if max_frame_sets <= 0 or max_frame_sets > 500:
		return

	# Count valid offset table entries
	var num_frame_sets: int = 0
	for i: int in max_frame_sets:
		var offset_pos: int = group_entries_end + i * 2
		if offset_pos + 2 > data.size():
			break
		var raw_offset: int = data.decode_u16(offset_pos)
		if raw_offset < first_offset:
			break
		num_frame_sets += 1

	framesets.resize(num_frame_sets)

	for fs_idx: int in num_frame_sets:
		var offset_pos: int = group_entries_end + fs_idx * 2
		var raw_offset: int = data.decode_u16(offset_pos)
		var fs_offset: int = raw_offset + 4

		if fs_offset + 4 > data.size():
			break

		var frame_set: VisualEffectData.VfxFrameSet = VisualEffectData.VfxFrameSet.new()
		frame_set.flags = data.decode_u16(fs_offset)
		var frame_count: int = data.decode_u16(fs_offset + 2)

		if frame_count <= 0 or frame_count > 100:
			framesets[fs_idx] = frame_set
			continue

		frame_set.num_frames = frame_count
		frame_set.frameset.resize(frame_count)

		for frame_idx: int in frame_count:
			var frame_offset: int = fs_offset + 4 + frame_idx * FRAME_DATA_SIZE
			if frame_offset + FRAME_DATA_SIZE > data.size():
				break

			var frame_bytes: PackedByteArray = data.slice(frame_offset, frame_offset + FRAME_DATA_SIZE)
			var new_frame: VisualEffectData.VfxFrame = VisualEffectData.VfxFrame.new()
			new_frame.parse_vram_bytes(frame_bytes)
			new_frame.parse_geometry_bytes(frame_bytes, TRAP1_VRAM_Y_OFFSET)

			frame_set.frameset[frame_idx] = new_frame

		framesets[fs_idx] = frame_set


func _parse_animations(data: PackedByteArray) -> void:
	if data.size() < NUM_ANIMATIONS * 2:
		return

	# Read offset table (17 × u16)
	var offsets: PackedInt32Array = []
	offsets.resize(NUM_ANIMATIONS)
	for i: int in NUM_ANIMATIONS:
		offsets[i] = data.decode_u16(i * 2)

	animations.resize(NUM_ANIMATIONS)
	for i: int in NUM_ANIMATIONS:
		var animation: VisualEffectData.VfxAnimation = VisualEffectData.VfxAnimation.new()
		var seq_offset: int = offsets[i]

		if seq_offset + 2 > data.size():
			animations[i] = animation
			continue

		var total_entries: int = data.decode_u16(seq_offset)

		for j: int in total_entries:
			var entry_offset: int = seq_offset + 2 + j * 2
			if entry_offset + 2 > data.size():
				break

			var duration: int = data.decode_u8(entry_offset)
			var frame_index: int = data.decode_u8(entry_offset + 1)

			var anim_frame: VisualEffectData.VfxAnimationFrame = VisualEffectData.VfxAnimationFrame.new()
			anim_frame.frameset_id = frame_index
			anim_frame.duration = duration
			anim_frame.byte_02 = 1 # PULL_FORWARD_8 depth mode (standard for TRAP)
			animation.animation_frames.append(anim_frame)

		# Append loop marker
		var loop_frame: VisualEffectData.VfxAnimationFrame = VisualEffectData.VfxAnimationFrame.new()
		loop_frame.frameset_id = VisualEffectData.ANIM_OPCODE_LOOP
		animation.animation_frames.append(loop_frame)

		animations[i] = animation


func _create_trap_texture(wep_bytes: PackedByteArray) -> void:
	if wep_bytes.size() < TRAP1_PIXEL_OFFSET + TRAP1_PIXEL_SIZE:
		push_warning("TrapEffectData: WEP.SPR too small for TRAP1 data")
		return

	trap_spr = Spr.new("TRAP1.SPR")
	trap_spr.width = 256
	trap_spr.height = 144
	trap_spr.bits_per_pixel = 4
	trap_spr.has_compressed = false
	trap_spr.num_pixels = trap_spr.width * trap_spr.height

	var palette_bytes: PackedByteArray = wep_bytes.slice(TRAP1_PALETTE_OFFSET, TRAP1_PALETTE_OFFSET + TRAP1_PALETTE_SIZE)
	trap_spr.set_palette_data(palette_bytes)

	var pixel_bytes: PackedByteArray = wep_bytes.slice(TRAP1_PIXEL_OFFSET, TRAP1_PIXEL_OFFSET + TRAP1_PIXEL_SIZE)
	trap_spr.color_indices = trap_spr.set_color_indices(pixel_bytes)
	trap_spr.set_pixel_colors()
	trap_spr.spritesheet = trap_spr.get_rgba8_image()

	texture = ImageTexture.create_from_image(trap_spr.spritesheet)
	textures_by_palette[0] = texture


func get_palette_texture(palette_id: int) -> Texture2D:
	if textures_by_palette.has(palette_id):
		return textures_by_palette[palette_id]
	if trap_spr == null:
		return texture
	trap_spr.set_pixel_colors(palette_id)
	var img: Image = trap_spr.get_rgba8_image()
	var tex: Texture2D = ImageTexture.create_from_image(img)
	textures_by_palette[palette_id] = tex
	return tex
