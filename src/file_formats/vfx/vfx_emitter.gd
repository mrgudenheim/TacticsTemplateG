class_name VfxEmitter
extends RefCounted

## Unit conversion constants (FFT raw → Godot units)
## These match godot-learning/tools/transform_for_godot.py
const POSITION_DIVISOR: float = 28.0           ## FFT world units → Godot tile units
const VELOCITY_DIVISOR: float = 14336.0        ## raw → Godot units/frame
const ACCEL_DIVISOR: float = 114688.0          ## raw → Godot units/frame² (4096 * 28)
const ANGLE_TO_RADIANS: float = TAU / 4096.0   ## 0-4096 → radians

var vfx_data: VisualEffectData
var anim_index: int
var motion_type_flag: int
var align_to_velocity: bool = false
var target_anchor_mode: int = 0
var animation_target_flag: int
var spread_mode: int = 0
var emitter_anchor_mode: int = 0
var frameset_group_index: int
# byte_05 unused
var emitter_flags: int = 0 # bytes 0x06 and 0x07
var child_death_mode: int = 0
var child_midlife_mode: int = 0
var is_velocity_inward: bool = false
var enable_color_curve: bool = false

var velocity_mode: int = 0

# curves
var interpolation_curve_indicies: Dictionary[int, int] = {
	VfxConstants.CurveParam.POSITION: 0,
	VfxConstants.CurveParam.PARTICLE_SPREAD: 0,
	VfxConstants.CurveParam.VELOCITY_ANGLE: 0,
	VfxConstants.CurveParam.VELOCITY_ANGLE_SPREAD: 0,
	VfxConstants.CurveParam.INERTIA: 0,
	VfxConstants.CurveParam.WEIGHT: 0,
	VfxConstants.CurveParam.RADIAL_VELOCITY: 0,
	VfxConstants.CurveParam.ACCELERATION: 0,
	VfxConstants.CurveParam.DRAG: 0,
	VfxConstants.CurveParam.PARTICLE_LIFETIME: 0,
	VfxConstants.CurveParam.TARGET_OFFSET: 0,
	VfxConstants.CurveParam.PARTICLE_COUNT: 0,
	VfxConstants.CurveParam.SPAWN_INTERVAL: 0,
	VfxConstants.CurveParam.HOMING_STRENGTH: 0,
	VfxConstants.CurveParam.HOMING_CURVE: 0,
	VfxConstants.CurveParam.COLOR_R: 0,
	VfxConstants.CurveParam.COLOR_G: 0,
	VfxConstants.CurveParam.COLOR_B: 0,
}

var start_position: Vector3 = Vector3.ZERO
var end_position: Vector3 = Vector3.ZERO

var start_position_spread: Vector3 = Vector3.ZERO
var end_position_spread: Vector3 = Vector3.ZERO

var start_angle: Vector3 = Vector3.ZERO
var end_angle: Vector3 = Vector3.ZERO

var start_angle_spread: Vector3 = Vector3.ZERO
var end_angle_spread: Vector3 = Vector3.ZERO

var inertia_min_start: int = 0
var inertia_max_start: int = 0
var inertia_min_end: int = 0
var inertia_max_end: int = 0

var weight_min_start: int = 0
var weight_max_start: int = 0
var weight_min_end: int = 0
var weight_max_end: int = 0

var radial_velocity_min_start: int = 0
var radial_velocity_max_start: int = 0
var radial_velocity_min_end: int = 0
var radial_velocity_max_end: int = 0

var acceleration_min_start: Vector3 = Vector3.ZERO
var acceleration_max_start: Vector3 = Vector3.ZERO
var acceleration_min_end: Vector3 = Vector3.ZERO
var acceleration_max_end: Vector3 = Vector3.ZERO

var drag_min_start: Vector3 = Vector3.ZERO
var drag_max_start: Vector3 = Vector3.ZERO
var drag_min_end: Vector3 = Vector3.ZERO
var drag_max_end: Vector3 = Vector3.ZERO

var particle_lifetime_min_start: int = 0
var particle_lifetime_max_start: int = 0
var particle_lifetime_min_end: int = 0
var particle_lifetime_max_end: int = 0

var target_offset_start: Vector3 = Vector3.ZERO
var target_offset_end: Vector3 = Vector3.ZERO

var particle_count_start: int = 0
var particle_count_end: int = 0

var spawn_interval_start: int = 0
var spawn_interval_end: int = 0

var homing_strength_min_start: int = 0
var homing_strength_max_start: int = 0
var homing_strength_min_end: int = 0
var homing_strength_max_end: int = 0

var child_emitter_idx_on_death: int = 0
var child_emitter_idx_on_interval: int = 0

## Converted fields (Godot units, matching godot-learning's EffectEmitter)
## Positions: / 28.0 with Y-flip
var conv_position_start: Vector3 = Vector3.ZERO
var conv_position_end: Vector3 = Vector3.ZERO
var conv_spread_start: Vector3 = Vector3.ZERO
var conv_spread_end: Vector3 = Vector3.ZERO
## Angles: * TAU / 4096.0 (radians)
var conv_angle_start: Vector3 = Vector3.ZERO
var conv_angle_end: Vector3 = Vector3.ZERO
var conv_angle_spread_start: Vector3 = Vector3.ZERO
var conv_angle_spread_end: Vector3 = Vector3.ZERO
## Inertia/weight: cast to float (no unit conversion, used directly in physics formula)
var conv_inertia_min_start: float = 0.0
var conv_inertia_max_start: float = 0.0
var conv_inertia_min_end: float = 0.0
var conv_inertia_max_end: float = 0.0
var conv_weight_min_start: float = 0.0
var conv_weight_max_start: float = 0.0
var conv_weight_min_end: float = 0.0
var conv_weight_max_end: float = 0.0
## Radial velocity: / 14336.0 (signed)
var conv_radial_velocity_min_start: float = 0.0
var conv_radial_velocity_max_start: float = 0.0
var conv_radial_velocity_min_end: float = 0.0
var conv_radial_velocity_max_end: float = 0.0
## Acceleration: / 114688.0 with Y-flip (signed)
var conv_acceleration_min_start: Vector3 = Vector3.ZERO
var conv_acceleration_max_start: Vector3 = Vector3.ZERO
var conv_acceleration_min_end: Vector3 = Vector3.ZERO
var conv_acceleration_max_end: Vector3 = Vector3.ZERO
## Drag: / 114688.0 with Y-flip (signed)
var conv_drag_min_start: Vector3 = Vector3.ZERO
var conv_drag_max_start: Vector3 = Vector3.ZERO
var conv_drag_min_end: Vector3 = Vector3.ZERO
var conv_drag_max_end: Vector3 = Vector3.ZERO
## Target offset: / 28.0 with Y-flip (signed)
var conv_target_offset_start: Vector3 = Vector3.ZERO
var conv_target_offset_end: Vector3 = Vector3.ZERO
## Homing strength: / 114688.0 (signed)
var conv_homing_strength_min_start: float = 0.0
var conv_homing_strength_max_start: float = 0.0
var conv_homing_strength_min_end: float = 0.0
var conv_homing_strength_max_end: float = 0.0

# var color_masking_motion_flags: int # byte 06
# var byte_07: int
# var start_position: Vector3i
# var end_position: Vector3i

func _init(emitter_bytes: PackedByteArray = [], new_vfx_data: VisualEffectData = null):
	if emitter_bytes.size() == 0:
		return
	
	vfx_data = new_vfx_data

	anim_index = emitter_bytes.decode_u8(1)
	
	motion_type_flag = emitter_bytes.decode_u8(2)
	align_to_velocity = motion_type_flag & 0x02 != 0
	target_anchor_mode = motion_type_flag >> 5
	
	animation_target_flag = emitter_bytes.decode_u8(3) 
	spread_mode = animation_target_flag & 1 # 0=sphere, 1=box
	emitter_anchor_mode = (animation_target_flag >> 1) & 7
	# (animation_target_flag >> 4) & 0x0F is unused (handler_index)
	
	frameset_group_index = emitter_bytes.decode_u8(4)
	# byte_05 = bytes.decode_u8(5) # unused
	# color_masking_motion_flags = bytes.decode_u8(6)
	# byte_07 = bytes.decode_u8(7)

	# byte_05 unused
	emitter_flags = emitter_bytes.decode_u16(0x06) # bytes 0x06 and 0x07
	child_death_mode = emitter_flags & 3
	child_midlife_mode = (emitter_flags >> 2) & 3
	is_velocity_inward = (emitter_flags >> 4) & 1 == 1
	enable_color_curve = (emitter_flags >> 6) & 1 == 1

	velocity_mode = emitter_flags & 0x0410

	# curves
	const CP := VfxConstants.CurveParam
	interpolation_curve_indicies[CP.POSITION] = emitter_bytes.decode_u8(0x08) & 0xF # lower nibble
	interpolation_curve_indicies[CP.PARTICLE_SPREAD] = (emitter_bytes.decode_u8(0x08) >> 4) & 0xF # upper nibble
	interpolation_curve_indicies[CP.VELOCITY_ANGLE] = emitter_bytes.decode_u8(0x09) & 0xF # lower nibble
	interpolation_curve_indicies[CP.VELOCITY_ANGLE_SPREAD] = (emitter_bytes.decode_u8(0x09) >> 4) & 0xF # upper nibble
	interpolation_curve_indicies[CP.INERTIA] = emitter_bytes.decode_u8(0x0a) & 0xF # lower nibble
	# byte 0x0a upper nibble not used
	interpolation_curve_indicies[CP.WEIGHT] = emitter_bytes.decode_u8(0x0b) & 0xF # lower nibble
	interpolation_curve_indicies[CP.RADIAL_VELOCITY] = (emitter_bytes.decode_u8(0x0b) >> 4) & 0xF # upper nibble
	interpolation_curve_indicies[CP.ACCELERATION] = emitter_bytes.decode_u8(0x0c) & 0xF # lower nibble
	interpolation_curve_indicies[CP.DRAG] = (emitter_bytes.decode_u8(0x0c) >> 4) & 0xF # upper nibble
	interpolation_curve_indicies[CP.PARTICLE_LIFETIME] = emitter_bytes.decode_u8(0x0d) & 0xF # lower nibble
	interpolation_curve_indicies[CP.TARGET_OFFSET] = (emitter_bytes.decode_u8(0x0d) >> 4) & 0xF # upper nibble
	# byte 0x0e low nibble not used
	interpolation_curve_indicies[CP.PARTICLE_COUNT] = (emitter_bytes.decode_u8(0x0e) >> 4) & 0xF # upper nibble
	interpolation_curve_indicies[CP.SPAWN_INTERVAL] = emitter_bytes.decode_u8(0x0f) & 0xF # lower nibble
	interpolation_curve_indicies[CP.HOMING_STRENGTH] = (emitter_bytes.decode_u8(0x0f) >> 4) & 0x3 # upper nibble 2 bits?
	interpolation_curve_indicies[CP.HOMING_CURVE] = (emitter_bytes.decode_u8(0x0f) >> 6) & 0x3 # upper nibble 2 bits?
	# TODO how is byte 0x0f handled for homing?

	# color curves
	interpolation_curve_indicies[CP.COLOR_R] = emitter_bytes.decode_u8(0x10) & 0xF # lower nibble
	interpolation_curve_indicies[CP.COLOR_G] = (emitter_bytes.decode_u8(0x10) >> 4) & 0xF # upper nibble
	interpolation_curve_indicies[CP.COLOR_B] = emitter_bytes.decode_u8(0x11) & 0xF # lower nibble

	start_position = Vector3(emitter_bytes.decode_s16(0x14), -emitter_bytes.decode_s16(0x16), emitter_bytes.decode_s16(0x18))
	end_position = Vector3(emitter_bytes.decode_s16(0x1a), -emitter_bytes.decode_s16(0x1c), emitter_bytes.decode_s16(0x1e))

	start_position_spread = Vector3(emitter_bytes.decode_s16(0x20), emitter_bytes.decode_s16(0x22), emitter_bytes.decode_s16(0x24))
	end_position_spread = Vector3(emitter_bytes.decode_s16(0x26), emitter_bytes.decode_s16(0x28), emitter_bytes.decode_s16(0x2a))

	start_angle = Vector3(emitter_bytes.decode_u16(0x2c), emitter_bytes.decode_u16(0x2e), emitter_bytes.decode_u16(0x30))
	end_angle = Vector3(emitter_bytes.decode_u16(0x32), emitter_bytes.decode_u16(0x34), emitter_bytes.decode_u16(0x36))

	start_angle_spread = Vector3(emitter_bytes.decode_u16(0x38), emitter_bytes.decode_u16(0x3a), emitter_bytes.decode_u16(0x3c))
	end_angle_spread = Vector3(emitter_bytes.decode_u16(0x3e), emitter_bytes.decode_u16(0x40), emitter_bytes.decode_u16(0x42))

	inertia_min_start = emitter_bytes.decode_u16(0x44)
	inertia_max_start = emitter_bytes.decode_u16(0x46)
	inertia_min_end = emitter_bytes.decode_u16(0x48)
	inertia_max_end = emitter_bytes.decode_u16(0x4a)
	
	# bytes 0x4c - 0x52 not used

	weight_min_start = emitter_bytes.decode_u16(0x54)
	weight_max_start = emitter_bytes.decode_u16(0x56)
	weight_min_end = emitter_bytes.decode_u16(0x58)
	weight_max_end = emitter_bytes.decode_u16(0x5a)

	radial_velocity_min_start = emitter_bytes.decode_u16(0x5c)
	radial_velocity_max_start = emitter_bytes.decode_u16(0x5e)
	radial_velocity_min_end = emitter_bytes.decode_u16(0x60)
	radial_velocity_max_end = emitter_bytes.decode_u16(0x62)

	acceleration_min_start = Vector3(emitter_bytes.decode_u16(0x64), emitter_bytes.decode_u16(0x68), emitter_bytes.decode_u16(0x6c))
	acceleration_max_start = Vector3(emitter_bytes.decode_u16(0x66), emitter_bytes.decode_u16(0x6a), emitter_bytes.decode_u16(0x6e))
	acceleration_min_end = Vector3(emitter_bytes.decode_u16(0x70), emitter_bytes.decode_u16(0x74), emitter_bytes.decode_u16(0x78))
	acceleration_max_end = Vector3(emitter_bytes.decode_u16(0x72), emitter_bytes.decode_u16(0x76), emitter_bytes.decode_u16(0x7a))

	drag_min_start = Vector3(emitter_bytes.decode_u16(0x7c), emitter_bytes.decode_u16(0x80), emitter_bytes.decode_u16(0x84))
	drag_max_start = Vector3(emitter_bytes.decode_u16(0x7e), emitter_bytes.decode_u16(0x82), emitter_bytes.decode_u16(0x86))
	drag_min_end = Vector3(emitter_bytes.decode_u16(0x88), emitter_bytes.decode_u16(0x8c), emitter_bytes.decode_u16(0x90))
	drag_max_end = Vector3(emitter_bytes.decode_u16(0x8a), emitter_bytes.decode_u16(0x8e), emitter_bytes.decode_u16(0x92))

	particle_lifetime_min_start = emitter_bytes.decode_s16(0x94)
	particle_lifetime_max_start = emitter_bytes.decode_s16(0x96)
	particle_lifetime_min_end = emitter_bytes.decode_s16(0x98)
	particle_lifetime_max_end = emitter_bytes.decode_s16(0x9a)

	target_offset_start = Vector3(emitter_bytes.decode_u16(0x9c), emitter_bytes.decode_u16(0x9e), emitter_bytes.decode_u16(0xa0))
	target_offset_end = Vector3(emitter_bytes.decode_u16(0xa2), emitter_bytes.decode_u16(0xa4), emitter_bytes.decode_u16(0xa6))

	# bytes 0xa8 - 0xaf not used

	particle_count_start = emitter_bytes.decode_u16(0xb0)
	particle_count_end = emitter_bytes.decode_u16(0xb2)

	spawn_interval_start = emitter_bytes.decode_u16(0xb4)
	spawn_interval_end = emitter_bytes.decode_u16(0xb6)

	homing_strength_min_start = emitter_bytes.decode_u16(0xb8)
	homing_strength_max_start = emitter_bytes.decode_u16(0xba)
	homing_strength_min_end = emitter_bytes.decode_u16(0xbc)
	homing_strength_max_end = emitter_bytes.decode_u16(0xbe)

	child_emitter_idx_on_death = emitter_bytes.decode_u8(0xc0)
	child_emitter_idx_on_interval = emitter_bytes.decode_u8(0xc1)

	# bytes 0xc2, 0xc3 not used

	_compute_converted_fields(emitter_bytes)


func _compute_converted_fields(emitter_bytes: PackedByteArray) -> void:
	## Position: already Y-flipped in raw parse, divide by 28
	conv_position_start = start_position / POSITION_DIVISOR
	conv_position_end = end_position / POSITION_DIVISOR

	## Spread: / 28 with Y-flip (raw was NOT Y-flipped)
	conv_spread_start = Vector3(
		start_position_spread.x / POSITION_DIVISOR,
		-start_position_spread.y / POSITION_DIVISOR,
		start_position_spread.z / POSITION_DIVISOR)
	conv_spread_end = Vector3(
		end_position_spread.x / POSITION_DIVISOR,
		-end_position_spread.y / POSITION_DIVISOR,
		end_position_spread.z / POSITION_DIVISOR)

	## Angles: * TAU / 4096
	conv_angle_start = start_angle * ANGLE_TO_RADIANS
	conv_angle_end = end_angle * ANGLE_TO_RADIANS
	conv_angle_spread_start = start_angle_spread * ANGLE_TO_RADIANS
	conv_angle_spread_end = end_angle_spread * ANGLE_TO_RADIANS

	## Inertia/weight: re-decode as signed, keep raw value (no unit conversion)
	conv_inertia_min_start = float(emitter_bytes.decode_s16(0x44))
	conv_inertia_max_start = float(emitter_bytes.decode_s16(0x46))
	conv_inertia_min_end = float(emitter_bytes.decode_s16(0x48))
	conv_inertia_max_end = float(emitter_bytes.decode_s16(0x4a))

	conv_weight_min_start = float(emitter_bytes.decode_s16(0x54))
	conv_weight_max_start = float(emitter_bytes.decode_s16(0x56))
	conv_weight_min_end = float(emitter_bytes.decode_s16(0x58))
	conv_weight_max_end = float(emitter_bytes.decode_s16(0x5a))

	## Radial velocity: re-decode as signed / 14336
	conv_radial_velocity_min_start = emitter_bytes.decode_s16(0x5c) / VELOCITY_DIVISOR
	conv_radial_velocity_max_start = emitter_bytes.decode_s16(0x5e) / VELOCITY_DIVISOR
	conv_radial_velocity_min_end = emitter_bytes.decode_s16(0x60) / VELOCITY_DIVISOR
	conv_radial_velocity_max_end = emitter_bytes.decode_s16(0x62) / VELOCITY_DIVISOR

	## Acceleration: re-decode as signed / 114688 with Y-flip
	conv_acceleration_min_start = Vector3(
		emitter_bytes.decode_s16(0x64) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x68) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x6c) / ACCEL_DIVISOR)
	conv_acceleration_max_start = Vector3(
		emitter_bytes.decode_s16(0x66) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x6a) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x6e) / ACCEL_DIVISOR)
	conv_acceleration_min_end = Vector3(
		emitter_bytes.decode_s16(0x70) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x74) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x78) / ACCEL_DIVISOR)
	conv_acceleration_max_end = Vector3(
		emitter_bytes.decode_s16(0x72) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x76) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x7a) / ACCEL_DIVISOR)

	## Drag: re-decode as signed / 114688 with Y-flip
	conv_drag_min_start = Vector3(
		emitter_bytes.decode_s16(0x7c) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x80) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x84) / ACCEL_DIVISOR)
	conv_drag_max_start = Vector3(
		emitter_bytes.decode_s16(0x7e) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x82) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x86) / ACCEL_DIVISOR)
	conv_drag_min_end = Vector3(
		emitter_bytes.decode_s16(0x88) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x8c) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x90) / ACCEL_DIVISOR)
	conv_drag_max_end = Vector3(
		emitter_bytes.decode_s16(0x8a) / ACCEL_DIVISOR,
		-emitter_bytes.decode_s16(0x8e) / ACCEL_DIVISOR,
		emitter_bytes.decode_s16(0x92) / ACCEL_DIVISOR)

	## Target offset: re-decode as signed / 28 with Y-flip
	conv_target_offset_start = Vector3(
		emitter_bytes.decode_s16(0x9c) / POSITION_DIVISOR,
		-emitter_bytes.decode_s16(0x9e) / POSITION_DIVISOR,
		emitter_bytes.decode_s16(0xa0) / POSITION_DIVISOR)
	conv_target_offset_end = Vector3(
		emitter_bytes.decode_s16(0xa2) / POSITION_DIVISOR,
		-emitter_bytes.decode_s16(0xa4) / POSITION_DIVISOR,
		emitter_bytes.decode_s16(0xa6) / POSITION_DIVISOR)

	## Homing strength: re-decode as signed / 114688
	conv_homing_strength_min_start = emitter_bytes.decode_s16(0xb8) / ACCEL_DIVISOR
	conv_homing_strength_max_start = emitter_bytes.decode_s16(0xba) / ACCEL_DIVISOR
	conv_homing_strength_min_end = emitter_bytes.decode_s16(0xbc) / ACCEL_DIVISOR
	conv_homing_strength_max_end = emitter_bytes.decode_s16(0xbe) / ACCEL_DIVISOR
	