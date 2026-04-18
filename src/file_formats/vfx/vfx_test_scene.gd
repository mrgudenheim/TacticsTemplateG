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
@export var effect_name_label: Label
@export var play_button: Button
@export var loop_checkbox: CheckBox
@export var speed_slider: HSlider
@export var speed_label: Label
@export var depth_scale_slider: HSlider
@export var depth_scale_label: Label
@export var show_markers_checkbox: CheckBox
@export var show_map_checkbox: CheckBox
@export var show_background_checkbox: CheckBox
@export var emitter_list_container: VBoxContainer
@export var anchor_list_container: VBoxContainer
@export var world_environment: WorldEnvironment
@export var background_canvas: CanvasLayer
@export var directional_light: DirectionalLight3D

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
# Command-line: --debug-emitters to log per-emitter particle counts and semi_trans state
var debug_emitters: bool = false
# Command-line: --debug-depth to log CUSTOM0 centroid data and enable depth visualization
var debug_depth: bool = false
var _debug_emitter_tick: int = 0
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
		if arg == "--debug-emitters":
			debug_emitters = true
			print("[VfxTestScene] debug_emitters=true")
		if arg == "--debug-depth":
			debug_depth = true
			print("[VfxTestScene] debug_depth=true")
		if arg.begins_with("--effect="):
			current_effect_index = int(arg.split("=")[1])
			print("[VfxTestScene] effect=%d" % current_effect_index)
		if arg.begins_with("--target-anchor="):
			var parts: PackedStringArray = arg.split("=")[1].split(",")
			if parts.size() == 3:
				target_anchor_override = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				target_anchor_overridden = true
				print("[VfxTestScene] target_anchor_override=%s" % target_anchor_override)

	effect_spinbox.value_changed.connect(_on_effect_changed)
	effect_spinbox.get_line_edit().gui_input.connect(_on_spinbox_gui_input)
	play_button.pressed.connect(_on_play_pressed)
	speed_slider.value_changed.connect(_on_speed_changed)
	depth_scale_slider.value_changed.connect(_on_depth_scale_changed)
	show_markers_checkbox.toggled.connect(_on_show_markers_toggled)
	show_map_checkbox.toggled.connect(_on_show_map_toggled)
	show_background_checkbox.toggled.connect(_on_show_background_toggled)

	if RomReader.is_ready:
		_on_rom_loaded()
	else:
		RomReader.rom_loaded.connect(_on_rom_loaded, CONNECT_ONE_SHOT)


func _on_rom_loaded() -> void:
	_load_map()
	_play_effect()


func _load_map() -> void:
	var map_node: MapChunkNodes = VfxTestUtils.load_mirrored_map(116, maps_container)
	if map_node == null:
		return

	if debug_depth:
		var map_mat: ShaderMaterial = map_node.mesh_instance.material_override as ShaderMaterial
		if map_mat:
			map_mat.set_shader_parameter("debug_depth", true)

	var map_data: MapData = map_node.map_data

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


func _stop_current_effect() -> void:
	if current_instance and is_instance_valid(current_instance):
		# Disconnect to avoid spurious _on_effect_instance_finished during teardown
		if current_instance.tree_exiting.is_connected(_on_effect_instance_finished):
			current_instance.tree_exiting.disconnect(_on_effect_instance_finished)
		current_instance.set_process(false)
		current_instance.queue_free()
		current_instance = null


func _create_effect_instance() -> bool:
	_stop_current_effect()

	if current_effect_index < 0 or current_effect_index >= RomReader.vfx.size():
		print("[VfxTestScene] Effect index %d out of range" % current_effect_index)
		return false

	var vfx_data: VisualEffectData = RomReader.vfx[current_effect_index]
	if vfx_data == null:
		print("[VfxTestScene] Effect %d is null" % current_effect_index)
		return false

	current_instance = VfxEffectInstance.new()
	current_instance.name = "VfxEffect_%d" % current_effect_index
	current_instance.position = target_world_pos
	vfx_container.add_child(current_instance)
	current_instance.initialize(vfx_data, target_world_pos, origin_world_pos, true)
	current_instance.tree_exiting.connect(_on_effect_instance_finished)
	current_instance.renderer.depth_scale = depth_scale_slider.value
	if debug_depth:
		current_instance.renderer.debug_depth_enabled = true

	if target_anchor_overridden:
		var m: VfxEffectManager = current_instance.manager
		m.set_anchors(m.anchor_world, m.anchor_cursor, m.anchor_origin, target_anchor_override)

	_loop_delay = 0.0

	if not show_markers_checkbox.button_pressed:
		_on_show_markers_toggled(false)

	return true


func _play_effect() -> void:
	if not _create_effect_instance():
		return

	var vfx_data: VisualEffectData = RomReader.vfx[current_effect_index]

	if debug_depth:
		for ai in range(vfx_data.animations.size()):
			var anim: VisualEffectData.VfxAnimation = vfx_data.animations[ai]
			var depth_modes: Dictionary = {}
			for af: VisualEffectData.VfxAnimationFrame in anim.animation_frames:
				if af.frameset_id <= VfxConstants.MAX_FRAMESET_ID:
					depth_modes[af.byte_02] = depth_modes.get(af.byte_02, 0) + 1
			if not depth_modes.is_empty():
				print("[DEPTH_DEBUG] Animation %d depth_modes (byte_02): %s" % [ai, depth_modes])

	if debug_emitters:
		var mgr: VfxEffectManager = current_instance.manager
		print("[TIMELINE] phase1_duration=%d phase2_offset=%d" % [mgr.phase1_duration, mgr.phase2_start])
		_dump_timelines("phase1", vfx_data.phase1_emitter_timelines)
		_dump_timelines("animate_tick", vfx_data.child_emitter_timelines)
		_dump_timelines("phase2", vfx_data.phase2_emitter_timelines)

	if target_anchor_overridden:
		print("[VfxTestScene] anchors after override: world=%s cursor=%s origin=%s target=%s" % [
			current_instance.manager.anchor_world, current_instance.manager.anchor_cursor,
			current_instance.manager.anchor_origin, current_instance.manager.anchor_target])

	_update_effect_name_label()
	_populate_emitter_list(vfx_data)
	_apply_emitter_mask()
	if anchor_spinboxes.is_empty():
		_populate_anchor_list()
	else:
		_apply_anchor_positions_from_spinboxes()
		_apply_anchor_mask()

	_first_play_started = true


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
	if not _create_effect_instance():
		return
	_apply_anchor_positions_from_spinboxes()
	_apply_emitter_mask()
	_apply_anchor_mask()


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
	var markers_on: bool = show_markers_checkbox.button_pressed
	for i in range(mini(anchor_checkboxes.size(), current_instance._debug_anchor_markers.size())):
		current_instance._debug_anchor_markers[i].visible = markers_on and anchor_checkboxes[i].button_pressed


func _on_effect_instance_finished() -> void:
	current_instance = null
	if quit_after_loop:
		print("[VfxTestScene] first loop done — quitting")
		get_tree().quit()
		return
	_loop_delay = 0.0


func _process(delta: float) -> void:
	# Emitter debug logging
	if debug_emitters and current_instance and is_instance_valid(current_instance) and current_instance.manager:
		_debug_emitter_tick += 1
		if _debug_emitter_tick % 15 == 1:
			var mgr: VfxEffectManager = current_instance.manager
			var vfx_data: VisualEffectData = mgr.vfx_data
			var counts: Dictionary = {}  # emitter_index -> particle count
			for emitter: VfxActiveEmitter in mgr.active_emitters:
				for p: VfxParticleData in emitter.particles:
					if p.age == 0 or not p.active:
						continue
					counts[p.emitter_index] = counts.get(p.emitter_index, 0) + 1
			if not counts.is_empty():
				var parts: Array[String] = []
				for ei: int in counts:
					parts.append("e%d=%d" % [ei, counts[ei]])
				print("[EMITTERS] tick=%d %s" % [_debug_emitter_tick, " ".join(parts)])

			# Detailed log for emitters 0 and 1
			for emitter: VfxActiveEmitter in mgr.active_emitters:
				if emitter.emitter_index > 1:
					continue
				for p: VfxParticleData in emitter.particles:
					if p.age == 0 or not p.active:
						continue
					var fs_idx: int = p.current_frameset
					if fs_idx < 0 or fs_idx >= vfx_data.framesets.size():
						continue
					var fs: VisualEffectData.VfxFrameSet = vfx_data.framesets[fs_idx]
					var info: String = ""
					for fr: VisualEffectData.VfxFrame in fs.frameset:
						var label: String = "OPAQUE" if not fr.semi_transparency_on else "SEMI(%d)" % fr.semi_transparency_mode
						info += "[%s] " % label
					print("[EMITTERS]   e%d uid=%d age=%d fs=%d %s" % [p.emitter_index, p.uid, p.age, fs_idx, info])
					break  # first particle only

	if not loop_checkbox.button_pressed:
		return

	if current_instance == null and _first_play_started:
		_loop_delay += delta
		if _loop_delay >= LOOP_DELAY_SECONDS:
			_play_effect_preserving_checkboxes()


func _on_effect_changed(value: float) -> void:
	current_effect_index = int(value)
	_update_effect_name_label()
	# Clear anchor UI so the new effect gets fresh defaults
	anchor_spinboxes.clear()
	anchor_checkboxes.clear()
	for child in anchor_list_container.get_children():
		child.queue_free()
	_play_effect()


func _update_effect_name_label() -> void:
	if current_effect_index >= 0 and current_effect_index < RomReader.vfx.size():
		var vfx: VisualEffectData = RomReader.vfx[current_effect_index]
		var names: String = vfx.ability_names.strip_edges() if vfx else ""
		effect_name_label.text = names if not names.is_empty() else "(no ability)"
	else:
		effect_name_label.text = ""


func _on_play_pressed() -> void:
	if emitter_checkboxes.is_empty():
		_play_effect()
	else:
		_play_effect_preserving_checkboxes()


func _on_speed_changed(value: float) -> void:
	Engine.time_scale = value
	speed_label.text = "%.1fx" % value


func _on_depth_scale_changed(value: float) -> void:
	depth_scale_label.text = "%.1f" % value
	if current_instance and is_instance_valid(current_instance) and current_instance.renderer:
		current_instance.renderer.depth_scale = value


func _on_spinbox_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key: Key = event.keycode
		if key == KEY_Q or key == KEY_E or key == KEY_W or key == KEY_A or key == KEY_S or key == KEY_D or key == KEY_ESCAPE:
			effect_spinbox.get_line_edit().release_focus()


func _on_show_markers_toggled(on: bool) -> void:
	origin_marker.visible = on
	target_marker.visible = on
	if current_instance and is_instance_valid(current_instance):
		current_instance.debug_markers_visible = on
		for marker: MeshInstance3D in current_instance._debug_anchor_markers:
			marker.visible = on
		for marker: MeshInstance3D in current_instance._debug_emitter_markers:
			marker.visible = on


func _on_show_map_toggled(on: bool) -> void:
	maps_container.visible = on


func _on_show_background_toggled(on: bool) -> void:
	if on:
		background_canvas.get_child(0).texture.gradient.colors = PackedColorArray([
			Color(0.1332, 0.14724, 0.18, 1), Color(0.39, 0.695, 1, 1)])
	else:
		background_canvas.get_child(0).texture.gradient.colors = PackedColorArray([
			Color.BLACK, Color.BLACK])
	directional_light.visible = on


func _dump_timelines(label: String, timelines: Array[VisualEffectData.EmitterTimeline]) -> void:
	for ch_idx in range(timelines.size()):
		var tl: VisualEffectData.EmitterTimeline = timelines[ch_idx]
		var spawns: Array[String] = []
		for kf_idx in range(tl.keyframes.size()):
			var kf: VisualEffectData.EmitterKeyframe = tl.keyframes[kf_idx]
			if kf.emitter_id > 0:
				spawns.append("kf[%d] t=%d eid=%d(e%d) flags=0x%04X" % [
					kf_idx, kf.time, kf.emitter_id, kf.emitter_id - 1,
					kf.flags.decode_u16(0) if kf.flags.size() >= 2 else 0])
		if not spawns.is_empty():
			print("[TIMELINE] %s ch[%d] num_kf=%d: %s" % [label, ch_idx, tl.num_keyframes, "; ".join(spawns)])
