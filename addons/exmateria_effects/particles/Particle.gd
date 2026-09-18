extends RefCounted
## Minimal particle state - all values in Godot units (pre-converted by parser)
## Vault: [[E001.BIN Memory Mapping]]
## Vault: [[Particle Runtime State]]

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
var homing_arrival_threshold: float = 0.0

# Lifetime
var age: int = 0
var lifetime: int = 60
# Terminal frame handling (for lifetime=-1 / animation-driven particles)
var animation_complete: bool = false  # Set when hitting terminal frame with lifetime=-1
var animation_held: bool = false      # Set when hitting terminal frame with lifetime>0

# State
var active: bool = false
var emitter_index: int = -1
var channel_index: int = 0  # Timeline lane identifier (0-4); NOT a Z-order key (see ADR-0015)

# Child emitters
var child_emitter_on_death: int = -1
var child_emitter_mid_life: int = -1

# Animation state
var anim_index: int = 0           # Which animation sequence to play
var anim_frame: int = 0           # Current opcode index in animation
var anim_time: int = 0            # Time spent in current opcode (frames)
var anim_offset: Vector2 = Vector2.ZERO  # Position offset from SET_OFFSET opcode
var frameset_group_offset: int = 0  # Offset into flat frameset array for this particle's group

# Render-ready derivations written by ParticleAnimator.tick() — kept on the
# particle so the renderer reads from one place per particle instead of
# reaching back into the animator. Defaults are valid for an un-ticked particle.
var frameset_idx: int = 0         # Frameset to render this tick (includes frameset_group_offset)
var depth_mode: int = 0           # PSX depth_mode for this tick (STANDARD = 0)


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

	age = 0
	active = true
	animation_complete = false
	animation_held = false
	acceleration = Vector3.ZERO
	drag = Vector3.ZERO
	homing_strength = 0.0
	homing_target = Vector3.ZERO
	homing_curve_index = -1
	homing_arrival_threshold = 0.0

	# Reset animation state
	anim_frame = 0
	anim_time = 0
	anim_offset = Vector2.ZERO
	frameset_group_offset = 0
	frameset_idx = 0
	depth_mode = 0


func is_dead() -> bool:
	if lifetime == -1:
		# Animation-driven: die when animation signals complete
		return animation_complete
	else:
		# Fixed lifetime: die when age reaches lifetime
		return age >= lifetime


func deactivate() -> void:
	active = false
