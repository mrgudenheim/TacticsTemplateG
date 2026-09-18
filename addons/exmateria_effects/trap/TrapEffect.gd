extends Node3D
## TRAP particle system for combat visual effects (hit clouds, charge particles, etc.)
##
## Implements the PSX TRAP effect system with proper particle physics.
## Supports all standard handlers (2-21) from the PSX g_charge_effect_handlers[] table.
## Each handler activates specific emitters from the shared 17-emitter pool.
##
## Loads texture and data from assets/effects/trap/, spawns particles with physics,
## and auto-cleans up when all particles are dead.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Elemental Puff Particle System]]
## Vault: [[Embedded MIPS Effect Code]]
## Vault: [[Footstep Dust Particle System]]
## Vault: [[Footstep Hard Surface Particle System]]
## Vault: [[Hit Reaction Particle Burst]]
## Vault: [[Knight Break Impact Particle System]]
## Vault: [[Spell Charge Effect System]]
## Vault: [[Summon Orb Orbital System]]
## Vault: [[TRAP Charge Particle System]]
## Vault: [[TRAP Hit Effect Particle System]]
## Vault: [[TRAP Sprite Effect System]]
## Vault: [[Unit Sprite Height Table]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectsContent = preload("res://addons/exmateria_effects/install/EffectsContent.gd")
const TrapConstants = preload("res://addons/exmateria_effects/trap/TrapConstants.gd")
const UnifiedPrimStager = preload("res://addons/exmateria_effects/render/UnifiedPrimStager.gd")

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


signal animation_finished

# Preload palette controller
const TrapPaletteControllerClass = preload("res://addons/exmateria_effects/trap/TrapPaletteController.gd")

# Constants
const DAMPING: float = (4096.0 - 560.0) / 4096.0  # ~0.863
const GRAVITY_Y: float = -0.035714  # Converted from PSX gravity 4096
const RADIUS_TO_VELOCITY: float = 1.0 / PsxMagnitude.RADIAL_VELOCITY_DIVISOR  # raw radius → Godot velocity (ADR-0091)

enum VelocityMode { NONE, SCATTER, DIRECTIONAL, SPHERICAL_RANDOM, FACING_DIRECTIONAL, ZERO }

# Emitter types
const EMITTER_DUST: int = 0
const EMITTER_FLASH: int = 1

# Handler ID → emitter indices (from PSX g_charge_effect_handlers[] func_id)
const HANDLER_CONFIGS: Dictionary = {
	2: [0, 1, 9],    # Hit Clouds (melee + ranged)
	3: [16],          # Elemental Puffs
	4: [12],          # Spell Charge Lines sparkle (emitter 12)
	6: [10],          # Charge+X particles
	8: [6],           # Charge Particles A
	9: [7],           # Footstep Puffs (Hard)
	12: [8],          # Hit/reaction dust
	13: [5],          # Rising Burst
	15: [4],          # Charge Drift
	17: [3],          # Element Particles
	19: [15],         # Teleport
	21: [11],         # Knight Break
	22: [14],         # Orbital Summon Orbs
}

# Handlers where ALL emitters use a fixed palette (overrides element)
const HANDLER_PALETTE_OVERRIDES: Dictionary = {
	3: 13,   # Elemental Puffs
	4: 15,   # Spell Charge Sparkles
	6: 11,   # Charge+X
	8: 9,    # Charge Particles A
	9: 11,   # Footstep Puffs
	12: 12,  # Hit Dust
	13: 11,  # Rising Burst
	15: 15,  # Charge Drift
	19: 11,  # Teleport
	21: 10,  # Knight Break (overbright white)
	22: 12,  # Orbital Summon Orbs
}

# Handler 17: element → palette lookup (elements 1-5 get unique palettes; rest → 0)
const ELEMENT_PARTICLE_PALETTES: Dictionary = {
	1: 10, 2: 11, 3: 12, 4: 13, 5: 14,
}

# Handler 2 flash emitters always use palette 10 (per-emitter, not per-handler)
const FLASH_EMITTER_INDICES: Array = [1, 9, 11]
const FLASH_PALETTE_ID: int = 10

const HANDLER_GROUP_NAMES: Dictionary = {
	2: "Hit Clouds", 3: "Elemental Puffs", 4: "Spell Charge Sparkles", 6: "Charge+X",
	8: "Charge Particles A", 9: "Footstep Puffs", 12: "Hit Dust",
	13: "Rising Burst", 15: "Charge Drift", 17: "Element Particles",
	19: "Teleport", 21: "Knight Break", 22: "Orbital Summon Orbs",
}

# Resources
var _texture: Texture2D  # Indexed-grayscale TRAP1.tga (R=G=B=idx*17, A=255)
var _palette_texture: Texture2D  # 16×16 RGBA TRAP1.palette.tga
var _framesets: Array = []
var _animations: Array = []
var _emitters_config: Array = []
var _element_config: Array = []
var _texture_size: Vector2

# State
var _particles: Array = []
var _tick_counter: int = 0
var _tick_timer: float = 0.0
var _is_playing: bool = false
var _element_index: int = 0  # 0=None, 1=Fire, 2=Lightning, etc.
var _impact_direction: Vector3 = Vector3.ZERO  # Direction for DIRECTIONAL mode rotation
var _active_emitter_indices: Array[int] = [EMITTER_DUST, EMITTER_FLASH]  # Which emitters to spawn
var _max_spawn_end: int = 0  # Cached from emitter configs in play_at()
var _handler_id: int = -1  # Active handler ID (-1 = legacy/direct play_at)
var _rising_burst_offset: float = 0.0  # Handler 13: cumulative Y offset for rising spawn

# Rendering — one slot borrowed from the global EffectMultiMeshPool (ADR-0045). #225: Trap no
# longer writes a mode MultiMesh; it stages 24-float unified prims and publishes them through the
# shared upload_unified path (data-derived per-prim mode). #227: the indexed TRAP1 sheet now rides
# the slot's plain _effect_tex field (set via set_effect_texture); the palette rides upload_unified.
const _TRAP_DEPTH_MODE: int = 1  # PULL_FORWARD_8 (ADR-0009), packed per-instance
var _pool: Node = null  # Cached reference to EffectMultiMeshPool autoload
var _use_global_pool: bool = false
var _pool_slot: int = -1  # Borrowed slot index (-1 = none)

# #225: emitter blend_mode (emitters.json) -> compositor mode enum (0=mix,1=add,2=sub,3=add25).
# The shipped trap asset is all "ADD" (-> 1), so this is pixel-identical today; the map future-
# proofs a sub/mix/add25 emitter without a code change. Mirrors the general renderer routing by
# blend mode, sourced from Trap's per-emitter string instead of the per-frame semi_trans_mode int.
const BLEND_MODE_TO_COMPOSITOR: Dictionary = {"MIX": 0, "ADD": 1, "SUB": 2, "ADD25": 3}

# #225/#6.2: submission-order unified staging for the display-space compositor, single-sourced in
# UnifiedPrimStager (shared with EffectParticleRenderer + the Category-A producers) — the 24-float
# record layout (ADR-0040 MultiMesh packing + per-prim level_scale at [20] + vec4 pad), the parallel
# mode / ot_order_z-depth / age keys, and the order()->upload_unified publish ceremony. Mode
# resolution stays here (Trap's per-emitter blend_mode string via _compositor_mode_for) — append()
# takes an already-resolved mode. The per-frame world->view for the fold key is handed to begin().
const _FLOATS_PER_INSTANCE: int = 24
var _stager: UnifiedPrimStager = UnifiedPrimStager.new()

# Palette controller for target white flash
var _palette_controller: TrapPaletteControllerClass = null

## Handler 22 Override Mode
## When enabled, particles are pre-spawned and their positions/brightness are
## set externally each tick by the caller (TrapOrbitalEffect). Physics and
## auto-cleanup are disabled; the caller controls the particle lifecycle.
var _override_mode: bool = false
var _particle_overrides: Array = []  # Parallel to _particles, Array of ParticleOverride


## Inner class representing a single particle
class TrapParticle:
	var position: Vector3
	var velocity: Vector3
	var lifetime: int  # -1 = animation-driven
	var weight: int  # Gravity weight (0 for dust, 1376 for flash)
	var emitter_type: int  # 0=dust, 1=flash
	var anim_index: int
	var anim_opcodes: Array
	var opcode_index: int
	var frame_timer: int
	var current_frameset: int
	var animation_complete: bool
	var palette_id: int
	var rgb_mod: Vector3  # RGB modulation (1.0 for dust, 2.0 for flash)
	var age: int  # #225: elapsed ticks since spawn — the compositor's within-bucket tie-break key
	              # (newest = smallest age folds ON TOP, PSX double-head-insert). See OTDepthPrimOrder.

	func _init() -> void:
		position = Vector3.ZERO
		velocity = Vector3.ZERO
		lifetime = -1
		weight = 0
		emitter_type = 0
		anim_index = 0
		anim_opcodes = []
		opcode_index = 0
		frame_timer = 0
		current_frameset = 0
		animation_complete = false
		palette_id = 0
		rgb_mod = Vector3.ONE
		age = 0


class ParticleOverride:
	var position: Vector3
	var brightness: float
	var visible: bool

	func _init():
		position = Vector3.ZERO
		brightness = 1.0
		visible = false


func _ready() -> void:
	# ADR-0037: combat-visual — rides combat domain's pause axis via process_mode
	add_to_group("combat_visuals")
	_use_global_pool = not Engine.is_editor_hint()
	if _use_global_pool:
		_pool = Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")
		if not _pool:
			_use_global_pool = false


func initialize(trap_type: int = 7, element_index: int = 0) -> bool:
	"""Initialize the TRAP effect.

	Args:
		trap_type: Animation type ID (7 = physical hit cloud, currently only type supported)
		element_index: Element index 0-8 (0=None, 1=Fire, 2=Lightning, 3=Ice, 4=Wind, 5=Earth, 6=Water, 7=Holy, 8=Dark)

	Returns:
		true if initialization succeeded
	"""
	_element_index = clampi(element_index, 0, 8)

	# Load emitters config
	if not _load_json(EffectsContent.trap_table_path("emitters.json"), func(data): _emitters_config = data):
		return false

	# Load framesets
	if not _load_json(EffectsContent.trap_table_path("frames.json"), func(data): _framesets = data):
		return false

	# Load animations
	if not _load_json(EffectsContent.trap_table_path("animations.json"), func(data): _animations = data):
		return false

	# Load element config
	if not _load_json(EffectsContent.trap_table_path("element_config.json"), func(data): _element_config = data):
		return false

	# Load textures for both dust (element-based) and flash (palette 10)
	if not _setup_textures():
		return false

	if EffectsDebug.iteration():
		print("[TrapEffect] Initialized type %d, element %d with %d framesets, %d animations" % [
			trap_type, element_index, _framesets.size(), _animations.size()
		])

	return true


func _load_json(path: String, callback: Callable) -> bool:
	"""Load JSON file and call callback with parsed data."""
	if not ResourceLoader.exists(path):
		push_error("TrapEffect: File not found: %s" % path)
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("TrapEffect: Failed to open: %s" % path)
		return false

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		push_error("TrapEffect: Failed to parse JSON: %s" % path)
		return false

	callback.call(json.data)
	return true


func _setup_textures() -> bool:
	"""Load the indexed TRAP1 texture and its companion palette table.

	ADR-0022 pattern: a single indexed-grayscale TGA + a 16×16 RGBA palette
	TGA, with the runtime shader picking a row via the palette_row uniform.
	"""
	# #658/ADR-0202 dec. 5: the addon no longer NAMES the host's asset tree. `var`, not
	# `const` — a content root is read from `ProjectSettings` at call time and a `const`
	# initialiser must be a constant expression.
	var indexed_path := EffectsContent.trap_tex_path()
	var palette_path := EffectsContent.trap_palette_path()
	# `resolve()` already reported the unset root once, by name. Returning here keeps the
	# `load("")` out of the log, where it would read as a missing FILE rather than a
	# missing install step.
	if indexed_path.is_empty() or palette_path.is_empty():
		return false

	_texture = load(indexed_path)
	if not _texture:
		push_error("TrapEffect: Failed to load indexed texture: %s" % indexed_path)
		return false

	_palette_texture = load(palette_path)
	if not _palette_texture:
		push_error("TrapEffect: Failed to load palette texture: %s" % palette_path)
		return false

	_texture_size = Vector2(_texture.get_width(), _texture.get_height())
	if EffectsDebug.particle():
		print("[TrapEffect] Indexed: %s, palette: %s, size: %s" % [
			indexed_path, palette_path, _texture_size])

	return true


func _exit_tree() -> void:
	_release_slot()


func _release_slot() -> void:
	"""Return the borrowed slot to the pool, withdrawing its CPU submission and sheet.
	There is no shared blend-mode material or RD palette handle to reset."""
	if not _use_global_pool or not _pool or _pool_slot < 0:
		return
	_pool.release_slot(_pool_slot)
	_pool_slot = -1


func _borrow_slot_if_needed() -> void:
	"""Borrow one slot and supply its indexed TRAP1 sheet and CLUT as ordinary textures.
	Idempotent — only borrows once per play; publish supplies the palette flag."""
	if not _use_global_pool or not _pool or _pool_slot >= 0:
		return
	_pool_slot = _pool.borrow_slot()
	_pool.set_effect_texture(_pool_slot, _texture)
	# Native and fold ShaderMaterials both sample the same ordinary CLUT texture.
	_pool.set_palette_texture(_pool_slot, _palette_texture)


func play_at(world_position: Vector3, impact_direction: Vector3 = Vector3.ZERO,
		target_unit: Node = null, emitter_indices: Array[int] = [],
		enable_palette_flash: bool = true) -> void:
	"""Start playing the effect at the given position.

	Args:
		world_position: World position to spawn the effect
		impact_direction: Direction of impact for DIRECTIONAL mode emitters (e.g., projectile travel direction)
		target_unit: Optional Unit node to apply white flash palette effect to
		emitter_indices: Which emitter configs to use (empty = default [EMITTER_DUST, EMITTER_FLASH])
		enable_palette_flash: Whether to apply white flash palette effect on target
	"""
	global_position = world_position
	_impact_direction = impact_direction.normalized() if impact_direction.length_squared() > 0.001 else Vector3.ZERO
	_particles.clear()
	_tick_counter = 0
	_tick_timer = 0.0
	_is_playing = true
	_rising_burst_offset = PsxMagnitude.tile_to_game(8.0)  # PSX starts at Y=-8 (flipped to +Y)

	# Set active emitter indices from param, or default
	if emitter_indices.size() > 0:
		_active_emitter_indices = emitter_indices
	else:
		_active_emitter_indices = [EMITTER_DUST, EMITTER_FLASH]

	# The MultiMesh slot is borrowed lazily on first render (_render_particles).

	# Cache max spawn end from emitter configs
	_max_spawn_end = 0
	for idx in _active_emitter_indices:
		if idx < _emitters_config.size():
			var spawn_end = _emitters_config[idx].get("spawn_window", [0, 4])[1]
			_max_spawn_end = maxi(_max_spawn_end, spawn_end)

	# Initialize palette controller for target white flash
	if enable_palette_flash and target_unit:
		_palette_controller = TrapPaletteControllerClass.new()
		_palette_controller.initialize(target_unit)
		if EffectsDebug.iteration():
			print("[TrapEffect] Initialized palette controller for unit: %s" % target_unit.name)

	if EffectsDebug.iteration():
		print("[TrapEffect] Playing at %s, element=%d, direction=%s, emitters=%s, palette_flash=%s" % [
			world_position, _element_index, _impact_direction, _active_emitter_indices, enable_palette_flash])


func play_handler(handler_id: int, element_id: int, world_position: Vector3,
		impact_direction: Vector3 = Vector3.ZERO, target_unit: Node = null) -> void:
	"""Play a specific handler effect by ID.

	Args:
		handler_id: PSX handler ID (2, 3, 6, 8, 9, 12, 13, 15, 17, 19, 21)
		element_id: Element index 0-8
		world_position: World position to spawn the effect
		impact_direction: Direction of impact for directional emitters
		target_unit: Optional Unit node to apply white flash palette effect to
	"""
	if not HANDLER_CONFIGS.has(handler_id):
		push_error("TrapEffect: Unknown handler_id %d" % handler_id)
		return
	_handler_id = handler_id
	_element_index = clampi(element_id, 0, 8)
	var emitter_indices: Array[int] = []
	for idx in HANDLER_CONFIGS[handler_id]:
		emitter_indices.append(idx)
	# Only handler 2 triggers white flash on target
	var enable_flash: bool = handler_id == 2
	play_at(world_position, impact_direction, target_unit, emitter_indices, enable_flash)


func enable_override_mode() -> void:
	"""Enable override mode for handler 22 orbital orbs.
	Pre-spawns all particles, disables physics and auto-cleanup.
	Caller sets positions via set_particle_override() each tick.
	Must be called after play_handler()."""
	_override_mode = true
	_particles.clear()
	for emitter_idx in _active_emitter_indices:
		if emitter_idx >= _emitters_config.size():
			continue
		var config = _emitters_config[emitter_idx]
		var count = config.get("max_particles", 8)
		for _i in range(count):
			var p = _create_particle(emitter_idx, config)
			_particles.append(p)
	_particle_overrides.clear()
	_particle_overrides.resize(_particles.size())
	for i in range(_particle_overrides.size()):
		_particle_overrides[i] = ParticleOverride.new()


func set_particle_override(index: int, world_position: Vector3, brightness: float) -> void:
	"""Set world position and brightness for a particle (handler 22 override mode only)."""
	if index < 0 or index >= _particle_overrides.size():
		return
	var ovr = _particle_overrides[index]
	ovr.position = world_position
	ovr.brightness = brightness
	ovr.visible = brightness > 0.0


func _process(delta: float) -> void:
	if not _is_playing:
		return

	if EffectsDebug.iteration():
		print("[TrapEffect] _process delta=%f, tick_timer=%f" % [delta, _tick_timer])

	_tick_timer += delta
	if EffectsDebug.iteration() and _tick_timer >= TrapConstants.TICK_DURATION:
		print("[TrapEffect] tick_timer=%f >= %f, calling _process_tick" % [_tick_timer, TrapConstants.TICK_DURATION])
	while _tick_timer >= TrapConstants.TICK_DURATION:
		_tick_timer -= TrapConstants.TICK_DURATION
		_process_tick()


func _process_tick() -> void:
	"""Process one tick (1/30th second)."""
	if EffectsDebug.iteration():
		print("[TrapEffect] Tick %d" % _tick_counter)

	# Log emitter details when particle debug is on
	var _log_particles = EffectsDebug.particle() and _tick_counter <= 2

	# Update palette controller (white flash on target)
	if _palette_controller and not _palette_controller.is_finished():
		_palette_controller.update()

	# Spawn particles based on tick counter (skip in override mode — particles pre-spawned)
	if not _override_mode:
		_spawn_particles_for_tick()

	# Handler 13 (Rising Burst): spawn center rises each tick, creating
	# a vertical column of particles that emerge from bottom to top
	if _handler_id == 13:
		_rising_burst_offset += PsxMagnitude.tile_to_game(3.0)

	if EffectsDebug.iteration():
		print("[TrapEffect] After spawn: %d particles" % _particles.size())
	if _log_particles:
		print("[TrapEffect] Tick %d, emitters=%s, after spawn: %d particles" % [_tick_counter, _active_emitter_indices, _particles.size()])
		for p in _particles:
			if p.emitter_type in _active_emitter_indices:
				print("[TrapEffect]   particle: pos=%s vel=%s palette=%d rgb_mod=%s frameset=%d alive=%s" % [
					p.position, p.velocity, p.palette_id, p.rgb_mod, p.current_frameset, not p.animation_complete])

	# Update all particles
	var alive_particles: Array = []
	for p in _particles:
		if _update_particle(p):
			alive_particles.append(p)

	_particles = alive_particles

	_tick_counter += 1

	# Check for effect completion (skip in override mode — caller controls lifecycle)
	if not _override_mode:
		var palette_done = _palette_controller == null or _palette_controller.is_finished()
		if _tick_counter > _max_spawn_end and _particles.is_empty() and palette_done:
			_is_playing = false
			_hide_all_meshes()
			animation_finished.emit()
			queue_free()
			return

	# Render particles
	_render_particles()


func _spawn_particles_for_tick() -> void:
	"""Spawn particles according to emitter configs for current tick."""
	for emitter_idx in _active_emitter_indices:
		if emitter_idx >= _emitters_config.size():
			continue
		var config = _emitters_config[emitter_idx]
		var spawn_window = config.get("spawn_window", [0, 4])
		var spawn_lo = spawn_window[0]
		var spawn_hi = spawn_window[1]

		# Debug: log spawn window check
		if EffectsDebug.iteration() and _tick_counter <= 3:
			print("[TrapEffect] Emitter %d spawn check: tick=%d, window=[%d,%d], in_window=%s" % [
				emitter_idx, _tick_counter, spawn_lo, spawn_hi,
				_tick_counter >= spawn_lo and _tick_counter <= spawn_hi
			])

		if _tick_counter >= spawn_lo and _tick_counter <= spawn_hi:
			var spawn_rate = config.get("spawn_rate", 1)
			var max_particles = config.get("max_particles", 8)

			# Count current particles of this type
			var current_count = 0
			for p in _particles:
				if p.emitter_type == emitter_idx:
					current_count += 1

			if EffectsDebug.iteration():
				print("[TrapEffect] Emitter %d spawning: rate=%d, max=%d, current=%d" % [emitter_idx, spawn_rate, max_particles, current_count])

			# Spawn up to spawn_rate particles, respecting max
			for _i in range(spawn_rate):
				if current_count >= max_particles:
					break
				var particle = _create_particle(emitter_idx, config)
				_particles.append(particle)
				current_count += 1


static func _range_from_config(value) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(float(value), float(value))


func _create_particle(emitter_type: int, config: Dictionary) -> TrapParticle:
	"""Create and initialize a new particle."""
	var p = TrapParticle.new()
	p.emitter_type = emitter_type
	var ellipsoid_offset = _init_particle_position(p, config)
	_init_particle_velocity(p, config, ellipsoid_offset)
	_init_particle_physics(p, config)
	_init_particle_animation(p, config)
	_init_particle_palette(p, config)
	return p


static func _parse_velocity_mode(mode_str: String) -> VelocityMode:
	match mode_str:
		"SCATTER": return VelocityMode.SCATTER
		"DIRECTIONAL": return VelocityMode.DIRECTIONAL
		"SPHERICAL_RANDOM": return VelocityMode.SPHERICAL_RANDOM
		"FACING_DIRECTIONAL": return VelocityMode.FACING_DIRECTIONAL
		"ZERO": return VelocityMode.ZERO
		_: return VelocityMode.NONE


func _init_particle_position(p: TrapParticle, config: Dictionary) -> Vector3:
	"""Initialize spawn position from ellipsoid config. Returns ellipsoid offset for velocity."""
	var flags = config.get("flags", {})
	var vel_mode := _parse_velocity_mode(flags.get("velocity_mode", ""))

	# pos_scatter = center of spawn ellipsoid (offset from anchor)
	# velocity = semi-axes of the ellipsoid (NOT movement velocity!)
	var pos_scatter = config.get("position_scatter", [0.0, 0.0, 0.0])
	var velocity = config.get("velocity", [0.0, 0.0, 0.0])
	var vel_vec = Vector3(velocity[0], velocity[1], velocity[2])
	var magnitude = vel_vec.length()

	# Calculate random point within ellipsoid defined by velocity semi-axes
	# PSX formula: unit_sphere_point * velocity_component_wise
	# velocity[] is already in Godot units (parser divides raw PSX by 28)
	var ellipsoid_offset = Vector3.ZERO
	if magnitude > 0.001:
		var random_dir = _random_unit_sphere()
		ellipsoid_offset = Vector3(
			random_dir.x * velocity[0],
			random_dir.y * velocity[1],
			random_dir.z * velocity[2]
		)

	# Final spawn position = ellipsoid offset + pos_scatter (center)
	# Handler 13 (Rising Burst): replace pos_scatter with rising Y offset (matches PSX)
	var pos_vec: Vector3
	if _handler_id == 13:
		pos_vec = ellipsoid_offset + Vector3(0.0, _rising_burst_offset, 0.0)
	else:
		pos_vec = ellipsoid_offset + Vector3(pos_scatter[0], pos_scatter[1], pos_scatter[2])

	# For DIRECTIONAL/FACING_DIRECTIONAL modes, rotate the whole spawn position by impact direction
	if (vel_mode == VelocityMode.DIRECTIONAL or vel_mode == VelocityMode.FACING_DIRECTIONAL) and _impact_direction.length_squared() > 0.001:
		pos_vec = _rotate_by_direction(pos_vec, _impact_direction)

	p.position = pos_vec

	if EffectsDebug.iteration():
		if p.emitter_type == EMITTER_FLASH:
			print("[TrapEffect] FLASH spawn: ellipsoid_offset=%s, pos_scatter=%s, final=%s" % [
				ellipsoid_offset, pos_scatter, pos_vec])
		elif _particles.size() == 0:
			print("[TrapEffect] DUST spawn: ellipsoid_offset=%s, pos_scatter=%s, final=%s" % [
				ellipsoid_offset, pos_scatter, pos_vec])

	return ellipsoid_offset


func _init_particle_velocity(p: TrapParticle, config: Dictionary, ellipsoid_offset: Vector3) -> void:
	"""Initialize movement velocity from radius and velocity mode."""
	var flags = config.get("flags", {})
	var vel_mode := _parse_velocity_mode(flags.get("velocity_mode", ""))
	var radius_range = _range_from_config(config.get("radius", 0))
	var radius_min: float = radius_range.x
	var radius_max: float = radius_range.y
	var vel_range = config.get("vel_range", [0.0, 0.0, 0.0])

	if vel_mode == VelocityMode.SCATTER:
		# SCATTER mode: velocity direction = outward from ellipsoid center
		var speed = randf_range(radius_min, radius_max) * RADIUS_TO_VELOCITY
		if ellipsoid_offset.length() > 0.001 and absf(speed) > 0.001:
			p.velocity = -ellipsoid_offset.normalized() * speed
		else:
			p.velocity = Vector3.ZERO
	elif vel_mode == VelocityMode.DIRECTIONAL or vel_mode == VelocityMode.FACING_DIRECTIONAL:
		# DIRECTIONAL / FACING_DIRECTIONAL mode: cone velocity system
		var scatter_half = config.get("scatter_half_range", [0.0, 0.0, 0.0])
		var angle_x = vel_range[0] + randf_range(-scatter_half[0] * 0.5, scatter_half[0] * 0.5)
		var angle_y = vel_range[1] + randf_range(-scatter_half[1] * 0.5, scatter_half[1] * 0.5)
		var angle_z = vel_range[2] + randf_range(-scatter_half[2] * 0.5, scatter_half[2] * 0.5)
		var cone_basis = Basis.from_euler(Vector3(angle_x, angle_y, angle_z), EULER_ORDER_ZYX)
		var speed = randf_range(radius_min, radius_max) * RADIUS_TO_VELOCITY
		var vel_local = cone_basis * Vector3(0, speed, 0)
		if _impact_direction.length_squared() > 0.001:
			var dir_basis = _build_direction_basis(_impact_direction)
			p.velocity = dir_basis * vel_local
		else:
			p.velocity = vel_local
	elif vel_mode == VelocityMode.SPHERICAL_RANDOM:
		# SPHERICAL_RANDOM mode: random direction from cone angles + speed from radius
		var scatter_half = config.get("scatter_half_range", [0.0, 0.0, 0.0])
		var angle_x = vel_range[0] + randf_range(-scatter_half[0] * 0.5, scatter_half[0] * 0.5)
		var angle_y = vel_range[1] + randf_range(-scatter_half[1] * 0.5, scatter_half[1] * 0.5)
		var angle_z = vel_range[2] + randf_range(-scatter_half[2] * 0.5, scatter_half[2] * 0.5)
		var cone_basis = Basis.from_euler(Vector3(angle_x, angle_y, angle_z), EULER_ORDER_ZYX)
		var speed = randf_range(radius_min, radius_max) * RADIUS_TO_VELOCITY
		p.velocity = cone_basis * Vector3(0, -speed, 0)
	elif vel_mode == VelocityMode.ZERO:
		p.velocity = Vector3.ZERO
	else:
		p.velocity = Vector3.ZERO


func _init_particle_physics(p: TrapParticle, config: Dictionary) -> void:
	"""Initialize weight and lifetime."""
	var weight_range = _range_from_config(config.get("weight", 0))
	p.weight = randi_range(int(weight_range.x), int(weight_range.y))
	var lifetime_range = _range_from_config(config.get("lifetime", -1))
	p.lifetime = randi_range(int(lifetime_range.y), int(lifetime_range.x))  # Note: min/max may be reversed


func _init_particle_animation(p: TrapParticle, config: Dictionary) -> void:
	"""Initialize animation index, opcodes, and initial frame."""
	var anim_index = config.get("anim_index", 0)
	p.anim_index = anim_index
	if anim_index < _animations.size():
		p.anim_opcodes = _animations[anim_index].get("opcodes", [])
	p.opcode_index = 0
	p.animation_complete = false

	if p.anim_opcodes.size() > 0:
		var first_op = p.anim_opcodes[0]
		if first_op.get("type") == "FRAME":
			p.current_frameset = first_op.get("frameset", 0)
			p.frame_timer = first_op.get("duration", 2)


func _init_particle_palette(p: TrapParticle, config: Dictionary) -> void:
	"""Initialize palette and RGB modulation based on handler + emitter type."""
	# Flash emitters (1, 9, 11) always use palette 10 with 2x overbright
	if p.emitter_type in FLASH_EMITTER_INDICES:
		p.palette_id = FLASH_PALETTE_ID
		p.rgb_mod = Vector3(2.0, 2.0, 2.0)
	elif _handler_id == 17:
		# Handler 17 (Element Particles): each element 1-5 gets a unique palette;
		# elements 6-8 and 0 fall back to palette 0 (base element)
		p.palette_id = ELEMENT_PARTICLE_PALETTES.get(_element_index, 0)
		p.rgb_mod = Vector3.ONE
	elif HANDLER_PALETTE_OVERRIDES.has(_handler_id):
		p.palette_id = HANDLER_PALETTE_OVERRIDES[_handler_id]
		p.rgb_mod = Vector3.ONE
	else:
		p.palette_id = _element_index
		p.rgb_mod = Vector3.ONE


func _random_unit_sphere() -> Vector3:
	"""Generate a random point on the unit sphere."""
	# Use spherical coordinates with uniform distribution
	var theta = randf() * TAU
	var phi = acos(2.0 * randf() - 1.0)
	return Vector3(
		sin(phi) * cos(theta),
		cos(phi),
		sin(phi) * sin(theta)
	)


func _rotate_by_direction(local_vec: Vector3, direction: Vector3) -> Vector3:
	"""Rotate a local-space vector by the impact direction.

	For DIRECTIONAL mode emitters:
	1. Base transform: local X maps to world Y (up), like FFT's effect system
	   - world X = local Y
	   - world Y = -local X (so local -X becomes world +Y)
	   - world Z = local Z
	2. Then rotate around world Y by the impact direction angle

	Args:
		local_vec: Vector in local/direction space (X=up after base transform)
		direction: World-space impact direction for horizontal rotation

	Returns:
		World-space vector after rotation
	"""
	# Step 1: Base transform - rotate so local X becomes world Y
	# This is a -90° rotation around Z axis: X → -Y, Y → X, Z → Z
	# So: world_x = local_y, world_y = -local_x, world_z = local_z
	var base_rotated = Vector3(
		local_vec.y,    # world X = local Y
		-local_vec.x,   # world Y = -local X (so local -X becomes +Y)
		local_vec.z     # world Z = local Z
	)

	# Step 2: Rotate around Y by impact direction angle
	var dir_xz = Vector3(direction.x, 0.0, direction.z)
	if dir_xz.length_squared() < 0.001:
		return base_rotated  # No horizontal rotation if direction is purely vertical

	dir_xz = dir_xz.normalized()

	# Angle from +X axis to direction in XZ plane
	var angle = atan2(dir_xz.z, dir_xz.x)

	# Rotate X and Z by this angle around Y axis
	var cos_a = cos(angle)
	var sin_a = sin(angle)

	return Vector3(
		base_rotated.x * cos_a - base_rotated.z * sin_a,
		base_rotated.y,  # Y unchanged by horizontal rotation
		base_rotated.x * sin_a + base_rotated.z * cos_a
	)


func _build_direction_basis(direction: Vector3) -> Basis:
	"""Build rotation matrix matching PSX direction matrix for DIRECTIONAL mode.

	PSX formula:
	  yaw   = atan2(-delta_x, delta_z)
	  pitch = atan2(delta_y, sqrt(delta_x² + delta_z²)) + 90°
	  roll  = 0

	This rotates local space (where X=forward toward target) into world space.
	"""
	var dir = direction.normalized()

	# Yaw: rotation around Y axis (horizontal direction)
	var yaw = atan2(-dir.x, dir.z)

	# Pitch: rotation around X axis (vertical angle) + 90°
	var horizontal_dist = sqrt(dir.x * dir.x + dir.z * dir.z)
	var pitch = atan2(dir.y, horizontal_dist) + PI * 0.5

	# Build rotation: apply pitch first, then yaw (ZYX order in Godot = pitch, yaw, roll)
	return Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


func _update_particle(p: TrapParticle) -> bool:
	"""Update particle physics and animation. Returns true if particle is still alive."""
	# #225: age one tick — the compositor's newest-on-top tie-break key (smaller age = newer = on top).
	p.age += 1

	# Physics: position += velocity (skip in override mode — positions set externally)
	if not _override_mode:
		p.position += p.velocity

		# Apply gravity (weight != 0; negative weight = upward force)
		if p.weight != 0:
			var gravity_effect = GRAVITY_Y * float(p.weight) / 4096.0
			p.velocity.y += gravity_effect

		p.velocity *= DAMPING

	# Animation advance
	p.frame_timer -= 1
	if p.frame_timer <= 0:
		_advance_animation(p)

	# In override mode, particles are always alive (caller controls lifecycle)
	if _override_mode:
		return true

	# Lifetime check
	if p.lifetime < 0:
		# Animation-driven lifetime
		return not p.animation_complete
	else:
		p.lifetime -= 1
		return p.lifetime > 0


func _advance_animation(p: TrapParticle) -> void:
	"""Advance to next animation frame."""
	if p.anim_opcodes.is_empty():
		p.animation_complete = true
		return

	p.opcode_index += 1

	# Find next FRAME opcode
	while p.opcode_index < p.anim_opcodes.size():
		var op = p.anim_opcodes[p.opcode_index]
		var op_type = op.get("type", "")

		if op_type == "FRAME":
			p.current_frameset = op.get("frameset", 0)
			p.frame_timer = op.get("duration", 2)
			if p.frame_timer == 0:
				# Duration 0 means hold frame, but check for LOOP next
				p.opcode_index += 1
				continue
			return
		elif op_type == "LOOP":
			if _override_mode:
				# Loop back to start for continuous animation cycling
				p.opcode_index = 0
				var first_op = p.anim_opcodes[0]
				if first_op.get("type") == "FRAME":
					p.current_frameset = first_op.get("frameset", 0)
					p.frame_timer = first_op.get("duration", 2)
				return
			# Animation complete (one loop)
			p.animation_complete = true
			return
		else:
			p.opcode_index += 1

	# Reached end without LOOP
	p.animation_complete = true


## Render: stage every live particle as a unified transparent-prim record, OT-depth-order it, and
## publish it to the pool for the combat display-space compositor to fold (#225). Trap folds through
## the SAME shared path as every other effect — its own MultiMesh is no longer a data source. The
## 24-float per-instance record mirrors EffectParticleRenderer's ADR-0040 packing:
##   MODEL_MATRIX basis — corners (8) + depth_mode (1)
##   MODEL_MATRIX[3].xyz — particle world position
##   INSTANCE_CUSTOM     — uv_rect (normalized, texel-centered)
##   COLOR               — color_modulate.rgb + palette_row/15 in alpha
##   [20] per-prim level_scale, [21..23] vec4 pad
func _render_particles() -> void:
	"""Stage + OT-depth-order the live particles, then publish the unified paletted buffer to the pool."""
	_borrow_slot_if_needed()
	if not _use_global_pool or not _pool or _pool_slot < 0:
		return

	if EffectsDebug.particle() and not has_meta("render_logged") and _particles.size() > 0:
		set_meta("render_logged", true)
		var dust_count = 0
		var flash_count = 0
		for p in _particles:
			if p.emitter_type == EMITTER_DUST:
				dust_count += 1
			elif p.emitter_type == EMITTER_FLASH:
				flash_count += 1
		print("[TrapEffect] Rendering %d particles (dust=%d, flash=%d), slot=%d" % [
			_particles.size(), dust_count, flash_count, _pool_slot])

	# Build the submission-order staging, then OT-depth-order it (far -> near, newest-on-top ties)
	# into the unified buffer + runs the compositor folds via the shared UnifiedPrimStager.publish
	# (which owns the order()->upload_unified ceremony + the "pass the ages or equal-depth ties
	# mis-order" contract). Trap's TRAP1 indexed sheet rides the fold shader's palette branch — pass
	# use_palette=true; the sheet and CLUT are ordinary Texture2D resources already stored on
	# the slot by _borrow_slot_if_needed. No RD texture exists on GL Compatibility.
	_stage_unified_prims()
	_stager.publish(_pool, _pool_slot, true)


func _compositor_mode_for(emitter_index: int) -> int:
	"""Map an emitter's blend_mode string (emitters.json) into the compositor mode enum
	(0=mix, 1=add, 2=sub, 3=add25). The shipped trap asset is all "ADD" -> 1 (pixel-identical
	today). Unknown / absent / out-of-range -> add (the safe additive-glow default)."""
	if emitter_index < 0 or emitter_index >= _emitters_config.size():
		return 1
	var bm: String = str(_emitters_config[emitter_index].get("blend_mode", "ADD"))
	return int(BLEND_MODE_TO_COMPOSITOR.get(bm, 1))


func _stage_unified_prims() -> void:
	"""#225: build the submission-order unified staging (records/modes/depths/ages) for the display-
	space compositor. Walks the SAME live-particle set + override-visibility skip as the MultiMesh
	write (so the staged prims match), computing each prim's 24-float record via the shared
	_particle_visual packing, its data-derived compositor mode, its ot_order_z fold key, and its age.
	The shared UnifiedPrimStager.append()s these (single-sourcing the 24-float layout + the ot_order_z
	depth key); it OT-depth-order()s them at publish (commit 4). No RD / no MultiMesh side effects."""
	# Per-frame camera view for the ot_order_z fold key (guarded — null camera leaves identity).
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var frame_view: Transform3D = cam.get_camera_transform().affine_inverse() if cam else Transform3D()
	_stager.begin(frame_view)

	for i in range(_particles.size()):
		var p: TrapParticle = _particles[i]
		# In override mode, skip invisible particles (same predicate as the MultiMesh write).
		if _override_mode and (i >= _particle_overrides.size() or not _particle_overrides[i].visible):
			continue
		var v := _particle_visual(p, i)
		if v.is_empty():
			continue
		_emit_record(v, _compositor_mode_for(p.emitter_type), p.age)


func _emit_record(v: Dictionary, mode: int, age: int) -> void:
	"""Stage one transparent prim via the shared UnifiedPrimStager (the 24-float record layout +
	parallel mode / ot_order_z depth / age keys, byte-identical across all producers). `mode` is
	already resolved (Trap's per-emitter blend_mode string via _compositor_mode_for); the stager uses
	_TRAP_DEPTH_MODE for the depth key and the view handed to begin()."""
	_stager.append(v["basis"], v["origin"], v["color"], v["uv_rect"], mode, _TRAP_DEPTH_MODE, float(age))


func _particle_visual(p: TrapParticle, index: int) -> Dictionary:
	"""Pure per-particle visual: the corner-basis (+depth_mode), world origin, texel-centered
	uv_rect, and color (rgb_mod or override brightness + palette_row packed in alpha). Feeds
	_emit_record, which packs it into the unified compositor staging (#225). Returns {} when the
	particle has no renderable frameset (the caller skips it). No side effects."""
	if p.current_frameset >= _framesets.size():
		return {}

	var frameset = _framesets[p.current_frameset]
	var frames = frameset.get("frames", [])
	if frames.is_empty():
		return {}

	# Use first frame in frameset
	var frame_data = frames[0]

	# Extract UV data
	var uv = frame_data.get("uv", {})
	var uv_x: float = float(uv.get("x", 0))
	var uv_y: float = float(uv.get("y", 0))
	var uv_w: float = float(uv.get("width", 8))
	var uv_h: float = float(uv.get("height", 8))

	# Get vertex corners
	var vertices = frame_data.get("vertices", {})
	var tl = vertices.get("top_left", [-8, -8])
	var tr = vertices.get("top_right", [8, -8])
	var bl = vertices.get("bottom_left", [-8, 8])
	var br = vertices.get("bottom_right", [8, 8])

	# World-space anchor (the shader rebuilds the billboard around MODEL_MATRIX[3])
	var world_pos: Vector3
	if _override_mode and index >= 0 and index < _particle_overrides.size():
		world_pos = _particle_overrides[index].position
	else:
		world_pos = global_position + p.position

	# Pack corners + depth_mode into the transform basis (ADR-0039 layout)
	var basis := Basis(
		Vector3(float(tl[0]), float(tl[1]), float(tr[0])),
		Vector3(float(tr[1]), float(bl[0]), float(bl[1])),
		Vector3(float(br[0]), float(br[1]), float(_TRAP_DEPTH_MODE))
	)

	# uv_rect (normalized, texel-centered) into INSTANCE_CUSTOM
	var uv_rect := Color(
		(uv_x + 0.5) / _texture_size.x,
		(uv_y + 0.5) / _texture_size.y,
		(uv_w - signf(uv_w)) / _texture_size.x,
		(uv_h - signf(uv_h)) / _texture_size.y
	)

	# color_modulate.rgb + per-instance palette_row (packed as palette_id/15 in alpha)
	var rgb: Vector3
	if _override_mode and index >= 0 and index < _particle_overrides.size():
		var b = _particle_overrides[index].brightness
		rgb = Vector3(b, b, b)
	else:
		rgb = p.rgb_mod
	var color := Color(rgb.x, rgb.y, rgb.z, float(p.palette_id) / 15.0)

	if EffectsDebug.iteration() and not has_meta("uv_logged"):
		set_meta("uv_logged", true)
		print("[TrapEffect] Frameset %d UV: x=%d y=%d w=%d h=%d, palette=%d, world=%s" % [
			p.current_frameset, uv_x, uv_y, uv_w, uv_h, p.palette_id, world_pos])

	return {"basis": basis, "origin": world_pos, "uv_rect": uv_rect, "color": color}


func _hide_all_meshes() -> void:
	"""Clear the slot's unified compositor buffer (count 0, no runs) so the combat compositor stops
	folding Trap (#225). No MultiMesh is a data source, so there's nothing else to zero — the sheet
	stays on the slot's plain _effect_tex field for get_active_effect_buckets (#227)."""
	if _use_global_pool and _pool and _pool_slot >= 0:
		_pool.upload_unified(_pool_slot, PackedByteArray(), 0, [])


func stop() -> void:
	"""Stop the effect immediately without emitting signal."""
	_is_playing = false
	_hide_all_meshes()
	_particles.clear()


func get_particle_count() -> int:
	"""Return current number of active particles."""
	return _particles.size()
