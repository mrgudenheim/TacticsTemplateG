class_name TrapOrbitalHandler
extends RefCounted
## PSX Handler 22 — Summon charge orb orbital system.
## 3 rings of 10 particles orbit the caster with comet-trail brightness falloff.
## Managed by a ring buffer and per-particle RGB modulation.

enum State { INIT, ORBIT, FADE, DONE }

const RING_COUNT: int = 3
const SLOTS_PER_RING: int = 10
const TOTAL_PARTICLES: int = 30  # 3 × 10
const RING_PHASE_OFFSET: int = 1365  # 0x555 = 120° in PSX 4096-unit circle
const FULL_CIRCLE: int = VfxConstants.PSX_FULL_CIRCLE
const PSX_SCALE: float = 1.0 / VfxEmitter.POSITION_DIVISOR
const ANCHOR_Y_OFFSET: float = 24.0 / 28.0  # 24 PSX units above origin

const BRIGHTNESS_WEIGHTS: PackedInt32Array = [128, 2, 6, 8, 10, 12, 16, 20, 24, 28]

const AUTO_FADE_TICKS: int = 90
const FADE_DURATION: int = 61
const EMITTER_INDEX: int = 14
const PARTICLE_LIFETIME: int = 9999  # Handler manages lifecycle, not particle age

var state: State = State.INIT
var particles: Array[VfxParticleData] = []

# Orbital state
var ring_buffer: Array[Array] = []  # [ring][slot] = Vector3
var write_head: int = 0
var orbital_radius: int = 0
var accumulated_angle: int = 0
var angular_velocity: int = 0
var brightness_scale: int = 0

# Counters
var _frame_counter: int = 0
var fade_counter: int = 0

# Anchor (Godot coordinates)
var anchor: Vector3 = Vector3.ZERO

# Auto-fade
var auto_fade_enabled: bool = true
var orbit_ticks: int = 0


func start(origin: Vector3) -> void:
	anchor = origin + Vector3(0, ANCHOR_Y_OFFSET, 0)

	# Clear orbital state
	write_head = 0
	orbital_radius = 0
	accumulated_angle = 0
	angular_velocity = 0
	brightness_scale = 0
	_frame_counter = 0
	fade_counter = 0
	orbit_ticks = 0

	# Initialize ring buffer: 3 rings × 10 slots, all zero
	ring_buffer.clear()
	for _r in range(RING_COUNT):
		var ring: Array[Vector3] = []
		ring.resize(SLOTS_PER_RING)
		ring.fill(Vector3.ZERO)
		ring_buffer.append(ring)

	# Create 30 particles
	particles.clear()
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	var emitter: TrapEffectData.TrapEmitter = trap_data.emitters[EMITTER_INDEX] if EMITTER_INDEX < trap_data.emitters.size() else null
	for _i in range(TOTAL_PARTICLES):
		var p := VfxParticleData.new()
		p.initialize(anchor, Vector3.ZERO, PARTICLE_LIFETIME, EMITTER_INDEX)
		p.weight = 0.0
		if emitter != null:
			TrapEffectInstance.init_trap_animation(p, emitter, trap_data)
		particles.append(p)

	state = State.ORBIT


func tick() -> void:
	match state:
		State.ORBIT:
			_tick_orbit()
		State.FADE:
			_tick_fade()
		State.DONE, State.INIT:
			return

	_compute_orbital_positions()
	_assign_particle_positions()
	_compute_brightness()
	write_head = (write_head + 1) % SLOTS_PER_RING


func start_fade() -> void:
	if state == State.ORBIT:
		state = State.FADE
		fade_counter = 0


func is_done() -> bool:
	return state == State.DONE


func _tick_orbit() -> void:
	if _frame_counter < 24:
		angular_velocity = _frame_counter * 3
		orbital_radius = _frame_counter

	if _frame_counter < 8:
		brightness_scale = (_frame_counter + 1) * 16

	if _frame_counter < 256:
		_frame_counter += 1

	orbit_ticks += 1
	if auto_fade_enabled and orbit_ticks >= AUTO_FADE_TICKS:
		start_fade()


func _tick_fade() -> void:
	if fade_counter < FADE_DURATION:
		if (fade_counter & 8) != 0:
			orbital_radius += 1
		angular_velocity += 1
		brightness_scale = (60 - fade_counter) * 4
		fade_counter += 1
	else:
		for p: VfxParticleData in particles:
			p.deactivate()
		state = State.DONE


func _compute_orbital_positions() -> void:
	accumulated_angle += angular_velocity

	for r in range(RING_COUNT):
		var angle: int = accumulated_angle + r * RING_PHASE_OFFSET
		var theta: float = float(angle) * TAU / float(FULL_CIRCLE)

		var x_offset: float = cos(theta) * float(orbital_radius) * PSX_SCALE
		var z_offset: float = sin(theta) * float(orbital_radius) * PSX_SCALE

		ring_buffer[r][write_head] = Vector3(x_offset, 0.0, z_offset)


func _assign_particle_positions() -> void:
	for r in range(RING_COUNT):
		var read_idx: int = write_head
		for slot in range(SLOTS_PER_RING):
			var particle_idx: int = r * SLOTS_PER_RING + slot
			var p: VfxParticleData = particles[particle_idx]

			var offset: Vector3 = ring_buffer[r][read_idx]
			p.position = anchor + offset

			read_idx = (read_idx + 1) % SLOTS_PER_RING


func _compute_brightness() -> void:
	for r in range(RING_COUNT):
		for slot in range(SLOTS_PER_RING):
			var particle_idx: int = r * SLOTS_PER_RING + slot
			var weight: int = BRIGHTNESS_WEIGHTS[slot]
			# PSX: brightness = weight * brightness_scale / 128 (range 0-255, 128 = neutral)
			# Shader multiplier: divide by 128 to get 0.0-2.0 range (1.0 = neutral)
			var psx_brightness: float = float(weight) * float(brightness_scale) / 128.0
			particles[particle_idx].color_modulate = psx_brightness / 128.0
