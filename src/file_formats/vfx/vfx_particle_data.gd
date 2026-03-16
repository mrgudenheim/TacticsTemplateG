class_name VfxParticleData
extends RefCounted
## Per-particle state (RefCounted, no scene tree)

# Diagnostic: unique ID for duplicate detection
static var _uid_counter: int = 0
var uid: int = 0

# Position and velocity (Godot units)
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var acceleration: Vector3 = Vector3.ZERO
var drag: Vector3 = Vector3.ZERO

# Physics parameters (raw values for formula)
var inertia: float = 1.0
var weight: float = 0.0

# Homing
var homing_strength: float = 0.0
var homing_target: Vector3 = Vector3.ZERO
var homing_curve_index: int = -1

# Lifetime
var age: int = 0
var lifetime: int = 60
var animation_complete: bool = false  # Set when hitting terminal frame with lifetime=-1
var animation_held: bool = false      # Set when hitting terminal frame with lifetime>0

# State
var active: bool = false
var emitter_index: int = -1
var channel_index: int = 0  # Timeline channel for Z-ordering

# Child emitters
var child_emitter_on_death: int = VfxConstants.NO_CHILD_EMITTER
var child_emitter_mid_life: int = VfxConstants.NO_CHILD_EMITTER

# Animation state
var anim_index: int = 0
var anim_frame: int = 0
var anim_time: int = 0
var anim_offset: Vector2 = Vector2.ZERO

# Pre-computed render state (set by animator.tick each physics frame)
var current_frameset: int = 0
var current_depth_mode: int = 0
var color_modulate: float = 1.0


func initialize(
	pos: Vector3,
	vel: Vector3,
	life: int,
	emitter_idx: int,
	child_death: int = -1,
	child_mid: int = -1
) -> void:
	position = pos
	velocity = vel
	lifetime = life
	emitter_index = emitter_idx
	child_emitter_on_death = child_death
	child_emitter_mid_life = child_mid

	_uid_counter += 1
	uid = _uid_counter

	age = 0
	active = true
	animation_complete = false
	animation_held = false
	acceleration = Vector3.ZERO
	drag = Vector3.ZERO
	homing_strength = 0.0
	homing_target = Vector3.ZERO
	homing_curve_index = -1

	anim_frame = 0
	anim_time = 0
	anim_offset = Vector2.ZERO
	current_frameset = 0
	current_depth_mode = 0
	color_modulate = 1.0


func is_dead() -> bool:
	if lifetime == -1:
		return animation_complete
	else:
		return age >= lifetime


func deactivate() -> void:
	active = false
