extends Node3D
## Pick an `E###` effect and scrub it on a map. The effect is spawned parked at frame 0.
## Play runs the effect's own clock, which applies its time-scale (slow-motion) curve;
## scrub and step park it and `seek()`, which lands on the same frame but cannot show pacing.
##
##   Space        play / pause
##   , / .        step one frame back / forward
##   Home         back to frame 0
##   Up / Down    previous / next effect in the list
##
## `-- --effect=N` opens E### N on start.

const EffectExtractPaths := preload("res://src/file_formats/vfx/effect_extract.gd")

const MAP_NAME: String = "map_116"
const CASTER_TILE := Vector2i(1, 1)
const TARGET_TILE := Vector2i(3, 1)
const DEFAULT_EFFECT: int = 1

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0]
const DEFAULT_SPEED_INDEX: int = 2
## Where the ruler ends before anything is known about the effect's tail.
const MIN_LENGTH_FRAMES: int = 60
## The palette RESTORE ramp runs past the last phase; see `EffectsPlayback`.
const TAIL_FRAMES: int = EffectsPlayback.PALETTE_RESTORE_RAMP_FRAMES
## A ruler that grows while particles are alive stops growing here.
const MAX_LENGTH_FRAMES: int = 1200
const LOOP_PAUSE_SECONDS: float = 0.5

@export var camera_controller: CameraController
@export var maps_container: Node3D
@export var ui_root: Control

## `EffectsCastHost` reads these off its stage, which this scene stands in for.
var units: Array = []
var total_map_tiles: Dictionary = {}

var _playback: EffectsPlayback
var _camera_track: EffectCameraTrack
var _caster: Node3D
var _target: Node3D

var _effect_ids: Array[int] = []
## E### -> the display names of the actions that draw it.
var _effect_names: Dictionary = {}
var _effect_id: int = -1
var _cast: Node3D = null
## Whether `_cast`'s camera has its base pose. Seeded once; a replay restarts from it.
var _camera_seeded: bool = false
var _length: int = MIN_LENGTH_FRAMES
var _playing: bool = false
var _loop_wait: float = 0.0
var _syncing_scrub: bool = false

var _filter_edit: LineEdit
var _effect_list: ItemList
var _title_label: Label
var _play_button: Button
var _scrub: HSlider
var _frame_label: Label
var _loop_check: CheckBox
var _camera_check: CheckBox
var _markers_check: CheckBox
var _map_check: CheckBox
var _emitter_box: VBoxContainer
var _emitter_checks: Array[CheckBox] = []
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_build_actors()
	_say("waiting for imported data — set the import path in the data panel")
	if GameData.is_ready:
		_on_data_ready()
	else:
		GameData.data_indexed.connect(_on_data_ready, CONNECT_ONE_SHOT)


func _on_data_ready() -> void:
	_load_map()
	if not _start_playback():
		return
	_index_effect_names()
	_scan_effects()
	var wanted: int = DEFAULT_EFFECT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--effect="):
			wanted = arg.get_slice("=", 1).to_int()
	_select_effect(wanted)


func _start_playback() -> bool:
	_playback = EffectsPlayback.new()
	_playback.name = "EffectsPlayback"
	_playback.enabled = true
	_playback.battle_manager = self
	var root: String = EffectExtractPaths.content_root()
	if DirAccess.dir_exists_absolute(EffectExtractPaths.effects_dir(root)):
		_playback.content_root = root
	add_child(_playback)
	if not _playback.initialize(camera_controller.camera):
		_say("PLAYBACK UNAVAILABLE: " + _playback.unavailable_reason)
		push_error("EffectViewer: " + _playback.unavailable_reason)
		return false
	_camera_track = EffectCameraTrack.new(camera_controller)
	add_child(_camera_track)
	return true


# --- stage ---


func _build_actors() -> void:
	_caster = _make_marker("Caster", Color(0.2, 0.6, 1.0))
	_target = _make_marker("Target", Color(1.0, 0.3, 0.2))
	_caster.position = Vector3(1.5, 0, 1.5)
	_target.position = Vector3(3.5, 0, 1.5)
	units = [_caster, _target]


func _make_marker(marker_name: String, color: Color) -> Node3D:
	var actor := Node3D.new()
	actor.name = marker_name
	add_child(actor)
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	marker.mesh = mesh
	marker.material_override = mat
	marker.position = Vector3(0, 0.15, 0)
	actor.add_child(marker)
	return actor


func _load_map() -> void:
	var map_node: MapChunkNodes = VfxTestUtils.load_mirrored_map(MAP_NAME, maps_container)
	if map_node == null:
		_say("map %s not found; effects play over an empty stage" % MAP_NAME)
		return
	for tile: TerrainTile in map_node.map_data.terrain_tiles:
		total_map_tiles[tile.location] = true
		if tile.location == CASTER_TILE:
			_caster.position = tile.get_world_position()
		elif tile.location == TARGET_TILE:
			_target.position = tile.get_world_position()
	camera_controller.position = (_caster.position + _target.position) * 0.5


# --- effect list ---


func _scan_effects() -> void:
	_effect_ids.clear()
	var dir: String = EffectExtractPaths.effects_dir(EffectExtractPaths.content_root())
	for entry: String in DirAccess.get_directories_at(dir):
		if entry.length() == 4 and entry.begins_with("E") and entry.substr(1).is_valid_int():
			_effect_ids.append(entry.substr(1).to_int())
	_effect_ids.sort()
	_refresh_list()
	if _effect_ids.is_empty():
		_say("no E### directories under \"%s\"" % dir)


func _index_effect_names() -> void:
	_effect_names.clear()
	for action_name: String in GameData.action_paths.keys():
		var action: Action = GameData.get_action(action_name)
		if action == null:
			continue
		var effect_id: int = EffectsPlayback.effect_id_for(action)
		if effect_id < 0 or action.display_name.is_empty():
			continue
		var names: PackedStringArray = _effect_names.get(effect_id, PackedStringArray())
		if not names.has(action.display_name):
			names.append(action.display_name)
		_effect_names[effect_id] = names


func _effect_label(effect_id: int) -> String:
	var names: PackedStringArray = _effect_names.get(effect_id, PackedStringArray())
	if names.is_empty():
		return "E%03d" % effect_id
	return "E%03d  %s" % [effect_id, ", ".join(names)]


func _refresh_list() -> void:
	var needle: String = _filter_edit.text.strip_edges().to_lower()
	_effect_list.clear()
	for effect_id: int in _effect_ids:
		var label: String = _effect_label(effect_id)
		if not needle.is_empty() and not label.to_lower().contains(needle):
			continue
		var index: int = _effect_list.add_item(label)
		_effect_list.set_item_metadata(index, effect_id)
		if effect_id == _effect_id:
			_effect_list.select(index)


func _on_effect_activated(index: int) -> void:
	_select_effect(int(_effect_list.get_item_metadata(index)))


func _step_selection(delta: int) -> void:
	if _effect_list.item_count == 0:
		return
	var selected: PackedInt32Array = _effect_list.get_selected_items()
	var index: int = selected[0] + delta if not selected.is_empty() else 0
	index = clampi(index, 0, _effect_list.item_count - 1)
	_effect_list.select(index)
	_effect_list.ensure_current_is_visible()
	_on_effect_activated(index)


# --- the cast ---


func _select_effect(effect_id: int) -> void:
	_effect_id = effect_id
	_title_label.text = _effect_label(effect_id)
	for i in _effect_list.item_count:
		if int(_effect_list.get_item_metadata(i)) == effect_id:
			_effect_list.select(i)
			_effect_list.ensure_current_is_visible()
	_spawn_parked()
	_populate_emitters()
	_set_playing(true)


## A fresh instance at frame 0, paused. Re-spawning rather than re-seeking is what a pick
## needs: the instance reads its directory once, in `initialize()`.
func _spawn_parked() -> void:
	_clear_cast()
	if _playback == null or not _playback.is_available():
		return
	var dir: String = ExMateriaEffects.EffectsContent.effect_dir("E%03d" % _effect_id)
	if not DirAccess.dir_exists_absolute(dir):
		_say("no content at \"%s\"" % dir)
		return
	var cast: Node3D = _playback.manager().spawn_cinematic_effect(_caster, _target, -1, _effect_id)
	if cast == null:
		_say("E%03d failed to initialize — see the log" % _effect_id)
		return
	_cast = cast
	_camera_seeded = false
	_cast.set_paused(true)
	# Before the first frame: keyframes resolve against the pose the adoption seeds.
	if _camera_check.button_pressed:
		_adopt_camera()
	_cast.seek(0)
	_length = _initial_length()
	_apply_emitter_filter()
	_sync_scrub()
	_say("loaded E%03d — %d emitters" % [_effect_id, _cast.get_emitter_count()])


func _clear_cast() -> void:
	if is_instance_valid(_camera_track):
		_camera_track.release()
	if is_instance_valid(_cast):
		_cast.queue_free()
	_cast = null


## The timeline's last phase plus the palette ramp. Particles can outlive it, so the ruler
## also grows while any are alive at its end.
func _initial_length() -> int:
	var length: int = MIN_LENGTH_FRAMES
	if _cast.effect_data != null and _cast.effect_data.timeline != null:
		var timeline = _cast.effect_data.timeline
		length = maxi(length, int(timeline.phase1_duration) + int(timeline.phase2_delay)
			+ TAIL_FRAMES)
	return mini(length, MAX_LENGTH_FRAMES)


func _adopt_camera() -> void:
	if not is_instance_valid(_cast) or not is_instance_valid(_camera_track):
		return
	var frame: int = _frame()
	if not _camera_track.adopt(_cast, not _camera_seeded) or _camera_seeded:
		return
	_camera_seeded = true
	# Seeded mid-cast: replay up to here so the pose is the one this frame would have.
	if frame > 0:
		_cast.seek(0)
		_cast.seek(frame)


func _frame() -> int:
	return _cast.get_effect_frame() if is_instance_valid(_cast) else 0


func _seek(frame: int) -> void:
	if not is_instance_valid(_cast):
		return
	frame = clampi(frame, 0, _length)
	if frame < _frame():
		# The cast replays its camera from the seeded pose; re-taking the rig, rather than
		# holding it, also covers a track that already ended.
		if is_instance_valid(_camera_track):
			_camera_track.release()
		_cast.seek(frame)
		if _camera_check.button_pressed:
			_adopt_camera()
	else:
		_cast.seek(frame)
	_sync_scrub()


func _process(delta: float) -> void:
	if not _playing or not is_instance_valid(_cast):
		return
	if _loop_wait > 0.0:
		_loop_wait -= delta
		if _loop_wait <= 0.0:
			_seek(0)
			_cast.set_paused(false)
		return
	var frame: int = _frame()
	if frame >= _length and _cast.get_active_particle_count() > 0 \
			and _length < MAX_LENGTH_FRAMES:
		_length = mini(frame + 1, MAX_LENGTH_FRAMES)
	if frame >= _length:
		_cast.set_paused(true)
		if _loop_check.button_pressed:
			_loop_wait = LOOP_PAUSE_SECONDS
		else:
			_set_playing(false)
	_sync_scrub()


func _set_playing(playing: bool) -> void:
	_playing = playing and is_instance_valid(_cast)
	_loop_wait = 0.0
	# Play from the end restarts, like any transport.
	if _playing and _frame() >= _length:
		_seek(0)
	if is_instance_valid(_cast):
		_cast.set_paused(not _playing)
	_play_button.text = "Pause" if _playing else "Play"


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _park_at(frame: int) -> void:
	_set_playing(false)
	_seek(frame)


func _step_frame(delta: int) -> void:
	_park_at(_frame() + delta)


func _sync_scrub() -> void:
	_syncing_scrub = true
	_scrub.max_value = _length
	_scrub.value = _frame()
	_syncing_scrub = false
	var particles: int = _cast.get_active_particle_count() if is_instance_valid(_cast) else 0
	_frame_label.text = "frame %d / %d   particles %d" % [_frame(), _length, particles]


# --- emitters ---


func _populate_emitters() -> void:
	for child: Node in _emitter_box.get_children():
		child.queue_free()
	_emitter_checks.clear()
	if not is_instance_valid(_cast):
		return
	for i in _cast.get_emitter_count():
		var check := CheckBox.new()
		check.text = "emitter %d" % i
		check.button_pressed = true
		check.toggled.connect(func(_on: bool) -> void: _apply_emitter_filter())
		_emitter_box.add_child(check)
		_emitter_checks.append(check)


func _apply_emitter_filter() -> void:
	if not is_instance_valid(_cast):
		return
	var hidden: Dictionary = {}
	for i in _emitter_checks.size():
		if not _emitter_checks[i].button_pressed:
			hidden[i] = true
	_cast.set_debug_emitter_filter(hidden)


# --- UI ---


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	ui_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_KEEP_WIDTH, 8)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	_title_label = Label.new()
	_title_label.text = "Effect viewer"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title_label)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "filter: number or ability name"
	_filter_edit.clear_button_enabled = true
	_filter_edit.text_changed.connect(func(_text: String) -> void: _refresh_list())
	column.add_child(_filter_edit)

	_effect_list = ItemList.new()
	_effect_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_effect_list.size_flags_stretch_ratio = 2.0
	_effect_list.item_selected.connect(_on_effect_activated)
	column.add_child(_effect_list)

	var transport := HBoxContainer.new()
	column.add_child(transport)
	transport.add_child(_button("|<", _park_at.bind(0)))
	transport.add_child(_button("<", _step_frame.bind(-1)))
	_play_button = _button("Play", func() -> void: _set_playing(not _playing))
	_play_button.custom_minimum_size.x = 64
	transport.add_child(_play_button)
	transport.add_child(_button(">", _step_frame.bind(1)))
	var speed := OptionButton.new()
	for s: float in SPEEDS:
		speed.add_item("%sx" % s)
	speed.select(DEFAULT_SPEED_INDEX)
	# The effect's clock reads the frame delta, so this is the one speed knob that keeps
	# its pacing curve intact.
	speed.item_selected.connect(func(i: int) -> void: Engine.time_scale = SPEEDS[i])
	speed.focus_mode = Control.FOCUS_NONE
	transport.add_child(speed)
	_loop_check = CheckBox.new()
	_loop_check.text = "Loop"
	_loop_check.button_pressed = true
	_loop_check.focus_mode = Control.FOCUS_NONE
	transport.add_child(_loop_check)

	_scrub = HSlider.new()
	_scrub.step = 1
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.value_changed.connect(_on_scrub_changed)
	column.add_child(_scrub)
	_frame_label = Label.new()
	column.add_child(_frame_label)

	_camera_check = _toggle("Effect camera", false, _on_camera_toggled)
	column.add_child(_camera_check)
	_markers_check = _toggle("Caster / target markers", true, _on_markers_toggled)
	column.add_child(_markers_check)
	_map_check = _toggle("Map", true, func(on: bool) -> void: maps_container.visible = on)
	column.add_child(_map_check)

	column.add_child(HSeparator.new())
	var emitter_scroll := ScrollContainer.new()
	emitter_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	emitter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(emitter_scroll)
	_emitter_box = VBoxContainer.new()
	emitter_scroll.add_child(_emitter_box)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	return button


func _toggle(text: String, on: bool, on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = on
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(on_toggled)
	return check


func _on_scrub_changed(value: float) -> void:
	if _syncing_scrub:
		return
	_park_at(int(value))


func _on_camera_toggled(on: bool) -> void:
	if on:
		_adopt_camera()
	elif is_instance_valid(_camera_track):
		_camera_track.release()


func _on_markers_toggled(on: bool) -> void:
	for actor: Node3D in [_caster, _target]:
		actor.get_node("Marker").visible = on


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	match event.keycode:
		KEY_SPACE:
			if not event.echo:
				_set_playing(not _playing)
		KEY_COMMA:
			_step_frame(-1)
		KEY_PERIOD:
			_step_frame(1)
		KEY_HOME:
			_park_at(0)
		KEY_UP:
			_step_selection(-1)
		KEY_DOWN:
			_step_selection(1)
		_:
			return
	get_viewport().set_input_as_handled()


func _say(text: String) -> void:
	_status_label.text = text
	print("[EffectViewer] " + text)
