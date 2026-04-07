class_name ProjectileEffectInstance
extends Node3D
## Self-contained projectile trajectory effect — linear or parabolic arc from origin to target
## with oriented 3D Gouraud-shaded polygon model parsed from PSX ROM data.
## Linear: crossbow bolts, thrown stones, ninja weapons (handler 20).
## Parabolic: bow arrows with lofting arc (handler 1).
## No dependency on TrapEffectData or TrapEffectInstance.

signal completed

enum ProjectileType { ARROW, STONE, SPECIAL }
enum Trajectory { LINEAR, PARABOLIC }

enum _State { IDLE, FLYING, DONE }

const TICK_DURATION: float = VfxConstants.TICK_DURATION

# PSX rotation rates converted from PSX angle units (4096 = full circle)
# Stone: rotation_y = countdown * 256, rotation_x = countdown * 128
const STONE_TUMBLE_Y_RATE: float = 256.0 / 4096.0 * TAU
const STONE_TUMBLE_X_RATE: float = 128.0 / 4096.0 * TAU
# Special (shuriken): reverse spin on X
const SPECIAL_SPIN_RATE: float = 256.0 / 4096.0 * TAU

# Projectile model coordinate scale — divide PSX vertex coords by this for Godot units
const PROJECTILE_COORD_SCALE: float = 100.0

# Model scales (matching godot-learning reference)
const ARROW_SCALE: float = 0.064
const STONE_SCALE: float = 0.1
const SPECIAL_SCALE: float = 0.1

var loop: bool = false

var _state: _State = _State.IDLE
var _projectile_type: ProjectileType = ProjectileType.STONE
var _trajectory: Trajectory = Trajectory.LINEAR
var _origin: Vector3
var _target: Vector3
var _delta: Vector3
var _total_distance: float
var _progress: float
var _step: float
var _current_position: Vector3
var _orientation: Basis

# Parabolic arc state (handler 1)
var _arc_height: float = 2.0
var _xz_distance: float
var _xz_direction: Vector3

# Rotation accumulators
var _tumble_y: float = 0.0
var _tumble_x: float = 0.0
var _spin_x: float = 0.0

var _tick_timer: float = 0.0

# Rendering — baked ArrayMesh per variant, transformed via MeshInstance3D
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _meshes: Dictionary = {} # Variant -> ArrayMesh (cached)


func initialize() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = _material
	_mesh_instance.visible = false
	add_child(_mesh_instance)

	# Build variant meshes from parsed BATTLE.BIN data
	var models: Dictionary = RomReader.battle_bin_data.projectile_models
	for variant_id: int in models:
		var verts: Array[Vector3] = models[variant_id]["vertices"]
		var faces: Array = models[variant_id]["faces"]
		_meshes[variant_id] = _build_mesh(verts, faces)


func play(origin: Vector3, target: Vector3, variant: ProjectileType, trajectory: Trajectory = Trajectory.LINEAR, arc_height: float = 2.0) -> void:
	stop()

	_origin = origin
	_target = target
	_trajectory = trajectory
	_arc_height = arc_height
	_delta = target - origin
	_total_distance = _delta.length()

	if trajectory == Trajectory.PARABOLIC:
		variant = ProjectileType.ARROW # Handler 1 is arrow-only
		# XZ-only distance (handler 1 ignores Y in distance calc)
		var xz_delta: Vector3 = Vector3(_delta.x, 0.0, _delta.z)
		_xz_distance = xz_delta.length()
		_xz_direction = xz_delta.normalized() if _xz_distance > 0.001 else Vector3.FORWARD

	_projectile_type = variant

	var effective_distance: float = _xz_distance if trajectory == Trajectory.PARABOLIC else _total_distance
	if effective_distance < 0.001:
		_state = _State.DONE
		completed.emit()
		return

	# Duration proportional to distance
	var duration_ticks: float = maxf(effective_distance * VfxConstants.TICKS_PER_TILE, 2.0)
	_step = effective_distance / duration_ticks

	_progress = 0.0
	_current_position = origin
	_tumble_y = 0.0
	_tumble_x = 0.0
	_spin_x = 0.0

	_orientation = _compute_orientation(_delta)

	_mesh_instance.mesh = _meshes[variant]
	_mesh_instance.visible = true

	_tick_timer = 0.0
	_state = _State.FLYING


func stop() -> void:
	_state = _State.IDLE
	_xz_distance = 0.0
	_tumble_y = 0.0
	_tumble_x = 0.0
	_spin_x = 0.0
	if _mesh_instance != null:
		_mesh_instance.visible = false


func is_playing() -> bool:
	return _state == _State.FLYING


func _process(delta: float) -> void:
	if _state != _State.FLYING:
		return

	_tick_timer += delta
	while _tick_timer >= TICK_DURATION:
		_tick_timer -= TICK_DURATION
		_process_tick()
		if _state != _State.FLYING:
			break

	if _state == _State.FLYING:
		_update_transform()


func _process_tick() -> void:
	_progress += _step
	var effective_distance: float = _xz_distance if _trajectory == Trajectory.PARABOLIC else _total_distance
	if _progress >= effective_distance:
		_progress = effective_distance
		_current_position = _target
		_mesh_instance.visible = false
		_state = _State.DONE
		if loop:
			play(_origin, _target, _projectile_type, _trajectory, _arc_height)
		else:
			completed.emit()
		return

	var t: float = _progress / effective_distance

	if _trajectory == Trajectory.PARABOLIC:
		# XZ position: linear interpolation along horizontal plane
		var xz_pos: Vector3 = Vector3(_origin.x, 0.0, _origin.z).lerp(Vector3(_target.x, 0.0, _target.z), t)
		# Y position: lerp base heights + parabolic arc offset
		var base_y: float = lerpf(_origin.y, _target.y, t)
		var arc_y: float = _evaluate_parabolic_arc(t)
		_current_position = Vector3(xz_pos.x, base_y + arc_y, xz_pos.z)

		# Recompute orientation from arc tangent each tick for arrow tilt
		var slope_y: float = (_target.y - _origin.y) / _xz_distance
		var arc_derivative: float = 4.0 * _arc_height * (1.0 - 2.0 * t) / _xz_distance
		var tangent: Vector3 = Vector3(_xz_direction.x, slope_y + arc_derivative, _xz_direction.z).normalized()
		_orientation = _compute_orientation(tangent * _xz_distance)
	else:
		# Linear interpolation
		_current_position = _origin.lerp(_target, t)

	# Update rotation per variant
	match _projectile_type:
		ProjectileType.STONE:
			_tumble_y += STONE_TUMBLE_Y_RATE
			_tumble_x += STONE_TUMBLE_X_RATE
		ProjectileType.SPECIAL:
			_spin_x -= SPECIAL_SPIN_RATE


func _compute_orientation(delta_vec: Vector3) -> Basis:
	var dir: Vector3 = delta_vec.normalized()
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	# Arrow: PSX tip is at -Y → 90° X tumble aligns tip with local -Z.
	# looking_at(dir) makes -Z face toward target, so tip points at target.
	return Basis.looking_at(dir, up)


## Symmetric parabola: rises from 0 at t=0, peaks at arc_height at t=0.5, returns to 0 at t=1.
## Matches PSX evaluate_parabolic_arc (0x801af59c) shape.
func _evaluate_parabolic_arc(t: float) -> float:
	return 4.0 * _arc_height * t * (1.0 - t)


# PSX bow arc constants
const PSX_PER_GODOT: float = MapData.TILE_SIDE_LENGTH
const PSX_ARC_K: float = 4096.0
const PSX_ARC_R: float = 336.0
const PSX_HEIGHT_UNIT: float = 12.0  # 1h = 12 PSX world units

## Compute PSX-accurate low-arc bow height (bulge above straight line).
## Computes H from the quadratic endpoint constraint, then derives
## arc_height = (H^2+K^2)*D^2/(4*K^3*R*ppg) — matching the B coefficient
## between PSX's parabola and Godot's 4t(1-t) arc system.
static func compute_psx_bow_arc(godot_xz_dist: float, godot_delta_y: float) -> float:
	var D: float = godot_xz_dist * PSX_PER_GODOT * 64.0  # Q6 fixed-point
	var delta_y: float = godot_delta_y * PSX_PER_GODOT / PSX_HEIGHT_UNIT  # h units

	if D < 1.0:
		return 0.0  # same-tile: no meaningful arc

	var K: float = PSX_ARC_K
	var R: float = PSX_ARC_R
	var disc: float = R * R - 4.0 * delta_y * R - 4.0 * D * D / (K * K)
	if disc <= 0.0:
		return 0.0  # beyond valid range

	# Low arc H (minus sign = flatter trajectory)
	var H: float = K * K * (R - sqrt(disc)) / (2.0 * D)

	# arc_height = (H^2+K^2)*D^2/(4*K^3*R*ppg) — bulge above straight line
	var K2: float = K * K
	var K3: float = K2 * K
	return (H * H + K2) * D * D / (4.0 * K3 * R * PSX_PER_GODOT)


func _update_transform() -> void:
	var model_scale: float = STONE_SCALE
	match _projectile_type:
		ProjectileType.ARROW:
			model_scale = ARROW_SCALE
		ProjectileType.STONE:
			model_scale = STONE_SCALE
		ProjectileType.SPECIAL:
			model_scale = SPECIAL_SCALE

	# Build rotation: orientation along trajectory + variant-specific tumble
	var tumble_basis: Basis = Basis.IDENTITY
	match _projectile_type:
		ProjectileType.ARROW:
			# PSX arrow tip is at -Y; rotate +90° around X to point tip along -Z
			# Then looking_at in _compute_orientation makes -Z face the velocity
			tumble_basis = Basis(Vector3.RIGHT, PI / 2.0)
		ProjectileType.STONE:
			tumble_basis = Basis.from_euler(Vector3(_tumble_x, _tumble_y, 0.0))
		ProjectileType.SPECIAL:
			tumble_basis = Basis.from_euler(Vector3(_spin_x, 0.0, 0.0))

	var model_basis: Basis = _orientation * tumble_basis
	model_basis.x *= model_scale
	model_basis.y *= model_scale
	model_basis.z *= model_scale

	_mesh_instance.global_transform = Transform3D(model_basis, _current_position)


# ============================================================
#  Mesh building — SurfaceTool, same approach as ProjectileMeshBuilder
# ============================================================

static func _build_mesh(vertices: Array[Vector3], faces: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Deduplicate faces (some PSX models have duplicates with different colors)
	var seen: Dictionary = {}

	for face: Array in faces:
		var indices: Array = face[0]
		var colors: Array = face[1]
		var face_type: String = face[2]

		var key: String = str(indices)
		if seen.has(key):
			continue
		seen[key] = true

		if face_type == "q":
			# Quad: split into 2 triangles [0,1,2] + [1,2,3]
			_add_triangle(st, vertices, indices, colors, [0, 1, 2])
			_add_triangle(st, vertices, indices, colors, [1, 2, 3])
		else:
			_add_triangle(st, vertices, indices, colors, [0, 1, 2])

	return st.commit()


static func _add_triangle(st: SurfaceTool, vertices: Array[Vector3],
		indices: Array, colors: Array, tri_order: Array) -> void:
	for i: int in tri_order:
		var idx: int = indices[i]
		var v: Vector3 = vertices[idx]
		var c: Array = colors[i]

		st.set_color(Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0))
		st.add_vertex(Vector3(v.x / PROJECTILE_COORD_SCALE, v.y / PROJECTILE_COORD_SCALE, v.z / PROJECTILE_COORD_SCALE))
