extends RefCounted
## Manages spell effects, trap effects, item effects, and charge VFX.
## Owns effect spawning, cleanup polling, and charge VFX lifecycle (ADR-0018);
## emits signals for reaction triggers.
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

# ADR-0364: the `AbilityDatabase` alias is intentionally absent — that one `deps=`
# edge cost a 20,830-line generated ROM table for five fields. The break-visual
# formulas live in `AbilityVisual`; the lookup is `_host.ability_visual(id)`,
# answered at the seam that already carries the roster.


## An ABILITY_REACT keyframe of the cast aimed at `target_idx`. `scope` is
## EffectInstance.action_scope() (an EffectInstance.ActionScope): every target at once, the
## FIRST target's beat of a for_each lane the ROM replays per target, or the caster alone.
## Which units the cast hit is the host's to know; it fans the react out to them.
signal ability_react_triggered(frame: int, target_idx: int, ability_id: int, scope: int)
signal hit_reaction_triggered(frame: int, target_idx: int, ability_id: int)
## A REFRESH_TILE keyframe (0x20: the react ends); `scope` as ability_react_triggered.
signal refresh_tile_triggered(frame: int, target_idx: int, scope: int)

const EffectInstanceClass = preload("res://addons/exmateria_effects/cast/EffectInstance.gd")
## TRAP visuals (hit clouds, Knight Break, charge particles, charge lines, summon orbs)
## are TRAP handlers lifted into E### form and played through EffectInstance (ADR-0369);
## the hand-written TrapEffect simulation they replace was retired once the ROM capture
## (research/working_documents/TRAP_HIT_CLOUD_RENDER_PARITY.md) showed the lift matches.
const TrapLift = preload("res://addons/exmateria_effects/trap/TrapLift.gd")

# The charge visual is `AbilitySequence.charge_variant(pose)`: `DAT_801B84AC[pose]`
# (BATTLE.BIN 0x1514AC: `00 02 05 00 ...`) is nonzero only for pose 1 (lines, handler 4)
# and pose 2 (summon orbs, handler 22). Every other pose — items' 9, Charge+N's and
# Accumulate's included — allocates nothing while charging (P1, PCSX DYNAMIC). Charge+N's
# and Accumulate's red orbs are an engine secondary at RELEASE (state 0x2B), not a charge
# visual: `AbilitySequence.plan().engine_secondary`.
const AbilitySequence = preload("res://addons/exmateria_effects/cast/AbilitySequence.gd")

# Active charge VFX effects (standard particles, charge lines, or orbital orbs)
var _active_charge_effects: Dictionary = {}  # unit_idx → Node

# Only ordinary spell/item instances: cinematics remain caller-owned. Keep these
# across tree exit, which can detach (not free) the stage and all its children.
var _owned_effects: Dictionary = {}  # instance_id → Node

const EFFECT_INITIAL_WAIT_SEC: float = 0.5
const EFFECT_POLL_INTERVAL_SEC: float = 0.1
## The reap backstop, in the effect's OWN frames past its loop bound (`reap_backstop_frame`).
## 315 = the ~10.5 s wall-clock cut it replaces, at 30 Hz, so no effect is freed earlier
## than before; over all 401 effects the ROM reap lands at most 210 frames past the bound
## (E453: bound 871, reap 1081), so the backstop never pre-empts it (EffectEndModelTest).
const EFFECT_REAP_BACKSTOP_MARGIN: int = 315
## Polls with the effect's frame standing still before it is freed anyway: a clock that
## never runs (a timeline-less slot never starts) would otherwise hold it forever. A
## running effect resets it every frame, so this never cuts one short.
const EFFECT_STALL_POLLS: int = 100
const EFFECT_MIN_FRAME_FOR_CLEANUP: int = 50

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

	var actors := _host.actors()
	var caster_idx = actors.find(caster)
	var target_idx = actors.find(target)
	_host.note_cast(caster_idx, target_idx, effect_id_str)

	var effect = EffectInstanceClass.new()
	# Parent to the in-scene stage, NOT the root viewport: a scene reset frees the
	# scene subtree but leaves root-viewport children orphaned — their _exit_tree
	# never fires, orphan_effect never runs, and the cast leaks (#121). Under the
	# stage the effect dies with the scene; the world transform is set via
	# global_position and pause/render are group-driven, so the parent is inert
	# except for lifetime.
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

	effect.global_position = caster_pos

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

	effect.auto_loop = false

	effect.ability_react_triggered.connect(
		func(frame): ability_react_triggered.emit(frame, target_idx, ability_id,
			effect.action_scope()))

	# HIT_REACT keyframe — the CPU-side "particles hit" beat; re-emitted so
	# tests/observers can correlate it with downstream events.
	effect.hit_reaction_triggered.connect(
		func(frame): hit_reaction_triggered.emit(frame, target_idx, ability_id))

	effect.refresh_tile_triggered.connect(
		func(frame): refresh_tile_triggered.emit(frame, target_idx, effect.action_scope()))

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
	# One for_each lane per unit the cast hits (N36), set before initialize arms the sound.
	var lanes := _host.for_each_lanes(caster_idx, target_idx, effect_id)
	if not lanes.is_empty():
		effect.set_for_each_lanes(lanes.units, lanes.offsets)
	# Parent to the in-scene CombatLoop, not the persistent root viewport, so a
	# scene reset frees it and its _exit_tree fires orphan_effect (#121). See
	# spawn_spell_effect for the rationale.
	scene_stage.add_child(effect)

	# Connect BEFORE initialize — camera_started emits inside initialize() when
	# the effect's CameraSubsystem comes online; connecting afterwards misses it.
	#
	# bind(effect) so the handler gets the live instance: the spawn call hasn't
	# returned, so the caller's `_active_cinematic_effect` is still the prior
	# value at handler-fire time.
	if on_camera_started.is_valid():
		effect.camera_started.connect(on_camera_started.bind(effect))
	if on_camera_finished.is_valid():
		effect.camera_finished.connect(on_camera_finished)

	# Seed map_center_godot before initialize so the CAMERA particle anchor matches
	# EFFECT_CTR (otherwise the camera controller orbits the wrong focal point).
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
		func(frame): ability_react_triggered.emit(frame, target_idx, ability_id,
			effect.action_scope()))
	effect.hit_reaction_triggered.connect(
		func(frame): hit_reaction_triggered.emit(frame, target_idx, ability_id))
	effect.refresh_tile_triggered.connect(
		func(frame): refresh_tile_triggered.emit(frame, target_idx, effect.action_scope()))

	# No _setup_effect_cleanup — the cinematic lifecycle is owned by the
	# CombatLoop edge handlers (teardown on cinematic-ended).
	return effect


func spawn_sequence_payload(caster: Node3D, target: Node3D, handler: String,
		ability_id: int = -1) -> EffectInstance:
	"""Spawn an ENGINE payload of an ability sequence (ADR-0372 dec. 15) — the TRAP
	handler `AbilitySequence.engine_payload_handler` names (Accumulate's red orbs, h06) —
	as the lifted document the Effect Studio opens for the same payload (TrapLift
	`load_document`, unit-anchored like the Studio's `_play`). is_cinematic=true: it plays
	inside the freeze window, exempt from combat_visuals (ADR-0037 dec. 7). It plays to its
	OWN reap — `_setup_effect_cleanup`, the rule every live cast ends by — never the
	window's end: the ROM runs the orbs through `battle_effect_update_secondary_effects`
	(0x801B47E0), not awaited by the action, and the Studio plays the whole document
	(EffectEndModel's end). Freeing it at the unfreeze cut it at frame ~5-11 of 21 (N10)."""
	var scene_stage := _live_stage()
	if scene_stage == null or not is_instance_valid(caster) or not is_instance_valid(target):
		return null
	var document_id := TrapLift.DOCUMENT_PREFIX + handler
	var data = TrapLift.load_document(document_id)
	if data == null:
		return null
	var actors := _host.actors()
	var target_idx := actors.find(target)
	_host.note_cast(actors.find(caster), target_idx, document_id)
	var effect = EffectInstanceClass.new()
	effect.is_cinematic = true
	scene_stage.add_child(effect)
	var caster_pos := caster.global_position
	if not effect.initialize_from_data(document_id, data, caster_pos, 512):
		effect.queue_free()
		return null
	effect.global_position = caster_pos
	var target_offset := target.global_position - caster_pos
	effect.set_anchors(target_offset, target_offset, Vector3.ZERO, target_offset)
	effect.set_unit_targets(caster, target)
	effect.attach_anchors_to_units(caster, target)
	effect.auto_loop = false
	# The payload's 0x40 / 0x20 reach the host's pose selector like a spell's, ruled on
	# the sequence's own ability. No payload lifted so far keys either; wired so one that
	# does is not silently dropped. Unwired without an ability: nothing to rule on.
	if ability_id >= 0:
		effect.ability_react_triggered.connect(
			func(frame): ability_react_triggered.emit(frame, target_idx, ability_id,
			effect.action_scope()))
		effect.refresh_tile_triggered.connect(
			func(frame): refresh_tile_triggered.emit(frame, target_idx, effect.action_scope()))
	_owned_effects[effect.get_instance_id()] = effect
	_setup_effect_cleanup(effect)
	return effect


func spawn_trap_effect(position: Vector3, impact_direction: Vector3,
		target_unit: Node, ability_id: int = -1, _is_melee: bool = true, cloud: int = -1) -> EffectInstance:
	"""Play the TRAP hit cloud at an impact: handler 2, or handler 21 (Knight Break) for a
	break/holy-sword formula. Lifted into E### form and played through EffectInstance.
	`cloud` is the ROM's cloud animation when the caller knows the result
	(`AbilitySequence.impact_cloud`: CLOUD_BREAK -> handler 21, CLOUD_HIT -> handler 2);
	-1 falls back to the ability's formula.

	Handler 2 is the variant with the white flash (config 1). The ROM picks config 9 (no
	flash) by the init record's result byte (+0x1d == 3), NOT by melee vs ranged — a real
	melee hit reads 0 and runs config 1 + flash (TRAP_HIT_CLOUD_RENDER_PARITY.md §2) — so
	`_is_melee` no longer chooses anything; which actions set 3 is still open there.
	Returns the instance, or null — the caller decides its freeze membership (a sequence's
	cloud plays inside its window, `CombatLoop._spawn_hit_cloud`)."""
	var scene_stage := _live_stage()
	if scene_stage == null or not is_instance_valid(target_unit):
		return null
	var element_id: int = 0
	var variant := "h02"
	if ability_id > 0:
		var ability := _host.ability_visual(ability_id)
		element_id = ability.element_id
		if cloud < 0 and ability.plays_break_visual():
			variant = "h21"
		if EffectsDebug.particle():
			print("[TRAP_ROUTE] ability=%d (%s) formula=%d -> %s element=%d" % [
				ability_id, ability.display_name, ability.formula, variant, element_id])
	if cloud == AbilitySequence.CLOUD_BREAK:
		variant = "h21"
	var data = TrapLift.runtime_data(variant, element_id)
	if data == null:
		return null
	var effect = EffectInstanceClass.new()
	scene_stage.add_child(effect)
	var at := position + Vector3(0, 0.3, 0)
	if not effect.initialize_from_data(TrapLift.DOCUMENT_PREFIX + variant, data, at, 256):
		effect.queue_free()
		return null
	effect.global_position = at
	# DIRECTIONAL emitters aim origin → target (the ROM's 0x400 start → end anchor).
	var dir := impact_direction.normalized() if impact_direction.length_squared() > 0.001 else Vector3.ZERO
	effect.set_anchors(Vector3.ZERO, Vector3.ZERO, -dir, Vector3.ZERO)
	effect.set_unit_targets(null, target_unit)   # the white flash rides the target palette track
	effect.auto_loop = false
	var target_idx = _host.actors().find(target_unit)
	_host.note_cast(-1, target_idx, TrapLift.DOCUMENT_PREFIX + variant)
	_owned_effects[effect.get_instance_id()] = effect
	_setup_effect_cleanup(effect)
	if EffectsDebug.iteration():
		print("[%s] Spawned TRAP %s at %s (ability=%d, element=%d)" % [
			_host.diagnostic_label(), variant, position, ability_id, element_id])
	return effect


func spawn_item_effect(target: Node3D, effect_dir_num: int, held: bool = false,
		caster: Node3D = null, ability_id: int = -1) -> EffectInstance:
	"""Spawn item visual effect at target location (e.g., E260 for Potion).

	`held` loads it without playing (PSX `effect_system_state` 1, ITEM_USE_EXECUTION.md
	§6): the caller releases it with `release_effect` — at projectile impact for a
	thrown item, at once for a hand-over. Returns the instance, or null.

	`caster` / `ability_id` are the item use's: the file's ABILITY_REACT (0x40) and
	REFRESH_TILE (0x20) keyframes are re-emitted exactly as a spell's, and the host's
	pose selector needs the real caster — FUN_80083978 (0x80083978) plays nothing when
	caster == target, so a Potion drunk by its own user does not react (N29)."""
	var scene_stage := _live_stage()
	if scene_stage == null:
		return null
	var effect_id_str = "E%03d" % effect_dir_num
	var effect_path = EffectsContent.effect_dir(effect_id_str)

	if not DirAccess.dir_exists_absolute(effect_path):
		if EffectsDebug.iteration():
			print("[%s] Item effect not found: %s" % [_host.diagnostic_label(), effect_path])
		return null

	var actors := _host.actors()
	var target_idx = actors.find(target)
	_host.note_cast(actors.find(caster) if caster != null else -1, target_idx, effect_id_str)

	var effect = EffectInstanceClass.new()
	effect.held = held
	# In-scene parent (CombatLoop), not the root viewport, so a scene reset frees
	# it and its _exit_tree fires orphan_effect (#121). See spawn_spell_effect.
	scene_stage.add_child(effect)

	# Seed the map centre BEFORE initialize, as spawn_cinematic_effect does: the camera
	# controller converts its target position with it during initialize, and an item's
	# FOR-EACH table pans to that target. Unseeded, the conversion skipped the map
	# reflection that the host's camera bridge then applied — the pan went to the
	# target's MIRROR image.
	var bounds := _host.arena_bounds()
	if bounds.has_area():
		effect.map_center_godot = Vector3(float(bounds.size.x) / 2.0, 0.0,
			float(bounds.size.y) / 2.0)

	var target_pos = target.global_position

	var success = effect.initialize(
		effect_id_str,
		effect_path,
		target_pos,
		256  # particle pool size
	)

	if not success:
		effect.queue_free()
		return null

	effect.global_position = target_pos
	effect.set_anchors(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	effect.set_unit_targets(null, target)
	effect.auto_loop = false

	effect.ability_react_triggered.connect(
		func(frame): ability_react_triggered.emit(frame, target_idx, ability_id,
			effect.action_scope()))
	effect.refresh_tile_triggered.connect(
		func(frame): refresh_tile_triggered.emit(frame, target_idx, effect.action_scope()))

	_owned_effects[effect.get_instance_id()] = effect
	# A held effect's clock stands still until it plays, which the cleanup poll would
	# read as a stall, so it is only handed to it then.
	if effect.is_held():
		effect.released.connect(_setup_effect_cleanup.bind(effect), CONNECT_ONE_SHOT)
	else:
		_setup_effect_cleanup(effect)

	if EffectsDebug.iteration():
		print("[%s] Spawned item effect %s at target %s" % [_host.diagnostic_label(), effect_id_str, target.name])
	return effect


func release_effect(effect: EffectInstance) -> void:
	"""Start a held effect (PSX `FUN_801A1880`, `effect_system_state` 1 -> 2)."""
	if is_instance_valid(effect):
		effect.play_held()


func spawn_charge_vfx(unit_idx: int, ability_id: int) -> void:
	"""Spawn charge VFX for a unit entering LOGICAL_ACTIVITY_SPELL_CHARGING.

	The visual is `AbilitySequence.charge_variant(charging pose)`, the ROM's table:
	- Pose 1 → handler 4 (spell charge lines, tinted by the ABILITY's element byte)
	- Pose 2 → handler 22 (orbital summon orbs)
	- Every other pose → nothing (PSX allocates no charge animation).
	Both are lifted TRAP documents (ADR-0369), HELD until stop_charge_vfx.
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
	match AbilitySequence.charge_variant(pose_id):
		"h04":
			_spawn_charge_lines(unit_idx, unit, ability.element_byte)
		"h22":
			_spawn_charge_orbital(unit_idx, unit)
		_:
			return

	if EffectsDebug.particle():
		var handler_name = ""
		if _active_charge_effects.has(unit_idx):
			var effect = _active_charge_effects[unit_idx]
			handler_name = effect.get_class()
		print("[Tick %d] [CHARGE_VFX] %s: ability=%d pose=%d -> %s" % [
			_host.diagnostic_tick(), unit.name, ability_id, pose_id, handler_name])


## The charge `unit_idx` is playing, or null.
func charge_effect(unit_idx: int) -> Node:
	var effect = _active_charge_effects.get(unit_idx)
	return effect if is_instance_valid(effect) else null


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

	if not force:
		# Held charges wind down (lines finish contracting, orbs fade), then free
		# themselves; a one-shot charge that is still playing just finishes.
		effect.release()
		return

	effect.queue_free()
	_active_charge_effects.erase(unit_idx)


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

	var backstop := reap_backstop_frame(effect)
	var saw_particles = false
	var last_frame := -1
	var stalled_polls := 0
	while is_instance_valid(effect) and _live_stage() != null:
		var count: int = effect.get_active_particle_count()
		if count > 0:
			saw_particles = true
		if reap_ready(effect, count, saw_particles):
			effect.queue_free()
			return
		var frame: int = effect.get_effect_frame()
		stalled_polls = stall_polls_after(stalled_polls, frame, last_frame, not effect.can_process())
		last_frame = frame
		if frame > backstop or stalled_polls > EFFECT_STALL_POLLS:
			effect.queue_free()
			return
		if _live_stage() == null:
			return
		await _live_stage().get_tree().create_timer(EFFECT_POLL_INTERVAL_SEC).timeout


## The stall count after one cleanup poll: one more when the effect's frame did not move since the
## last poll, else zero. A FROZEN effect is not a stalled one — the host's stop (the Space stop, the
## pause, a cinematic's spotlight) disables its processing, and a stop longer than the stall budget
## used to reap every effect it froze (N37) — so only a clock that could run counts.
static func stall_polls_after(stalled_polls: int, frame: int, last_frame: int, frozen: bool) -> int:
	if frozen:
		return 0
	return stalled_polls + 1 if frame == last_frame else 0


## The frame past which a live cast is freed whatever it is doing (N5): the ROM's loop bound
## — the timeline bound T of a 3-phase root, hdr+0xA of a 1-phase one (0x801A2C28, which
## `EffectEndModel.timeline_bound` leaves at 0) — plus EFFECT_REAP_BACKSTOP_MARGIN. Counted
## in the effect's own frames, so a long T (E453: 871) plays out and pacing slows it too.
static func reap_backstop_frame(effect) -> int:
	var bound: int = effect.timeline_bound()
	if bound <= 0:
		var data = effect.get("effect_data")
		if data != null and data.timeline != null:
			bound = int(data.timeline.header.get("phase2_delay", 0))
	return bound + EFFECT_REAP_BACKSTOP_MARGIN


## May the live cast be freed now? Freeing it ends its camera (camera_finished), so this
## is also when the battle gets its camera back. A 3-phase root (EffectInstance.
## timeline_bound() > 0) ends at the ROM's reap, `is_finished()`: held to the timeline
## bound T however early its particles die (N3; E005 T = 140). Any other root ends when
## its particles are gone: the model has no ROM end for a 1-phase root, and its
## quiescence answer waits on block windows that close ~f600 or never (E043, E192, E231,
## E232, E486) — measured over all 401 effects, EffectEndModelTest. Always past
## EFFECT_MIN_FRAME_FOR_CLEANUP, after particles were seen, and never mid-camera (an
## item's restore would be cut short when its particles die first). `particle_count` is
## this poll's one read of get_active_particle_count().
static func reap_ready(effect, particle_count: int, saw_particles: bool) -> bool:
	if not saw_particles or effect.get_effect_frame() <= EFFECT_MIN_FRAME_FOR_CLEANUP:
		return false
	var cam_ctrl = effect.get("camera_controller")
	if cam_ctrl != null and not cam_ctrl.is_settled():
		return false
	if effect.timeline_bound() > 0:
		return effect.is_finished()
	return particle_count == 0


func _spawn_charge_lines(unit_idx: int, unit: Node, element_byte: int) -> void:
	"""Spell charge lines (handler 4), held until release, tinted by the ABILITY's element
	byte — its first set bit in the ROM's order (SPELL_CHARGE_LINES.md §7), not the caster's."""
	_spawn_charge("h04", TrapLift.TrapChargeLineColours.index_for_element_byte(element_byte),
		TrapLift.HOLD_TICKS, unit_idx, unit, unit.global_position)


func _spawn_charge_orbital(unit_idx: int, unit: Node) -> void:
	"""Orbital summon orbs (handler 22), held until LOGICAL_ACTIVITY_SPELL_CHARGING exits."""
	_spawn_charge("h22", 0, TrapLift.HOLD_TICKS, unit_idx, unit, unit.global_position)


func _spawn_charge(variant: String, element_id: int, hold_ticks: int, unit_idx: int,
		unit: Node, at: Vector3) -> void:
	var effect = _spawn_trap(variant, element_id, hold_ticks, unit, at)
	if effect == null:
		return
	_active_charge_effects[unit_idx] = effect
	_watch_charge(unit_idx, effect)


## The level-up sparkle, secondary effect 0xD (`battle_effect_level_up_secondary_handler`
## 0x801B2D28, research/working_documents/LEVEL_UP_PRESENTATION.md §3): TRAP h13, one burst rising
## off the unit's feet that ends by itself (~55 vsyncs). It is no charge: `charge_effect` never
## sees it, and a second one plays beside the first. Returns the effect, or null.
func spawn_level_up_sparkle(unit: Node) -> Node:
	if not unit is Node3D:
		return null
	var effect = _spawn_trap("h13", 0, 0, unit, unit.global_position)
	if effect != null:
		_reap_when_drawn(effect)
	return effect


## A TRAP-lifted effect on `unit` at `at`, or null.
func _spawn_trap(variant: String, element_id: int, hold_ticks: int, unit: Node, at: Vector3) -> Node:
	var scene_stage := _live_stage()
	if scene_stage == null:
		return null
	var data = TrapLift.runtime_data(variant, element_id, hold_ticks)
	if data == null:
		return null
	var effect = EffectInstanceClass.new()
	# A charge plays in the cast's wind-up, inside the cinematic that freezes the rest of
	# combat_visuals, so it opts out like the cinematic's own effect (ADR-0037 dec. 7).
	effect.is_cinematic = true
	scene_stage.add_child(effect)
	if not effect.initialize_from_data(TrapLift.DOCUMENT_PREFIX + variant, data, Vector3.ZERO, 256):
		effect.queue_free()
		return null
	effect.global_position = at
	effect.set_anchors(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	effect.auto_loop = false
	# Follow the charging unit, as the hand-written charge effects did.
	if unit is Node3D:
		effect.attach_anchors_to_units(unit, unit)
	return effect


func _watch_charge(unit_idx: int, effect: Node) -> void:
	"""Free a charge effect once it has nothing left to draw (a one-shot burst ends by
	itself; a held one after release()), and drop its entry."""
	await _reap_when_drawn(effect)
	if _active_charge_effects.get(unit_idx) == effect:
		_on_charge_vfx_finished(unit_idx)


func _reap_when_drawn(effect: Node) -> void:
	while is_instance_valid(effect) and _live_stage() != null:
		await _live_stage().get_tree().create_timer(EFFECT_POLL_INTERVAL_SEC).timeout
		if not is_instance_valid(effect):
			break
		if effect.get_effect_frame() > 2 and effect.is_finished():
			effect.queue_free()
			break


func _on_charge_vfx_finished(unit_idx: int) -> void:
	"""Clean up charge effect entry after it finishes fading out."""
	_active_charge_effects.erase(unit_idx)
