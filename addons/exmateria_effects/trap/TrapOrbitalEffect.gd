extends Node3D
## Orbital summon orb effect (PSX TRAP handler 22).
##
## 3 concentric rings of 10 particles each orbit the caster.
## Uses a ring buffer per ring to create comet-trail effect.
## Delegates particle animation and rendering to a TrapEffect instance
## in override mode (positions and brightness set externally each tick).
## Vault: [[Summon Orb Orbital System]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const TrapConstants = preload("res://addons/exmateria_effects/trap/TrapConstants.gd")

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


signal animation_finished

# Constants matching PSX handler 22
const RING_COUNT: int = 3
const SLOTS_PER_RING: int = 10
const TOTAL_PARTICLES: int = 30  # 3 x 10
const RING_PHASE_OFFSET: int = 1365  # 0x555 = 120 degrees in PSX 4096-unit circle
const ANCHOR_Y_OFFSET: float = 24.0 / PsxMagnitude.UNITS_PER_TILE  # 24 PSX units above origin (ADR-0091)
const AUTO_FADE_TICKS: int = 90
const FADE_DURATION: int = 61
const RAMP_UP_FRAMES: int = 24
const FADE_BRIGHTNESS_BASE: int = 60
const FADE_EXPANSION_MASK: int = 8

# Per-slot brightness weights: head bright, tail dim
const BRIGHTNESS_WEIGHTS: PackedInt32Array = [128, 2, 6, 8, 10, 12, 16, 20, 24, 28]

enum State { INIT, ORBIT, FADE, DONE }

# State
var _state: int = State.INIT
var _tick_timer: float = 0.0
var _frame_counter: int = 0
var _orbit_ticks: int = 0
var _accumulated_angle: int = 0
var _angular_velocity: int = 0
var _orbital_radius: int = 0
var _brightness_scale: int = 0
var _fade_counter: int = 0
var _auto_fade_enabled: bool = true
var _anchor_position: Vector3 = Vector3.ZERO
var _target_unit: Node = null
var _write_head: int = 0

# Ring buffers: ring_buffer[ring][slot] = Vector3 offset
var _ring_buffer: Array = []  # Array of Array of Vector3

# Particle animation and rendering delegated to TrapEffect
const TrapEffectClass = preload("res://addons/exmateria_effects/trap/TrapEffect.gd")
var _trap_effect: Node3D = null


func _ready() -> void:
	# ADR-0037: combat-visual — rides combat domain's pause axis via process_mode
	add_to_group("combat_visuals")
	# Initialize ring buffers
	_ring_buffer.resize(RING_COUNT)
	for r in range(RING_COUNT):
		var ring: Array = []
		ring.resize(SLOTS_PER_RING)
		for s in range(SLOTS_PER_RING):
			ring[s] = Vector3.ZERO
		_ring_buffer[r] = ring


func _clear_ring_buffers() -> void:
	for r in range(RING_COUNT):
		for s in range(SLOTS_PER_RING):
			_ring_buffer[r][s] = Vector3.ZERO


func start(world_position: Vector3, unit: Node = null, auto_fade: bool = true) -> void:
	"""Begin orbital ramp-up at the given position."""
	_anchor_position = world_position
	_target_unit = unit
	_auto_fade_enabled = auto_fade
	_state = State.ORBIT
	_frame_counter = 0
	_orbit_ticks = 0
	_accumulated_angle = 0
	_angular_velocity = 0
	_orbital_radius = 0
	_brightness_scale = 0
	_fade_counter = 0
	_write_head = 0
	_tick_timer = 0.0

	_clear_ring_buffers()

	# Create TrapEffect for particle animation and rendering
	_trap_effect = TrapEffectClass.new()
	add_child(_trap_effect)
	if _trap_effect.initialize(7, 0):
		_trap_effect.play_handler(22, 0, world_position, Vector3.ZERO, null)
		_trap_effect.enable_override_mode()

	if EffectsDebug.particle():
		print("[TrapOrbital] Started at %s with TrapEffect override mode" % [world_position])


func start_fade() -> void:
	"""Trigger expand+accelerate+fade sequence."""
	if _state == State.ORBIT:
		_state = State.FADE
		_fade_counter = 0
		if EffectsDebug.particle():
			print("[TrapOrbital] Starting fade")


func stop() -> void:
	"""Stop immediately without emitting signal."""
	_state = State.DONE
	if _trap_effect:
		_trap_effect.stop()


func _process(delta: float) -> void:
	if _state == State.INIT or _state == State.DONE:
		return

	# Update anchor from unit position if available
	if _target_unit and is_instance_valid(_target_unit):
		_anchor_position = _target_unit.global_position

	_tick_timer += delta
	while _tick_timer >= TrapConstants.TICK_DURATION:
		_tick_timer -= TrapConstants.TICK_DURATION
		_process_tick()

	# Update TrapEffect particle positions and brightness
	_update_particle_overrides()


func _process_tick() -> void:
	"""Process one orbital tick."""
	if _state == State.ORBIT:
		_tick_orbit()
	elif _state == State.FADE:
		_tick_fade()


func _tick_orbit() -> void:
	"""Update orbital physics during active phase."""
	# Ramp-up: first N frames increase radius and angular velocity
	if _frame_counter < RAMP_UP_FRAMES:
		_angular_velocity = _frame_counter * 3
		_orbital_radius = _frame_counter

	# Brightness ramp: first 8 frames
	if _frame_counter < 8:
		_brightness_scale = (_frame_counter + 1) * 16

	if _frame_counter < 256:
		_frame_counter += 1

	_orbit_ticks += 1

	# Compute positions and advance ring buffer
	_compute_orbital_positions()
	_write_head = (_write_head + 1) % SLOTS_PER_RING

	# Auto-fade after timeout
	if _auto_fade_enabled and _orbit_ticks >= AUTO_FADE_TICKS:
		start_fade()


func _tick_fade() -> void:
	"""Update fade-out physics: expand, accelerate, dim."""
	if _fade_counter < FADE_DURATION:
		if (_fade_counter & FADE_EXPANSION_MASK) != 0:
			_orbital_radius += 1
		_angular_velocity += 1
		_brightness_scale = (FADE_BRIGHTNESS_BASE - _fade_counter) * 4
		_fade_counter += 1

		_compute_orbital_positions()
		_write_head = (_write_head + 1) % SLOTS_PER_RING
	else:
		_state = State.DONE
		if _trap_effect:
			_trap_effect.stop()
		animation_finished.emit()
		queue_free()


func _compute_orbital_positions() -> void:
	"""Compute current orbital position for each ring and write to ring buffer."""
	_accumulated_angle += _angular_velocity

	for r in range(RING_COUNT):
		var angle: int = _accumulated_angle + r * RING_PHASE_OFFSET
		var theta: float = PsxMagnitude.angle_to_rad(angle)
		var x_offset: float = cos(theta) * PsxMagnitude.tile_to_game(_orbital_radius)
		var z_offset: float = sin(theta) * PsxMagnitude.tile_to_game(_orbital_radius)
		_ring_buffer[r][_write_head] = Vector3(x_offset, 0.0, z_offset)


func _update_particle_overrides() -> void:
	"""Push current ring buffer positions and brightness to TrapEffect particles."""
	if not _trap_effect:
		return

	var anchor = _anchor_position + Vector3(0, ANCHOR_Y_OFFSET, 0)

	for r in range(RING_COUNT):
		# Start at most recently written slot (write_head was already incremented)
		var read_idx: int = (_write_head - 1 + SLOTS_PER_RING) % SLOTS_PER_RING
		for slot in range(SLOTS_PER_RING):
			var particle_idx: int = r * SLOTS_PER_RING + slot
			var offset: Vector3 = _ring_buffer[r][read_idx]

			# Brightness: weight * brightness_scale / 128 gives PSX 0-255 range,
			# then / 128 maps to shader multiplier (1.0 = neutral)
			var weight: int = BRIGHTNESS_WEIGHTS[slot]
			var color_mod: float = float(weight) * float(_brightness_scale) / 16384.0

			if color_mod <= 0.0:
				_trap_effect.set_particle_override(particle_idx, Vector3.ZERO, 0.0)
			else:
				_trap_effect.set_particle_override(particle_idx, anchor + offset, color_mod)

			read_idx = (read_idx + 1) % SLOTS_PER_RING
