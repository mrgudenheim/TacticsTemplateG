class_name EffectCameraTrack
extends Node
## Moves `CameraController` for the duration of a cast, converting the camera poses the
## addon computes in PSX units into Godot ones.


const PsxChirality = ExMateriaPlatform.PsxChirality
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const CameraCalibration = ExMateriaPlatform.CameraCalibration
const DisplayPort = ExMateriaPlatform.DisplayPort

## PSX angle units, where 4096 is a full turn, so ~0.09 degrees. Below this a roll is float
## noise on an authored whole turn.
const ROLL_EPSILON: float = 1.0

## Must run after the node that advances the cast. At equal priority the one added first
## wins, and this would then apply last frame's pose — a lag nothing would log.
const PUMP_PRIORITY: int = 100

## The rig being driven.
var rig: CameraController = null

var _cast: Node = null
## Cached: `release()` still needs it after the cast's `_exit_tree` has cleared its own.
var _subsystem = null
var _warned_roll: bool = false

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


## Offer a freshly spawned cast the camera, right after the spawn and before its first
## frame: `camera_started` fires inside `initialize()`, and keyframes resolve against the
## pose seeded here. `seed_pose` false re-takes a cast already seeded — its backward seek
## replays the camera from that same pose. False when the cast has no camera track or the
## rig is taken.
func adopt(cast: Node, seed_pose: bool = true) -> bool:
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
	if seed_pose:
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


## Convert one PSX pose and write it to the rig.
func apply_pose(psx_position: Vector3, psx_angles: Vector3, psx_zoom: float) -> void:
	if not is_instance_valid(rig) or not rig.is_effect_driven():
		return
	_warn_roll_once(psx_angles.z)
	# Through the subsystem: camera positions live in the ROM's map frame, reflected in depth
	# about the map centre relative to the imported terrain.
	var focus: Vector3 = _subsystem.psx_position_to_world(psx_position) if _subsystem != null \
		else PsxChirality.psx_position_to_godot(psx_position)
	var rot: Vector3 = PsxChirality.psx_angles_to_godot_rotation(
		psx_angles.x, psx_angles.y, psx_angles.z)
	var orbit := Vector3(rad_to_deg(rot.x), rad_to_deg(rot.y), rad_to_deg(rot.z))
	# An additive zoom channel accumulates without bound.
	var size: float = clampf(CameraCalibration.zoom_to_ortho_size(psx_zoom),
		rig.zoom_in_max, rig.zoom_out_max)
	# FFT frames its optical centre 40 native px below the frame's middle, an offset kept in
	# the GTE translation rather than the keyframe; without it the scene sits that much too
	# high. Camera-local up, so it holds at every orbit.
	focus += Basis.from_euler(rot).y * DisplayPort.VERTICAL_DATUM_PX \
		* DisplayPort.native_px_to_world(size)
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


## Tell the cast where the camera already is. Most camera keyframes are relative to this
## starting pose; unseeded, they resolve against addon defaults and the camera jumps away.
func _seed_from_rig() -> void:
	if _subsystem == null or not is_instance_valid(rig):
		return
	# `map_center` is already set: the cast seeds it from the host's arena bounds during
	# `initialize()`, and the conversion reflects about it.
	_subsystem.saved_position = _subsystem.world_position_to_psx(rig.global_position)
	# `+ 360`: the subsystem snaps yaw with `floorf(yaw / 512.0)`, which sends a negative yaw
	# to the spoke below rather than the nearest.
	_subsystem.saved_angles = Vector3(
		PsxMagnitude.deg_to_angle(-rig.rotation_degrees.x),
		PsxMagnitude.deg_to_angle(rig.rotation_degrees.y + 360.0),
		0.0)
	_subsystem.saved_zoom = CameraCalibration.ortho_size_to_zoom(rig.camera.size)
	_subsystem.current_position = _subsystem.saved_position
	_subsystem.current_angles = _subsystem.saved_angles
	_subsystem.current_zoom = _subsystem.saved_zoom


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
