extends Node3D
## Plays real TRAP effects through the addon, so the integration can be SEEN rather than only
## asserted. A DEMO, not a test. Needs only the TRAP content (~660 KB), not the 224 MB of
## per-effect `E###` directories — spell and cinematic casts need those, TRAP handlers do not.
##
##   1..6        play a handler (hit clouds melee/ranged, knight break, charge particles,
##               spell charge lines, orbital summon orbs)
##   Left/Right  cycle element — recolours the particles
##   Space       stop any continuous charge effect

const CONTENT_ROOT := "res://content/"

## handler id -> label. These are the addon's own TRAP handler numbers.
const HANDLERS := {
	1: [2, "hit clouds (melee)"],
	2: [2, "hit clouds (ranged)"],
	3: [21, "knight break"],
	4: [8, "charge particles"],
	5: [4, "spell charge lines"],
	6: [22, "orbital summon orbs"],
}
const ELEMENT_NAMES := ["none", "fire", "lightning", "ice", "wind", "earth", "water", "holy", "dark"]

var _playback: EffectsPlayback
var _target: Node3D
var _element: int = 1
var _status: Label


func _ready() -> void:
	# Set here rather than in project.godot, so a checkout with no content keeps failing
	# legibly.
	ProjectSettings.set_setting(
		ExMateriaEffects.EffectsContent.ROOT_SETTING, CONTENT_ROOT)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.2, 5.0)
	camera.look_at_from_position(Vector3(0, 2.2, 5.0), Vector3(0, 1.0, 0), Vector3.UP)
	add_child(camera)

	# A stand-in for a Unit: the addon parents trap effects to the struck actor.
	_target = Node3D.new()
	_target.name = "Target"
	add_child(_target)
	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 1.6, 0.6)
	marker.mesh = mesh
	marker.position = Vector3(0, 0.8, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.2, 0.26)
	marker.material_override = mat
	_target.add_child(marker)

	_status = Label.new()
	_status.position = Vector2(16, 12)
	var layer := CanvasLayer.new()
	layer.add_child(_status)
	add_child(layer)

	_playback = EffectsPlayback.new()
	_playback.enabled = true            # the demo is the opt-in
	_playback.battle_manager = self     # this scene stands in for the battle
	add_child(_playback)

	if not _playback.begin(camera):
		_say("PLAYBACK UNAVAILABLE: " + _playback.unavailable_reason)
		push_error("EffectsDemo: " + _playback.unavailable_reason)
		return
	_say("ready")
	if "auto" in OS.get_cmdline_user_args():
		_auto_capture()


## Evidence that particles REACH THE FRAMEBUFFER: reads the viewport back and counts pixels
## that are not the clear colour. "ready" only proves `begin()` succeeded.
func _auto_capture() -> void:
	await get_tree().process_frame
	var before := await _lit_pixels()
	# NEGATIVE CONTROL: `-- auto noplay` is identical timing and measurement with no cast.
	var control: bool = "noplay" in OS.get_cmdline_user_args()
	if not control:
		_play(1)
	for i in 30:
		await get_tree().process_frame
	var after := await _lit_pixels()
	print("[EffectsDemo] AUTO%s lit_before=%d lit_after=%d delta=%d" % [
		" (CONTROL, no cast)" if control else "", before, after, after - before])
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("user://effects-demo.png")
	print("[EffectsDemo] AUTO screenshot user://effects-demo.png")
	if control:
		print("[EffectsDemo] AUTO CONTROL delta should be ~0")
		get_tree().quit(0)
		return
	print("[EffectsDemo] AUTO " + ("PARTICLES DREW" if after > before else "NOTHING DREW"))
	get_tree().quit(0 if after > before else 1)


func _lit_pixels() -> int:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if c.r + c.g + c.b > 0.35:
				count += 1
	return count


## Stands in for the battle, answering the two things the addon asks for.
## `EffectsCastHost` reads `units` off whatever it is given, so the name matters.
var units: Array = []
var total_map_tiles: Dictionary = {}


func _say(text: String) -> void:
	var handler_note := "  |  element: %s  (Left/Right)" % ELEMENT_NAMES[_element]
	_status.text = "ExMateria Effects demo — keys 1-6 play, Space stops\n" + text + handler_note
	print("[EffectsDemo] " + text)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if key == KEY_LEFT or key == KEY_RIGHT:
		_element = wrapi(_element + (1 if key == KEY_RIGHT else -1), 0, ELEMENT_NAMES.size())
		_say("element changed")
		return
	if key == KEY_SPACE:
		if _playback.is_available():
			_playback.manager().stop_charge_vfx(0, true)
		_say("charge stopped")
		return
	var slot: int = key - KEY_0
	if not HANDLERS.has(slot):
		return
	if not _playback.is_available():
		_say("PLAYBACK UNAVAILABLE: " + _playback.unavailable_reason)
		return
	_play(slot)


func _play(slot: int) -> void:
	var handler_id: int = HANDLERS[slot][0]
	var label: String = HANDLERS[slot][1]
	var trap := ExMateriaEffects.TrapEffect.new()
	_target.add_child(trap)
	if not trap.initialize(7, _element):
		trap.queue_free()
		_say("FAILED to initialize handler %d (%s) — is the TRAP content present?" % [handler_id, label])
		return
	var impact := Vector3(0, 1.0, 0)
	var direction := Vector3(0, 0, 1)
	if handler_id == 2:
		# Hit clouds split melee/ranged by emitter set, exactly as the manager does.
		var emitters: Array[int] = []
		emitters.assign([0, 9] if slot == 1 else [0, 1])
		trap.play_at(impact, direction, _target, emitters, true)
	else:
		trap.play_handler(handler_id, _element, impact, direction, _target)
	_say("played handler %d — %s" % [handler_id, label])
