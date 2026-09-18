extends RefCounted
## Emitter configuration - all values pre-converted to Godot units by parser
## Vault: [[E001.BIN Memory Mapping]]
## Vault: [[Emitter Anchor Modes]]
## Vault: [[Particle Emitter Format]]

const _Self = preload("res://addons/exmateria_effects/file_model/EffectEmitter.gd")

enum AnchorMode { WORLD = 0, CURSOR = 1, ORIGIN = 2, TARGET = 3, PARENT = 4, CAMERA = 5 }
enum SpreadMode { SPHERICAL = 0, BOX = 1 }

# Identification
var index: int = 0
var anim_index: int = 0
var anim_param: int = 0

# Curve indices
var curves: Dictionary = {}
var color_curves: Dictionary = {}

# Flags
var flags: Dictionary = {}

# Position (Godot units, Y-flipped)
var position_start: Vector3 = Vector3.ZERO
var position_end: Vector3 = Vector3.ZERO
var spread_start: Vector3 = Vector3.ZERO
var spread_end: Vector3 = Vector3.ZERO

# Velocity angles (radians)
var velocity_base_angle_start: Vector3 = Vector3.ZERO
var velocity_base_angle_end: Vector3 = Vector3.ZERO
var velocity_direction_spread_start: Vector3 = Vector3.ZERO
var velocity_direction_spread_end: Vector3 = Vector3.ZERO

# Radial velocity (Godot units/frame)
var radial_velocity_min_start: float = 0.0
var radial_velocity_max_start: float = 0.0
var radial_velocity_min_end: float = 0.0
var radial_velocity_max_end: float = 0.0

# Physics (raw values for formula)
var inertia_min_start: float = 4096.0
var inertia_max_start: float = 4096.0
var inertia_min_end: float = 4096.0
var inertia_max_end: float = 4096.0

var weight_min_start: float = 0.0
var weight_max_start: float = 0.0
var weight_min_end: float = 0.0
var weight_max_end: float = 0.0

# Acceleration (Godot units/frame²)
var acceleration_min_start: Vector3 = Vector3.ZERO
var acceleration_max_start: Vector3 = Vector3.ZERO
var acceleration_min_end: Vector3 = Vector3.ZERO
var acceleration_max_end: Vector3 = Vector3.ZERO

# Drag (Godot units/frame²)
var drag_min_start: Vector3 = Vector3.ZERO
var drag_max_start: Vector3 = Vector3.ZERO
var drag_min_end: Vector3 = Vector3.ZERO
var drag_max_end: Vector3 = Vector3.ZERO

# Lifetime (frames)
var lifetime_min_start: int = 60
var lifetime_max_start: int = 60
var lifetime_min_end: int = 60
var lifetime_max_end: int = 60

# Target offset (Godot units)
var target_offset_start: Vector3 = Vector3.ZERO
var target_offset_end: Vector3 = Vector3.ZERO

# Spawn control
var particle_count_start: int = 1
var particle_count_end: int = 1
var spawn_interval_start: int = 1
var spawn_interval_end: int = 1

# Homing (Godot units)
var homing_strength_min_start: float = 0.0
var homing_strength_max_start: float = 0.0
var homing_strength_min_end: float = 0.0
var homing_strength_max_end: float = 0.0

# Child emitters
var child_emitter_on_death: int = -1
var child_emitter_mid_life: int = -1

# Callback params (raw emitter bytes read by MIPS callbacks, meaning varies per callback ID)
var callback_params: Dictionary = {}

# Full raw dictionary (pre-conversion PSX integers, for MIPS callback reimplementations)
var raw_data: Dictionary = {}


static func from_json(data: Dictionary) -> _Self:
	"""Create emitter from parser JSON (values already converted)"""
	var emitter = _Self.new()

	emitter.index = data.get("index", 0)
	emitter.anim_index = data.get("anim_index", 0)
	emitter.anim_param = data.get("anim_param", 0)

	emitter.curves = data.get("curves", {})
	emitter.color_curves = data.get("color_curves", {})
	emitter.flags = data.get("flags", {})

	# Position (already Godot units from parser)
	var pos = data.get("position", {})
	emitter.position_start = _array_to_vec3(pos.get("start", [0, 0, 0]))
	emitter.position_end = _array_to_vec3(pos.get("end", [0, 0, 0]))

	var spread = data.get("spread", {})
	emitter.spread_start = _array_to_vec3(spread.get("start", [0, 0, 0]))
	emitter.spread_end = _array_to_vec3(spread.get("end", [0, 0, 0]))

	# Velocity angles (already radians from parser)
	var vel_angle = data.get("velocity_base_angle", {})
	emitter.velocity_base_angle_start = _array_to_vec3(vel_angle.get("start", [0, 0, 0]))
	emitter.velocity_base_angle_end = _array_to_vec3(vel_angle.get("end", [0, 0, 0]))

	var vel_spread = data.get("velocity_direction_spread", {})
	emitter.velocity_direction_spread_start = _array_to_vec3(vel_spread.get("start", [0, 0, 0]))
	emitter.velocity_direction_spread_end = _array_to_vec3(vel_spread.get("end", [0, 0, 0]))

	# Radial velocity (already Godot units/frame)
	var radial = data.get("radial_velocity", {})
	emitter.radial_velocity_min_start = radial.get("min_start", 0.0)
	emitter.radial_velocity_max_start = radial.get("max_start", 0.0)
	emitter.radial_velocity_min_end = radial.get("min_end", 0.0)
	emitter.radial_velocity_max_end = radial.get("max_end", 0.0)

	# Inertia (raw)
	var inertia = data.get("inertia", {})
	emitter.inertia_min_start = inertia.get("min_start", 4096.0)
	emitter.inertia_max_start = inertia.get("max_start", 4096.0)
	emitter.inertia_min_end = inertia.get("min_end", 4096.0)
	emitter.inertia_max_end = inertia.get("max_end", 4096.0)

	# Weight (raw)
	var weight = data.get("weight", {})
	emitter.weight_min_start = weight.get("min_start", 0.0)
	emitter.weight_max_start = weight.get("max_start", 0.0)
	emitter.weight_min_end = weight.get("min_end", 0.0)
	emitter.weight_max_end = weight.get("max_end", 0.0)

	# Acceleration (already Godot units)
	var accel = data.get("acceleration", {})
	emitter.acceleration_min_start = _array_to_vec3(accel.get("min_start", [0, 0, 0]))
	emitter.acceleration_max_start = _array_to_vec3(accel.get("max_start", [0, 0, 0]))
	emitter.acceleration_min_end = _array_to_vec3(accel.get("min_end", [0, 0, 0]))
	emitter.acceleration_max_end = _array_to_vec3(accel.get("max_end", [0, 0, 0]))

	# Drag (already Godot units)
	var drag_data = data.get("drag", {})
	emitter.drag_min_start = _array_to_vec3(drag_data.get("min_start", [0, 0, 0]))
	emitter.drag_max_start = _array_to_vec3(drag_data.get("max_start", [0, 0, 0]))
	emitter.drag_min_end = _array_to_vec3(drag_data.get("min_end", [0, 0, 0]))
	emitter.drag_max_end = _array_to_vec3(drag_data.get("max_end", [0, 0, 0]))

	# Lifetime (frames)
	var lifetime = data.get("lifetime", {})
	emitter.lifetime_min_start = int(lifetime.get("min_start", 60))
	emitter.lifetime_max_start = int(lifetime.get("max_start", 60))
	emitter.lifetime_min_end = int(lifetime.get("min_end", 60))
	emitter.lifetime_max_end = int(lifetime.get("max_end", 60))

	# Target offset (already Godot units)
	var target = data.get("target_offset", {})
	emitter.target_offset_start = _array_to_vec3(target.get("start", [0, 0, 0]))
	emitter.target_offset_end = _array_to_vec3(target.get("end", [0, 0, 0]))

	# Spawn control
	var spawn = data.get("spawn", {})
	emitter.particle_count_start = int(spawn.get("particle_count_start", 1))
	emitter.particle_count_end = int(spawn.get("particle_count_end", 1))
	emitter.spawn_interval_start = int(spawn.get("interval_start", 1))
	emitter.spawn_interval_end = int(spawn.get("interval_end", 1))

	# Homing (already Godot units)
	var homing = data.get("homing_strength", {})
	emitter.homing_strength_min_start = homing.get("min_start", 0.0)
	emitter.homing_strength_max_start = homing.get("max_start", 0.0)
	emitter.homing_strength_min_end = homing.get("min_end", 0.0)
	emitter.homing_strength_max_end = homing.get("max_end", 0.0)

	# Child emitters
	var child_death = data.get("child_emitter_on_death", 255)
	emitter.child_emitter_on_death = -1 if child_death >= 255 else int(child_death)

	var child_mid = data.get("child_emitter_mid_life", 255)
	emitter.child_emitter_mid_life = -1 if child_mid >= 255 else int(child_mid)

	# Callback params
	emitter.callback_params = data.get("callback_params", {})

	# Raw acceleration (used by callbacks for UV offsets, etc.)
	var raw = data.get("raw", {})
	# Include curve_indices_raw in raw_data (top-level field, needed by _curve_t_nibble)
	var ci = data.get("curve_indices_raw", [])
	if not ci.is_empty():
		raw["curve_indices_raw"] = ci
	# Stash the packed control + reserved bytes (parsed top-level) — the storage the
	# EmitterChannel sub-field edits mask into (ADR-0089), and what the const rows show.
	for packed_key in ["byte_00", "byte_05", "motion_type_flag", "animation_target_flag",
			"emitter_flags_lo", "emitter_flags_hi"]:
		if data.has(packed_key):
			raw[packed_key] = int(data[packed_key])
	emitter.raw_data = raw

	return emitter


static func _array_to_vec3(arr) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


func get_emitter_anchor_mode() -> AnchorMode:
	var mode_str: String = flags.get("emitter_anchor_mode", "WORLD")
	match mode_str:
		"CURSOR": return AnchorMode.CURSOR
		"ORIGIN": return AnchorMode.ORIGIN
		"TARGET": return AnchorMode.TARGET
		"PARENT": return AnchorMode.PARENT
		"CAMERA": return AnchorMode.CAMERA
	return AnchorMode.WORLD


func get_target_anchor_mode() -> AnchorMode:
	var mode_str: String = flags.get("target_anchor_mode", "WORLD")
	match mode_str:
		"CURSOR": return AnchorMode.CURSOR
		"ORIGIN": return AnchorMode.ORIGIN
		"TARGET": return AnchorMode.TARGET
		"PARENT": return AnchorMode.PARENT
		"CAMERA": return AnchorMode.CAMERA
	return AnchorMode.WORLD


func get_spread_mode() -> SpreadMode:
	var mode_str: String = flags.get("spread_mode", "SPHERICAL")
	return SpreadMode.BOX if mode_str == "BOX" else SpreadMode.SPHERICAL


func is_child_death_enabled() -> bool:
	"""Check if child-on-death spawning is enabled for this emitter."""
	return flags.get("child_death_enabled", false)


func is_child_midlife_enabled() -> bool:
	"""Check if child-mid-life spawning is enabled for this emitter."""
	return flags.get("child_midlife_enabled", false)
