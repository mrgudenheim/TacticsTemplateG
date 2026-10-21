extends RefCounted
## Runtime camera subsystem.
##
## Mirrors the PSX routines at 0x801AD198 (per-frame channel advance) and
## 0x801ACB08 (`battle_camera_find_active_keyframe`, the active-keyframe search, ported
## branch for branch in [method _find_active_keyframe]). Evaluates keyframes from 3 phase
## tables (phase1 = main, for_each, phase2 = cleanup) and interpolates angle, position, and
## zoom channels independently. A for_each keyframe is found FOR A TARGET — the search's
## target index — and its TARGET source frames that target (gl-ADR-0410). `Keyframe.channel_mask` is a bitmask that
## selects which of {angle, position, zoom} a keyframe activates.
## Vault: [[Effect Camera System]]
## Vault: [[Effect Execution Model]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const CameraData = preload("res://addons/exmateria_effects/file_model/CameraData.gd")

## ADR-0212 dec. 1 — aliased from the single global `ExMateriaPlatform` the
## platform addon publishes (ADR-0211 dec. 4).
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


const CameraDataClass = preload("res://addons/exmateria_effects/file_model/CameraData.gd")

# Channel IDs (bitmask values stored in Keyframe.channel_mask)
const CHANNEL_ANGLE := 1
const CHANNEL_POSITION := 2
const CHANNEL_ZOOM := 4

# Per-channel interpolation state ("" = idle, non-empty = interpolating)
var angle_state: String = ""   # angles
var position_state: String = ""   # position
var zoom_state: String = ""   # zoom

# Current camera values (PSX coordinate space)
var current_angles: Vector3 = Vector3(302, 3584, 0)   # pitch, yaw, roll
var current_position: Vector3 = Vector3.ZERO
var current_zoom: float = 4096.0
# Standard sprites submit BEFORE the camera advances on PSX (0x801AA1F8 reads
# 0x800C7CA0; the later camera setter 0x8008B834 publishes the next zoom).
# Preserve that sample across rendering/paused redraws rather than using the
# post-advance pose. This is Q12 corner scale, not Camera3D.size.
var sprite_zoom_q12: float = 4096.0

# Interpolation targets (per channel)
var angle_from: Vector3 = Vector3.ZERO
var angle_to: Vector3 = Vector3.ZERO
var position_from: Vector3 = Vector3.ZERO
var position_to: Vector3 = Vector3.ZERO
var zoom_from: float = 0.0
var zoom_to: float = 0.0
var angle_frame: int = 0
var angle_total: int = 0
var position_frame: int = 0
var position_total: int = 0
var zoom_frame: int = 0
var zoom_total: int = 0

# Additive per-frame values (for ADDITIVE interpolation)
var angle_additive: Vector3 = Vector3.ZERO
var position_additive: Vector3 = Vector3.ZERO
var zoom_additive: float = 0.0

# Shake amplitude (for SHAKE_* interpolation)
var angle_shake_amp: Vector3 = Vector3.ZERO
var position_shake_amp: Vector3 = Vector3.ZERO
var zoom_shake_amp: float = 0.0

# Saved slots for SLOT_COPY (populated at effect start from current camera)
var saved_angles: Vector3 = Vector3(302, 3584, 0)
var saved_position: Vector3 = Vector3.ZERO
var saved_zoom: float = 4096.0

# Map center in PSX world coords (map_tiles * 14 per axis, Y=0)
# Used by EFFECT_CTR source mode and CAMERA particle anchor
var map_center: Vector3 = Vector3.ZERO

# Phase timing (the effect's misc header: phase1_duration, spawn_delay, phase2_delay) and the
# hit counter. phase2_start is derived: the cleanup table's origin,
# phase1 + (hit_counter - 1) * spawn_delay + phase2_delay (0x801ACB08).
var phase1_duration: int = 0
var spawn_delay: int = 0
var phase2_delay: int = 0
var phase2_start: int = 0
var target_count: int = 1

# External position references (set by EffectInstance)
var target_position: Vector3 = Vector3.ZERO   # PSX coords
var caster_position: Vector3 = Vector3.ZERO
var cursor_position: Vector3 = Vector3.ZERO
## The ALL_TARGETS source (0x180): the centroid of the target table, as
## execute_camera_position_command (0x801AB1D4) averages every entry's unit. Set by a
## fanned-out EffectInstance (N36); null = the one target (a single-target document).
var all_targets_position = null

# Cinematic facing resolution (ADR-0039). Injected by the cinematic host; null
# in standalone EffectViewerScene, where _get_facing_yaw falls back to the bare
# ROM snap. The focused-unit refs (plain Unit nodes) let the resolver raycast
# the right silhouette and exclude the unit's own collider. Resolution is
# cached per focused subject — the cinematic freeze pins every position, so the
# only thing that changes is WHICH subject we're framing (caster -> target).
var facing_resolver = null
var caster_unit = null
var target_unit = null
var cursor_unit = null
## The target table, in hit order: the unit the for_each search's target index k names
## (0x801ACB08 reports k with the keyframe it finds). Empty = the one-target document, whose
## target is `target_unit`. Set with [method set_target_units].
var target_units: Array = []
## PSX positions of `target_units`, pushed by the host each frame alongside target_position.
var target_positions: Array = []
var _facing_yaw_cache := {}   # "unit|base|pitch|yaw_offset" -> resolved yaw (PSX)

# Pre-phase-1 pan to the caster (issue #53): the live battle's casters fire without
# the turn change that frames the actor on PSX, so without it the camera opens the
# effect from wherever it was. The PATH is the host's — the ROM's turn-change pan, one
# pivot per battle loop (CinematicManager, N22) — this only plays it back.
var pre_pan_armed: bool = false
var pre_pan_remaining: int = 0
var _pre_pan_path: Array = []   # PSX positions, [0] = the pose the pan starts from
var _pre_pan_index: int = 0

var _data: CameraData = null
var _active: bool = false
var _last_frame: int = -1  # last frame advance() ran for (is_settled)

# Per-instance RNG (ADR-0070). Threaded from the owning EffectInstance so camera
# SHAKE is deterministic within the instance — a scrub back-and-forth reproduces
# the same jitter instead of re-rolling it. null = global fallback.
var rng: RandomNumberGenerator = null


func _rr(a: float, b: float) -> float:
	"""Instance-RNG randf_range() with a global fallback (camera shake draws)."""
	return rng.randf_range(a, b) if rng != null else randf_range(a, b)


## `p2_delay` is the header's phase2_delay; `t_count` the hit counter (targets in the table).
func initialize(data: CameraData, p1_duration: int, s_delay: int, p2_delay: int, t_count: int = 1) -> void:
	"""Initialize with parsed camera keyframe data and phase timing"""
	_data = data
	phase1_duration = p1_duration
	spawn_delay = s_delay
	phase2_delay = p2_delay
	target_count = maxi(1, t_count)
	phase2_start = phase1_duration + (target_count - 1) * spawn_delay + phase2_delay
	_active = data != null and data.has_active_keyframes()

	# New cinematic -> drop any cached per-subject facing yaws.
	_facing_yaw_cache.clear()

	angle_state = ""
	position_state = ""
	zoom_state = ""
	_last_frame = -1
	angle_frame = 0
	position_frame = 0
	zoom_frame = 0


func is_active() -> bool:
	return _active


## The target table, hit order (see `target_units`). `units[0]` also becomes `target_unit`.
func set_target_units(units: Array) -> void:
	target_units = units.duplicate()
	if not target_units.is_empty():
		target_unit = target_units[0]


func _target_unit_at(k: int):
	return target_units[k] if k >= 0 and k < target_units.size() else target_unit


func _target_position_at(k: int) -> Vector3:
	if k >= 0 and k < target_positions.size():
		return target_positions[k]
	return target_position


## The table has run out: no track is interpolating and no keyframe is active at
## the last frame advanced. A host that hands the camera back when the effect goes
## away keeps the effect until this holds, so an item's SLOT_COPY restore is not cut
## short by a particle-driven cleanup. False before the first advance.
func is_settled() -> bool:
	if not _active:
		return true
	if _last_frame < 0 or pre_pan_armed:
		return false
	if angle_state != "" or position_state != "" or zoom_state != "":
		return false
	for channel in [CHANNEL_ANGLE, CHANNEL_POSITION, CHANNEL_ZOOM]:
		if _find_active_keyframe(_last_frame, channel) != null:
			return false
	return true


## Camera keyframes use the ROM map frame; imported terrain reverses depth.
## Keep this at the camera boundary, not in the effect-vector conversion shared
## by emitters. The map centre supplies the continuous reflection plane.
func world_position_to_psx(world: Vector3) -> Vector3:
	var pos := ExMateriaPlatform.PsxChirality.godot_position_to_psx(world)
	if map_center.z > 0.0:
		pos.z = 2.0 * map_center.z - pos.z
	return pos


func psx_position_to_world(pos: Vector3) -> Vector3:
	if map_center.z > 0.0:
		pos.z = 2.0 * map_center.z - pos.z
	return ExMateriaPlatform.PsxChirality.psx_position_to_godot(pos)


## Arm the pre-phase-1 pan to the caster as a PATH of PSX camera positions, one per
## battle loop: `path[0]` is the pose it starts from (the seeded `current_position`), and
## each [method advance_pre_pan] moves `current_position` to the next entry. Angle and zoom
## are left alone — the ROM's turn-change pan moves the pivot only (N22). A path of one
## entry (the caster is already framed) arms nothing, so the effect opens at once.
##
## Called once by the cinematic host (CinematicManager._on_camera_started) after it has
## seeded current_/saved_* from the live camera pose.
func arm_pre_phase_pan_to_caster(path: Array) -> void:
	if not _active or path.size() < 2:
		return
	_pre_pan_path = path
	_pre_pan_index = 0
	current_position = path[0]
	pre_pan_armed = true
	pre_pan_remaining = path.size() - 1


func is_pre_panning() -> bool:
	return pre_pan_armed


## Step the pre-pan one battle loop OUTSIDE the effect timeline. On PSX the base camera
## reaches the active unit before the effect clock starts, so a host that holds the
## cinematic until the pan lands (CinematicManager's pre-roll) drives it here while the
## timeline is parked; [method advance] then opens on frame 0 with the keyframe search,
## not with the tail of the pan.
func advance_pre_pan() -> void:
	if not pre_pan_armed:
		return
	_pre_pan_index = mini(_pre_pan_index + 1, _pre_pan_path.size() - 1)
	current_position = _pre_pan_path[_pre_pan_index]
	pre_pan_remaining -= 1
	if pre_pan_remaining <= 0:
		pre_pan_armed = false
		_pre_pan_path = []


func advance(frame: int, _phase = null) -> void:
	"""Process one frame of camera animation.

	Subsystem contract (ADR-0011/0012). The camera derives its own phase
	windowing from the frame plus the boundaries it took at initialize()
	(phase1_duration / spawn_delay / phase2_start, with for_each per-target
	timing), so it ignores the open phase-window set the timeline passes the
	cursor-based subsystems (`_phase` is untyped here precisely because camera
	never reads it).
	"""
	if not _active:
		return
	_last_frame = frame

	sprite_zoom_q12 = current_zoom

	# Hold the keyframe search until the pre-pan's path is played out (a host that
	# does not park the timeline for it gets one pan step per effect frame).
	if pre_pan_armed:
		advance_pre_pan()
	else:
		if angle_state == "":
			_find_and_execute(frame, CHANNEL_ANGLE)
		if position_state == "":
			_find_and_execute(frame, CHANNEL_POSITION)
		if zoom_state == "":
			_find_and_execute(frame, CHANNEL_ZOOM)

	if angle_state != "":
		_advance_angle()
	if position_state != "":
		_advance_position()
	if zoom_state != "":
		_advance_zoom()


func reset() -> void:
	"""Reset controller state for effect restart.

	Restore the pose to the SAVED base (the takeover snapshot) rather than a
	hardcoded origin, so a backward seek (Studio scrub) or loop restart
	re-establishes the camera at its base instead of snapping to world origin
	(the "stuck at 0,0,0" scrub/stop bug). saved_* default to exactly the former
	hardcoded values ((302,3584,0) / ZERO / 4096), so this is a no-op for any path
	that never seeds a base (combat single-shots, fresh controllers)."""
	angle_state = ""
	position_state = ""
	zoom_state = ""
	angle_frame = 0
	position_frame = 0
	zoom_frame = 0
	current_angles = saved_angles
	current_position = saved_position
	current_zoom = saved_zoom
	sprite_zoom_q12 = saved_zoom


# --- Keyframe search ---

func _find_and_execute(frame: int, channel_id: int) -> void:
	"""Find active keyframe for this frame and channel, then execute it"""
	var result = _find_active_keyframe(frame, channel_id)
	if result == null:
		return

	var table: CameraData.PhaseTable = result["table"]
	var kf: CameraData.Keyframe = table.get_keyframe(result["kf_index"])
	if kf == null:
		return

	# PSX no-op: interp_bits=0x0000 means hold current values (timing placeholder)
	if kf.interpolation.begins_with("UNKNOWN"):
		return

	var remaining = result["absolute_end_frame"] - frame
	# A one-frame non-IMMEDIATE camera keyframe is still a real command. E070
	# Carbuncle's for-each table begins with TARGET/COSINE_A over local frame 0..1;
	# treating that as a timing placeholder leaves the camera at phase1's offset pose
	# exactly when the callback phase starts. Collapse zero/one-frame spans to an
	# immediate one-tick interpolation instead.
	if remaining <= 0:
		remaining = 1

	var target_index: int = result["target_index"]
	if channel_id == CHANNEL_ANGLE:
		_execute_angle_command(kf, remaining, target_index)
	elif channel_id == CHANNEL_POSITION:
		_execute_position_command(kf, remaining, target_index)
	elif channel_id == CHANNEL_ZOOM:
		_execute_zoom_command(kf, remaining)

	if EffectsDebug.camera():
		var channel_name = "ANGLE" if channel_id == CHANNEL_ANGLE else ("POSITION" if channel_id == CHANNEL_POSITION else "ZOOM")
		print("[CAM] frame=%d %s KF%d (%s) target=%d src=%s interp=%s remaining=%d" % [
			frame, channel_name, result["kf_index"], table.table_name, target_index, kf.source_mode,
			kf.interpolation, remaining])
		if channel_id == CHANNEL_ANGLE:
			print("[CAM]   angle: from=%s to=%s" % [str(angle_from), str(angle_to)])
		elif channel_id == CHANNEL_POSITION:
			print("[CAM]   pos: from=%s to=%s" % [str(position_from), str(position_to)])
		elif channel_id == CHANNEL_ZOOM:
			print("[CAM]   zoom: from=%.1f to=%.1f" % [zoom_from, zoom_to])


## `battle_camera_find_active_keyframe` 0x801ACB08, branch for branch: the first keyframe of
## `channel_id` still ahead of `frame`, or null. Returns {table, kf_index, absolute_end_frame,
## target_index}.
##
##   * main (phase1): frames before phase1_duration, target 0.
##   * for_each, per target k (only when spawn_delay != 0 and frame is before the LAST
##     target's window): local frame = (frame - phase1) mod spawn_delay, k = its quotient,
##     keyframes at or past spawn_delay excluded; before phase1 the local frame is -1, which
##     is how a for_each keyframe arms in the gap after the main table runs dry (E070's
##     196 -> 208 bridge). Nothing ahead in k's window -> the NEXT target's first keyframe
##     (local -1), so the camera travels to target k+1 before its window opens.
##   * for_each, last target (k = hit_counter - 1, the only window when spawn_delay == 0 —
##     a simultaneous effect frames its LAST target): until phase1 + k * spawn_delay +
##     phase2_delay, every keyframe.
##   * cleanup (phase2): relative to phase2_start; before it the local frame is -1, so its
##     first keyframe arms as soon as nothing earlier is ahead. Target 0.
func _find_active_keyframe(frame: int, channel_id: int) -> Variant:
	var hit_counter := target_count
	if frame < phase1_duration and _data.has_table("phase1"):
		var main = _data.get_table("phase1")
		var i := _scan(main, frame, channel_id, -1)
		if i >= 0:
			return _found(main, i, main.get_keyframe(i).end_frame, 0)

	if _data.has_table("for_each"):
		var fe = _data.get_table("for_each")
		if spawn_delay != 0 and frame < phase1_duration + (hit_counter - 1) * spawn_delay:
			var k := 0
			var local := -1
			if frame >= phase1_duration:
				k = (frame - phase1_duration) / spawn_delay
				local = frame - phase1_duration - k * spawn_delay
			var i := _scan(fe, local, channel_id, spawn_delay)
			if i < 0:
				k += 1
				if k < hit_counter:
					i = _scan(fe, -1, channel_id, spawn_delay)
			if i >= 0:
				return _found(fe, i, fe.get_keyframe(i).end_frame + k * spawn_delay + phase1_duration, k)
		var last := hit_counter - 1
		var start := phase1_duration + last * spawn_delay
		if frame < start + phase2_delay:
			var local := frame - phase1_duration - last * spawn_delay if frame >= start else -1
			var i := _scan(fe, local, channel_id, -1)
			if i >= 0:
				return _found(fe, i, fe.get_keyframe(i).end_frame + last * spawn_delay + phase1_duration, last)

	if _data.has_table("phase2"):
		var cleanup = _data.get_table("phase2")
		var local := frame - phase2_start if frame >= phase2_start else -1
		var i := _scan(cleanup, local, channel_id, -1)
		if i >= 0:
			return _found(cleanup, i, cleanup.get_keyframe(i).end_frame + phase2_start, 0)
	return null


## The first keyframe index of `table` with `channel_id` whose end frame is past `local`, or
## -1. `cap` > 0 stops the scan at the first keyframe ending at or past it (the per-target
## windows' `frame_thresholds[i] >= spawn_delay` break).
func _scan(table, local: int, channel_id: int, cap: int) -> int:
	for i in range(table.max_keyframe + 1):
		var kf = table.get_keyframe(i)
		if kf == null:
			continue
		if cap > 0 and kf.end_frame >= cap:
			break
		if local < kf.end_frame and (kf.channel_mask & channel_id) != 0:
			return i
	return -1


func _found(table, i: int, absolute_end: int, target_index: int) -> Dictionary:
	return {"table": table, "kf_index": i, "absolute_end_frame": absolute_end,
		"target_index": target_index}


func _all_targets() -> Vector3:
	return all_targets_position if all_targets_position != null else target_position


# --- Angle command execution ---

func _execute_angle_command(kf: CameraData.Keyframe, remaining: int, target_index: int = 0) -> void:
	"""Execute angle channel command based on source mode"""
	var kf_angle = Vector3(kf.angle.x, kf.angle.y, kf.angle.z)

	match kf.source_mode:
		"TARGET":
			# Pitch/roll = current + keyframe, yaw = facing + keyframe. The facing is the
			# search's target k (0x801AAD98 hands 0x801AAC28 that target's tile).
			var face_yaw = _get_facing_yaw(_target_position_at(target_index), _target_unit_at(target_index), kf_angle)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"CASTER":
			var face_yaw = _get_facing_yaw(caster_position, caster_unit, kf_angle)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"CURSOR":
			var face_yaw = _get_facing_yaw(cursor_position, cursor_unit, kf_angle)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"EFFECT_CTR":
			# Map-center anchored, not a unit — no facing resolution (ROM no-op).
			var ctr_angle = Vector3(map_center.x, 0.0, map_center.z)
			var face_yaw = _get_facing_yaw(ctr_angle)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"ALL_TARGETS":
			# Multi-target fallback anchor, not a single unit — no facing (ROM no-op).
			var face_yaw = _get_facing_yaw(_all_targets())
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"OFFSET":
			# Keyframe replaces pitch, adds to yaw/roll
			angle_from = current_angles
			angle_to = Vector3(kf_angle.x, current_angles.y + kf_angle.y, current_angles.z + kf_angle.z)
		"DIRECT":
			# Direct angle with shortest-path yaw wrapping
			angle_from = current_angles
			angle_to = Vector3(kf_angle.x, _wrap_yaw_shortest(current_angles.y, kf_angle.y), kf_angle.z)
		"MAP":
			# Current + keyframe offset
			angle_from = current_angles
			angle_to = current_angles + kf_angle
		"SLOT_COPY":
			# Saved + keyframe (yaw wrapped shortest path)
			angle_from = current_angles
			angle_to = Vector3(
				saved_angles.x + kf_angle.x,
				_wrap_yaw_shortest(current_angles.y, saved_angles.y + kf_angle.y),
				saved_angles.z + kf_angle.z)
		"ORIGIN":
			# Saved pitch + keyframe, current yaw + keyframe, current roll + keyframe
			angle_from = current_angles
			angle_to = Vector3(saved_angles.x + kf_angle.x, current_angles.y + kf_angle.y, current_angles.z + kf_angle.z)
		_:
			# Unknown - use keyframe directly
			angle_from = current_angles
			angle_to = kf_angle

	# For shake interpolation, kf_angle is amplitude — shake around current angles
	if kf.interpolation in ["SHAKE_DAMPED", "SHAKE_DAMPED_B", "SHAKE_DIRECT"]:
		angle_to = current_angles

	_setup_interpolation_angle(kf.interpolation, remaining, kf_angle)


func _setup_interpolation_angle(interp: String, remaining: int, kf_value: Vector3) -> void:
	angle_state = interp
	angle_frame = 0
	angle_total = remaining

	if interp == "ADDITIVE" or interp == "ADDITIVE_B":
		angle_additive = kf_value
	elif interp == "SHAKE_DAMPED" or interp == "SHAKE_DAMPED_B":
		angle_shake_amp = kf_value
	elif interp == "SHAKE_DIRECT":
		angle_shake_amp = kf_value


# --- Position command execution ---

func _execute_position_command(kf: CameraData.Keyframe, remaining: int, target_index: int = 0) -> void:
	"""Execute position channel command based on source mode"""
	var kf_pos = Vector3(kf.position.x, kf.position.y, kf.position.z)

	match kf.source_mode:
		"TARGET":
			# The search's target k (0x801AB1D4's TARGET arm).
			position_from = current_position
			position_to = _target_position_at(target_index) + kf_pos
		"CASTER":
			position_from = current_position
			position_to = caster_position + kf_pos
		"DIRECT":
			position_from = current_position
			position_to = kf_pos
		"MAP":
			position_from = current_position
			position_to = current_position + kf_pos
		"SLOT_COPY":
			position_from = current_position
			position_to = saved_position + kf_pos
		"ORIGIN":
			position_from = current_position
			position_to = saved_position + kf_pos
		"EFFECT_CTR":
			# PSX: get_camera_position() returns map dimensions, * 14 = map center
			var ctr = Vector3(map_center.x, 0.0, map_center.z)
			position_from = current_position
			position_to = ctr + kf_pos
		"ALL_TARGETS":
			# The target table's centroid (0x801AB1D4's 0x180 arm); one target = that target.
			position_from = current_position
			position_to = _all_targets() + kf_pos
		"CURSOR":
			position_from = current_position
			position_to = cursor_position + kf_pos
		_:
			position_from = current_position
			position_to = kf_pos

	# For shake interpolation, kf_pos is amplitude — shake around current position
	if kf.interpolation in ["SHAKE_DAMPED", "SHAKE_DAMPED_B", "SHAKE_DIRECT"]:
		position_to = current_position

	_setup_interpolation_position(kf.interpolation, remaining, kf_pos)


func _setup_interpolation_position(interp: String, remaining: int, kf_value: Vector3) -> void:
	position_state = interp
	position_frame = 0
	position_total = remaining

	if interp == "ADDITIVE" or interp == "ADDITIVE_B":
		position_additive = kf_value
	elif interp == "SHAKE_DAMPED" or interp == "SHAKE_DAMPED_B":
		position_shake_amp = kf_value
	elif interp == "SHAKE_DIRECT":
		position_shake_amp = kf_value


# --- Zoom command execution ---

func _execute_zoom_command(kf: CameraData.Keyframe, remaining: int) -> void:
	"""Execute zoom channel command based on source mode"""
	var kf_zoom = float(kf.zoom.x)

	match kf.source_mode:
		"MAP":
			zoom_from = current_zoom
			zoom_to = current_zoom + kf_zoom
		"SLOT_COPY":
			zoom_from = current_zoom
			zoom_to = saved_zoom + kf_zoom
		"OFFSET", "CURSOR":
			# No-op for zoom
			return
		_:
			# TARGET, DIRECT, EFFECT_CTR, ALL_TARGETS, CASTER, ORIGIN
			zoom_from = current_zoom
			zoom_to = kf_zoom

	# For shake interpolation, kf_zoom is amplitude — shake around current zoom
	if kf.interpolation in ["SHAKE_DAMPED", "SHAKE_DAMPED_B", "SHAKE_DIRECT"]:
		zoom_to = current_zoom

	_setup_interpolation_zoom(kf.interpolation, remaining, kf_zoom)


func _setup_interpolation_zoom(interp: String, remaining: int, kf_value: float) -> void:
	zoom_state = interp
	zoom_frame = 0
	zoom_total = remaining

	if interp == "ADDITIVE" or interp == "ADDITIVE_B":
		zoom_additive = kf_value
	elif interp == "SHAKE_DAMPED" or interp == "SHAKE_DAMPED_B":
		zoom_shake_amp = kf_value
	elif interp == "SHAKE_DIRECT":
		zoom_shake_amp = kf_value


# --- Interpolation advancement ---

func _advance_angle() -> void:
	"""Advance angle interpolation by one frame"""
	angle_frame += 1
	var t = float(angle_frame) / float(maxi(1, angle_total))

	match angle_state:
		"IMMEDIATE":
			current_angles = angle_to
			angle_state = ""
		"LINEAR":
			current_angles = angle_from.lerp(angle_to, t)
			if angle_frame >= angle_total:
				current_angles = angle_to
				angle_state = ""
		"COSINE_A", "COSINE_B", "COSINE_C":
			var ct = 0.5 - 0.5 * cos(PI * t)
			current_angles = angle_from.lerp(angle_to, ct)
			if angle_frame >= angle_total:
				current_angles = angle_to
				angle_state = ""
		"ADDITIVE", "ADDITIVE_B":
			current_angles += angle_additive
			if angle_frame >= angle_total:
				angle_state = ""
		"SHAKE_DAMPED", "SHAKE_DAMPED_B":
			var decay = 1.0 - t
			current_angles = angle_to + Vector3(
				_rr(-angle_shake_amp.x, angle_shake_amp.x) * decay,
				_rr(-angle_shake_amp.y, angle_shake_amp.y) * decay,
				_rr(-angle_shake_amp.z, angle_shake_amp.z) * decay)
			if angle_frame >= angle_total:
				current_angles = angle_to
				angle_state = ""
		"SHAKE_DIRECT":
			current_angles = angle_to + Vector3(
				_rr(-angle_shake_amp.x, angle_shake_amp.x),
				_rr(-angle_shake_amp.y, angle_shake_amp.y),
				_rr(-angle_shake_amp.z, angle_shake_amp.z))
			if angle_frame >= angle_total:
				current_angles = angle_to
				angle_state = ""
		_:
			# Unknown interpolation - snap
			current_angles = angle_to
			angle_state = ""


func _advance_position() -> void:
	"""Advance position interpolation by one frame"""
	position_frame += 1
	var t = float(position_frame) / float(maxi(1, position_total))

	match position_state:
		"IMMEDIATE":
			current_position = position_to
			position_state = ""
		"LINEAR":
			current_position = position_from.lerp(position_to, t)
			if position_frame >= position_total:
				current_position = position_to
				position_state = ""
		"COSINE_A", "COSINE_B", "COSINE_C":
			var ct = 0.5 - 0.5 * cos(PI * t)
			current_position = position_from.lerp(position_to, ct)
			if position_frame >= position_total:
				current_position = position_to
				position_state = ""
		"ADDITIVE", "ADDITIVE_B":
			current_position += position_additive
			if position_frame >= position_total:
				position_state = ""
		"SHAKE_DAMPED", "SHAKE_DAMPED_B":
			var decay = 1.0 - t
			current_position = position_to + Vector3(
				_rr(-position_shake_amp.x, position_shake_amp.x) * decay,
				_rr(-position_shake_amp.y, position_shake_amp.y) * decay,
				_rr(-position_shake_amp.z, position_shake_amp.z) * decay)
			if position_frame >= position_total:
				current_position = position_to
				position_state = ""
		"SHAKE_DIRECT":
			current_position = position_to + Vector3(
				_rr(-position_shake_amp.x, position_shake_amp.x),
				_rr(-position_shake_amp.y, position_shake_amp.y),
				_rr(-position_shake_amp.z, position_shake_amp.z))
			if position_frame >= position_total:
				current_position = position_to
				position_state = ""
		_:
			current_position = position_to
			position_state = ""


func _advance_zoom() -> void:
	"""Advance zoom interpolation by one frame"""
	zoom_frame += 1
	var t = float(zoom_frame) / float(maxi(1, zoom_total))

	match zoom_state:
		"IMMEDIATE":
			current_zoom = zoom_to
			zoom_state = ""
		"LINEAR":
			current_zoom = lerpf(zoom_from, zoom_to, t)
			if zoom_frame >= zoom_total:
				current_zoom = zoom_to
				zoom_state = ""
		"COSINE_A", "COSINE_B", "COSINE_C":
			var ct = 0.5 - 0.5 * cos(PI * t)
			current_zoom = lerpf(zoom_from, zoom_to, ct)
			if zoom_frame >= zoom_total:
				current_zoom = zoom_to
				zoom_state = ""
		"ADDITIVE", "ADDITIVE_B":
			current_zoom += zoom_additive
			if zoom_frame >= zoom_total:
				zoom_state = ""
		"SHAKE_DAMPED", "SHAKE_DAMPED_B":
			var decay = 1.0 - t
			current_zoom = zoom_to + _rr(-zoom_shake_amp, zoom_shake_amp) * decay
			if zoom_frame >= zoom_total:
				current_zoom = zoom_to
				zoom_state = ""
		"SHAKE_DIRECT":
			current_zoom = zoom_to + _rr(-zoom_shake_amp, zoom_shake_amp)
			if zoom_frame >= zoom_total:
				current_zoom = zoom_to
				zoom_state = ""
		_:
			current_zoom = zoom_to
			zoom_state = ""


# --- Utility ---

func _wrap_yaw_shortest(from_yaw: float, to_yaw: float) -> float:
	"""Wrap yaw to shortest path in 4096-unit circle"""
	var delta = fposmod(to_yaw - from_yaw + 2048.0, 4096.0) - 2048.0
	return from_yaw + delta


func _get_facing_yaw(_subject_pos: Vector3, subject_unit = null, kf_angle: Vector3 = Vector3.ZERO) -> float:
	"""0x801AAC28's heir. The base is the snap-to-45° yaw (PSX yaw & 0xE00; floor division
	handles yaw values outside 0-4095, e.g. 5632 from deg_to_psx_angle(495)).

	With a facing_resolver and a focused unit (a battle host), the resolver turns the base to
	the quadrant from which the unit can be seen — ROM: byte +7 of its tile; LIVE: the rendered
	map at the pose this keyframe SETTLES at (current pitch + kf pitch, candidate + kf yaw) with
	other units as the tie-break (gl-ADR-0410). Re-asked every time such a keyframe arms, as the
	ROM does; cached on (unit, base, settled pitch, kf yaw) since the cinematic freeze pins
	every position. Without a resolver (the standalone viewer) it is the bare snap."""
	var base_yaw := floorf(current_angles.y / 512.0) * 512.0
	if facing_resolver == null or subject_unit == null or not is_instance_valid(subject_unit):
		return base_yaw
	var pitch := current_angles.x + kf_angle.x
	var key := "%d|%d|%d|%d" % [subject_unit.get_instance_id(), int(base_yaw), roundi(pitch), roundi(kf_angle.y)]
	if _facing_yaw_cache.has(key):
		return _facing_yaw_cache[key]
	var resolved: float = facing_resolver.resolve_facing_yaw(base_yaw, pitch, subject_unit, kf_angle.y)
	_facing_yaw_cache[key] = resolved
	if EffectsDebug.camera():
		var delta := resolved - base_yaw
		var note := "kept base" if is_equal_approx(delta, 0.0) else ("rotated %+.0f deg" % PsxMagnitude.angle_to_deg(delta))
		print("[CAM][FACING] subject=%s base_yaw=%.0f pitch=%.0f -> %.0f (%s)" % [
			subject_unit.name, base_yaw, pitch, resolved, note])
	return resolved
