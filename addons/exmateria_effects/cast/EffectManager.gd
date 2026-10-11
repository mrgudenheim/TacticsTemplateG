extends RefCounted
## Manages spell effects, trap effects, item effects, and charge VFX.
##
## Extracted from the combat loop (ADR-0018). Owns effect spawning, cleanup polling,
## and charge VFX lifecycle. Emits signals for reaction triggers.
## Vault: [[Elemental Puff Particle System]]
## Vault: [[Emitter Anchor Modes]]
## Vault: [[Hit Reaction Particle Burst]]
## Vault: [[Knight Break Impact Particle System]]
## Vault: [[Spell Charge Effect System]]
## Vault: [[Spell Charge Lines System]]
## Vault: [[Summon Charge Lines System]]
## Vault: [[Summon Orb Orbital System]]
## Vault: [[TRAP Charge Particle System]]
## Vault: [[TRAP Hit Effect Particle System]]
## Vault: [[TRAP Sprite Effect System]]
## Vault: [[Transformed Pose System]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectsContent = preload("res://addons/exmateria_effects/install/EffectsContent.gd")
const CastHost = preload("res://addons/exmateria_effects/install/CastHost.gd")
const EffectInstance = preload("res://addons/exmateria_effects/cast/EffectInstance.gd")

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaPlatform` a complete census of host->addon symbol coupling.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

# 🔴 ADR-0364 — `const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase` STOOD HERE.
# Two calls off it (`get_ability_view`, `is_break_visual_formula`) were this addon's
# whole reach into `exmateria_almanac`, and they cost a `deps=` edge onto a
# 20,830-line generated ROM table for FIVE fields. The break-visual formulas were
# a visual fact and moved INTO `AbilityVisual`; the lookup is now
# `_host.ability_visual(id)`, answered at the seam that already carries the roster.


signal ability_react_triggered(frame: int, target_idx: int, ability_id: int)
signal hit_reaction_triggered(frame: int, target_idx: int, ability_id: int)
signal refresh_tile_triggered(frame: int, target_idx: int)

const EffectInstanceClass = preload("res://addons/exmateria_effects/cast/EffectInstance.gd")
const TrapEffectClass = preload("res://addons/exmateria_effects/trap/TrapEffect.gd")
const TrapChargeLineEffectClass = preload("res://addons/exmateria_effects/trap/TrapChargeLineEffect.gd")
const TrapOrbitalEffectClass = preload("res://addons/exmateria_effects/trap/TrapOrbitalEffect.gd")

# Charge pose → TRAP handler for standard particle effects
# Poses 1 and 2 use special renderers (handlers 4, 22)
const CHARGE_POSE_TO_HANDLER: Dictionary = {
	0: 8, 1: 15, 2: 8, 3: 8, 4: 8, 5: 8,
}
# Charge+N ability IDs always use handler 6 regardless of pose
const CHARGE_PLUS_ABILITY_IDS: Array = [0x92, 0x196, 0x197, 0x198, 0x199, 0x19A, 0x19B, 0x19C, 0x19D]

# Active charge VFX effects (standard particles, charge lines, or orbital orbs)
var _active_charge_effects: Dictionary = {}  # unit_idx → Node

# Only ordinary spell/item instances: cinematics remain caller-owned. Keep these
# across tree exit, which can detach (not free) the stage and all its children.
var _owned_effects: Dictionary = {}  # instance_id → Node

# Pending TRAP effects deferred to PostGenericAttack animation opcode
var _pending_trap: Dictionary = {}  # caster_unit_idx -> { position, impact_dir, target_unit, ability_id, is_melee }

# Policy belongs to the module that polls, not its host.
const EFFECT_INITIAL_WAIT_SEC: float = 0.5
const EFFECT_POLL_INTERVAL_SEC: float = 0.1
const EFFECT_POLL_TIMEOUT: int = 100
const EFFECT_MIN_FRAME_FOR_CLEANUP: int = 50
const HEAD_HEIGHT_PSX: float = 24.0 / PsxMagnitude.UNITS_PER_TILE

var _host: CastHost
var _ended: bool = false


func _init(host: CastHost) -> void:
	_host = host
	var scene_stage := _live_stage()
	if scene_stage == null:
		push_error("EffectManager requires a CastHost with a live scene-owned stage (not the root viewport).")
		return
	# Teardown is terminal, even if the host later reparents/reuses the stage.
	scene_stage.tree_exiting.connect(_on_stage_exiting, CONNECT_ONE_SHOT)


func _live_stage() -> Node:
	if _ended or _host == null:
		return null
	var scene_stage := _host.stage()
	if not is_instance_valid(scene_stage) or not scene_stage.is_inside_tree() \
			or scene_stage.is_queued_for_deletion() or scene_stage == scene_stage.get_tree().root:
		_ended = true
		return null
	return scene_stage


func _on_stage_exiting() -> void:
	_ended = true
	_pending_trap.clear()
	# Actors can be siblings of the stage (NavigatorMain preserves the world after
	# freeing its CombatLoop). Their charges must not survive the manager's battle.
	for unit_idx in _active_charge_effects.keys():
		stop_charge_vfx(unit_idx, true)
	for effect in _owned_effects.values():
		if is_instance_valid(effect):
			effect.queue_free()
	_owned_effects.clear()


func spawn_spell_effect(caster: Node3D, target: Node3D, ability_id: int, effect_id: int) -> void:
	"""Spawn visual spell effect at target location."""
	var scene_stage := _live_stage()
	if scene_stage == null:
		return
	var effect_id_str = "E%03d" % effect_id
	var effect_path = EffectsContent.effect_dir(effect_id_str)
	if EffectsDebug.iteration():
		var dir_exists = DirAccess.dir_exists_absolute(effect_path)
		print("  [EFFECT_DEBUG] _spawn_spell_effect: effect_id=%d -> id_str='%s' path='%s' exists=%s" % [
			effect_id, effect_id_str, effect_path, str(dir_exists)])

	# Find unit indices for logging
	var actors := _host.actors()
	var caster_idx = actors.find(caster)
	var target_idx = actors.find(target)
	_host.note_cast(caster_idx, target_idx, effect_id_str)

	var effect = EffectInstanceClass.new()
	# Parent to the CombatLoop node (in the scene), NOT get_viewport() (the
	# persistent root viewport). A scene reset (reload_current_scene via
	# _reset_arena / --combat-auto-reset / Ctrl+R) frees the scene subtree but
	# leaves root-viewport children orphaned — their _exit_tree never fires, so
	# orphan_effect never reaches ExMateriaEffectSfx and the cast leaks (#121,
	# orphan_sub=-1). Under CombatLoop the effect dies with the scene and cleans
	# up correctly. The effect's world transform is set via global_position below,
	# and pause/render are group/global-driven, so the parent change is inert
	# except for lifetime. Same World3D either way (CombatLoop is a sibling of the
	# old parent under the root viewport).
	scene_stage.add_child(effect)

	var caster_pos = caster.global_position
	var target_pos = target.global_position

	var success = effect.initialize(
		effect_id_str,
		effect_path,
		caster_pos,
		512  # particle pool size
	)

	if not success:
		effect.queue_free()
		return

	# Position effect at caster, use local offsets for anchors
	effect.global_position = caster_pos

	# Anchors as local offsets from effect position
	var target_offset = target_pos - caster_pos

	effect.set_anchors(
		target_offset,   # world = toward target
		target_offset,   # cursor = toward target
		Vector3.ZERO,    # origin = at effect position (caster)
		target_offset    # target = toward target
	)

	# Set unit references for palette tinting
	effect.set_unit_targets(caster, target)

	# Attach anchor markers so effect tracks unit movement
	effect.attach_anchors_to_units(caster, target)
	if EffectsDebug.iteration():
		print("  [EFFECT_DEBUG] attach_anchors_to_units complete: origin=%s target=%s" % [
			str(effect._origin_anchor != null), str(effect._target_anchor != null)])

	# Disable looping - spell effects play once
	effect.auto_loop = false

	# Connect ability_react_triggered to emit signal for reaction manager
	effect.ability_react_triggered.connect(
		func(frame): ability_react_triggered.emit(frame, target_idx, ability_id))

	# Connect hit_reaction_triggered (HIT_REACT keyframe — CPU-side "particles
	# hit" beat). Re-emitted so tests/observers can correlate the runtime's
	# heal-applies beat with downstream events like the carrier's rise pose.
	effect.hit_reaction_triggered.connect(
		func(frame): hit_reaction_triggered.emit(frame, target_idx, ability_id))

	# Connect refresh_tile_triggered to emit signal for reaction manager
	effect.refresh_tile_triggered.connect(
		func(frame): refresh_tile_triggered.emit(frame, target_idx))

	# Set up cleanup when effect finishes
	_owned_effects[effect.get_instance_id()] = effect
	_setup_effect_cleanup(effect)


func spawn_cinematic_effect(caster: Node3D, target: Node3D, ability_id: int,
		effect_id: int, on_camera_started: Callable = Callable(),
		on_camera_finished: Callable = Callable()) -> EffectInstance:
	"""Spawn the cinematic-spell EffectInstance for a charge_time > 0 ability.

	Mirrors spawn_spell_effect but flips is_cinematic=true so the EffectInstance
	opts out of the combat_visuals group (ADR-0037 dec. 7). The caller
	holds the returned reference for cinematic-ended teardown; reaction wiring
	stays identical to the standard spell-effect spawn. Camera signal callbacks
	(if supplied) are wired BEFORE initialize() because camera_started fires
	during init — matches EffectViewerScene._on_effect_camera_started's flow.
	"""
	var scene_stage := _live_stage()
	if scene_stage == null:
		return null
	var effect_id_str = "E%03d" % effect_id
	var effect_path = EffectsContent.effect_dir(effect_id_str)

	var actors := _host.actors()
	var caster_idx = actors.find(caster)
	var target_idx = actors.find(target)
	_host.note_cast(caster_idx, target_idx, effect_id_str)

	var effect = EffectInstanceClass.new()
	effect.is_cinematic = true
	# Parent to the in-scene CombatLoop, not the persistent root viewport, so a
	# scene reset frees it and its _exit_tree fires orphan_effect (#121). See
	# spawn_spell_effect for the rationale.
	scene_stage.add_child(effect)

	# Connect BEFORE initialize — camera_started emits inside initialize() when
	# the effect's CameraSubsystem comes online. Connecting afterwards misses it
	# entirely (the camera takeover never fires).
	#
	# bind(effect) so the handler gets the instance — the spawn function hasn't
	# returned to the caller yet, so the caller's own `_active_cinematic_effect`
	# field is still the prior value at handler-fire time. The handler needs
	# the live one for its camera-controller seeding.
	if on_camera_started.is_valid():
		effect.camera_started.connect(on_camera_started.bind(effect))
	if on_camera_finished.is_valid():
		effect.camera_finished.connect(on_camera_finished)

	# Seed map_center_godot before initialize so the CAMERA particle anchor
	# matches EFFECT_CTR (otherwise the camera controller orbits the wrong
	# focal point). EffectViewerScene does the same for its standalone scene.
	var bounds := _host.arena_bounds()
	if bounds.has_area():
		effect.map_center_godot = Vector3(float(bounds.size.x) / 2.0, 0.0,
			float(bounds.size.y) / 2.0)

	var caster_pos = caster.global_position
	var target_pos = target.global_position
	var success = effect.initialize(effect_id_str, effect_path, caster_pos, 512)
	if not success:
		effect.queue_free()
		return null

	effect.global_position = caster_pos
	var target_offset = target_pos - caster_pos
	effect.set_anchors(target_offset, target_offset, Vector3.ZERO, target_offset)
	effect.set_unit_targets(caster, target)
	effect.attach_anchors_to_units(caster, target)
	effect.auto_loop = false

	effect.ability_react_triggered.connect(
		func(frame): ability_react_triggered.emit(frame, target_idx, ability_id))
	effect.hit_reaction_triggered.connect(
		func(frame): hit_reaction_triggered.emit(frame, target_idx, ability_id))
	effect.refresh_tile_triggered.connect(
		func(frame): refresh_tile_triggered.emit(frame, target_idx))

	# No _setup_effect_cleanup — the cinematic lifecycle is owned by the
	# CombatLoop edge handlers (Phase 4.6 teardown on cinematic-ended).
	return effect


func spawn_trap_effect(position: Vector3, impact_direction: Vector3,
		target_unit: Node, ability_id: int = -1, is_melee: bool = true) -> void:
	"""Spawn TrapEffect at impact location using play_handler() API.

	Routes to correct handler based on ability formula:
	- formula 0x25/0x2E (break/holy sword): handler 21 (Knight Break)
	- all other attacks: handler 2 (Hit Clouds)
	Hit Clouds use melee=[0, 9] vs ranged=[0, 1] emitter split.
	"""
	if _live_stage() == null or not is_instance_valid(target_unit):
		return
	var trap = TrapEffectClass.new()
	target_unit.add_child(trap)

	var element_id: int = 0
	var handler_id: int = 2  # Default: Hit Clouds

	if ability_id > 0:
		var ability := _host.ability_visual(ability_id)
		element_id = ability.element_id
		if ability.plays_break_visual():
			handler_id = 21  # Knight Break
		if EffectsDebug.particle():
			print("[TRAP_ROUTE] ability=%d (%s) formula=%d -> handler=%d element=%d" % [
				ability_id, ability.display_name, ability.formula, handler_id, element_id])

	if not trap.initialize(7, element_id):
		trap.queue_free()
		return

	# Log effect spawn
	var target_idx = _host.actors().find(target_unit)
	_host.note_cast(-1, target_idx, "TrapEffect")

	if handler_id == 2:
		# Hit Clouds: melee uses [0, 9], ranged uses [0, 1]
		var emitter_indices: Array[int] = []
		if is_melee:
			emitter_indices.assign([0, 9])
		else:
			emitter_indices.assign([0, 1])
		trap.play_at(position + Vector3(0, 0.3, 0), impact_direction,
			target_unit, emitter_indices, true)
	else:
		trap.play_handler(handler_id, element_id, position + Vector3(0, 0.3, 0),
			impact_direction, target_unit)

	if EffectsDebug.iteration():
		print("[%s] Spawned TrapEffect at %s (ability=%d, handler=%d, element=%d)" % [
			_host.diagnostic_label(), position, ability_id, handler_id, element_id])


func spawn_item_effect(target: Node3D, effect_dir_num: int) -> void:
	"""Spawn item visual effect at target location (e.g., E260 for Potion)."""
	var scene_stage := _live_stage()
	if scene_stage == null:
		return
	var effect_id_str = "E%03d" % effect_dir_num
	var effect_path = EffectsContent.effect_dir(effect_id_str)

	# Check if effect directory exists
	if not DirAccess.dir_exists_absolute(effect_path):
		if EffectsDebug.iteration():
			print("[%s] Item effect not found: %s" % [_host.diagnostic_label(), effect_path])
		return

	# Log effect spawn
	var target_idx = _host.actors().find(target)
	_host.note_cast(-1, target_idx, effect_id_str)

	var effect = EffectInstanceClass.new()
	# In-scene parent (CombatLoop), not the root viewport, so a scene reset frees
	# it and its _exit_tree fires orphan_effect (#121). See spawn_spell_effect.
	scene_stage.add_child(effect)

	var target_pos = target.global_position

	var success = effect.initialize(
		effect_id_str,
		effect_path,
		target_pos,
		256  # particle pool size
	)

	if not success:
		effect.queue_free()
		return

	effect.global_position = target_pos
	effect.set_anchors(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	effect.set_unit_targets(null, target)
	effect.auto_loop = false

	_owned_effects[effect.get_instance_id()] = effect
	_setup_effect_cleanup(effect)

	if EffectsDebug.iteration():
		print("[%s] Spawned item effect %s at target %s" % [_host.diagnostic_label(), effect_id_str, target.name])


func spawn_charge_vfx(unit_idx: int, ability_id: int) -> void:
	"""Spawn charge VFX for a unit entering LOGICAL_ACTIVITY_SPELL_CHARGING.

	Routes to handler based on ability:
	- Charge+N abilities → handler 6 (Charge+X particles)
	- Pose 0, 3-5 → handler 8 (Charge Particles A) via TrapEffect
	- Pose 1 → TrapChargeLineEffect (handler 4: spell charge lines)
	- Pose 2 → TrapOrbitalEffect (handler 22: orbital summon orbs)
	"""
	if _live_stage() == null:
		return
	var actors := _host.actors()
	if unit_idx < 0 or unit_idx >= actors.size() or not is_instance_valid(actors[unit_idx]):
		return

	# Stop any existing charge effect on this unit (force kill for replacement)
	stop_charge_vfx(unit_idx, true)

	var unit = actors[unit_idx]
	var ability := _host.ability_visual(ability_id)
	if ability.is_empty():
		return

	var pose_id: int = ability.charging_pose_id
	var element_id: int = ability.element_id

	# Route to effect type
	if ability_id in CHARGE_PLUS_ABILITY_IDS:
		# Charge+N abilities always use handler 6
		_spawn_charge_standard(unit_idx, unit, 6, element_id)
	elif pose_id == 1:
		# Spell charge lines (handler 4)
		_spawn_charge_lines(unit_idx, unit)
	elif pose_id == 2:
		# Orbital summon orbs (handler 22)
		_spawn_charge_orbital(unit_idx, unit)
	else:
		# Standard charge particles (handler 8 for pose 0, 3-5)
		var handler_id: int = CHARGE_POSE_TO_HANDLER.get(pose_id, 8)
		_spawn_charge_standard(unit_idx, unit, handler_id, element_id)

	if EffectsDebug.particle():
		var handler_name = ""
		if _active_charge_effects.has(unit_idx):
			var effect = _active_charge_effects[unit_idx]
			handler_name = effect.get_class()
		print("[Tick %d] [CHARGE_VFX] %s: ability=%d pose=%d -> %s" % [
			_host.diagnostic_tick(), unit.name, ability_id, pose_id, handler_name])


func stop_charge_vfx(unit_idx: int, force: bool = false) -> void:
	"""Stop charge effect for a unit.

	When force=false (default), effects with start_fade() fade out gracefully
	and clean up via _on_charge_vfx_finished. When force=true, kills immediately
	(used by spawn_charge_vfx to replace an existing effect).
	"""
	var effect = _active_charge_effects.get(unit_idx)
	if not effect or not is_instance_valid(effect):
		_active_charge_effects.erase(unit_idx)
		return

	if not force and effect.has_method("start_fade"):
		effect.start_fade()
		# Leave in _active_charge_effects — animation_finished will clean up
		return

	if effect.has_method("stop"):
		effect.stop()
	effect.queue_free()
	_active_charge_effects.erase(unit_idx)


func set_pending_trap(caster_idx: int, data: Dictionary) -> void:
	if _live_stage() == null:
		return
	_pending_trap[caster_idx] = data


func fire_pending_trap(caster_idx: int) -> bool:
	"""Fire deferred TRAP if one is pending for this caster.

	Returns true iff a pending trap was consumed — the caller uses this to avoid
	also spawning the hit cloud for the same PostGenericAttack (deferred weapon
	abilities own their cloud)."""
	var pending = _pending_trap.get(caster_idx)
	if not pending:
		return false
	_pending_trap.erase(caster_idx)
	var target_unit = pending["target_unit"]
	if _live_stage() != null and is_instance_valid(target_unit):
		if EffectsDebug.particle():
			var actors := _host.actors()
			var caster: Node3D = actors[caster_idx] if caster_idx >= 0 and caster_idx < actors.size() else null
			print("[Tick %d] [TRAP_DEBUG] PostGenericAttack -> deferred TRAP: caster=%s target=%s ability=%d" % [
				_host.diagnostic_tick(),
				caster.name if is_instance_valid(caster) else "?",
				target_unit.name, pending["ability_id"]])
		spawn_trap_effect(pending["position"], pending["impact_dir"],
			target_unit, pending["ability_id"], pending["is_melee"])
	return true


func clear_pending_trap(caster_idx: int) -> void:
	_pending_trap.erase(caster_idx)


func _setup_effect_cleanup(effect: Node) -> void:
	var instance_id := effect.get_instance_id()
	await _poll_effect_cleanup(effect)
	_owned_effects.erase(instance_id)


func _poll_effect_cleanup(effect: Node) -> void:
	"""Monitor effect and clean it up when finished."""
	# Wait for initial particles to spawn
	if _live_stage() == null:
		return
	await _live_stage().get_tree().create_timer(EFFECT_INITIAL_WAIT_SEC).timeout

	if not is_instance_valid(effect) or _live_stage() == null:
		return

	# Poll until no particles remain or timeout
	var poll_count = 0
	var saw_particles = false
	while is_instance_valid(effect) and _live_stage() != null:
		var count = effect.get_active_particle_count()
		var frame = effect.get_effect_frame()
		poll_count += 1
		if count > 0:
			saw_particles = true
		# Clean up if we've seen particles and they've all finished
		if count == 0 and saw_particles and frame > EFFECT_MIN_FRAME_FOR_CLEANUP:
			effect.queue_free()
			return
		if poll_count > EFFECT_POLL_TIMEOUT:
			effect.queue_free()
			return
		if _live_stage() == null:
			return
		await _live_stage().get_tree().create_timer(EFFECT_POLL_INTERVAL_SEC).timeout


func _spawn_charge_standard(unit_idx: int, unit: Node, handler_id: int, element_id: int) -> void:
	"""Spawn a standard TrapEffect-based charge particle effect (handlers 6, 8, 15)."""
	var trap = TrapEffectClass.new()
	unit.add_child(trap)
	if not trap.initialize(7, element_id):
		trap.queue_free()
		return
	var pos = unit.global_position + Vector3(0, HEAD_HEIGHT_PSX, 0)
	trap.play_handler(handler_id, element_id, pos, Vector3.ZERO, null)
	trap.animation_finished.connect(_on_charge_vfx_finished.bind(unit_idx))
	_active_charge_effects[unit_idx] = trap


func _spawn_charge_lines(unit_idx: int, unit: Node) -> void:
	"""Spawn spell charge line effect (handler 4)."""
	var effect = TrapChargeLineEffectClass.new()
	unit.add_child(effect)
	effect.start(unit.global_position, unit, _host.actor_element_id(unit))
	effect.animation_finished.connect(_on_charge_vfx_finished.bind(unit_idx))
	_active_charge_effects[unit_idx] = effect


func _spawn_charge_orbital(unit_idx: int, unit: Node) -> void:
	"""Spawn orbital summon orb effect (handler 22)."""
	var effect = TrapOrbitalEffectClass.new()
	unit.add_child(effect)
	effect.start(unit.global_position, unit, false)  # No auto-fade; controlled by LOGICAL_ACTIVITY_SPELL_CHARGING exit
	effect.animation_finished.connect(_on_charge_vfx_finished.bind(unit_idx))
	_active_charge_effects[unit_idx] = effect


func _on_charge_vfx_finished(unit_idx: int) -> void:
	"""Clean up charge effect entry after it finishes fading out."""
	_active_charge_effects.erase(unit_idx)
