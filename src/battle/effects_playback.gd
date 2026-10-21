class_name EffectsPlayback
extends Node3D
## Builds and owns the three addon objects one battle needs to draw effects, and is the
## only route by which an ability's VFX reach the screen.

## Opt-in. While false this node builds nothing, so the addon cannot affect a frame.
@export var enabled: bool = false

## Must be in the scene tree: spawned effects are parented under it and share its 3D world.
@export var battle_manager: Node

## Where the ROM-derived content lives. Empty keeps whatever the project setting holds.
@export var content_root: String = ""

## The rig a cast's CAMERA track drives, or null to leave the camera alone. Ordinary casts
## drive it too, not only cinematics.
@export var camera_rig: CameraController

## An effect's own clock rate — `EffectTimeline.PHYSICS_TIMESTEP`, the FFT game loop.
const EFFECT_FRAME_HZ: float = 30.0

## The longest palette RESTORE ramp in the corpus. Counted from the content — re-count if
## it is re-exported.
const PALETTE_RESTORE_RAMP_FRAMES: int = 32

## Keep in sync with `EffectManager.EFFECT_MIN_FRAME_FOR_CLEANUP`: the camera hand-back
## and the gameplay wait both end on this frame.
const VISUAL_DONE_MIN_FRAME: int = 50

## Wall-clock ceiling on one cast — a hang guard, not a policy. Derived per cast because
## `phase1_duration + phase2_delay` spans 0..618 frames; the slack covers `time_scale`
## pacing, as low as ~0.5x real time.
const CAST_PACING_SLACK: float = 3.0
const CAST_CAP_MIN_SECONDS: float = 12.0
const CAST_CAP_MAX_SECONDS: float = 30.0

var _producer: ExMateriaEffects.EngineFoldCompositor
var _host: EffectsCastHost
var _manager: ExMateriaEffects.EffectManager
## Moves `camera_rig` for whichever cast currently has it. Created on first use.
var _camera_track: EffectCameraTrack

## These must be freed here. The addon only cleans up casts it started through its own
## spell path, and these were started through a different one.
var _owned_casts: Array[Node3D] = []

var _camera_cast: Node3D = null

## Why playback is unavailable, or "" when it is.
var unavailable_reason: String = ""


func is_available() -> bool:
	return _manager != null


func manager() -> ExMateriaEffects.EffectManager:
	return _manager


## Set everything up for `camera`. On failure returns false with `unavailable_reason`
## filled in, and leaves nothing half-built.
func initialize(camera: Camera3D) -> bool:
	_shutdown()
	if not enabled:
		unavailable_reason = "disabled: EffectsPlayback.enabled is false"
		return false
	if not is_instance_valid(battle_manager) or not battle_manager.is_inside_tree():
		unavailable_reason = "no battle: battle_manager is unset or not in the scene"
		return false
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		unavailable_reason = "no camera: setup_auto needs an IN-TREE Camera3D"
		return false
	# Without a root every cast resolves to "" and fails as a missing file.
	if not content_root.is_empty():
		ProjectSettings.set_setting(
			ExMateriaEffects.EffectsContent.ROOT_SETTING, content_root)
	if not ExMateriaEffects.EffectsContent.has_root():
		unavailable_reason = (
			"no content root: set `%s` to a directory holding effects/, effects/trap/ "
			+ "and sprites/textures/TRAP1*.tga"
		) % ExMateriaEffects.EffectsContent.ROOT_SETTING
		return false

	var producer := ExMateriaEffects.EngineFoldCompositor.new()
	add_child(producer)
	if not producer.setup_auto(camera):
		producer.queue_free()
		unavailable_reason = "setup_auto refused for this camera/renderer"
		return false

	_producer = producer
	_host = EffectsCastHost.new(battle_manager)
	_manager = ExMateriaEffects.EffectManager.new(_host)
	unavailable_reason = ""
	return true


func shutdown() -> void:
	_shutdown()


func _shutdown() -> void:
	# Before the manager goes, or the rig freezes mid-track with nothing to advance it.
	if is_instance_valid(_camera_track):
		_camera_track.release()
	_camera_cast = null
	# The addon will not clean these up, so a torn-down battle would leave every live cast
	# still holding a unit tint and a map tint.
	for cast: Node3D in _owned_casts:
		if is_instance_valid(cast):
			cast.queue_free()
	_owned_casts.clear()
	_manager = null
	_host = null
	if is_instance_valid(_producer):
		_producer.queue_free()
	_producer = null


func _exit_tree() -> void:
	_shutdown()


## The `E###` number `action` should draw, or -1 for nothing. Only the digits of `vfx_name`
## count, since exports spell it `e_192` or `E192`; it wins over a disagreeing `vfx_id`.
static func effect_id_for(action: Action) -> int:
	if action == null:
		return -1
	var named: int = -1
	if not action.vfx_name.is_empty():
		var digits: String = ""
		for c: String in action.vfx_name:
			if c >= "0" and c <= "9":
				digits += c
		if not digits.is_empty():
			named = digits.to_int()
	if named >= 0:
		if named != action.vfx_id:
			push_warning(
				("EffectsPlayback: action \"%s\" disagrees with itself about its effect "
				+ "— vfx_name \"%s\" says E%03d, vfx_id says E%03d. Drawing the name's, "
				+ "which is what the old vfx_data path resolved. Re-export the action "
				+ "data; a stale export here draws the WRONG effect, not nothing.")
				% [action.unique_name, action.vfx_name, named, action.vfx_id])
		return named
	# Only here does 0 mean "none": with no `vfx_name` to corroborate it, a zero is
	# indistinguishable from an unset field.
	return action.vfx_id if action.vfx_id > 0 else -1


## Ids already reported missing, so a per-action cast loop cannot bury the reason.
var _missing_content: Dictionary = {}


## Play `action`'s ability VFX from `caster` at `target`. Returns the spawned node, or null
## when nothing was cast; pass it to `await_casts` for gameplay timing.
func play_action_vfx(caster: Node3D, target: Node3D, action: Action) -> Node3D:
	if not is_available() or not is_instance_valid(caster) or not is_instance_valid(target):
		return null
	if caster is Unit or target is Unit:
		push_error("EffectsPlayback: pass `unit.char_body`, not the Unit — a Unit's own "
			+ "transform is never set, so the cast would spawn at the world origin.")
		return null
	var effect_id: int = effect_id_for(action)
	if effect_id < 0:
		return null
	# `initialize()` reports a missing directory only by freeing the instance, which looks
	# exactly like an effect that drew nothing.
	var dir: String = ExMateriaEffects.EffectsContent.effect_dir("E%03d" % effect_id)
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		if not _missing_content.has(effect_id):
			_missing_content[effect_id] = true
			push_warning(
				("EffectsPlayback: no content at \"%s\" for E%03d, so \"%s\" draws "
				+ "nothing. Copy the per-effect `E###` directories into the content root.")
				% [dir, effect_id, action.unique_name])
		return null
	# -1: `Action` has no numeric ability id. The cinematic spawn skips the wall-clock
	# cleanup that would cut a cast off mid-timeline (see `_reap_cast`).
	var cast: Node3D = _manager.spawn_cinematic_effect(caster, target, -1, effect_id)
	if cast == null:
		# Initialization failed; the manager already freed its instance.
		return null
	_owned_casts.append(cast)
	_offer_camera(cast)
	_reap_cast(cast)
	return cast


## TODO: route charge-time abilities through `spawn_cinematic_effect` if they need the
## real callbacks.
func _offer_camera(cast: Node) -> void:
	if not is_instance_valid(camera_rig):
		return
	if not is_instance_valid(_camera_track):
		_camera_track = EffectCameraTrack.new(camera_rig)
		add_child(_camera_track)
	_camera_track.rig = camera_rig
	if not _camera_track.adopt(cast):
		return
	_camera_cast = cast as Node3D


## Owns one cast's lifetime. The addon's reaper budgets wall-clock time while effects count
## frames, so it cuts casts before `phase1_duration + phase2_delay`, the palette RESTORE never
## runs, and the flash snaps off. `_cast_visual_done` still ends the camera and gameplay waits.
func _reap_cast(cast: Node3D) -> void:
	var restore_frame: int = _palette_restore_frame(cast)
	# A hang guard: if the effect never gets there, the cast still goes.
	var budget: float = clampf(
		float(restore_frame) / EFFECT_FRAME_HZ * CAST_PACING_SLACK,
		CAST_CAP_MIN_SECONDS, CAST_CAP_MAX_SECONDS)
	var waited: float = 0.0
	var handed_back: bool = false
	while is_instance_valid(cast) and waited < budget:
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
		if not is_instance_valid(cast) or not is_inside_tree():
			break
		waited += tree.root.get_process_delta_time()
		var visual_done: bool = _cast_visual_done(cast)
		if visual_done and not handed_back:
			handed_back = true
			# Back when the cast stops DRAWING, not at the end of the colour tail.
			if is_instance_valid(_camera_track) and _camera_cast == cast:
				_camera_track.release()
				_camera_cast = null
		if visual_done and cast.get_effect_frame() >= restore_frame:
			break
	_owned_casts.erase(cast)
	if _camera_cast == cast:
		if is_instance_valid(_camera_track):
			_camera_track.release()
		_camera_cast = null
	if is_instance_valid(cast):
		cast.queue_free()


## Phase 2's start plus the longest ramp, off the cast's own parsed timeline. 0 when an
## effect carries no timeline, leaving the wall-clock floor.
func _palette_restore_frame(cast: Node3D) -> int:
	if not is_instance_valid(cast) or cast.effect_data == null \
			or cast.effect_data.timeline == null:
		return 0
	var timeline = cast.effect_data.timeline
	return int(timeline.phase1_duration) + int(timeline.phase2_delay) \
		+ PALETTE_RESTORE_RAMP_FRAMES


func _cast_visual_done(cast: Node3D) -> bool:
	if not is_instance_valid(cast):
		return true
	return cast.get_active_particle_count() == 0 \
		and cast.get_effect_frame() > VISUAL_DONE_MIN_FRAME


## The live camera track, or null.
func camera_track() -> EffectCameraTrack:
	return _camera_track


## `play_action_vfx` aimed at a position rather than a node.
func play_action_vfx_at(caster: Node3D, world_position: Vector3, action: Action) -> Node3D:
	if not is_available() or not is_instance_valid(caster):
		return null
	var marker := Node3D.new()
	marker.name = "AbilityVfxTarget"
	add_child(marker)
	marker.global_position = world_position
	var cast: Node3D = play_action_vfx(caster, marker, action)
	if cast == null:
		marker.queue_free()
		return null
	# The addon parents a tracking anchor to the marker, so it lives until the cast exits;
	# the timer only guards a cast that never leaves the tree.
	cast.tree_exited.connect(
		func() -> void:
			if is_instance_valid(marker):
				marker.queue_free(),
		CONNECT_ONE_SHOT)
	get_tree().create_timer(CAST_CAP_MAX_SECONDS + 2.0).timeout.connect(
		func() -> void:
			if is_instance_valid(marker):
				marker.queue_free(),
		CONNECT_ONE_SHOT)
	return cast


## Plays a TRAP handler: hit clouds, knight break, the charge and orb poses. Take `handler_id`
## from the ROM's tables; deriving it from an ability id misses handler 6 (Accumulate's orbs).
## The addon lifts the handler into E### form, so it plays as an ordinary EffectInstance.
func play_shared_vfx(handler_id: int, element_id: int, from_position: Vector3,
		target_unit: Node3D, flash: bool, _is_melee: bool = true) -> bool:
	if not is_available() or handler_id <= 0 or not is_instance_valid(target_unit):
		return false
	var variant: String = "h%02d" % handler_id
	if not ExMateriaEffects.TrapLift.HANDLERS.has(variant):
		return false
	var data = ExMateriaEffects.TrapLift.runtime_data(variant, element_id)
	if data == null:
		return false
	var impact: Vector3 = target_unit.global_position + Vector3(0, TRAP_IMPACT_RISE, 0)
	var effect := ExMateriaEffects.EffectInstance.new()
	battle_manager.add_child(effect)
	if not effect.initialize_from_data(
			ExMateriaEffects.TrapLift.DOCUMENT_PREFIX + variant, data, impact, TRAP_POOL_SIZE):
		effect.queue_free()
		return false
	effect.global_position = impact
	var direction: Vector3 = (impact - from_position).normalized()
	effect.set_anchors(Vector3.ZERO, Vector3.ZERO, -direction, Vector3.ZERO)
	# The white flash rides the target's palette track.
	effect.set_unit_targets(null, target_unit if flash else null)
	effect.auto_loop = false
	_owned_casts.append(effect)
	_reap_when_finished(effect)
	return true


func _reap_when_finished(effect: Node3D) -> void:
	while is_instance_valid(effect) and is_inside_tree():
		await get_tree().process_frame
		if is_instance_valid(effect) and effect.get_effect_frame() > 2 and effect.is_finished():
			break
	_owned_casts.erase(effect)
	if is_instance_valid(effect):
		effect.queue_free()


const TRAP_POOL_SIZE: int = 256
## Lifts the impact off the tile floor so clouds read as hitting a body, not the ground.
const TRAP_IMPACT_RISE: float = 0.3


## Wait for the casts `play_action_vfx*` returned, or `fallback_seconds` when none. Gameplay
## timing depends on it; `any()` lets several targets resolve together, not in sequence.
func await_casts(casts: Array[Node3D], fallback_seconds: float = 0.5,
		max_seconds: float = 12.0) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var live := casts.filter(func(c: Node3D) -> bool: return is_instance_valid(c))
	if live.is_empty():
		await tree.create_timer(fallback_seconds).timeout
		return
	# Waits on the VISUAL, not the node: `_reap_cast` holds a cast past its last particle,
	# and node validity would add that colour tail to every ability's resolution.
	var waited: float = 0.0
	while waited < max_seconds and live.any(
			func(c: Node3D) -> bool:
				return is_instance_valid(c) and not _cast_visual_done(c)):
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
