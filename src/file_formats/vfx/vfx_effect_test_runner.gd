class_name VfxEffectTestRunner
extends Node3D
## Headless VFX test runner — plays an effect once with debug logging, then quits.
## Usage: godot --path <project> res://src/file_formats/vfx/vfx_effect_test_runner.tscn -- --effect=5

var effect_index: int = 5
var current_instance: VfxEffectInstance = null
var origin_world_pos: Vector3 = Vector3(1.5, 0, 1.5)
var target_world_pos: Vector3 = Vector3(3.5, 0, 1.5)
var _started: bool = false
var _timeout_frames: int = 0
const MAX_FRAMES: int = 600  # 20 seconds at 30fps


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--effect="):
			effect_index = int(arg.split("=")[1])

	print("[VFX_TEST] Running effect E%03d" % effect_index)

	if RomReader.is_ready:
		_start()
	else:
		RomReader.rom_loaded.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	# Load map for tile positions
	var maps_container := Node3D.new()
	maps_container.name = "Maps"
	add_child(maps_container)
	var map_node: MapChunkNodes = VfxTestUtils.load_mirrored_map(116, maps_container)
	if map_node:
		var map_data: MapData = map_node.map_data
		for tile: TerrainTile in map_data.terrain_tiles:
			if tile.location == Vector2i(1, 1):
				origin_world_pos = tile.get_world_position()
			elif tile.location == Vector2i(3, 1):
				target_world_pos = tile.get_world_position()

	# Load and play effect
	if effect_index < 0 or effect_index >= RomReader.vfx.size():
		print("[VFX_TEST] Effect index %d out of range" % effect_index)
		get_tree().quit()
		return

	var vfx_data: VisualEffectData = RomReader.vfx[effect_index]
	if vfx_data == null:
		print("[VFX_TEST] Effect %d is null" % effect_index)
		get_tree().quit()
		return

	# Ensure effect data is loaded
	if not vfx_data.is_initialized:
		vfx_data.init_from_file()

	# Print effect metadata
	print("[VFX_TEST] Emitters: %d, Curves: %d, Framesets: %d" % [
		vfx_data.emitters.size(), vfx_data.curves.size(), vfx_data.framesets.size()])

	# Dump emitter color curve config
	for i in range(vfx_data.emitters.size()):
		var em: VfxEmitter = vfx_data.emitters[i]
		var r: int = em.interpolation_curve_indicies.get(VfxConstants.CurveParam.COLOR_R, -1)
		var g: int = em.interpolation_curve_indicies.get(VfxConstants.CurveParam.COLOR_G, -1)
		var b: int = em.interpolation_curve_indicies.get(VfxConstants.CurveParam.COLOR_B, -1)
		if em.enable_color_curve or r > 0 or g > 0 or b > 0:
			print("[VFX_TEST] Emitter %d: enable_color_curve=%s, R=%d G=%d B=%d" % [
				i, em.enable_color_curve, r, g, b])

	var vfx_container := Node3D.new()
	vfx_container.name = "VfxContainer"
	add_child(vfx_container)

	current_instance = VfxEffectInstance.new()
	current_instance.name = "VfxEffect_%d" % effect_index
	current_instance.position = target_world_pos
	vfx_container.add_child(current_instance)
	current_instance.initialize(vfx_data, target_world_pos, origin_world_pos, false)

	# Enable color curve debug logging on the manager
	current_instance.manager.debug_color_curves_enabled = true

	# Prevent the instance from auto-freeing itself so we control the lifecycle
	current_instance.set_meta("test_runner_owned", true)

	_started = true
	_timeout_frames = 0
	print("[VFX_TEST] Effect started, waiting for completion...")


func _process(_delta: float) -> void:
	if not _started:
		return
	_timeout_frames += 1

	# Check if effect is done via manager (not tree_exiting)
	if current_instance and is_instance_valid(current_instance) and current_instance.manager:
		if current_instance.manager.is_done():
			print("[VFX_TEST] Effect completed after %d frames" % _timeout_frames)
			get_tree().quit()
			return

	if _timeout_frames >= MAX_FRAMES:
		print("[VFX_TEST] Timeout after %d frames — force quitting" % MAX_FRAMES)
		get_tree().quit()
