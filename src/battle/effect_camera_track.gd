class_name EffectCameraTrack
extends Node
## Moves `CameraController` for the duration of a cast. The addon reports where it wants
## the camera in the PS1 game's own units and never touches a `Camera3D` itself, so these
## three conversions do the whole job — the same ones the addon runs in reverse:
##
##   position  `PsxChirality.psx_position_to_godot`      (28 units/tile, Y negate)
##   angles    `PsxChirality.psx_angles_to_godot_rotation` (4096 = 360, pitch negated)
##   zoom      `CameraCalibration.zoom_to_ortho_size`    (12.6 ortho size at 4096)
## Roll is dropped — this rig has no roll axis — but warns once rather than silently.


const PsxChirality = ExMateriaPlatform.PsxChirality
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const CameraCalibration = ExMateriaPlatform.CameraCalibration

## PSX angle units, where 4096 is a full turn, so ~0.09 degrees. Below this a roll is float
## noise on an authored whole turn.
const ROLL_EPSILON: float = 1.0

## Must run after the node that advances the cast. At equal priority the one added first
## wins, and this would then apply last frame's pose — a lag nothing would log.
const PUMP_PRIORITY: int = 100

## The rig being driven. Nothing happens without one.
var rig: CameraController = null

## The `EffectInstance` currently holding the camera, or null.
var _cast: Node = null
## Cached: `release()` still needs it after the cast's `_exit_tree` has cleared its own.
var _subsystem = null
var _warned_roll: bool = false

## Counters rather than flags, so a volley that hands the camera to its first cast and
## refuses the rest is still legible afterwards.
var takeovers: int = 0
var refusals: int = 0
var frames_applied: int = 0
## The last pose pushed, both sides of the conversion, so a caller can compare them.
var last_psx_position: Vector3 = Vector3.ZERO
var last_psx_angles: Vector3 = Vector3.ZERO
var last_psx_zoom: float = 0.0
var last_focus: Vector3 = Vector3.ZERO
var last_orbit_degrees: Vector3 = Vector3.ZERO
var last_ortho_size: float = 0.0


func _init(camera_rig: CameraController = null) -> void:
	rig = camera_rig
	name = "EffectCameraTrack"
	process_priority = PUMP_PRIORITY


## Is an effect driving the camera right now?
func is_driving() -> bool:
	return _subsystem != null


## Offer a freshly spawned cast the camera. Checked by inspection, not by signal: the
## cast emits `camera_started` from inside `initialize()`, so anything connecting after
## the spawn has already missed it. `camera_finished` fires later and IS connected.
func adopt(cast: Node) -> bool:
	if not is_instance_valid(rig) or not is_instance_valid(cast):
		return false
	if not ("camera_controller" in cast) or cast.camera_controller == null:
		return false
	if is_driving():
		refusals += 1
		return false
	if not rig.begin_effect_takeover():
		refusals += 1
		return false
	_cast = cast
	_subsystem = cast.camera_controller
	takeovers += 1
	frames_applied = 0
	_seed_from_rig()
	if cast.has_signal(&"camera_finished") \
			and not cast.camera_finished.is_connected(_on_camera_finished):
		cast.camera_finished.connect(_on_camera_finished, CONNECT_ONE_SHOT)
	# Seed before returning, or the rig spends one frame marked as driven with no pose
	# written to it.
	pump()
	return true


## Push one frame. Safe to call unconditionally; does nothing unless a cast is driving.
func pump() -> void:
	if not is_driving():
		return
	# Either way the camera must come back rather than freeze mid-track.
	if not is_instance_valid(_cast) or not is_instance_valid(rig) \
			or not _subsystem.is_active():
		release()
		return
	apply_pose(_subsystem.current_position, _subsystem.current_angles,
		_subsystem.current_zoom)
	frames_applied += 1


## Convert one pose and write it to the rig. The only place the conversion happens, so a
## test can drive it directly with no cast in the scene.
func apply_pose(psx_position: Vector3, psx_angles: Vector3, psx_zoom: float) -> void:
	if not is_instance_valid(rig) or not rig.is_effect_driven():
		return
	_warn_roll_once(psx_angles.z)
	var focus: Vector3 = PsxChirality.psx_position_to_godot(psx_position)
	var rot: Vector3 = PsxChirality.psx_angles_to_godot_rotation(
		psx_angles.x, psx_angles.y, psx_angles.z)
	var orbit := Vector3(rad_to_deg(rot.x), rad_to_deg(rot.y), rad_to_deg(rot.z))
	# An ADDITIVE zoom channel accumulates unbounded, and the corpus carries raw keyframes
	# from -2976 to 8192.
	var size: float = clampf(CameraCalibration.zoom_to_ortho_size(psx_zoom),
		rig.zoom_in_max, rig.zoom_out_max)
	last_psx_position = psx_position
	last_psx_angles = psx_angles
	last_psx_zoom = psx_zoom
	last_focus = focus
	last_orbit_degrees = orbit
	last_ortho_size = size
	rig.apply_effect_pose(focus, orbit, size)


## Hand the camera back. Idempotent.
func release() -> void:
	if _cast != null and is_instance_valid(_cast) \
			and _cast.has_signal(&"camera_finished") \
			and _cast.camera_finished.is_connected(_on_camera_finished):
		_cast.camera_finished.disconnect(_on_camera_finished)
	_cast = null
	_subsystem = null
	if is_instance_valid(rig):
		rig.end_effect_takeover()


func _process(_delta: float) -> void:
	pump()


func _exit_tree() -> void:
	# A torn-down battle must not leave the rig driven with nothing left to drive it.
	release()


func _on_camera_finished() -> void:
	release()


## Tell the cast where the camera already is, converting the other way round from
## `apply_pose`. Most camera keyframes are relative to that starting pose, so without this
## they resolve against the addon's built-in defaults and the camera jumps somewhere
## unrelated to the battle.
func _seed_from_rig() -> void:
	if _subsystem == null or not is_instance_valid(rig):
		return
	_subsystem.saved_position = PsxChirality.godot_position_to_psx(rig.global_position)
	# The `+ 360` is load-bearing: the subsystem's 45-degree snap is `floorf(yaw / 512.0)`,
	# which sends a negative yaw to the spoke below rather than the nearest. A whole turn
	# is a no-op everywhere else.
	_subsystem.saved_angles = Vector3(
		PsxMagnitude.deg_to_angle(-rig.rotation_degrees.x),
		PsxMagnitude.deg_to_angle(rig.rotation_degrees.y + 360.0),
		0.0)
	_subsystem.saved_zoom = CameraCalibration.ortho_size_to_zoom(rig.camera.size)
	_subsystem.current_position = _subsystem.saved_position
	_subsystem.current_angles = _subsystem.saved_angles
	_subsystem.current_zoom = _subsystem.saved_zoom


## Some camera keyframes are positioned relative to the middle of the map, which the addon
## otherwise assumes is the world origin. `bounds` is in tiles.
func set_map_bounds(bounds: Rect2i) -> void:
	if _subsystem == null:
		return
	# `map_tiles * 14` per axis — half the 28 units a tile spans — and Y = 0.
	_subsystem.map_center = Vector3(
		float(bounds.size.x) * 14.0, 0.0, float(bounds.size.y) * 14.0)


func _warn_roll_once(psx_roll: float) -> void:
	if _warned_roll:
		return
	if absf(fposmod(psx_roll + 2048.0, 4096.0) - 2048.0) <= ROLL_EPSILON:
		return
	_warned_roll = true
	push_warning(("EffectCameraTrack: effect camera roll of %.0f PSX units (%.1f deg) "
		+ "DROPPED — CameraController has no roll axis and "
		+ "PsxChirality.psx_angles_to_godot_rotation returns z=0. Measured across the "
		+ "installed corpus this affects one effect (E452); if you are seeing it "
		+ "elsewhere the corpus changed.")
		% [psx_roll, PsxMagnitude.angle_to_deg(psx_roll)])
