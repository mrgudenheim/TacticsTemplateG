class_name DepthDebugScene
extends Node3D
## Isolated depth ordering test — renders a map + particle at known positions,
## rotates camera through 4 angles, and logs depth values + captures screenshots.
##
## Usage: godot --path <project> res://src/file_formats/vfx/depth_debug_scene.tscn -- [--screenshots]

@export var camera: Camera3D

var _frame: int = 0
var _angle_index: int = 0
var _angles: Array[float] = [0.0, 90.0, 180.0, 270.0]
var _angle_names: Array[String] = ["NW (0)", "SW (90)", "SE (180)", "NE (270)"]
var _map_node: MapChunkNodes = null
var _save_screenshots: bool = false
var _waiting_for_settle: int = 0

const SETTLE_FRAMES: int = 5  # Wait frames after rotation for GPU to stabilize
const CAMERA_DISTANCE: float = 8.0
const CAMERA_PITCH: float = -30.0  # degrees, looking down


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--screenshots":
			_save_screenshots = true

	if RomReader.is_ready:
		_start()
	else:
		RomReader.rom_loaded.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# Load map
	var maps_container := Node3D.new()
	maps_container.name = "Maps"
	add_child(maps_container)
	_map_node = VfxTestUtils.load_mirrored_map(116, maps_container)

	# Enable depth debug on map material
	if _map_node:
		var map_mat: ShaderMaterial = _map_node.mesh_instance.material_override as ShaderMaterial
		if map_mat:
			map_mat.set_shader_parameter("debug_depth", true)

	# Create a simple particle-like mesh at a known position above the map
	var particle_marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	particle_marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.MAGENTA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_marker.material_override = mat
	particle_marker.position = Vector3(3.5, 1.0, 1.5)  # Above target tile
	particle_marker.name = "ParticleMarker"
	add_child(particle_marker)

	# Position camera
	_set_camera_angle(0.0)

	print("[DEPTH_TEST] === Depth Ordering Debug Test ===")
	print("[DEPTH_TEST] Map loaded: %s" % (_map_node != null))
	print("[DEPTH_TEST] Camera projection: %s" % ("perspective" if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else "orthographic"))
	print("[DEPTH_TEST] Camera near: %.2f, far: %.2f" % [camera.near, camera.far])

	# Log map mesh info
	if _map_node:
		var mesh: Mesh = _map_node.mesh_instance.mesh
		var format: int = mesh.surface_get_format(0)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vert_count: int = arrays[Mesh.ARRAY_VERTEX].size()
		var has_custom0: bool = arrays.size() > Mesh.ARRAY_CUSTOM0 and arrays[Mesh.ARRAY_CUSTOM0] != null
		print("[DEPTH_TEST] Mesh vertices: %d, has CUSTOM0: %s, format: 0x%X" % [vert_count, has_custom0, format])

	_angle_index = 0
	_waiting_for_settle = SETTLE_FRAMES


func _set_camera_angle(y_rotation_deg: float) -> void:
	var look_at_pos := Vector3(2.5, 0.0, 1.5)  # Center of map area
	var pitch_rad: float = deg_to_rad(CAMERA_PITCH)
	var yaw_rad: float = deg_to_rad(y_rotation_deg)

	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad) * CAMERA_DISTANCE,
		-sin(pitch_rad) * CAMERA_DISTANCE,
		cos(yaw_rad) * cos(pitch_rad) * CAMERA_DISTANCE
	)

	camera.position = look_at_pos + offset
	camera.look_at(look_at_pos)


func _process(_delta: float) -> void:
	_frame += 1

	if _angle_index >= _angles.size():
		return

	if _waiting_for_settle > 0:
		_waiting_for_settle -= 1
		return

	# Log depth info at current angle
	_log_depth_at_angle(_angles[_angle_index], _angle_names[_angle_index])

	if _save_screenshots:
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "user://depth_test_angle_%d.png" % int(_angles[_angle_index])
		img.save_png(path)
		print("[DEPTH_TEST] Screenshot saved: %s" % path)

	_angle_index += 1
	if _angle_index >= _angles.size():
		print("[DEPTH_TEST] === Test Complete ===")
		get_tree().quit()
		return

	_set_camera_angle(_angles[_angle_index])
	_waiting_for_settle = SETTLE_FRAMES


func _log_depth_at_angle(angle: float, angle_name: String) -> void:
	print("[DEPTH_TEST] --- Camera angle: %s (%.0f deg) ---" % [angle_name, angle])

	if not _map_node:
		print("[DEPTH_TEST] No map loaded")
		return

	# Sample CUSTOM0 centroids and compute expected depth for a few representative faces
	var mesh: Mesh = _map_node.mesh_instance.mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var has_custom0: bool = arrays.size() > Mesh.ARRAY_CUSTOM0 and arrays[Mesh.ARRAY_CUSTOM0] != null

	if not has_custom0:
		print("[DEPTH_TEST] WARNING: No CUSTOM0 data — all faces will have same depth!")
		return

	var custom0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]

	# Get camera matrices
	var view_matrix: Transform3D = camera.get_camera_transform().affine_inverse()
	var proj: Projection = camera.get_camera_projection()

	# Sample first 3 triangles
	for tri in range(mini(3, verts.size() / 3)):
		var vi: int = tri * 3
		var v0: Vector3 = verts[vi]
		var v1: Vector3 = verts[vi + 1]
		var v2: Vector3 = verts[vi + 2]
		var vert_centroid: Vector3 = (v0 + v1 + v2) / 3.0

		var ci: int = tri * 3 * 3  # 3 floats per vertex, 3 vertices per tri
		var custom_centroid := Vector3(custom0[ci], custom0[ci + 1], custom0[ci + 2])

		# Compute depth the way the shader does: PROJECTION * MODELVIEW * centroid
		# Since map instance has identity transform (no additional model matrix), MODELVIEW ≈ VIEW
		var map_transform: Transform3D = _map_node.mesh_instance.global_transform
		var view_pos_custom: Vector3 = view_matrix * (map_transform * custom_centroid)
		var view_pos_vert: Vector3 = view_matrix * (map_transform * vert_centroid)

		var clip_custom: Vector4 = proj * Vector4(view_pos_custom.x, view_pos_custom.y, view_pos_custom.z, 1.0)
		var clip_vert: Vector4 = proj * Vector4(view_pos_vert.x, view_pos_vert.y, view_pos_vert.z, 1.0)

		var depth_custom: float = clip_custom.z / clip_custom.w
		var depth_vert: float = clip_vert.z / clip_vert.w

		print("[DEPTH_TEST] Tri %d: custom0=%s vert_centroid=%s depth_custom=%.4f depth_vert=%.4f delta=%.4f" % [
			tri, VfxTestUtils.vec3_str(custom_centroid), VfxTestUtils.vec3_str(vert_centroid),
			depth_custom, depth_vert, depth_custom - depth_vert])

	# Also compute depth for a particle-like position
	var particle_pos := Vector3(3.5, 1.0, 1.5)
	var view_pos_particle: Vector3 = view_matrix * particle_pos
	var clip_particle: Vector4 = proj * Vector4(view_pos_particle.x, view_pos_particle.y, view_pos_particle.z, 1.0)
	var depth_particle: float = clip_particle.z / clip_particle.w
	print("[DEPTH_TEST] Particle at %s: depth=%.4f" % [VfxTestUtils.vec3_str(particle_pos), depth_particle])
