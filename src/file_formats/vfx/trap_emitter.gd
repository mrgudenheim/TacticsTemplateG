class_name TrapEmitter
extends Resource

const FLAG_DIRECTIONAL: int = 0x400
const FLAG_FACING: int = 0x010
const FLAG_DIRECTIONAL_AND_FACING: int = FLAG_DIRECTIONAL | FLAG_FACING # 0x410
const FLAG_VELOCITY_ZERO: int = 0x1000

var index: int = 0
@export var name: String = ""
@export var anim_index: int = 0
@export var spawn_check_lo: int = 0
@export var spawn_check_hi: int = 0
@export var max_particles: int = 0
@export var direction_mode: TrapEffectData.DirectionMode = TrapEffectData.DirectionMode.NONE
@export var velocity_mode: TrapEffectData.VelocityMode = TrapEffectData.VelocityMode.SPHERICAL_RANDOM
@export var pos_scatter: Vector3 = Vector3.ZERO
@export var velocity: Vector3 = Vector3.ZERO # spawn ellipsoid
@export var vel_range: Vector3 = Vector3.ZERO # radians
@export var scatter_half_range: Vector3 = Vector3.ZERO # radians
@export var weight_min: int = 0
@export var weight_max: int = 0
@export var radius_min: int = 0 # signed: negative = fly away
@export var radius_max: int = 0
@export var spawn_rate: int = 0
@export var spawn_count: int = 0
@export var lifetime_min: int = 0 # -1 = animation-driven
@export var lifetime_max: int = 0


func init_from_bytes(config_bytes: PackedByteArray, emitter_index: int) -> void:
	index = emitter_index
	name = TrapEffectData.EMITTER_NAMES.get(emitter_index, "config_%d" % emitter_index)
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
		direction_mode = TrapEffectData.DirectionMode.FACING
	elif direction_flags & FLAG_DIRECTIONAL:
		direction_mode = TrapEffectData.DirectionMode.DIRECTIONAL
	else:
		direction_mode = TrapEffectData.DirectionMode.NONE

	# Velocity mode flags
	var velocity_mode_flags: int = config_bytes.decode_u16(0x08)
	if velocity_mode_flags & FLAG_VELOCITY_ZERO:
		velocity_mode = TrapEffectData.VelocityMode.ZERO
	elif velocity_mode_flags & FLAG_DIRECTIONAL_AND_FACING == FLAG_DIRECTIONAL_AND_FACING:
		velocity_mode = TrapEffectData.VelocityMode.FACING_DIRECTIONAL
	elif velocity_mode_flags & FLAG_DIRECTIONAL:
		velocity_mode = TrapEffectData.VelocityMode.DIRECTIONAL
	elif velocity_mode_flags & FLAG_FACING:
		velocity_mode = TrapEffectData.VelocityMode.SCATTER
	else:
		velocity_mode = TrapEffectData.VelocityMode.SPHERICAL_RANDOM

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
