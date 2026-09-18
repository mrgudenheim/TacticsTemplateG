extends RefCounted
## Runtime camera subsystem (renamed from CameraTrackController, #31).
##
## Mirrors the PSX routines at 0x801AD198 (per-frame channel advance) and
## 0x801ACB08 (active-keyframe search). Evaluates keyframes from 3 phase
## tables (phase1, for_each, phase2) and interpolates angle, position, and
## zoom channels independently. `Keyframe.channel_mask` is a bitmask that
## selects which of {angle, position, zoom} a keyframe activates.
## Vault: [[Effect Camera System]]
## Vault: [[Effect Execution Model]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const CameraData = preload("res://addons/exmateria_effects/file_model/CameraData.gd")

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
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

# Phase timing
var phase1_duration: int = 0
var spawn_delay: int = 0
var phase2_start: int = 0
var target_count: int = 1

# External position references (set by EffectInstance)
var target_position: Vector3 = Vector3.ZERO   # PSX coords
var caster_position: Vector3 = Vector3.ZERO
var cursor_position: Vector3 = Vector3.ZERO

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
var _facing_yaw_cache := {}   # subject instance_id -> resolved yaw (PSX)

# Parsed camera-keyframe data
var continuous_for_each: bool = false  # Pattern 2: for_each runs continuously, not per-target

# Pre-phase-1 pan-to-caster (issue #53 Phase 4 refinement).
#
# Vanilla FFT pans the strategy-view camera to the active unit before a spell's
# Phase 1 keyframes fire — that pan is part of the cursor-follow / turn-camera
# layer, not the effect's camera tracks. In GPUArena, AI casters fire cinematics
# without any cursor-follow priming, so without an explicit pre-pan the camera
# jumps straight from "wherever it was" to the effect's first keyframe target
# (Fire's TARGET source is the target unit, skipping the caster entirely). The
# pre-phase interpolates angle+position from the seeded saved pose to the
# caster's PSX position over PRE_PAN_FRAMES effect frames before the keyframe
# search begins. After the pre-pan completes, normal Phase 1 keyframes pick up.
const PRE_PAN_FRAMES: int = 15
var pre_pan_armed: bool = false
var pre_pan_remaining: int = 0

var _data: CameraData = null
var _active: bool = false

# Per-instance RNG (ADR-0070). Threaded from the owning EffectInstance so camera
# SHAKE is deterministic within the instance — a scrub back-and-forth reproduces
# the same jitter instead of re-rolling it. null = global fallback.
var rng: RandomNumberGenerator = null


func _rr(a: float, b: float) -> float:
	"""Instance-RNG randf_range() with a global fallback (camera shake draws)."""
	return rng.randf_range(a, b) if rng != null else randf_range(a, b)


func initialize(data: CameraData, p1_duration: int, s_delay: int, p2_start: int, t_count: int = 1) -> void:
	"""Initialize with parsed camera keyframe data and phase timing"""
	_data = data
	phase1_duration = p1_duration
	spawn_delay = s_delay
	phase2_start = p2_start
	target_count = maxi(1, t_count)
	_active = data != null and data.has_active_keyframes()

	# New cinematic -> drop any cached per-subject facing yaws.
	_facing_yaw_cache.clear()

	# Reset per-channel interpolation state
	angle_state = ""
	position_state = ""
	zoom_state = ""
	angle_frame = 0
	position_frame = 0
	zoom_frame = 0


func is_active() -> bool:
	return _active


## Arm a pre-phase-1 COSINE_A interpolation from the live camera pose toward the
## caster (angle + position + zoom). After PRE_PAN_FRAMES the angle/position/zoom
## interpolation slots go idle and the normal Phase 1 keyframe search begins.
##
## Called once by the cinematic host (CombatLoop._on_cinematic_camera_started)
## after it has seeded current_/saved_* from the live PlayerCamera pose AND set
## caster_position from the live caster Unit. Standalone EffectViewerScene plays
## skip this hook so the manual-positioning workflow there is untouched.
func arm_pre_phase_pan_to_caster() -> void:
	if not _active:
		return
	pre_pan_armed = true
	pre_pan_remaining = PRE_PAN_FRAMES
	# Position: lerp current -> caster, no kf offset.
	position_from = current_position
	position_to = caster_position
	position_state = "COSINE_A"
	position_frame = 0
	position_total = PRE_PAN_FRAMES
	# Angle: keep pitch/roll, snap yaw to caster facing (same as TARGET-source
	# yaw quantization). Skips if the caster is at the same XZ as the camera.
	var face_yaw := _get_facing_yaw(caster_position, caster_unit)
	angle_from = current_angles
	angle_to = Vector3(current_angles.x, face_yaw, current_angles.z)
	angle_state = "COSINE_A"
	angle_frame = 0
	angle_total = PRE_PAN_FRAMES


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

	# Pre-phase-1 pan-to-caster: hold the keyframe search until our seeded
	# COSINE_A interpolation drains. The advance steps below still tick the
	# channel slots, so position/angle continue interpolating toward the
	# caster pose each frame.
	if pre_pan_armed:
		pre_pan_remaining -= 1
		if pre_pan_remaining <= 0:
			pre_pan_armed = false
	else:
		# For each idle channel, search for a new keyframe
		if angle_state == "":
			_find_and_execute(frame, CHANNEL_ANGLE)
		if position_state == "":
			_find_and_execute(frame, CHANNEL_POSITION)
		if zoom_state == "":
			_find_and_execute(frame, CHANNEL_ZOOM)

	# Advance interpolation for active channels
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
	# PSX no-op: 1-frame non-IMMEDIATE keyframes hold current values (timing placeholder)
	if remaining <= 1 and kf.interpolation != "IMMEDIATE":
		return
	if remaining <= 0:
		remaining = 1

	# Execute based on which channel
	if channel_id == CHANNEL_ANGLE:
		_execute_angle_command(kf, remaining)
	elif channel_id == CHANNEL_POSITION:
		_execute_position_command(kf, remaining)
	elif channel_id == CHANNEL_ZOOM:
		_execute_zoom_command(kf, remaining)

	# Debug logging after execution
	if EffectsDebug.camera():
		var channel_name = "ANGLE" if channel_id == CHANNEL_ANGLE else ("POSITION" if channel_id == CHANNEL_POSITION else "ZOOM")
		print("[CAM] frame=%d %s KF%d (%s) src=%s interp=%s remaining=%d" % [
			frame, channel_name, result["kf_index"], table.table_name, kf.source_mode, kf.interpolation, remaining])
		if channel_id == CHANNEL_ANGLE:
			print("[CAM]   angle: from=%s to=%s" % [str(angle_from), str(angle_to)])
		elif channel_id == CHANNEL_POSITION:
			print("[CAM]   pos: from=%s to=%s" % [str(position_from), str(position_to)])
		elif channel_id == CHANNEL_ZOOM:
			print("[CAM]   zoom: from=%.1f to=%.1f" % [zoom_from, zoom_to])


func _find_active_keyframe(frame: int, channel_id: int) -> Variant:
	"""Search tables for active keyframe at given frame.
	Returns {table, kf_index, absolute_end_frame} or null."""

	# Table 0 (phase1): if frame < phase1_duration
	if frame < phase1_duration and _data.has_table("phase1"):
		var table = _data.get_table("phase1")
		for i in range(table.max_keyframe + 1):
			var kf = table.get_keyframe(i)
			if kf == null:
				continue
			if kf.channel_mask & channel_id == 0:
				continue
			if frame < kf.end_frame:
				return {"table": table, "kf_index": i, "absolute_end_frame": kf.end_frame}

	# Table 1 (for_each): during for-each window
	if frame >= phase1_duration and _data.has_table("for_each"):
		if continuous_for_each:
			# Pattern 2: continuous timeline from phase1_duration (no per-target modulo)
			var local_frame = frame - phase1_duration
			var table = _data.get_table("for_each")
			for i in range(table.max_keyframe + 1):
				var kf = table.get_keyframe(i)
				if kf == null:
					continue
				if kf.channel_mask & channel_id == 0:
					continue
				if local_frame < kf.end_frame:
					var abs_end = kf.end_frame + phase1_duration
					return {"table": table, "kf_index": i, "absolute_end_frame": abs_end}
		elif spawn_delay > 0:
			# Pattern 1: per-target windowed timing
			var for_each_end = phase1_duration + spawn_delay * target_count
			if frame < for_each_end:
				var table = _data.get_table("for_each")
				var elapsed = frame - phase1_duration
				var _target_index = elapsed / spawn_delay
				var local_frame = elapsed % spawn_delay
				for i in range(table.max_keyframe + 1):
					var kf = table.get_keyframe(i)
					if kf == null:
						continue
					if kf.channel_mask & channel_id == 0:
						continue
					if local_frame < kf.end_frame:
						var abs_end = kf.end_frame + phase1_duration + _target_index * spawn_delay
						return {"table": table, "kf_index": i, "absolute_end_frame": abs_end}

	# Table 2 (phase2): if frame >= phase2_start
	if frame >= phase2_start and _data.has_table("phase2"):
		var table = _data.get_table("phase2")
		var local_frame = frame - phase2_start
		for i in range(table.max_keyframe + 1):
			var kf = table.get_keyframe(i)
			if kf == null:
				continue
			if kf.channel_mask & channel_id == 0:
				continue
			if local_frame < kf.end_frame:
				var abs_end = kf.end_frame + phase2_start
				return {"table": table, "kf_index": i, "absolute_end_frame": abs_end}

	return null


# --- Angle command execution ---

func _execute_angle_command(kf: CameraData.Keyframe, remaining: int) -> void:
	"""Execute angle channel command based on source mode"""
	var kf_angle = Vector3(kf.angle.x, kf.angle.y, kf.angle.z)

	match kf.source_mode:
		"TARGET":
			# Pitch/roll = current + keyframe, yaw = facing + keyframe
			var face_yaw = _get_facing_yaw(target_position, target_unit)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"CASTER":
			var face_yaw = _get_facing_yaw(caster_position, caster_unit)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"CURSOR":
			var face_yaw = _get_facing_yaw(cursor_position, cursor_unit)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"EFFECT_CTR":
			# Map-center anchored, not a unit — no facing resolution (ROM no-op).
			var ctr_angle = Vector3(map_center.x, 0.0, map_center.z)
			var face_yaw = _get_facing_yaw(ctr_angle)
			angle_from = current_angles
			angle_to = Vector3(current_angles.x + kf_angle.x, face_yaw + kf_angle.y, current_angles.z + kf_angle.z)
		"ALL_TARGETS":
			# Averaged multi-target anchor, not a single unit — no facing (ROM no-op).
			var face_yaw = _get_facing_yaw(target_position)
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

func _execute_position_command(kf: CameraData.Keyframe, remaining: int) -> void:
	"""Execute position channel command based on source mode"""
	var kf_pos = Vector3(kf.position.x, kf.position.y, kf.position.z)

	match kf.source_mode:
		"TARGET":
			position_from = current_position
			position_to = target_position + kf_pos
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
			# Same as target for single-target
			position_from = current_position
			position_to = target_position + kf_pos
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


func _get_facing_yaw(_subject_pos: Vector3, subject_unit = null) -> float:
	"""PSX calc_facing_angles heir. The base is the snap-to-45° yaw (PSX yaw &
	0xE00; floor division handles yaw values outside 0-4095, e.g. 5632 from
	deg_to_psx_angle(495)).

	When a facing_resolver and a focused unit are present (cinematic host path),
	the base is upgraded to the resolver's gate+tie-break choice among the 4
	fixed yaws (ADR-0039): rotate off the base only if terrain hides the unit
	there, preferring shots where no other unit blocks it. Resolved once per
	subject and cached (the cinematic freeze pins positions). Standalone scenes
	leave facing_resolver null and get the bare ROM snap (terrain step skipped —
	we have no per-tile data there)."""
	var base_yaw := floorf(current_angles.y / 512.0) * 512.0
	if facing_resolver == null or subject_unit == null or not is_instance_valid(subject_unit):
		return base_yaw
	var key = subject_unit.get_instance_id()
	if _facing_yaw_cache.has(key):
		return _facing_yaw_cache[key]
	var resolved: float = facing_resolver.resolve_facing_yaw(base_yaw, current_angles.x, subject_unit)
	_facing_yaw_cache[key] = resolved
	if EffectsDebug.camera():
		var delta := resolved - base_yaw
		var note := "kept base" if is_equal_approx(delta, 0.0) else ("rotated %+.0f deg" % PsxMagnitude.angle_to_deg(delta))
		print("[CAM][FACING] subject=%s base_yaw=%.0f -> %.0f (%s)" % [
			subject_unit.name, base_yaw, resolved, note])
	return resolved
