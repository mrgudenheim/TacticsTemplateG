class_name VfxTestScene
extends Node3D
## Standalone VFX debug scene — loads a map, places origin/target markers,
## and loops effects with a debug UI for selecting effects, toggling emitters,
## and controlling playback speed.

@export var camera_controller: CameraController
@export var maps_container: Node3D
@export var vfx_container: Node3D
@export var origin_marker: MeshInstance3D
@export var target_marker: MeshInstance3D

# Debug UI
@export var effect_spinbox: SpinBox
@export var play_button: Button
@export var loop_checkbox: CheckBox
@export var speed_slider: HSlider
@export var speed_label: Label
@export var z_bias_spinbox: SpinBox
@export var emitter_list_container: VBoxContainer
@export var anchor_list_container: VBoxContainer

var current_effect_index: int = 10
var current_instance: VfxEffectInstance = null
var origin_world_pos: Vector3 = Vector3(1.5, 0, 1.5)
var target_world_pos: Vector3 = Vector3(3.5, 0, 1.5)
var emitter_checkboxes: Array[CheckBox] = []
var anchor_checkboxes: Array[CheckBox] = []
var anchor_spinboxes: Array = []  # Array of [SpinBox, SpinBox, SpinBox] per anchor

# Command-line: --solo-emitter=N to only enable emitter N at startup
var solo_emitter: int = -1  # -1 = all enabled
# Command-line: --enable-emitters=0,1,2 to enable specific emitters at startup
var enable_emitters: Array[int] = []
# Command-line: --quit-after-loop to exit after first playthrough
var quit_after_loop: bool = false
var _first_play_started: bool = false
# Command-line: --target-anchor=x,y,z to override target anchor (local space)
var target_anchor_override: Vector3 = Vector3.ZERO
var target_anchor_overridden: bool = false

# Loop replay delay
var _loop_delay: float = 0.0
const LOOP_DELAY_SECONDS: float = 0.5


func _ready() -> void:
	# Parse command-line args for --solo-emitter=N
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--solo-emitter="):
			solo_emitter = int(arg.split("=")[1])
			print("[VfxTestScene] solo_emitter=%d" % solo_emitter)
		if arg.begins_with("--enable-emitters="):
			var parts: PackedStringArray = arg.split("=")[1].split(",")
			for p: String in parts:
				enable_emitters.append(int(p))
			print("[VfxTestScene] enable_emitters=%s" % [enable_emitters])
		if arg == "--quit-after-loop":
			quit_after_loop = true
			print("[VfxTestScene] quit_after_loop=true")
		if arg.begins_with("--target-anchor="):
			var parts: PackedStringArray = arg.split("=")[1].split(",")
			if parts.size() == 3:
				target_anchor_override = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				target_anchor_overridden = true
				print("[VfxTestScene] target_anchor_override=%s" % target_anchor_override)

	effect_spinbox.value_changed.connect(_on_effect_changed)
	play_button.pressed.connect(_on_play_pressed)
	speed_slider.value_changed.connect(_on_speed_changed)
	z_bias_spinbox.value_changed.connect(_on_z_bias_changed)

	if RomReader.is_ready:
		_on_rom_loaded()
	else:
		RomReader.rom_loaded.connect(_on_rom_loaded, CONNECT_ONE_SHOT)


func _on_rom_loaded() -> void:
	_load_map()
	_play_effect()


func _load_map() -> void:
	if 116 >= RomReader.maps_array.size():
		push_warning("[VfxTestScene] Map index 116 out of range")
		return

	var map_data: MapData = RomReader.maps_array[116]
	if not map_data.is_initialized:
		map_data.init_map()

	var new_map_instance: MapChunkNodes = MapChunkNodes.instantiate()
	new_map_instance.map_data = map_data
	new_map_instance.name = map_data.unique_name

	# Apply Y-mirror (same as battle system default: mirror_xyz = [false, true, false])
	var mirror_scale := Vector3(1, -1, 1)
	var mesh_aabb: AABB = map_data.mesh.get_aabb()
	var surface_arrays: Array = map_data.mesh.surface_get_arrays(0)
	var original_mesh_center: Vector3 = mesh_aabb.get_center()
	for vertex_idx: int in surface_arrays[Mesh.ARRAY_VERTEX].size():
		var vertex: Vector3 = surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx]
		vertex = vertex - original_mesh_center
		vertex = vertex * mirror_scale
		vertex = vertex + (mesh_aabb.size / 2.0)
		surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx] = vertex

	# Flip winding order for odd-axis mirror
	for idx: int in surface_arrays[Mesh.ARRAY_VERTEX].size() / 3:
		var tri_idx: int = idx * 3
		var temp_vertex: Vector3 = surface_arrays[Mesh.ARRAY_VERTEX][tri_idx]
		surface_arrays[Mesh.ARRAY_VERTEX][tri_idx] = surface_arrays[Mesh.ARRAY_VERTEX][tri_idx + 2]
		surface_arrays[Mesh.ARRAY_VERTEX][tri_idx + 2] = temp_vertex
		var temp_uv: Vector2 = surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx]
		surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx] = surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx + 2]
		surface_arrays[Mesh.ARRAY_TEX_UV][tri_idx + 2] = temp_uv

	var modified_mesh: ArrayMesh = ArrayMesh.new()
	modified_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
	new_map_instance.mesh_instance.mesh = modified_mesh

	new_map_instance.set_mesh_shader(map_data.albedo_texture_indexed, map_data.texture_palettes)
	new_map_instance.collision_shape.shape = new_map_instance.mesh_instance.mesh.create_trimesh_shape()
	new_map_instance.play_animations(map_data)
	maps_container.add_child(new_map_instance)

	# Find tile positions
	for tile: TerrainTile in map_data.terrain_tiles:
		if tile.location == Vector2i(1, 1):
			origin_world_pos = tile.get_world_position()
		elif tile.location == Vector2i(3, 1):
			target_world_pos = tile.get_world_position()

	# Position markers slightly above tiles
	origin_marker.position = origin_world_pos + Vector3(0, 0.15, 0)
	target_marker.position = target_world_pos + Vector3(0, 0.15, 0)

	# Point camera at midpoint
	var midpoint: Vector3 = (origin_world_pos + target_world_pos) * 0.5
	camera_controller.position = midpoint


func _play_effect() -> void:
	if current_instance and is_instance_valid(current_instance):
		current_instance.queue_free()
		current_instance = null

	if current_effect_index < 0 or current_effect_index >= RomReader.vfx.size():
		print("[VfxTestScene] Effect index %d out of range" % current_effect_index)
		return

	var vfx_data: VisualEffectData = RomReader.vfx[current_effect_index]
	if vfx_data == null:
		print("[VfxTestScene] Effect %d is null" % current_effect_index)
		return

	current_instance = VfxEffectInstance.new()
	current_instance.name = "VfxEffect_%d" % current_effect_index
	current_instance.position = target_world_pos
	vfx_container.add_child(current_instance)
	current_instance.initialize(vfx_data, target_world_pos, origin_world_pos)
	current_instance.tree_exiting.connect(_on_effect_instance_finished)
	current_instance.renderer.set_z_bias(z_bias_spinbox.value)

	# Override target anchor if requested
	if target_anchor_overridden:
		var m: VfxEffectManager = current_instance.manager
		m.set_anchors(m.anchor_world, m.anchor_cursor, m.anchor_origin, target_anchor_override)
		print("[VfxTestScene] anchors after override: world=%s cursor=%s origin=%s target=%s" % [
			m.anchor_world, m.anchor_cursor, m.anchor_origin, m.anchor_target])

	# Populate checkboxes first, then apply mask
	_populate_emitter_list(vfx_data)
	_apply_emitter_mask()
	if anchor_spinboxes.is_empty():
		_populate_anchor_list()
	else:
		_apply_anchor_positions_from_spinboxes()
		_apply_anchor_mask()

	_first_play_started = true
	_loop_delay = 0.0


func _populate_emitter_list(vfx_data: VisualEffectData) -> void:
	# Clear existing
	for child in emitter_list_container.get_children():
		child.queue_free()
	emitter_checkboxes.clear()

	for i in range(vfx_data.emitters.size()):
		var cb := CheckBox.new()
		cb.text = "e[%d]" % i
		if not enable_emitters.is_empty():
			cb.button_pressed = enable_emitters.has(i)
		else:
			cb.button_pressed = (solo_emitter < 0 or i == solo_emitter)
		cb.toggled.connect(_on_emitter_toggled.bind(i))
		emitter_list_container.add_child(cb)
		emitter_checkboxes.append(cb)


func _populate_anchor_list() -> void:
	for child in anchor_list_container.get_children():
		child.queue_free()
	anchor_checkboxes.clear()
	anchor_spinboxes.clear()

	var anchor_names: Array[String] = ["world", "cursor", "origin", "target", "instance"]
	var anchor_colors: Array[String] = ["white", "yellow", "cyan", "magenta", "green"]
	# Convert local anchor positions to world space for display
	var instance_pos: Vector3 = current_instance.position
	var world_positions: Array[Vector3] = [
		instance_pos + current_instance.manager.anchor_world,
		instance_pos + current_instance.manager.anchor_cursor,
		instance_pos + current_instance.manager.anchor_origin,
		instance_pos + current_instance.manager.anchor_target,
		instance_pos,  # instance origin = its world position
	]

	for i in range(anchor_names.size()):
		var vbox := VBoxContainer.new()

		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [anchor_names[i], anchor_colors[i]]
		cb.button_pressed = true
		cb.toggled.connect(_on_anchor_toggled.bind(i))
		vbox.add_child(cb)
		anchor_checkboxes.append(cb)

		var world_pos: Vector3 = world_positions[i]
		var xyz_row := HBoxContainer.new()
		var spinboxes: Array[SpinBox] = []
		var axis_labels: Array[String] = ["X", "Y", "Z"]
		var axis_values: Array[float] = [world_pos.x, world_pos.y, world_pos.z]
		for axis in range(3):
			var lbl := Label.new()
			lbl.text = axis_labels[axis]
			lbl.add_theme_font_size_override("font_size", 11)
			xyz_row.add_child(lbl)

			var sb := SpinBox.new()
			sb.min_value = -50.0
			sb.max_value = 50.0
			sb.step = 1.0
			sb.custom_arrow_step = 1.0
			sb.value = axis_values[axis]
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sb.custom_minimum_size.x = 70
			sb.value_changed.connect(_on_anchor_spinbox_changed.bind(i))
			xyz_row.add_child(sb)
			spinboxes.append(sb)

		vbox.add_child(xyz_row)
		anchor_list_container.add_child(vbox)
		anchor_spinboxes.append(spinboxes)


func _on_emitter_toggled(_pressed: bool, _index: int) -> void:
	_apply_emitter_mask()
	# Restart effect so the mask takes effect from the beginning
	_play_effect_preserving_checkboxes()


func _on_anchor_toggled(_pressed: bool, _index: int) -> void:
	_apply_anchor_mask()


func _on_anchor_spinbox_changed(_value: float, index: int) -> void:
	if not current_instance or not is_instance_valid(current_instance):
		return
	if index >= anchor_spinboxes.size():
		return

	var sbs: Array[SpinBox] = anchor_spinboxes[index]
	var world_pos := Vector3(sbs[0].value, sbs[1].value, sbs[2].value)

	# Index 4 = instance origin — move the instance node itself
	if index == 4:
		current_instance.position = world_pos
		print("[VfxTestScene] instance origin → world %s" % world_pos)
		return

	# Convert world space to local (instance local space)
	var local_pos: Vector3 = world_pos - current_instance.position

	var m: VfxEffectManager = current_instance.manager
	var anchors: Array[Vector3] = [m.anchor_world, m.anchor_cursor, m.anchor_origin, m.anchor_target]
	anchors[index] = local_pos
	m.set_anchors(anchors[0], anchors[1], anchors[2], anchors[3])

	# Update the debug marker (markers are in local space)
	if index < current_instance._debug_anchor_markers.size():
		current_instance._debug_anchor_markers[index].position = local_pos

	var names: Array[String] = ["world", "cursor", "origin", "target"]
	print("[VfxTestScene] anchor '%s' → world %s (local %s)" % [names[index], world_pos, local_pos])


func _play_effect_preserving_checkboxes() -> void:
	if current_instance and is_instance_valid(current_instance):
		current_instance.queue_free()
		current_instance = null

	if current_effect_index < 0 or current_effect_index >= RomReader.vfx.size():
		return

	var vfx_data: VisualEffectData = RomReader.vfx[current_effect_index]
	if vfx_data == null:
		return

	current_instance = VfxEffectInstance.new()
	current_instance.name = "VfxEffect_%d" % current_effect_index
	current_instance.position = target_world_pos
	vfx_container.add_child(current_instance)
	current_instance.initialize(vfx_data, target_world_pos, origin_world_pos)
	current_instance.tree_exiting.connect(_on_effect_instance_finished)
	current_instance.renderer.set_z_bias(z_bias_spinbox.value)

	if target_anchor_overridden:
		var m: VfxEffectManager = current_instance.manager
		m.set_anchors(m.anchor_world, m.anchor_cursor, m.anchor_origin, target_anchor_override)

	_apply_anchor_positions_from_spinboxes()
	_apply_emitter_mask()
	_apply_anchor_mask()
	_loop_delay = 0.0


func _apply_emitter_mask() -> void:
	if not current_instance or not is_instance_valid(current_instance):
		return
	if current_instance.manager == null:
		return

	if emitter_checkboxes.is_empty():
		current_instance.manager.debug_emitter_mask = []
		return

	var mask: Array[bool] = []
	for cb: CheckBox in emitter_checkboxes:
		mask.append(cb.button_pressed)
	current_instance.manager.debug_emitter_mask = mask


func _apply_anchor_positions_from_spinboxes() -> void:
	if not current_instance or not is_instance_valid(current_instance):
		return
	if anchor_spinboxes.is_empty():
		return

	# Apply instance position first (index 4) since other anchors are relative to it
	if anchor_spinboxes.size() > 4:
		var sbs_inst: Array[SpinBox] = anchor_spinboxes[4]
		current_instance.position = Vector3(sbs_inst[0].value, sbs_inst[1].value, sbs_inst[2].value)

	var m: VfxEffectManager = current_instance.manager
	var anchors: Array[Vector3] = [m.anchor_world, m.anchor_cursor, m.anchor_origin, m.anchor_target]
	for i in range(mini(anchor_spinboxes.size(), anchors.size())):
		var sbs: Array[SpinBox] = anchor_spinboxes[i]
		var world_pos := Vector3(sbs[0].value, sbs[1].value, sbs[2].value)
		anchors[i] = world_pos - current_instance.position
	m.set_anchors(anchors[0], anchors[1], anchors[2], anchors[3])
	# Update debug markers for the 4 manager anchors
	for i in range(mini(4, current_instance._debug_anchor_markers.size())):
		current_instance._debug_anchor_markers[i].position = anchors[i]


func _apply_anchor_mask() -> void:
	if not current_instance or not is_instance_valid(current_instance):
		return
	for i in range(mini(anchor_checkboxes.size(), current_instance._debug_anchor_markers.size())):
		current_instance._debug_anchor_markers[i].visible = anchor_checkboxes[i].button_pressed


func _on_effect_instance_finished() -> void:
	current_instance = null
	if quit_after_loop:
		print("[VfxTestScene] first loop done — quitting")
		get_tree().quit()
		return
	_loop_delay = 0.0


func _process(delta: float) -> void:
	if not loop_checkbox.button_pressed:
		return

	if current_instance == null and _first_play_started:
		_loop_delay += delta
		if _loop_delay >= LOOP_DELAY_SECONDS:
			_play_effect_preserving_checkboxes()


func _on_effect_changed(value: float) -> void:
	current_effect_index = int(value)
	# Clear anchor UI so the new effect gets fresh defaults
	anchor_spinboxes.clear()
	anchor_checkboxes.clear()
	for child in anchor_list_container.get_children():
		child.queue_free()
	_play_effect()


func _on_play_pressed() -> void:
	_play_effect()


func _on_speed_changed(value: float) -> void:
	Engine.time_scale = value
	speed_label.text = "%.1fx" % value


func _on_z_bias_changed(value: float) -> void:
	if current_instance and is_instance_valid(current_instance) and current_instance.renderer:
		current_instance.renderer.set_z_bias(value)
