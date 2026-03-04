class_name VfxEffectInstance
extends Node3D
## Scene-tree wrapper that owns VfxEffectManager + VfxRenderer

var manager: VfxEffectManager
var renderer: VfxRenderer

# Debug anchor/emitter markers (used by VfxTestScene UI)
var _debug_anchor_markers: Array[MeshInstance3D] = []
var _debug_emitter_markers: Array[MeshInstance3D] = []


func initialize(vfx_data: VisualEffectData, target_position: Vector3, origin_position: Vector3 = Vector3.ZERO) -> void:
	if not vfx_data.is_initialized:
		vfx_data.init_from_file()

	manager = VfxEffectManager.new()
	manager.initialize(vfx_data)
	# Anchors are relative to the instance position (which is at target_position).
	# anchor_origin (mode 2) = caster position relative to instance
	# anchor_target (mode 3) = target position relative to instance = (0,0,0)
	var rel_origin: Vector3 = origin_position - target_position
	manager.set_anchors(Vector3.ZERO, Vector3.ZERO, rel_origin, Vector3.ZERO)
	manager.enable_timeline()

	renderer = VfxRenderer.new()
	renderer.name = "VfxRenderer"
	add_child(renderer)
	renderer.initialize(vfx_data)

	_create_debug_markers(vfx_data)


func _create_debug_markers(vfx_data: VisualEffectData) -> void:
	# Track positions so overlapping markers get stacked vertically
	var placed_positions: Array[Vector3] = []
	const STACK_OFFSET: float = 0.12

	# Anchor markers (local space — instance is at target_position)
	var anchor_names: Array[String] = ["world", "cursor", "origin", "target"]
	var anchor_positions: Array[Vector3] = [
		manager.anchor_world, manager.anchor_cursor,
		manager.anchor_origin, manager.anchor_target
	]
	var anchor_colors: Array[Color] = [
		Color.WHITE,       # world
		Color.YELLOW,      # cursor
		Color.CYAN,        # origin
		Color.MAGENTA,     # target
	]

	for i in range(anchor_positions.size()):
		var base_pos: Vector3 = anchor_positions[i]
		var display_pos: Vector3 = _stack_position(base_pos, placed_positions, STACK_OFFSET)
		placed_positions.append(base_pos)
		var marker: MeshInstance3D = _make_sphere_marker(display_pos, anchor_colors[i], 0.08)
		marker.name = "Anchor_%s" % anchor_names[i]
		add_child(marker)
		_debug_anchor_markers.append(marker)

	# Instance origin marker (shows where the instance root Node3D is — all particles render relative to this)
	var origin_marker: MeshInstance3D = _make_sphere_marker(Vector3.ZERO, Color.GREEN, 0.10)
	origin_marker.name = "InstanceOrigin"
	add_child(origin_marker)
	_debug_anchor_markers.append(origin_marker)

	# Emitter spawn position markers
	var emitter_colors: Array[Color] = [
		Color.RED, Color.GREEN, Color.BLUE, Color.ORANGE,
		Color.LIME_GREEN, Color.DEEP_SKY_BLUE, Color.HOT_PINK, Color.GOLD,
		Color.MEDIUM_PURPLE, Color.CORAL, Color.SPRING_GREEN, Color.DODGER_BLUE,
		Color.TOMATO, Color.CHARTREUSE, Color.STEEL_BLUE, Color.SALMON,
	]
	for ei in range(vfx_data.emitters.size()):
		var em: VfxEmitter = vfx_data.emitters[ei]
		var anchor_offset: Vector3
		match em.emitter_anchor_mode:
			1: anchor_offset = manager.anchor_cursor
			2: anchor_offset = manager.anchor_origin
			3: anchor_offset = manager.anchor_target
			_: anchor_offset = manager.anchor_world
		var base_pos: Vector3 = anchor_offset + em.conv_position_start
		var display_pos: Vector3 = _stack_position(base_pos, placed_positions, STACK_OFFSET)
		placed_positions.append(base_pos)
		var col: Color = emitter_colors[ei % emitter_colors.size()]
		var marker: MeshInstance3D = _make_sphere_marker(display_pos, col, 0.05)
		marker.name = "Emitter_%d" % ei
		add_child(marker)
		_debug_emitter_markers.append(marker)


func _stack_position(base: Vector3, existing: Array[Vector3], offset: float) -> Vector3:
	var stack_count: int = 0
	for pos: Vector3 in existing:
		if pos.distance_to(base) < 0.01:
			stack_count += 1
	return base + Vector3(0, stack_count * offset, 0)


func _make_sphere_marker(pos: Vector3, color: Color, radius: float = 0.08) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh_instance.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	mesh_instance.material_override = mat

	mesh_instance.position = pos
	return mesh_instance


func _process(delta: float) -> void:
	if not manager:
		return

	manager.update(delta)

	var active_particles: Array[VfxParticleData] = manager.get_all_particles()

	# Update emitter marker visibility based on debug mask
	var mask: Array[bool] = manager.debug_emitter_mask
	for ei in range(_debug_emitter_markers.size()):
		_debug_emitter_markers[ei].visible = mask.is_empty() or (ei < mask.size() and mask[ei])

	if renderer:
		renderer.render(active_particles, manager.vfx_data)

	if manager.is_done():
		queue_free()
