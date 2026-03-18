class_name TrapEffectInstance
extends Node3D
## Self-contained TRAP particle effect — mesh pool, physics, spawning, rendering.
## Add as a child node, call play() with handler/element/direction.
## Designed to drop into battle_manager the same way VfxEffectInstance works for E###.BIN.

signal completed

## If true, automatically replays when all particles expire.
var loop: bool = false

# --- Particle simulation state ---
const TICK_DURATION: float = VfxConstants.TICK_DURATION
const TRAP_INERTIA: float = VfxConstants.PSX_FIXED_POINT_ONE
const RADIUS_TO_VELOCITY: float = 1.0 / VfxEmitter.VELOCITY_DIVISOR
const SOMETHING_SPARKLES_INITIAL_Y: float = 8.0 / VfxEmitter.POSITION_DIVISOR  # PSX raw -8, Y-flipped, /POSITION_DIVISOR
const SOMETHING_SPARKLES_Y_STEP: float = 3.0 / VfxEmitter.POSITION_DIVISOR     # PSX decrement 3/frame, Y-flipped

var _particles: Array[VfxParticleData] = []
var _physics: VfxPhysics
var _tick_counter: int = 0
var _tick_timer: float = 0.0
var _is_playing: bool = false
var _active_emitter_indices: Array[int] = []
var _max_spawn_end: int = 0
var _impact_direction: Vector3 = Vector3.ZERO

# Per-emitter palette override (handler-assigned at spawn, not baked in frame data)
# Flash emitters (1, 9) and knight break (11) always use palette 10 (overbright white);
# dust (0) uses element palette
const FLASH_EMITTER_INDICES: PackedInt32Array = [1, 9, 11]
const FLASH_PALETTE_ID: int = 10
var _emitter_palette: Dictionary[int, int] = {} # emitter_index -> palette_id

# Unit sprite white flash
var _palette_controller: TrapPaletteController

# --- Mesh pool + renderer ---
var _mesh_pool: TrapMeshPool
var _renderer: TrapParticleRenderer
var _initialized: bool = false

# --- Unified handler dispatch ---
var _active_handler: Variant = null  # TrapOrbitalHandler, TrapSpellChargeHandler, or TrapSummonChargeHandler
var _scatter_anchor: Vector3 = Vector3.ZERO  # PSX anchor for SCATTER convergence
# Animated pos_scatter — handler 13 something sparkles shifts spawn center upward each frame
var _animate_pos_scatter: bool = false
var _rising_center_y: float = 0.0


func initialize() -> void:
	var trap_data: TrapEffectData = RomReader.trap_effect_data

	# Physics
	_physics = VfxPhysics.new()
	_physics.gravity = trap_data.gravity
	_physics.inertia_threshold = float(trap_data.inertia_threshold)

	# Renderer
	if trap_data.texture == null:
		return

	_mesh_pool = TrapMeshPool.new()
	_mesh_pool.name = "TrapMeshPool"
	add_child(_mesh_pool)
	_mesh_pool.initialize()

	_renderer = TrapParticleRenderer.new()
	_renderer.initialize(_mesh_pool)

	_initialized = _mesh_pool.is_initialized


## Start the effect. handler_id selects which emitter group to fire.
## element_id selects the dust palette (0-8). direction is attacker→target vector.
## target_unit enables white flash on the unit sprite if provided.
func play(handler_id: int, element_id: int, direction: Vector3 = Vector3.ZERO, target_unit: Unit = null) -> void:
	if not _initialized:
		push_error("TrapEffectInstance.play() called before initialize()")
		return

	stop()

	_impact_direction = direction

	# Handler 4: spell charge lines
	if handler_id == TrapEffectData.HANDLER_SPELL_CHARGE:
		var sprite_height: float = _get_sprite_height(target_unit)
		var handler := TrapSpellChargeHandler.new()
		handler.start(element_id, sprite_height)
		_active_handler = handler
		_renderer.setup_line_mesh(self)
		_emitter_palette.clear()
		_emitter_palette[TrapSpellChargeHandler.SPARKLE_EMITTER_INDEX] = TrapSpellChargeHandler.SPARKLE_PALETTE_ID
		# PSX patches SCATTER anchor to (height + 8) above feet
		_scatter_anchor = Vector3(0.0, handler.convergence_y, 0.0)
		_tick_counter = 0
		_tick_timer = 0.0
		_is_playing = true
		return

	# Handler 18: plain charge lines
	if handler_id == TrapEffectData.HANDLER_PLAIN_CHARGE:
		var sprite_height: float = _get_sprite_height(target_unit)
		var handler := TrapSummonChargeHandler.new()
		handler.start(element_id, sprite_height, direction)
		_active_handler = handler
		_renderer.setup_line_mesh(self)
		_tick_counter = 0
		_tick_timer = 0.0
		_is_playing = true
		return

	# Handler 22: orbital summon charge orbs
	if handler_id == TrapEffectData.HANDLER_ORBITAL:
		var handler := TrapOrbitalHandler.new()
		handler.start(Vector3.ZERO)  # Local space — instance node is already at unit position
		_active_handler = handler
		_particles = handler.particles
		_emitter_palette.clear()
		_emitter_palette[TrapOrbitalHandler.EMITTER_INDEX] = TrapEffectData.ORBITAL_PALETTE_ID
		_tick_counter = 0
		_tick_timer = 0.0
		_is_playing = true
		return

	# Determine which emitters to activate
	if handler_id == 0:
		_active_emitter_indices.assign(range(TrapEffectData.NUM_EMITTERS))
	else:
		_active_emitter_indices.assign(TrapEffectData.HANDLER_CONFIGS.get(handler_id, []))

	# Cache max spawn end + set per-emitter palettes
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	_max_spawn_end = 0
	_emitter_palette.clear()
	for idx: int in _active_emitter_indices:
		if idx < trap_data.emitters.size():
			_max_spawn_end = maxi(_max_spawn_end, trap_data.emitters[idx].spawn_check_hi)
		if idx in FLASH_EMITTER_INDICES:
			_emitter_palette[idx] = FLASH_PALETTE_ID
		else:
			_emitter_palette[idx] = element_id

	# Handler 17: element-dependent palette from lookup table (not a fixed override)
	if handler_id == TrapEffectData.HANDLER_BLUE_SPARKLE_CLUSTER:
		var palette_id: int = TrapEffectData.ELEMENT_PARTICLE_PALETTES.get(element_id, 0)
		for idx: int in _active_emitter_indices:
			_emitter_palette[idx] = palette_id

	# Some handlers force a single palette for all emitters (ignoring element_id)
	if handler_id in TrapEffectData.HANDLER_PALETTE_OVERRIDES:
		var palette_id: int = TrapEffectData.HANDLER_PALETTE_OVERRIDES[handler_id]
		for idx: int in _active_emitter_indices:
			_emitter_palette[idx] = palette_id

	_animate_pos_scatter = handler_id == TrapEffectData.HANDLER_SOMETHING_SPARKLES
	if _animate_pos_scatter:
		_rising_center_y = SOMETHING_SPARKLES_INITIAL_Y

	_tick_counter = 0
	_tick_timer = 0.0
	_is_playing = true

	if target_unit != null:
		_palette_controller = TrapPaletteController.new()
		_palette_controller.start(target_unit)
	else:
		_palette_controller = null


func stop() -> void:
	_is_playing = false
	_animate_pos_scatter = false
	_rising_center_y = 0.0
	_active_handler = null
	_scatter_anchor = Vector3.ZERO
	if _renderer != null:
		_renderer.cleanup_line_mesh()
	_particles.clear()
	if _mesh_pool != null:
		_mesh_pool.release_all_meshes()
	if _palette_controller != null:
		_palette_controller.reset()
		_palette_controller = null


func start_fade() -> void:
	if _active_handler != null:
		_active_handler.start_fade()


func is_playing() -> bool:
	return _is_playing


func set_z_bias(value: float) -> void:
	if _mesh_pool != null:
		_mesh_pool.set_z_bias(value)


# ============================================================
#  _process — fixed-timestep tick loop
# ============================================================

func _process(delta: float) -> void:
	if not _is_playing:
		return

	_tick_timer += delta
	while _tick_timer >= TICK_DURATION:
		_tick_timer -= TICK_DURATION
		_process_tick()

	_renderer.render(_particles, _active_handler as TrapSpellChargeHandler,
		_active_handler as TrapSummonChargeHandler, _emitter_palette)


func _handle_loop_or_complete(restart_fn: Callable) -> void:
	if loop:
		restart_fn.call()
		_tick_counter = 0
		_tick_timer = 0.0
	else:
		_is_playing = false
		completed.emit()


func _process_tick() -> void:
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	if trap_data.emitters.is_empty():
		return
	if _active_handler is TrapOrbitalHandler:
		_process_orbital_tick(trap_data)
		return
	if _active_handler is TrapSpellChargeHandler:
		_process_spell_charge_tick(trap_data)
		return
	if _active_handler is TrapSummonChargeHandler:
		_process_summon_charge_tick(trap_data)
		return
	_process_standard_tick(trap_data)


func _process_orbital_tick(trap_data: TrapEffectData) -> void:
	var handler: TrapOrbitalHandler = _active_handler
	handler.tick()
	for p: VfxParticleData in _particles:
		p.age += 1  # Orbital particles bypass physics, must increment age manually
		_tick_trap_animation(p, trap_data)
	_tick_counter += 1
	if handler.is_done():
		_handle_loop_or_complete(func() -> void:
			handler.start(Vector3.ZERO))


func _process_spell_charge_tick(trap_data: TrapEffectData) -> void:
	var handler: TrapSpellChargeHandler = _active_handler
	handler.tick()
	_spawn_handler_sparkles(trap_data)
	var removed: int = _update_and_cull_particles(trap_data)
	handler.active_sparkle_count -= removed
	_tick_counter += 1
	if handler.is_done():
		_handle_loop_or_complete(func() -> void:
			handler.restart()
			_particles.clear())


func _process_summon_charge_tick(trap_data: TrapEffectData) -> void:
	var handler: TrapSummonChargeHandler = _active_handler
	handler.tick()
	_tick_counter += 1
	if handler.is_done():
		_handle_loop_or_complete(func() -> void:
			handler.restart())


func _process_standard_tick(trap_data: TrapEffectData) -> void:
	_spawn_particles_for_tick(trap_data)
	if _animate_pos_scatter:
		_rising_center_y += SOMETHING_SPARKLES_Y_STEP
	_update_and_cull_particles(trap_data)

	if _palette_controller != null and not _palette_controller.is_done():
		_palette_controller.update()

	_tick_counter += 1

	var flash_done: bool = _palette_controller == null or _palette_controller.is_done()
	if _tick_counter > _max_spawn_end and _particles.is_empty() and flash_done:
		_handle_loop_or_complete(func() -> void:
			_particles.clear()
			if _animate_pos_scatter:
				_rising_center_y = SOMETHING_SPARKLES_INITIAL_Y)


func _update_and_cull_particles(trap_data: TrapEffectData) -> int:
	for p: VfxParticleData in _particles:
		_physics.update_particle(p)
		_tick_trap_animation(p, trap_data)
	var prev_count: int = _particles.size()
	_particles = _particles.filter(
		func(p: VfxParticleData) -> bool: return p.active and not p.is_dead())
	return prev_count - _particles.size()


# ============================================================
#  Particle spawning — tick-window based
# ============================================================

func _spawn_particles_for_tick(trap_data: TrapEffectData) -> void:
	for emitter_idx: int in _active_emitter_indices:
		if emitter_idx >= trap_data.emitters.size():
			continue
		var emitter: TrapEffectData.TrapEmitter = trap_data.emitters[emitter_idx]

		if _tick_counter < emitter.spawn_check_lo or _tick_counter > emitter.spawn_check_hi:
			continue

		var current_count: int = 0
		for p: VfxParticleData in _particles:
			if p.emitter_index == emitter_idx:
				current_count += 1

		for _i: int in range(emitter.spawn_rate):
			if current_count >= emitter.max_particles:
				break
			var p: VfxParticleData = _create_particle(emitter_idx, emitter, trap_data)
			_particles.append(p)
			current_count += 1


func _create_particle(emitter_idx: int, emitter: TrapEffectData.TrapEmitter, trap_data: TrapEffectData) -> VfxParticleData:
	var p := VfxParticleData.new()
	var has_direction: bool = _impact_direction.length_squared() > 0.001

	var ellipsoid_offset: Vector3 = _calc_ellipsoid_offset(emitter)
	var pos_scatter: Vector3 = Vector3(0.0, _rising_center_y, 0.0) if _animate_pos_scatter else emitter.pos_scatter
	var spawn_pos: Vector3 = ellipsoid_offset + pos_scatter

	if has_direction and emitter.velocity_mode == TrapEffectData.VelocityMode.DIRECTIONAL:
		spawn_pos = _rotate_by_direction(spawn_pos, _impact_direction)

	var vel: Vector3 = Vector3.ZERO
	match emitter.velocity_mode:
		TrapEffectData.VelocityMode.SPHERICAL_RANDOM:
			vel = _calc_directional_velocity(emitter)
		TrapEffectData.VelocityMode.SCATTER:
			# PSX SCATTER: velocity points inward toward center.
			# spawn_pos already set by common code: ellipsoid_offset + pos_scatter
			var center: Vector3 = _scatter_anchor + pos_scatter
			vel = _calc_scatter_velocity(emitter, center - spawn_pos)
		TrapEffectData.VelocityMode.DIRECTIONAL, TrapEffectData.VelocityMode.FACING_DIRECTIONAL:
			var vel_local: Vector3 = _calc_directional_velocity(emitter)
			if has_direction:
				var dir_basis: Basis = _build_direction_basis(_impact_direction)
				vel = dir_basis * vel_local
			else:
				vel = vel_local

	var lifetime: int = randi_range(emitter.lifetime_min, emitter.lifetime_max)
	p.initialize(spawn_pos, vel, lifetime, emitter_idx)

	p.inertia = TRAP_INERTIA
	p.weight = float(randi_range(emitter.weight_min, emitter.weight_max))

	init_trap_animation(p, emitter, trap_data)
	return p


func _calc_ellipsoid_offset(emitter: TrapEffectData.TrapEmitter) -> Vector3:
	var vel: Vector3 = emitter.velocity  # semi-axes, already in world units
	if vel.length_squared() < 0.001:
		return Vector3.ZERO

	var dir: Vector3 = _random_unit_sphere()
	return Vector3(dir.x * vel.x, dir.y * vel.y, dir.z * vel.z)


func _calc_scatter_velocity(emitter: TrapEffectData.TrapEmitter, ellipsoid_offset: Vector3) -> Vector3:
	var speed: float = randf_range(float(emitter.radius_min), float(emitter.radius_max)) * RADIUS_TO_VELOCITY
	var vel: Vector3 = Vector3.ZERO
	if ellipsoid_offset.length() > 0.001 and absf(speed) > 0.001:
		vel = ellipsoid_offset.normalized() * speed
	return vel


func _calc_directional_velocity(emitter: TrapEffectData.TrapEmitter) -> Vector3:
	var angle_x: float = emitter.vel_range.x + randf_range(
		-emitter.scatter_half_range.x * 0.5, emitter.scatter_half_range.x * 0.5)
	var angle_y: float = emitter.vel_range.y + randf_range(
		-emitter.scatter_half_range.y * 0.5, emitter.scatter_half_range.y * 0.5)
	var angle_z: float = emitter.vel_range.z + randf_range(
		-emitter.scatter_half_range.z * 0.5, emitter.scatter_half_range.z * 0.5)

	var cone_basis: Basis = Basis.from_euler(Vector3(angle_x, angle_y, angle_z), EULER_ORDER_ZYX)
	var speed: float = randf_range(float(emitter.radius_min), float(emitter.radius_max)) * RADIUS_TO_VELOCITY
	return cone_basis * Vector3(0, -speed, 0)


static func _random_unit_sphere() -> Vector3:
	var theta: float = randf() * TAU
	var phi: float = acos(2.0 * randf() - 1.0)
	return Vector3(
		sin(phi) * cos(theta),
		cos(phi),
		sin(phi) * sin(theta)
	)


# ============================================================
#  Impact direction — rotate positions/velocities by attacker angle
# ============================================================

static func _rotate_by_direction(local_vec: Vector3, direction: Vector3) -> Vector3:
	var base_rotated := Vector3(local_vec.y, -local_vec.x, local_vec.z)

	var dir_xz := Vector3(direction.x, 0.0, direction.z)
	if dir_xz.length_squared() < 0.001:
		return base_rotated

	dir_xz = dir_xz.normalized()
	var angle: float = atan2(dir_xz.z, dir_xz.x)
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)

	return Vector3(
		base_rotated.x * cos_a - base_rotated.z * sin_a,
		base_rotated.y,
		base_rotated.x * sin_a + base_rotated.z * cos_a)


static func _build_direction_basis(direction: Vector3) -> Basis:
	var dir: Vector3 = direction.normalized()
	var yaw: float = atan2(-dir.x, dir.z)
	var horizontal_dist: float = sqrt(dir.x * dir.x + dir.z * dir.z)
	var pitch: float = atan2(dir.y, horizontal_dist) + PI * 0.5
	return Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


# ============================================================
#  TRAP animation — 1:1 tick (not /2 like E###.BIN)
# ============================================================

static func init_trap_animation(p: VfxParticleData, emitter: TrapEffectData.TrapEmitter, trap_data: TrapEffectData) -> void:
	p.anim_index = emitter.anim_index
	p.anim_frame = 0
	p.anim_time = 0

	if p.anim_index < 0 or p.anim_index >= trap_data.animations.size():
		return
	var animation: VisualEffectData.VfxAnimation = trap_data.animations[p.anim_index]
	if animation.animation_frames.is_empty():
		return

	var first: VisualEffectData.VfxAnimationFrame = animation.animation_frames[0]
	if first.frameset_id < 0x80:
		p.current_frameset = first.frameset_id
		p.anim_time = first.duration
		if first.duration == 0:
			mark_animation_terminal(p)


static func _tick_trap_animation(p: VfxParticleData, trap_data: TrapEffectData) -> void:
	if p.animation_complete or p.animation_held:
		return
	if p.anim_index < 0 or p.anim_index >= trap_data.animations.size():
		return

	var animation: VisualEffectData.VfxAnimation = trap_data.animations[p.anim_index]
	if animation.animation_frames.is_empty():
		return

	p.anim_time -= 1
	if p.anim_time > 0:
		return

	p.anim_frame += 1
	_resolve_trap_animation_frame(p, animation)


static func _resolve_trap_animation_frame(p: VfxParticleData, animation: VisualEffectData.VfxAnimation) -> void:
	while p.anim_frame < animation.animation_frames.size():
		var af: VisualEffectData.VfxAnimationFrame = animation.animation_frames[p.anim_frame]

		if af.frameset_id == VisualEffectData.ANIM_OPCODE_LOOP:
			mark_animation_terminal(p)
			return

		p.current_frameset = af.frameset_id
		p.anim_time = af.duration

		if af.duration == 0:
			mark_animation_terminal(p)
			return

		return

	p.animation_complete = true


static func mark_animation_terminal(p: VfxParticleData) -> void:
	if p.lifetime == -1:
		p.animation_complete = true
	else:
		p.animation_held = true


# ============================================================
#  Spell charge line helpers
# ============================================================

func _spawn_handler_sparkles(trap_data: TrapEffectData) -> void:
	var handler: TrapSpellChargeHandler = _active_handler
	var count: int = handler.sparkles_to_spawn
	handler.sparkles_to_spawn = 0
	var emitter_idx: int = TrapSpellChargeHandler.SPARKLE_EMITTER_INDEX
	if emitter_idx >= trap_data.emitters.size():
		return
	var emitter: TrapEffectData.TrapEmitter = trap_data.emitters[emitter_idx]
	for _i in range(count):
		var p: VfxParticleData = _create_particle(emitter_idx, emitter, trap_data)
		_particles.append(p)
		handler.active_sparkle_count += 1


static func _get_sprite_height(unit: Unit) -> float:
	if unit != null and unit.animation_manager != null \
			and unit.animation_manager.global_spr != null:
		return float(unit.animation_manager.global_spr.graphic_height)
	return TrapChargeHandlerBase.DEFAULT_HEIGHT
