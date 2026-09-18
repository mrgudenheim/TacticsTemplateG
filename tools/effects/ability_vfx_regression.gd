extends Node3D
## Scores a real battle ABILITY drawing through `addons/exmateria_effects`: the `E###`
## mapping, the cast's pixels, the TRAP handlers, and the SCREEN, CAMERA and PALETTE
## tracks.
##
##   Godot --path . res://tools/effects/ability_vfx_regression.tscn -- auto [--actions=DIR]
##   Godot --path . res://tools/effects/ability_vfx_regression.tscn -- auto noplay [...]
##
## Arm A needs `--actions=<dir>`. Never `--headless`: arms B/C/D read a framebuffer.

## Must be the path `RomReader.generate_effects_content()` writes and `BattleManager` reads.
const EffectExtractPaths := preload("res://src/file_formats/vfx/effect_extract.gd")
const CONTENT_ROOT := EffectExtractPaths.CONTENT_ROOT

## Fire: bright, centred and long-lived, so arm B cannot fail for dimness.
const PROBE_ACTION := {"unique_name": "fire", "vfx_name": "e_016", "vfx_id": 16}

## SECONDS, not frames — the effect advances on delta time. A spell peaks ~1.7s-4s.
const SAMPLE_SECONDS: float = 6.0
## Time for the producer to reach a steady state before the baseline is taken.
const SETTLE_SECONDS: float = 1.0
const MIN_DREW_PX: int = 500
## The control's honest reading is 0; this covers renderer dither.
const CONTROL_TOLERANCE_PX: int = 50
const PIXEL_EPSILON: float = 0.02
## Above this fraction a sample is desktop interference, and is re-baselined not scored.
const DISTURBANCE_FRACTION: float = 0.5
## Hit clouds: the handler almost every physical attack resolves to.
const TRAP_PROBE_HANDLER: int = 2
const TRAP_PROBE_ELEMENT: int = 1
## Trap handlers are immediate — no spell wind-up to wait through.
const TRAP_SAMPLE_SECONDS: float = 2.5
## Far enough to separate caster and origin on screen; near enough that both stay in frame.
const CASTER_ORIGIN_OFFSET := Vector3(2.2, 0.0, 0.0)
## The cast must land nearer the caster than the origin by at least this ratio.
const POSITION_MARGIN: float = 1.5

## Far apart in every channel, so a top/bottom swap fails the orientation check.
const BG_TOP := Color(0.10, 0.06, 0.30)
const BG_BOTTOM := Color(0.75, 0.45, 0.20)
## The sampled sky patch: top eighth of the frame, clear of the centre where casts play.
const BG_PATCH_FRACTION: float = 0.125
const BG_MIN_DELTA: float = 0.02
## Covers readback rounding only; the control's honest reading is 0.0.
const BG_CONTROL_TOLERANCE: float = 0.004

## The shipped rig: its projection, child stand-off and starting zoom are under test.
const CAMERA_RIG_SCENE := preload("res://src/camera_controller.tscn")
## Loaded by path, not through the addon's entry-point script whose export count another
## check pins. This is the addon's own answer for which way a given PSX yaw faces.
const FACING_RESOLVER_PATH := "res://addons/exmateria_effects/camera/CinematicFacingResolver.gd"
## The addon's own active-keyframe gate, used directly so the count cannot drift from it.
const CAMERA_DATA_PATH := "res://addons/exmateria_effects/file_model/CameraData.gd"
## E016's camera track runs ~71 effect frames at 30 Hz; the cast outlives it.
const CAM_SAMPLE_SECONDS: float = 6.0
## A spell is capped at ~10.5s, so past this a stuck camera is a defect, not a slow test.
const CAM_RELEASE_TIMEOUT: float = 14.0
## Float noise only — the camera is given exactly the numbers the conversion produced.
const CAM_TRACK_EPSILON: float = 0.0005
## Godot units of focus travel the rig must show.
const CAM_MIN_FOCUS_MOVE: float = 0.5
## The restore must land on the pre-cast numbers, not near them.
const CAM_RESTORE_EPSILON: float = 0.001
const CAM_CONTROL_TOLERANCE: float = 0.004
## PSX yaw 1024 = 90 degrees.
const CAM_PROBE_YAW: float = 1024.0

## The sprite rig alone: a whole `Unit` needs an indexed `GameData`, and every material
## and registration under test lives on this scene.
const UNIT_SPRITES_SCENE := preload("res://src/Unit/unit_sprites_manager.tscn")
## Loaded by path for the reason above. Lets the test aim a colour change at ONE surface,
## which the addon's public API cannot do, and supplies the expected arithmetic below.
const COLOR_STACK_PATH := "res://addons/exmateria_schema/colour_model/ColorStack.gd"
## A READBACK tolerance, not a modelling one: just above 8-bit framebuffer rounding.
const UNIT_FOLD_EPSILON: float = 0.02
## NOT E016, which has no CASTER keyframes. E015 drives both channels mode-4
## `base + delta` at the full 5-bit parameter (31/31 = white).
const UNIT_TINT_ACTION := {"unique_name": "e015-unit-colour-probe", "vfx_name": "e_015", "vfx_id": 15}
## The BYSTANDER is targeted by nothing — the control for a stray layer and for particles.
## Nothing past +/-2.1: a probe off-frame reads as "did not move" and PASSES.
const UNIT_CASTER_POS := Vector3(-1.8, 1.4, 0.0)
const UNIT_TARGET_POS := Vector3(1.8, 1.4, 0.0)
const UNIT_BYSTANDER_POS := Vector3(1.8, -1.4, 0.0)
## Pushed off the body along Y so all three surfaces sample independently.
const UNIT_WEAPON_OFFSET := Vector3(0.0, -0.8, 0.0)
const UNIT_EFFECT_OFFSET := Vector3(0.0, 0.8, 0.0)
## 256 px over the scene's 16 hframes/vframes is a 16 px frame, ~0.57 world units.
const UNIT_TEXTURE_PX: int = 256
## Half-extent of the sampled box; the sprite projects to ~64 px at worst.
const UNIT_PATCH_HALF_PX: int = 12
## The probe's CLUT entry. Mid grey leaves headroom for a tint to rise without clipping.
const UNIT_BASE_COLOUR := Color(0.35, 0.35, 0.35, 1.0)
## One channel each, so a wrong-channel fold fails rather than passing on magnitude.
const UNIT_CASTER_DELTA := Color(0.60, 0.0, 0.0)
const UNIT_TARGET_DELTA := Color(0.0, 0.0, 0.60)
## Far from `PaletteSubsystem.owner_id` so these cannot be mistaken for a cast's layers.
const UNIT_TINT_OWNER: int = 0x7F000001
const UNIT_MASK_OWNER: int = 0x7F000002
## A tinted channel must rise by this; the untinted two stay under the tolerance.
const UNIT_MIN_RISE: float = 0.08
const UNIT_TINT_TOLERANCE: float = 0.02
## E015's unit keyframes ramp over 32 effect frames and the cast outlives that.
const UNIT_SAMPLE_SECONDS: float = 6.0
## Past `EffectsPlayback.CAST_CAP_MAX_SECONDS`: the claim is what the cast does BEFORE
## it is freed, so this must measure the cast ending, not the arm giving up.
const UNIT_CAST_WATCH_SECONDS: float = 34.0
## How much longer the target holds its colour than the bystander is brushed by the plume.
const UNIT_SUSTAIN_RATIO: float = 3.0
## A spell is capped at roughly 10.5s.
const UNIT_QUIET_TIMEOUT: float = 14.0
## Two tiles sideways, with no cast in the scene, so only the camera can repaint.
const CAM_PIXEL_OFFSET_PSX := Vector3(56.0, 0.0, 0.0)   # 2 tiles, 28 units each
const CAM_MIN_MOVED_PX: int = 2000
const CAM_RETURN_TOLERANCE_PX: int = 50
## A spell is capped at roughly 10.5s.
const CAM_QUIET_TIMEOUT: float = 14.0
## What the camera move is measured against; an empty frame does not move when the camera
## does. Unshaded, and spread so a pan, orbit and zoom each repaint a different part.
const CAM_LANDMARKS: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(-3, 0, 0),
	Vector3(0, 0, 3), Vector3(0, 0, -3),
]
const CAM_LANDMARK_SIZE := Vector3(1.6, 1.6, 1.6)

## E016's angle keyframes are `TARGET` with a zero offset, leaving the ABSOLUTE-yaw path
## untested. E063's `DIRECT ang=[302, 3584, 0]` names one, where chirality cannot hide.
const CAM_YAW_PROBE := {"unique_name": "e063-yaw-probe", "vfx_name": "e_063", "vfx_id": 63}
## PSX 3584 = 315 degrees, consumed RAW, so the rig must land on exactly this.
const CAM_YAW_TARGET_PSX: float = 3584.0
## The short way round: -512 PSX = -45 degrees. The wrong direction reads +315.
const CAM_YAW_EXPECTED_DELTA: float = -45.0
const CAM_YAW_EPSILON: float = 1.0
const CAM_YAW_SAMPLE_SECONDS: float = 5.0
## A synthetic arena so `arena_bounds()` has a known value. Not square: a transposed x/y
## fails.
const FAKE_MAP_TILES := Vector2i(12, 7)

var _playback: EffectsPlayback
## Arm F's cast, kept so it can be waited out before arm D takes the frame.
var _unit_cast: Node3D
var _caster: Node3D
var _background: ScreenBackgroundQuad
var _failures: Array[String] = []
var _checks: int = 0

## `EffectsCastHost` reads these off the battle, so the names must match `BattleManager`'s.
var units: Array = []
var total_map_tiles: Dictionary = {}


func _ready() -> void:
	ProjectSettings.set_setting(
		ExMateriaEffects.EffectsContent.ROOT_SETTING, CONTENT_ROOT)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.2, 5.0)
	camera.look_at_from_position(Vector3(0, 2.2, 5.0), Vector3(0, 1.0, 0), Vector3.UP)
	add_child(camera)

	# Attached with the camera, as `BattleManager._ready` does — the overlay latches its
	# material on the first screen frame. Hidden until arm D, or B and C re-baseline.
	_background = ScreenBackgroundQuad.attach(camera)
	_background.set_gradient(BG_TOP, BG_BOTTOM)
	_background.visible = false

	_caster = Node3D.new()
	_caster.name = "Caster"
	add_child(_caster)
	# Off the origin, or "at the caster" and "at the origin" are the same pixels.
	_caster.position = CASTER_ORIGIN_OFFSET
	units.append(_caster)

	# Read off the battle for `arena_bounds()` -> `CameraSubsystem.map_center`.
	for x in FAKE_MAP_TILES.x:
		for y in FAKE_MAP_TILES.y:
			total_map_tiles[Vector2i(x, y)] = true

	_playback = EffectsPlayback.new()
	_playback.enabled = true
	_playback.battle_manager = self
	_playback.content_root = CONTENT_ROOT
	add_child(_playback)

	if not "auto" in OS.get_cmdline_user_args():
		print("[AbilityVfx] interactive mode; pass `-- auto` to score.")
		return

	_run_mapping_arm()

	if not _playback.begin(camera):
		_fail("playback unavailable: " + _playback.unavailable_reason)
		_finish(false)
		return
	await _run_pixel_arm()


# --- ARM A: the mapping --------------------------------------------------------

## Does `effect_id_for` name the effect `Action.vfx_data` did? `vfx_name` was that key,
## and every resolved id must also exist on disk.
func _run_mapping_arm() -> void:
	var dir_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--actions="):
			dir_path = arg.substr("--actions=".length())
	if dir_path.is_empty():
		print("[AbilityVfx] ARM A MAPPING: SKIPPED — pass --actions=<dir of *.action.json>")
		return

	var dir := DirAccess.open(dir_path)
	if dir == null:
		_fail("ARM A: cannot open actions dir " + dir_path)
		return

	var drew := 0
	var routed := 0
	var missing_dir: Array[String] = []
	var disagreed: Array[String] = []
	var names := dir.get_files()
	for file_name: String in names:
		if not file_name.ends_with(".action.json"):
			continue
		var text := FileAccess.get_file_as_string(dir_path.path_join(file_name))
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = parsed
		var action := Action.new()
		action.unique_name = str(data.get("unique_name", file_name))
		action.vfx_name = str(data.get("vfx_name", ""))
		action.vfx_id = int(data.get("vfx_id", 0))

		# The `vfx_data` gate verbatim: set only when `vfx_name` was non-empty.
		var old_drew: bool = not action.vfx_name.is_empty()
		var effect_id: int = EffectsPlayback.effect_id_for(action)
		if old_drew:
			drew += 1
		if effect_id < 0:
			if old_drew:
				disagreed.append("%s: old drew %s, new route declines"
					% [action.unique_name, action.vfx_name])
			continue
		routed += 1
		# The `vfx_name` key's digits must name the effect that was picked.
		if old_drew:
			var expected: int = _digits_of(action.vfx_name)
			if expected != effect_id:
				disagreed.append("%s: old key %s, new id E%03d"
					% [action.unique_name, action.vfx_name, effect_id])
		if not DirAccess.dir_exists_absolute(
				ExMateriaEffects.EffectsContent.effect_dir("E%03d" % effect_id)):
			missing_dir.append("%s -> E%03d" % [action.unique_name, effect_id])

	print("[AbilityVfx] ARM A MAPPING: %d actions drew under the old path, %d route now"
		% [drew, routed])
	_check(not disagreed.is_empty() == false,
		"every routed ability keeps the effect the old path drew (%d disagreements)"
			% disagreed.size())
	for d: String in disagreed.slice(0, 10):
		print("    DISAGREEMENT: " + d)
	_check(missing_dir.is_empty(),
		"every routed ability has content on disk (%d missing)" % missing_dir.size())
	for m: String in missing_dir.slice(0, 10):
		print("    MISSING CONTENT: " + m)
	_check(routed > 100, "a real ability set routed, not a handful (%d)" % routed)


func _digits_of(text: String) -> int:
	var digits := ""
	for c: String in text:
		if c >= "0" and c <= "9":
			digits += c
	return digits.to_int() if not digits.is_empty() else -1


# --- ARM B: the pixels ---------------------------------------------------------

## Plays one real ability and proves it REACHED THE FRAMEBUFFER. CHANGED pixels, not bright
## ones — the clear is already past any threshold. `-- auto noplay` is the control.
func _run_pixel_arm() -> void:
	var action := Action.new()
	action.unique_name = PROBE_ACTION["unique_name"]
	action.vfx_name = PROBE_ACTION["vfx_name"]
	action.vfx_id = PROBE_ACTION["vfx_id"]
	_check(EffectsPlayback.effect_id_for(action) == PROBE_ACTION["vfx_id"],
		"probe ability \"%s\" routes to E%03d" % [action.unique_name, PROBE_ACTION["vfx_id"]])

	# The producer's first frames after `begin()` are not steady enough to baseline on.
	await _settle(SETTLE_SECONDS)
	var baseline := await _grab()
	var control: bool = "noplay" in OS.get_cmdline_user_args()
	if not control:
		# The exact call `Unit.use_ability` makes, target relative to the caster.
		_check(_playback.play_action_vfx_at(
				_caster, _caster.global_position + Vector3(0, 1.0, 0), action) != null,
			"play_action_vfx_at spawned a cast")

	# Sampled across the whole cast: a spell winds up ~100 frames and has decayed by 250.
	var peak := 0
	var peak_image: Image = null
	var elapsed: float = 0.0
	while elapsed < SAMPLE_SECONDS:
		await get_tree().process_frame
		elapsed += get_tree().root.get_process_delta_time()
		var current := await _grab()
		var changed := _changed_pixels(baseline, current)
		if _is_disturbance(changed):
			baseline = current
			continue
		if changed > peak:
			peak = changed
			peak_image = current

	print("[AbilityVfx] ARM B PIXELS%s peak_changed_px=%d" % [
		" (CONTROL, no cast)" if control else "", peak])
	var suffix: String = "-control" if control else ""
	if peak_image != null:
		peak_image.save_png("user://ability-vfx-regression%s.png" % suffix)
	else:
		baseline.save_png("user://ability-vfx-regression%s.png" % suffix)
	print("[AbilityVfx] screenshot user://ability-vfx-regression%s.png" % suffix)

	# Where, not just whether — everything above passes for a cast in the wrong place.
	if not control and peak_image != null:
		var centroid := _changed_centroid(baseline, peak_image)
		if centroid.x >= 0.0:
			var cam := get_viewport().get_camera_3d()
			var at_caster: Vector2 = cam.unproject_position(_caster.global_position)
			var at_origin: Vector2 = cam.unproject_position(Vector3.ZERO)
			var d_caster: float = centroid.distance_to(at_caster)
			var d_origin: float = centroid.distance_to(at_origin)
			print("[AbilityVfx] ARM B WHERE centroid=%s caster=%s origin=%s d_caster=%.1f d_origin=%.1f"
				% [str(centroid), str(at_caster), str(at_origin), d_caster, d_origin])
			_check(d_origin > d_caster * POSITION_MARGIN,
				"the cast drew ON THE CASTER, not at the world origin (%.1f vs %.1f px)"
					% [d_caster, d_origin])

	if control:
		_check(peak <= CONTROL_TOLERANCE_PX,
			"CONTROL drew nothing (%d changed px must be <= %d)"
				% [peak, CONTROL_TOLERANCE_PX])
	else:
		_check(peak > MIN_DREW_PX,
			"ability pixels reached the framebuffer (%d changed px must be > %d)"
				% [peak, MIN_DREW_PX])
	await _run_trap_arm(control)
	# Before D and E, which add a gradient and landmarks; this arm needs a flat clear.
	await _run_unit_tint_arm(control)
	await _run_background_arm(control)
	await _run_camera_arm(control)
	_finish(true)


# --- ARM C: the TRAP handlers ---------------------------------------------------

## `show_shared_vfx` has no renderer behind it but `play_shared_vfx`, so nothing else
## would report hit clouds missing.
func _run_trap_arm(control: bool) -> void:
	# Let the spell decay first, or its tail counts as the trap.
	await _settle(SAMPLE_SECONDS)
	var baseline := await _grab()
	if not control:
		_check(_playback.play_shared_vfx(
				TRAP_PROBE_HANDLER, TRAP_PROBE_ELEMENT,
				_caster.global_position + Vector3(0, 1.0, -2.0), _caster, true, true),
			"play_shared_vfx started handler %d" % TRAP_PROBE_HANDLER)
	var peak := 0
	var elapsed: float = 0.0
	while elapsed < TRAP_SAMPLE_SECONDS:
		await get_tree().process_frame
		elapsed += get_tree().root.get_process_delta_time()
		var current := await _grab()
		var changed := _changed_pixels(baseline, current)
		if _is_disturbance(changed):
			baseline = current
			continue
		peak = maxi(peak, changed)
	print("[AbilityVfx] ARM C TRAP%s peak_changed_px=%d" % [
		" (CONTROL, no cast)" if control else "", peak])
	if control:
		_check(peak <= CONTROL_TOLERANCE_PX,
			"CONTROL drew no trap (%d changed px must be <= %d)"
				% [peak, CONTROL_TOLERANCE_PX])
	else:
		_check(peak > MIN_DREW_PX,
			"trap pixels reached the framebuffer (%d changed px must be > %d)"
				% [peak, MIN_DREW_PX])


## True when a sample reflects the desktop, not the cast. Reported, since constant
## re-baselining means the reading cannot be trusted.
func _is_disturbance(changed: int) -> bool:
	if _sampled_total <= 0 or changed < int(_sampled_total * DISTURBANCE_FRACTION):
		return false
	print("[AbilityVfx] NOTE viewport disturbance (%d/%d px) — re-baselining, not scoring"
		% [changed, _sampled_total])
	return true


## Screen-space centroid of the pixels that changed, or (-1,-1) when none did.
func _changed_centroid(before: Image, after: Image) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for y in range(0, before.get_height(), 2):
		for x in range(0, before.get_width(), 2):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > PIXEL_EPSILON:
				sum += Vector2(x, y)
				n += 1
	return sum / float(n) if n > 0 else Vector2(-1.0, -1.0)


## Wall-clock wait — frame counts are not interchangeable here, see `SAMPLE_SECONDS`.
func _settle(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_tree().root.get_process_delta_time()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Pixels differing between two frames, every other row and column; the epsilon sits above
## renderer dither and below a drawn particle.
var _sampled_total: int = 0


func _changed_pixels(before: Image, after: Image) -> int:
	var count := 0
	_sampled_total = 0
	for y in range(0, before.get_height(), 2):
		for x in range(0, before.get_width(), 2):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			_sampled_total += 1
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > PIXEL_EPSILON:
				count += 1
	return count


# --- ARM F: the unit colour track -----------------------------------------------

## Proves the PALETTE track's CASTER and TARGET channels reach the unit sprites:
## `update_stack` returns early on an unknown surface, silently dropping every tint.
func _run_unit_tint_arm(control: bool) -> void:
	# Arm C's trap must finish decaying first.
	await _settle(TRAP_SAMPLE_SECONDS)

	var registry: Node = get_tree().root.get_node_or_null(^"/root/TintedSurfaces")
	if registry == null:
		_fail("ARM F: the TintedSurfaces autoload is absent — nothing can be registered")
		return

	var caster := _make_unit_probe("ProbeCaster", UNIT_CASTER_POS, true)
	var target := _make_unit_probe("ProbeTarget", UNIT_TARGET_POS, false)
	var bystander := _make_unit_probe("ProbeBystander", UNIT_BYSTANDER_POS, false)
	await _settle(SETTLE_SECONDS)

	_run_unit_registration(registry, caster, target, bystander)
	await _run_unit_fold(caster, target, bystander)
	await _run_unit_surface_masks(caster)
	await _run_unit_cast(control, registry, caster, target, bystander)
	await _run_unit_teardown(caster, target, bystander)

	for probe: Dictionary in [caster, target, bystander]:
		(probe["body"] as Node3D).queue_free()

	# GONE before arm D, not just done with the units: the same instance still drives the
	# SCREEN track, and arm D opens by asserting the background is at rest.
	var waited: float = 0.0
	while is_instance_valid(_unit_cast) and waited < UNIT_QUIET_TIMEOUT:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	if _unit_cast != null:
		_check(not is_instance_valid(_unit_cast),
			"F5 the cast freed itself within %.0fs (waited %.1fs), so the next arm "
				% [UNIT_QUIET_TIMEOUT, waited] + "measures a frame at rest")
	_unit_cast = null
	await get_tree().process_frame


## One probe "unit": a `Node3D` standing in for `char_body`. The bind precedes `add_child`
## deliberately — `Unit` binds from `_enter_tree`, so it arrives with both materials null.
func _make_unit_probe(probe_name: String, at: Vector3, with_sub_sprites: bool) -> Dictionary:
	var body := Node3D.new()
	body.name = probe_name
	add_child(body)
	body.global_position = at

	var sprites: UnitSpritesManager = UNIT_SPRITES_SCENE.instantiate()
	sprites.bind_tint_surface(body.get_instance_id())
	body.add_child(sprites)

	var texture := _index_texture()
	var palette := _index_palette(UNIT_BASE_COLOUR)
	sprites.set_primary_texture(texture)
	sprites.sprite_primary.material_override.set_shader_parameter("palette_colors", palette)

	if with_sub_sprites:
		sprites.set_weapon_texture(texture)
		sprites.sprite_weapon.material_override.set_shader_parameter("palette_colors", palette)
		sprites.sprite_weapon.position += UNIT_WEAPON_OFFSET
		# The per-unit duplicate: the scene's is a shared SubResource, and registering
		# that one ties every unit's effect sprite together.
		var effect_material: ShaderMaterial = sprites.sprite_effect.material_override.duplicate()
		effect_material.set_shader_parameter("sprite_texture", texture)
		effect_material.set_shader_parameter("palette_colors", palette)
		sprites.set_effect_material(effect_material)
		sprites.sprite_effect.texture = texture
		sprites.sprite_effect.position += UNIT_EFFECT_OFFSET
	else:
		sprites.sprite_weapon.visible = false
		sprites.sprite_effect.visible = false

	return {"body": body, "sprites": sprites, "token": body.get_instance_id()}


## Every texel is CLUT index 1, travelling in r/255 — the shaders read
## `round(tex.x * 255.0)`.
func _index_texture() -> ImageTexture:
	var image := Image.create_empty(UNIT_TEXTURE_PX, UNIT_TEXTURE_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0 / 255.0, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(image)


## 16 entries: index 0 transparent (discarded by the shaders), index 1 the probe colour.
func _index_palette(entry: Color) -> PackedColorArray:
	var palette := PackedColorArray()
	palette.resize(16)
	for i in 16:
		palette[i] = Color(0.0, 0.0, 0.0, 0.0)
	palette[1] = entry
	return palette


## F1. Registered, under the right id, with every material the unit paints with.
func _run_unit_registration(registry: Node, caster: Dictionary, target: Dictionary,
		bystander: Dictionary) -> void:
	for probe: Dictionary in [caster, target, bystander]:
		var sprites: UnitSpritesManager = probe["sprites"]
		var body: Node3D = probe["body"]
		_check(registry.is_surface_registered(probe["token"]),
			"F1 %s is a registered tint surface" % body.name)
		# Read back off the host, so a `Unit` id — which compiles and tints nothing — fails.
		_check(sprites.tint_surface_token() == body.get_instance_id(),
			"F1 %s's token IS its char_body's instance id (%d)"
				% [body.name, body.get_instance_id()])

	# The whole material set: a layer's mask covers all three sub-surfaces.
	var caster_materials: Array = registry._surface_materials.get(caster["token"], [])
	_check(caster_materials.size() == 3,
		"F1 all THREE of the caster's sprite materials are on the surface (body, "
		+ "weapon, effect — got %d)" % caster_materials.size())
	var plain_materials: Array = registry._surface_materials.get(target["token"], [])
	_check(plain_materials.size() == 2,
		"F1 a unit whose effect material has not been duplicated yet registers the two "
		+ "it has (got %d), rather than the scene's SHARED effect material"
			% plain_materials.size())

	# The bind ran with both materials null, so this passing means `_ready` completed it.
	var sprites_caster: UnitSpritesManager = caster["sprites"]
	_check(caster_materials.has(sprites_caster.sprite_primary.material_override),
		"F1 the body material registered even though the bind preceded its creation")
	_check(int(sprites_caster.sprite_primary.material_override.get_shader_parameter(
			"color_surface_id")) == UnitSpritesManager.SURFACE_BODY
		and int(sprites_caster.sprite_weapon.material_override.get_shader_parameter(
			"color_surface_id")) == UnitSpritesManager.SURFACE_WEAPON
		and int(sprites_caster.sprite_effect.material_override.get_shader_parameter(
			"color_surface_id")) == UnitSpritesManager.SURFACE_EFFECT,
		"F1 the three materials pass DISTINCT color_surface_ids (0/1/2), so a "
		+ "single-surface mask can mean the body alone")


## F2. A known layer moves its own unit's pixels in the named channel and no other's.
## No cast, so no particles.
func _run_unit_fold(caster: Dictionary, target: Dictionary, bystander: Dictionary) -> void:
	var before := await _grab()
	# Both halves: a probe off-frame samples nothing, and "did not move" passes on black.
	var clear_patch: Color = _mean_of(before, false)
	for probe: Dictionary in [caster, target, bystander]:
		var body_name: String = (probe["body"] as Node3D).name
		_check(_probe_visible(before, probe, Vector3.ZERO),
			"F2 %s projects inside the viewport" % body_name)
		var patch: Color = _unit_patch(before, probe, Vector3.ZERO)
		_check(_distance(patch, UNIT_BASE_COLOUR) < 0.1
				and _distance(patch, clear_patch) > 0.02,
			"F2 %s's sprite is what the patch is sampling (patch %s, CLUT entry %s, "
				% [body_name, patch, UNIT_BASE_COLOUR] + "clear %s)" % clear_patch)
	for offset: Vector3 in [UNIT_WEAPON_OFFSET, UNIT_EFFECT_OFFSET]:
		_check(_probe_visible(before, caster, offset),
			"F2 the caster's sub-sprite at %s projects inside the viewport" % _v3(offset))

	TintedSurfaces.update_layer(caster["token"], UNIT_TINT_OWNER, UNIT_CASTER_DELTA)
	TintedSurfaces.update_layer(target["token"], UNIT_TINT_OWNER, UNIT_TARGET_DELTA)
	await _settle(0.2)
	var after := await _grab()
	after.save_png("user://ability-vfx-unit-tint.png")
	print("[AbilityVfx] screenshot user://ability-vfx-unit-tint.png")

	# F6 scored here, the one clean frame: a disagreement can only be the shader.
	_check_fold_parity(after, caster, UnitSpritesManager.SURFACE_BODY, Vector3.ZERO,
		"a caster's own additive layer")
	_check_fold_parity(after, target, UnitSpritesManager.SURFACE_BODY, Vector3.ZERO,
		"a target's own additive layer")
	_check_fold_parity(after, bystander, UnitSpritesManager.SURFACE_BODY, Vector3.ZERO,
		"an untouched unit (the identity fold)")

	var caster_rise := _rise(_unit_patch(before, caster, Vector3.ZERO),
		_unit_patch(after, caster, Vector3.ZERO))
	var target_rise := _rise(_unit_patch(before, target, Vector3.ZERO),
		_unit_patch(after, target, Vector3.ZERO))
	var bystander_rise := _rise(_unit_patch(before, bystander, Vector3.ZERO),
		_unit_patch(after, bystander, Vector3.ZERO))
	print("[AbilityVfx] ARM F2 FOLD caster_rise=%s target_rise=%s bystander_rise=%s"
		% [_v3(caster_rise), _v3(target_rise), _v3(bystander_rise)])

	_check(caster_rise.x > UNIT_MIN_RISE
			and caster_rise.x > caster_rise.y + UNIT_MIN_RISE
			and caster_rise.x > caster_rise.z + UNIT_MIN_RISE,
		"F2 the CASTER's own layer reached its sprite, in RED (%s)" % _v3(caster_rise))
	_check(target_rise.z > UNIT_MIN_RISE
			and target_rise.z > target_rise.x + UNIT_MIN_RISE
			and target_rise.z > target_rise.y + UNIT_MIN_RISE,
		"F2 the TARGET's own layer reached its sprite, in BLUE (%s)" % _v3(target_rise))
	_check(absf(target_rise.x) < UNIT_TINT_TOLERANCE,
		"F2 the caster's RED did not leak onto the target (%.4f)" % target_rise.x)
	_check(absf(caster_rise.z) < UNIT_TINT_TOLERANCE,
		"F2 the target's BLUE did not leak onto the caster (%.4f)" % caster_rise.z)
	_check(bystander_rise.length() < UNIT_TINT_TOLERANCE,
		"F2 the UNPUSHED third unit did not move at all (%s)" % _v3(bystander_rise))

	TintedSurfaces.remove_layer(caster["token"], UNIT_TINT_OWNER)
	TintedSurfaces.remove_layer(target["token"], UNIT_TINT_OWNER)
	await _settle(0.2)
	var cleared := await _grab()
	var caster_residue := _rise(_unit_patch(before, caster, Vector3.ZERO),
		_unit_patch(cleared, caster, Vector3.ZERO))
	_check(caster_residue.length() < UNIT_TINT_TOLERANCE,
		"F2 withdrawing the layer put the sprite back (%s)" % _v3(caster_residue))


## F3. The three sub-surfaces address separately, which is why the host passes 0/1/2
## rather than 0 three times — with 0 everywhere `MASK_SURFACE0` lights all three.
func _run_unit_surface_masks(caster: Dictionary) -> void:
	var stack_script: Script = load(COLOR_STACK_PATH)
	if stack_script == null:
		_fail("ARM F3: cannot load " + COLOR_STACK_PATH)
		return
	var before := await _grab()

	for phase: Array in [["MASK_SURFACE0", stack_script.MASK_SURFACE0],
			["MASK_WHOLE", stack_script.MASK_WHOLE]]:
		var mask_name: String = phase[0]
		var mask: int = phase[1]
		# One settled affine layer: mode 0 `current + delta`, full 5-bit parameter in RED,
		# duration 0 snapping to full progress at frame 0.
		var stack: Variant = stack_script.new()
		stack.set_quantize(true)
		stack.push_op(0, 31, 0, 0, 0, 0, mask, 0)
		TintedSurfaces.update_stack(caster["token"], UNIT_MASK_OWNER, stack, 0)
		await _settle(0.2)
		var after := await _grab()

		var body_rise := _rise(_unit_patch(before, caster, Vector3.ZERO),
			_unit_patch(after, caster, Vector3.ZERO))
		var weapon_rise := _rise(_unit_patch(before, caster, UNIT_WEAPON_OFFSET),
			_unit_patch(after, caster, UNIT_WEAPON_OFFSET))
		var effect_rise := _rise(_unit_patch(before, caster, UNIT_EFFECT_OFFSET),
			_unit_patch(after, caster, UNIT_EFFECT_OFFSET))
		print("[AbilityVfx] ARM F3 SURFACES %s body=%s weapon=%s effect=%s"
			% [mask_name, _v3(body_rise), _v3(weapon_rise), _v3(effect_rise)])

		# The same parity question against a real ColorStack, on each surface id.
		_check_fold_parity(after, caster, UnitSpritesManager.SURFACE_BODY, Vector3.ZERO,
			"%s on the body" % mask_name)
		_check_fold_parity(after, caster, UnitSpritesManager.SURFACE_WEAPON,
			UNIT_WEAPON_OFFSET, "%s on the weapon" % mask_name)
		_check(body_rise.x > UNIT_MIN_RISE,
			"F3 %s lights the BODY (%.4f)" % [mask_name, body_rise.x])
		if mask == stack_script.MASK_SURFACE0:
			_check(weapon_rise.length() < UNIT_TINT_TOLERANCE
					and effect_rise.length() < UNIT_TINT_TOLERANCE,
				"F3 MASK_SURFACE0 lights the body ALONE — weapon %s, effect %s"
					% [_v3(weapon_rise), _v3(effect_rise)])
		else:
			_check(weapon_rise.x > UNIT_MIN_RISE and effect_rise.x > UNIT_MIN_RISE,
				"F3 MASK_WHOLE lights body, weapon AND effect (weapon %.4f, effect %.4f)"
					% [weapon_rise.x, effect_rise.x])

	TintedSurfaces.remove_layer(caster["token"], UNIT_MASK_OWNER)
	await _settle(0.2)


## F4/F5. A real cast's channels land on the real materials and the ROM's RESTORE runs
## first. Teardown also returns a unit to base, so only `restored_while_alive` proves it.
func _run_unit_cast(control: bool, registry: Node, caster: Dictionary,
		target: Dictionary, bystander: Dictionary) -> void:
	var caster_body: ShaderMaterial = _probe_material(caster, UnitSpritesManager.SURFACE_BODY)
	var target_body: ShaderMaterial = _probe_material(target, UnitSpritesManager.SURFACE_BODY)
	var bystander_body: ShaderMaterial = _probe_material(bystander, UnitSpritesManager.SURFACE_BODY)
	var base := Vector3(UNIT_BASE_COLOUR.r, UNIT_BASE_COLOUR.g, UNIT_BASE_COLOUR.b)

	var action := Action.new()
	action.unique_name = UNIT_TINT_ACTION["unique_name"]
	action.vfx_name = UNIT_TINT_ACTION["vfx_name"]
	action.vfx_id = UNIT_TINT_ACTION["vfx_id"]
	_check(EffectsPlayback.effect_id_for(action) == UNIT_TINT_ACTION["vfx_id"],
		"F4 the probe ability routes to E%03d" % UNIT_TINT_ACTION["vfx_id"])

	var baseline := await _grab()
	var base_caster: Color = _unit_patch(baseline, caster, Vector3.ZERO)
	var base_target: Color = _unit_patch(baseline, target, Vector3.ZERO)
	var base_bystander: Color = _unit_patch(baseline, bystander, Vector3.ZERO)
	if not control:
		# The exact call `ActionInstance.show_vfx` makes: `char_body`s, never `Unit`s.
		_unit_cast = _playback.play_action_vfx(caster["body"], target["body"], action)
		_check(_unit_cast != null,
			"F4 the cast spawned from the caster probe at the target probe")

	# `color_layer_count` on the unit's OWN material; 0 unless something was registered.
	var peak_caster_layers := 0
	var peak_target_layers := 0
	var peak_bystander_layers := 0
	var peak_caster_rise := Vector3.ZERO
	var peak_target_rise := Vector3.ZERO
	var peak_bystander_rise := Vector3.ZERO
	var peak_target_patch := Color.BLACK
	var budget_exceeded := 0
	var peak_effect_frame := 0
	var addon_owners: Dictionary = {}
	# Seconds off base, not peak: a layer holds for SECONDS, a particle for frames — and
	# E015's late flash washes the bystander white enough to fool a peak reading.
	var target_off_base: float = 0.0
	var bystander_off_base: float = 0.0
	var saw_tint := false
	var restored_at: float = -1.0
	var restored_while_alive := false
	var cast_freed_at: float = -1.0
	var elapsed: float = 0.0
	var deadline: float = UNIT_SAMPLE_SECONDS if control else UNIT_CAST_WATCH_SECONDS
	while elapsed < deadline:
		await get_tree().process_frame
		var dt: float = get_tree().root.get_process_delta_time()
		elapsed += dt
		peak_caster_layers = maxi(peak_caster_layers, _layer_count(caster_body))
		peak_target_layers = maxi(peak_target_layers, _layer_count(target_body))
		peak_bystander_layers = maxi(peak_bystander_layers, _layer_count(bystander_body))
		for token: int in [caster["token"], target["token"]]:
			for owner_id: int in registry._active_layers.get(token, {}).keys():
				addon_owners[owner_id] = true
		budget_exceeded = maxi(budget_exceeded,
			registry._active_layers.get(target["token"], {}).values().reduce(
				func(total: int, snap: Dictionary) -> int: return total + snap.rgb0.size(), 0))
		if is_instance_valid(_unit_cast):
			peak_effect_frame = maxi(peak_effect_frame, _unit_cast.get_effect_frame())
		elif not control and cast_freed_at < 0.0:
			cast_freed_at = elapsed

		# Off the CPU mirror: particles sit on the patch at exactly these frames.
		var folded: Vector3 = _fold_oracle(target, UnitSpritesManager.SURFACE_BODY)
		if (folded - base).length() > UNIT_TINT_TOLERANCE:
			saw_tint = true
		elif saw_tint and restored_at < 0.0:
			restored_at = elapsed
			restored_while_alive = is_instance_valid(_unit_cast)

		var now := await _grab()
		var caster_rise := _rise(base_caster, _unit_patch(now, caster, Vector3.ZERO))
		var target_patch: Color = _unit_patch(now, target, Vector3.ZERO)
		var target_rise := _rise(base_target, target_patch)
		var bystander_rise := _rise(base_bystander, _unit_patch(now, bystander, Vector3.ZERO))
		peak_caster_rise = _peak_rise(peak_caster_rise, caster_rise)
		peak_bystander_rise = _peak_rise(peak_bystander_rise, bystander_rise)
		if target_rise.length() > peak_target_rise.length():
			peak_target_rise = target_rise
			peak_target_patch = target_patch
		if target_rise.length() > UNIT_TINT_TOLERANCE:
			target_off_base += dt
		if bystander_rise.length() > UNIT_TINT_TOLERANCE:
			bystander_off_base += dt

		if not control and cast_freed_at >= 0.0 and elapsed > cast_freed_at + 0.5:
			break

	print("[AbilityVfx] ARM F4 CAST%s layers caster=%d target=%d bystander=%d "
		% [" (CONTROL, no cast)" if control else "",
			peak_caster_layers, peak_target_layers, peak_bystander_layers]
		+ "(the addon offered up to %d, capped at its own MAX_COLOR_LAYERS budget); "
			% budget_exceeded
		+ "rise caster=%s target=%s bystander=%s; peak target patch %s"
			% [_v3(peak_caster_rise), _v3(peak_target_rise), _v3(peak_bystander_rise),
				peak_target_patch])
	print("[AbilityVfx] ARM F5 LIFETIME peak_frame=%d restore_frame=%d restored@%.1fs "
		% [peak_effect_frame, _probe_restore_frame(), restored_at]
		+ "(cast %s) freed@%.1fs; off-base seconds target=%.1f bystander=%.1f"
			% ["ALIVE" if restored_while_alive else "already gone",
				cast_freed_at, target_off_base, bystander_off_base])

	if control:
		_check(peak_caster_layers == 0 and peak_target_layers == 0,
			"F4 CONTROL: with no cast, no colour layer ever reached a unit material "
			+ "(%d / %d)" % [peak_caster_layers, peak_target_layers])
		_check(peak_caster_rise.length() < UNIT_TINT_TOLERANCE
				and peak_target_rise.length() < UNIT_TINT_TOLERANCE,
			"F4 CONTROL: and no unit sprite moved (%s / %s)"
				% [_v3(peak_caster_rise), _v3(peak_target_rise)])
		return

	_check(peak_caster_layers > 0,
		"F4 the cast's CASTER colour stack reached the caster's material (%d layers)"
			% peak_caster_layers)
	_check(peak_target_layers > 0,
		"F4 the cast's TARGET colour stack reached the target's material (%d layers)"
			% peak_target_layers)
	_check(peak_bystander_layers == 0,
		"F4 and nothing reached the unit the cast never named (%d layers)"
			% peak_bystander_layers)
	_check(addon_owners.size() >= 1
			and not addon_owners.has(UNIT_TINT_OWNER) and not addon_owners.has(UNIT_MASK_OWNER),
		"F4 the layers are the ADDON's, not this arm's leftovers (owners %s)"
			% [addon_owners.keys()])
	_check(peak_caster_rise.length() > UNIT_MIN_RISE,
		"F4 and the CASTER's sprite pixels moved (%s)" % _v3(peak_caster_rise))
	_check(peak_target_rise.length() > UNIT_MIN_RISE,
		"F4 and the TARGET's sprite pixels moved (%s)" % _v3(peak_target_rise))
	# Where it landed: the wrong recipe, quantization or operand order also moves it.
	_check(peak_target_patch.r > 0.95 and peak_target_patch.g > 0.95
			and peak_target_patch.b > 0.95,
		"F4 and it landed where the ROM's own keyframes say — mode 4 `base + 31/31` "
		+ "saturates the CLUT entry to white (%s)" % peak_target_patch)
	_check(target_off_base > bystander_off_base * UNIT_SUSTAIN_RATIO,
		"F4 the TARGET held its colour for %.1fs while the untargeted unit beside it "
			% target_off_base + "was only brushed for %.1fs — sustained, so what moved "
			% bystander_off_base + "it was the colour track and not particles")

	# A wall-clock reap cuts the cast off mid-timeline, so the ROM's restore never runs.
	_check(peak_effect_frame >= _probe_restore_frame(),
		"F5 the cast ran to its palette RESTORE — effect frame %d of the %d "
			% [peak_effect_frame, _probe_restore_frame()]
		+ "`phase1_duration + phase2_delay + ramp` needs")
	_check(restored_while_alive,
		"F5 and the unit went back to its untinted CLUT entry WHILE THE CAST WAS STILL "
		+ "RUNNING (at %.1fs, cast freed at %.1fs) — the ROM's restore ran, rather than "
			% [restored_at, cast_freed_at]
		+ "teardown snapping the tint off")

	# F5a: nothing left behind once the cast goes.
	var waited: float = 0.0
	while waited < UNIT_QUIET_TIMEOUT:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
		if _layer_count(caster_body) == 0 and _layer_count(target_body) == 0:
			break
	_check(_layer_count(caster_body) == 0 and _layer_count(target_body) == 0,
		"F5 the cast took its colour layers back with it when it ended (after %.1fs)"
			% waited)
	await _settle(0.3)
	var after_cast := await _grab()
	var residue := _rise(_unit_patch(baseline, target, Vector3.ZERO),
		_unit_patch(after_cast, target, Vector3.ZERO))
	_check(residue.length() < UNIT_TINT_TOLERANCE,
		"F5 and the sprite is back to its untinted colour (%s)" % _v3(residue))


## The effect frame the probe's palette RESTORE finishes on, from the content's own
## `timeline.json`. The ramp constant is shared with `EffectsPlayback` — keep it that way.
func _probe_restore_frame() -> int:
	var path: String = EffectExtractPaths.EFFECTS_DIR.path_join(
		"E%03d" % int(UNIT_TINT_ACTION["vfx_id"])).path_join("timeline.json")
	if not FileAccess.file_exists(path):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("header"):
		return 0
	var header: Dictionary = parsed["header"]
	return (int(header.get("phase1_duration", 0)) + int(header.get("phase2_delay", 0))
		+ EffectsPlayback.PALETTE_RESTORE_RAMP_FRAMES)


## F5b. `unbind_tint_surface` must push an empty stack before dropping the surface, or a
## unit removed mid-cast keeps the last frame's tint baked in.
func _run_unit_teardown(caster: Dictionary, target: Dictionary, bystander: Dictionary) -> void:
	var sprites: UnitSpritesManager = target["sprites"]
	var material: ShaderMaterial = sprites.sprite_primary.material_override
	var before := await _grab()

	TintedSurfaces.update_layer(target["token"], UNIT_TINT_OWNER, UNIT_TARGET_DELTA)
	await _settle(0.2)
	var tinted := await _grab()
	_check(_rise(_unit_patch(before, target, Vector3.ZERO),
			_unit_patch(tinted, target, Vector3.ZERO)).z > UNIT_MIN_RISE,
		"F5 a layer is live on the unit about to be torn down")

	sprites.unbind_tint_surface()
	await _settle(0.2)
	var torn := await _grab()
	_check(not TintedSurfaces.is_surface_registered(target["token"]),
		"F5 unbinding drops the surface from the registry")
	_check(sprites.tint_surface_token() == 0,
		"F5 and the host stops claiming a token it no longer holds")
	_check(_layer_count(material) == 0,
		"F5 and the material's stack was CLEARED, not just orphaned (%d layers)"
			% _layer_count(material))
	var residue := _rise(_unit_patch(before, target, Vector3.ZERO),
		_unit_patch(torn, target, Vector3.ZERO))
	_check(residue.length() < UNIT_TINT_TOLERANCE,
		"F5 and the sprite went back to untinted (%s)" % _v3(residue))

	# Leave nothing behind for arms D and E.
	for probe: Dictionary in [caster, bystander]:
		TintedSurfaces.remove_layer(probe["token"], UNIT_TINT_OWNER)
		TintedSurfaces.remove_layer(probe["token"], UNIT_MASK_OWNER)
		(probe["sprites"] as UnitSpritesManager).unbind_tint_surface()


## Mean colour of a box on one sub-sprite's projected centre; `offset` selects it, zero =
## body.
func _unit_patch(image: Image, probe: Dictionary, offset: Vector3) -> Color:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Color.BLACK
	var at: Vector2 = camera.unproject_position((probe["body"] as Node3D).global_position + offset)
	var total := Vector3.ZERO
	var count := 0
	for y in range(int(at.y) - UNIT_PATCH_HALF_PX, int(at.y) + UNIT_PATCH_HALF_PX + 1):
		if y < 0 or y >= image.get_height():
			continue
		for x in range(int(at.x) - UNIT_PATCH_HALF_PX, int(at.x) + UNIT_PATCH_HALF_PX + 1):
			if x < 0 or x >= image.get_width():
				continue
			var c := image.get_pixel(x, y)
			total += Vector3(c.r, c.g, c.b)
			count += 1
	if count == 0:
		return Color.BLACK
	return Color(total.x / count, total.y / count, total.z / count)


## What the addon's CPU mirror says the current uniforms fold to. `color_apply` and
## `fold_packed` implement one specification twice, so this needs no expected value.
func _fold_oracle(probe: Dictionary, surface_id: int) -> Vector3:
	var stack_script: Script = load(COLOR_STACK_PATH)
	var material: ShaderMaterial = _probe_material(probe, surface_id)
	var base := Vector3(UNIT_BASE_COLOUR.r, UNIT_BASE_COLOUR.g, UNIT_BASE_COLOUR.b)
	if stack_script == null or material == null:
		return base
	var count: Variant = material.get_shader_parameter("color_layer_count")
	if count == null or int(count) == 0:
		return base
	var quantize: Variant = material.get_shader_parameter("quantize")
	return stack_script.fold_packed(
		Array(material.get_shader_parameter("color_layer_rgb0")),
		Array(material.get_shader_parameter("color_layer_rgb1")),
		Array(material.get_shader_parameter("color_layer_meta")),
		int(count), base, surface_id, quantize != null and bool(quantize))


## The material painting one of a probe's three colour sub-surfaces.
func _probe_material(probe: Dictionary, surface_id: int) -> ShaderMaterial:
	var sprites: UnitSpritesManager = probe["sprites"]
	match surface_id:
		UnitSpritesManager.SURFACE_WEAPON:
			return sprites.sprite_weapon.material_override as ShaderMaterial
		UnitSpritesManager.SURFACE_EFFECT:
			return sprites.sprite_effect.material_override as ShaderMaterial
		_:
			return sprites.sprite_primary.material_override as ShaderMaterial


## Score one sub-sprite's drawn pixels against the colour it should have come out.
func _check_fold_parity(image: Image, probe: Dictionary, surface_id: int,
		offset: Vector3, label: String) -> void:
	var measured_colour: Color = _unit_patch(image, probe, offset)
	var measured := Vector3(measured_colour.r, measured_colour.g, measured_colour.b)
	var expected: Vector3 = _fold_oracle(probe, surface_id)
	_check((expected - measured).length() < UNIT_FOLD_EPSILON,
		"F6 %s folds to what ColorStack.fold_packed says these exact uniforms mean "
			% label + "(shader %s vs oracle %s, %.4f apart)"
			% [_v3(measured), _v3(expected), (expected - measured).length()])


## SIGNED and per-channel: a scalar magnitude scores a wrong-channel tint as a pass.
func _rise(before: Color, after: Color) -> Vector3:
	return Vector3(after.r - before.r, after.g - before.g, after.b - before.b)


func _peak_rise(best: Vector3, candidate: Vector3) -> Vector3:
	return candidate if candidate.length() > best.length() else best


## Never `int(...)` directly: an unwritten material answers `null`, and `int(null)` is a
## runtime error that kills the arm without failing a check.
func _layer_count(material: ShaderMaterial) -> int:
	var value: Variant = material.get_shader_parameter("color_layer_count")
	return 0 if value == null else int(value)


## Whether the whole sampled patch lands inside the frame.
func _probe_visible(image: Image, probe: Dictionary, offset: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var world: Vector3 = (probe["body"] as Node3D).global_position + offset
	if camera.is_position_behind(world):
		return false
	var at: Vector2 = camera.unproject_position(world)
	var margin: float = float(UNIT_PATCH_HALF_PX) + 1.0
	return (at.x >= margin and at.y >= margin
		and at.x < float(image.get_width()) - margin
		and at.y < float(image.get_height()) - margin)


# --- ARM D: the background ------------------------------------------------------

## Proves the SCREEN track reaches the background. `_is_disturbance` would reject this arm's
## own signal, so it measures D1 the corner colours and D2 a patch of sky; D2 without D1 is
## interference, so both print.
func _run_background_arm(control: bool) -> void:
	# Only now: everything above is scored against a flat clear.
	_background.visible = true
	await _settle(SETTLE_SECONDS)

	var rest := _background.corners()
	_check(rest[0].is_equal_approx(BG_TOP) and rest[1].is_equal_approx(BG_TOP)
			and rest[2].is_equal_approx(BG_BOTTOM) and rest[3].is_equal_approx(BG_BOTTOM),
		"at rest the host's two map colours sit on the addon's four corners (%s)" % [rest])

	# The overlay's own lookup asks the ROOT viewport, which has no camera while the battle
	# is in the editor's SubViewport, so the material is handed over directly.
	var overlay: Node = get_tree().root.get_node_or_null(^"/root/ScreenEffectOverlay")
	_check(overlay != null and "_material" in overlay
			and overlay._material == _background.material_override,
		"the overlay is primed with the host quad's material, not a camera search")

	# `Gradient.colors[0]` is the BOTTOM, `[1]` the TOP; an inverted sky renders without
	# complaint, so it is checked against pixels.
	var sky := await _patch_mean(true)
	var ground := await _patch_mean(false)
	_check(_distance(sky, BG_TOP) < _distance(sky, BG_BOTTOM)
			and _distance(ground, BG_BOTTOM) < _distance(ground, BG_TOP),
		"the gradient is the right way up (sky %s vs top %s, ground %s vs bottom %s)"
			% [sky, BG_TOP, ground, BG_BOTTOM])

	var baseline := await _patch_mean(true)
	if not control:
		var cast_action := Action.new()
		cast_action.unique_name = PROBE_ACTION["unique_name"]
		cast_action.vfx_name = PROBE_ACTION["vfx_name"]
		cast_action.vfx_id = PROBE_ACTION["vfx_id"]
		_check(_playback.play_action_vfx_at(_caster, Vector3(0, 1.0, 0), cast_action) != null,
			"background arm spawned a cast")

	var peak_px: float = 0.0
	var peak_corner: float = 0.0
	var peak_image: Image = null
	var elapsed: float = 0.0
	while elapsed < SAMPLE_SECONDS:
		await get_tree().process_frame
		elapsed += get_tree().root.get_process_delta_time()
		var now := await _grab()
		var patch := _mean_of(now, true)
		var d_px := _distance(patch, baseline)
		if d_px > peak_px:
			peak_px = d_px
			peak_image = now
		var corners := _background.corners()
		for i in 4:
			var default_colour: Color = BG_TOP if i < 2 else BG_BOTTOM
			peak_corner = maxf(peak_corner, _distance(corners[i], default_colour))

	print("[AbilityVfx] ARM D BACKGROUND%s peak_d_rgb=%.4f peak_d_corner=%.4f"
		% [" (CONTROL, no cast)" if control else "", peak_px, peak_corner])
	var suffix: String = "-control" if control else ""
	if peak_image != null:
		peak_image.save_png("user://ability-vfx-background%s.png" % suffix)
		print("[AbilityVfx] screenshot user://ability-vfx-background%s.png" % suffix)

	if control:
		_check(peak_corner <= BG_CONTROL_TOLERANCE,
			"CONTROL never moved the gradient corners (%.4f <= %.4f)"
				% [peak_corner, BG_CONTROL_TOLERANCE])
		_check(peak_px <= BG_CONTROL_TOLERANCE,
			"CONTROL background patch is unchanged (%.4f <= %.4f)"
				% [peak_px, BG_CONTROL_TOLERANCE])
	else:
		_check(peak_corner > BG_MIN_DELTA,
			"D1 the cast drove the addon's gradient corners (%.4f > %.4f)"
				% [peak_corner, BG_MIN_DELTA])
		_check(peak_px > BG_MIN_DELTA,
			"D2 and it reached the framebuffer (%.4f > %.4f)" % [peak_px, BG_MIN_DELTA])


## Mean colour of a sky (top) or ground (bottom) band, every other row and column.
func _patch_mean(top: bool) -> Color:
	return _mean_of(await _grab(), top)


func _mean_of(image: Image, top: bool) -> Color:
	var height := image.get_height()
	var band := maxi(2, int(height * BG_PATCH_FRACTION))
	var first: int = 0 if top else height - band
	var total := Vector3.ZERO
	var count := 0
	for y in range(first, mini(first + band, height), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			total += Vector3(c.r, c.g, c.b)
			count += 1
	if count == 0:
		return Color.BLACK
	total /= float(count)
	return Color(total.x, total.y, total.z, 1.0)


## Largest per-channel difference. Max, not sum, so a threshold reads as "this channel
## moved by N% of full scale".
func _distance(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


# --- ARM E: the camera track ----------------------------------------------------

## Proves the addon's CAMERA track reaches TacticsG's camera rig. A `CameraSubsystem` runs
## for any effect with active camera keyframes, not just cinematics, and a host that never
## reads its output gets no error. Measures in arm D's pairs, for arm D's reason.
func _run_camera_arm(control: bool) -> void:
	_background.visible = false
	_run_camera_coverage()

	# The rig the game ships, not a bare Camera3D: its projection and its child
	# stand-off are two of the things under test.
	var rig: CameraController = CAMERA_RIG_SCENE.instantiate()
	add_child(rig)
	rig.global_position = Vector3.ZERO
	rig.camera.current = true
	var landmarks := _add_camera_landmarks()
	await _settle(SETTLE_SECONDS)

	# `CameraCalibration` speaks ORTHOGRAPHIC size (12.6 at zoom 4096), so the rig being
	# ortho decides the whole zoom mapping; nothing is forced or restored per cast.
	_check(rig.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"E0 the shipped rig is ORTHOGRAPHIC, so CameraCalibration's ortho size is "
		+ "the zoom mapping directly (projection=%d)" % rig.camera.projection)

	await _run_camera_chirality(rig)
	await _run_camera_pixels(rig)

	# Re-point the producer at the rig's camera and hand the rig over. Arms B-D ran on
	# the scene's own camera and are finished.
	if not _playback.begin(rig.camera):
		_fail("E camera arm: playback unavailable on the rig camera: "
			+ _playback.unavailable_reason)
		return
	_playback.camera_rig = rig

	var pre_position: Vector3 = rig.global_position
	var pre_rotation: Vector3 = rig.rotation_degrees
	var pre_zoom: float = rig.zoom
	var pre_size: float = rig.camera.size
	var pre_projection: int = rig.camera.projection
	var baseline := await _grab()

	if not control:
		var cast_action := Action.new()
		cast_action.unique_name = PROBE_ACTION["unique_name"]
		cast_action.vfx_name = PROBE_ACTION["vfx_name"]
		cast_action.vfx_id = PROBE_ACTION["vfx_id"]
		_check(_playback.play_action_vfx_at(
				_caster, _caster.global_position + Vector3(0, 1.0, 0), cast_action) != null,
			"camera arm spawned a cast")

	var track: EffectCameraTrack = _playback.camera_track()
	if not control:
		_check(track != null and track.takeovers == 1,
			"E2 the cast claimed the rig (takeovers=%d)"
				% [track.takeovers if track != null else -1])
		# `EFFECT_CTR` keyframes anchor on the map centre, which the spawn defaults to the
		# origin. The host alone knows the arena's size; this line carries it across.
		var expected_centre := Vector3(
			float(FAKE_MAP_TILES.x) * 14.0, 0.0, float(FAKE_MAP_TILES.y) * 14.0)
		_check(track != null and track._subsystem != null
				and track._subsystem.map_center.is_equal_approx(expected_centre),
			"E2 the host handed the subsystem the map centre for EFFECT_CTR (%s, expected %s)"
				% [_v3(track._subsystem.map_center) if track != null and track._subsystem != null
					else "<none>", _v3(expected_centre)])

	var drift: float = 0.0          # worst host-vs-converted-subsystem disagreement
	var stale: int = 0              # frames where the adapter read a stale subsystem
	var peak_focus: float = 0.0
	var peak_yaw: float = 0.0
	var peak_size: float = 0.0
	var peak_image: Image = null
	var samples: int = 0
	var logged: int = 0
	var elapsed: float = 0.0
	# No per-frame pixel scan: `_changed_pixels` costs ~78 ms a call, which would drop this
	# loop to watching a 30 Hz track at 13 Hz. The framebuffer claim is E4's.
	while elapsed < CAM_SAMPLE_SECONDS:
		await get_tree().process_frame
		elapsed += get_tree().root.get_process_delta_time()
		if track == null or not track.is_driving():
			continue
		samples += 1
		# E2a: THIS frame's subsystem values, not last frame's. `EffectCameraTrack` pumps
		# at priority 100, after the EffectInstance that advances the subsystem.
		var live: Vector3 = track._subsystem.current_position
		if not live.is_equal_approx(track.last_psx_position):
			stale += 1
		# E2b: and the camera carries exactly what the conversion produced.
		drift = maxf(drift, (rig.global_position - track.last_focus).length())
		drift = maxf(drift, (rig.rotation_degrees - track.last_orbit_degrees).length())
		drift = maxf(drift, absf(rig.camera.size - track.last_ortho_size))
		var focus_travel: float = (rig.global_position - pre_position).length()
		if focus_travel > peak_focus:
			peak_focus = focus_travel
			peak_image = await _grab()   # the frame at the far end of the pan
		peak_focus = maxf(peak_focus, focus_travel)
		# Wrapped to (-180, 180]: the seed adds a whole turn to keep the 45-degree snap
		# positive, and an unwrapped reading reports that no-op as a 360-degree spin.
		peak_yaw = maxf(peak_yaw,
			absf(fposmod(rig.rotation_degrees.y - pre_rotation.y + 180.0, 360.0) - 180.0))
		peak_size = maxf(peak_size, absf(rig.camera.size - pre_size))
		if logged < 6:
			logged += 1
			# Subsystem values beside host values: "no errors in the log" is not
			# evidence, two columns that track each other is.
			print(("[AbilityVfx]   E2 f%-3d SUBSYS pos=%s ang=%s zoom=%.0f"
				+ "  ->  HOST pos=%s rot=%s size=%.3f")
				% [samples, _v3(track.last_psx_position), _v3(track.last_psx_angles),
					track.last_psx_zoom, _v3(rig.global_position),
					_v3(rig.rotation_degrees), rig.camera.size])

	# How many times this loop CAUGHT the track driving, not how many effect frames ran:
	# render rate against a fixed 30 Hz clock. It bounds the evidence, not the effect.
	print(("[AbilityVfx] ARM E CAMERA%s samples_driving=%d drift=%.6f stale=%d "
		+ "peak_focus=%.3f peak_yaw=%.2f peak_size=%.3f")
		% [" (CONTROL, no cast)" if control else "", samples, drift, stale,
			peak_focus, peak_yaw, peak_size])
	var suffix: String = "-control" if control else ""
	if peak_image != null:
		peak_image.save_png("user://ability-vfx-camera%s.png" % suffix)
		print("[AbilityVfx] screenshot user://ability-vfx-camera%s.png" % suffix)

	if control:
		_check(track == null or track.takeovers == 0,
			"CONTROL nothing claimed the camera (takeovers=%d)"
				% [track.takeovers if track != null else 0])
		_check(rig.global_position.is_equal_approx(pre_position)
				and rig.rotation_degrees.is_equal_approx(pre_rotation)
				and absf(rig.camera.size - pre_size) <= CAM_CONTROL_TOLERANCE,
			"CONTROL the rig never moved (pos %s rot %s size %.3f)"
				% [_v3(rig.global_position), _v3(rig.rotation_degrees), rig.camera.size])
		var drifted := _changed_pixels(baseline, await _grab())
		_check(drifted <= CONTROL_TOLERANCE_PX,
			"CONTROL the frame is unchanged (%d <= %d px)"
				% [drifted, CONTROL_TOLERANCE_PX])
		_free_all(landmarks)
		rig.queue_free()
		return

	_check(samples > 0, "E2 the track drove the rig at all (%d samples)" % samples)
	_check(stale == 0,
		"E2 every applied pose came from the LIVE subsystem, not a frame behind "
		+ "(%d stale of %d)" % [stale, samples])
	_check(drift <= CAM_TRACK_EPSILON,
		"E2 the rig carries exactly the converted subsystem pose (worst drift %.6f <= %.6f)"
			% [drift, CAM_TRACK_EPSILON])
	_check(peak_focus > CAM_MIN_FOCUS_MOVE,
		"E3 a real cast moved the camera (%.3f > %.3f units of focus travel)"
			% [peak_focus, CAM_MIN_FOCUS_MOVE])

	# E5. The cast frees itself when the spell ends and `camera_finished` fires from its
	# `_exit_tree`; the camera must come back WITHOUT this test asking for it.
	var waited: float = 0.0
	while waited < CAM_RELEASE_TIMEOUT and track != null and track.is_driving():
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	_check(track == null or not track.is_driving(),
		"E5 the cast handed the camera back on its own within %.0fs (waited %.1fs)"
			% [CAM_RELEASE_TIMEOUT, waited])
	if track != null and track.is_driving():
		track.release()   # so the restore assertions below still mean something
	_check(not rig.is_effect_driven(), "E5 the rig is no longer in a driven state")
	print("[AbilityVfx]   E5 pre=%s/%s/%.3f  post=%s/%s/%.3f"
		% [_v3(pre_position), _v3(pre_rotation), pre_size,
			_v3(rig.global_position), _v3(rig.rotation_degrees), rig.camera.size])
	_check((rig.global_position - pre_position).length() <= CAM_RESTORE_EPSILON
			and (rig.rotation_degrees - pre_rotation).length() <= CAM_RESTORE_EPSILON
			and absf(rig.zoom - pre_zoom) <= CAM_RESTORE_EPSILON
			and absf(rig.camera.size - pre_size) <= CAM_RESTORE_EPSILON
			and rig.camera.projection == pre_projection,
		"E5 the rig is back at its exact pre-cast state")

	await _run_camera_yaw_arm(rig)
	_free_all(landmarks)
	rig.queue_free()


## E0. All 401 `camera.json` files carry 59 fixed slots per table, so "every effect has a
## camera track" says nothing. The gate is `has_active_keyframes()`.
func _run_camera_coverage() -> void:
	var camera_data_script: Script = load(CAMERA_DATA_PATH)
	if camera_data_script == null:
		_fail("E0: cannot load " + CAMERA_DATA_PATH)
		return
	var dir := DirAccess.open(EffectExtractPaths.EFFECTS_DIR)
	if dir == null:
		print("[AbilityVfx] ARM E0 COVERAGE: SKIPPED — no content at "
			+ EffectExtractPaths.EFFECTS_DIR)
		return
	var total := 0
	var active := 0
	var rolled: Array[String] = []
	var inactive: Array[String] = []
	for effect_name: String in dir.get_directories():
		var path: String = EffectExtractPaths.EFFECTS_DIR.path_join(effect_name).path_join(
			"camera.json")
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		total += 1
		var data: Variant = camera_data_script.from_json(parsed)
		if not data.has_active_keyframes():
			inactive.append(effect_name)
			continue
		active += 1
		# ROLL, the one channel this host drops — the rig has no roll axis. A whole turn is
		# the identity, so E242's single 4096 component is not a roll.
		for table_name: String in ["phase1", "for_each", "phase2"]:
			var table: Variant = data.get_table(table_name)
			if table == null or table.max_keyframe <= 0:
				continue
			for i in range(table.max_keyframe + 1):
				var kf: Variant = table.get_keyframe(i)
				if kf == null or (kf.channel_mask & 1) == 0:
					continue
				if absf(fposmod(float(kf.angle.z) + 2048.0, 4096.0) - 2048.0) > 1.0:
					if not rolled.has(effect_name):
						rolled.append(effect_name)
	print("[AbilityVfx] ARM E0 COVERAGE %d/%d effects pass has_active_keyframes(); "
		% [active, total] + "%d carry a real ROLL %s; inactive: %s"
		% [rolled.size(), str(rolled), str(inactive)])
	_check(total > 0 and active > 0,
		"E0 the installed corpus has camera tracks to drive (%d of %d)" % [active, total])
	# Not an academic entry: fifteen physical abilities (Attack, the Breaks, the Aims,
	# Throw Stone, Accumulate, Seal Evil) resolve to E000.
	_check(inactive.has("E000"),
		"E0 E000 — the effect every physical attack resolves to — has NO camera track, "
		+ "so a plain Attack must not move the camera")


## E1. Which way does a PSX yaw turn? At pitch 0 and PSX yaw 1024 (= 90 degrees) the rig
## looks down world -X, putting world +Z on its LEFT; the wrong direction puts it on the
## right with no complaint from the engine. Driven through `apply_pose`, no cast.
func _run_camera_chirality(rig: CameraController) -> void:
	var track := EffectCameraTrack.new(rig)
	add_child(track)
	_check(rig.begin_effect_takeover(), "E1 the rig accepts a takeover")
	track.apply_pose(Vector3.ZERO, Vector3(0.0, CAM_PROBE_YAW, 0.0), 4096.0)
	await get_tree().process_frame

	var forward: Vector3 = (rig.camera.global_transform.basis * Vector3(0, 0, -1)).normalized()
	_check(forward.is_equal_approx(Vector3(-1, 0, 0)),
		"E1 PSX yaw %.0f looks down world -X (forward %s)" % [CAM_PROBE_YAW, _v3(forward)])

	# Ask the addon itself where that pose looks, as an independent answer: if this side
	# applied it to the wrong node, in the wrong units, or with the wrong euler order,
	# the two disagree.
	var resolver_script: Script = load(FACING_RESOLVER_PATH)
	if resolver_script != null:
		var resolver: Variant = resolver_script.new(rig, Callable())
		var addon_forward: Vector3 = resolver._view_forward(0.0, CAM_PROBE_YAW)
		_check(forward.is_equal_approx(addon_forward),
			"E1 the host rig points exactly where the ADDON's own CinematicFacingResolver "
			+ "says that pose looks (%s vs %s)" % [_v3(forward), _v3(addon_forward)])

	# The same claim in screen space, which is what a wrong-way yaw looks like: a
	# landmark at world +Z must land LEFT of centre.
	var marker := Node3D.new()
	add_child(marker)
	marker.global_position = Vector3(0, 0, 1)
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	_check(cam == rig.camera, "E1 the rig's camera is the one rendering")
	var at_marker: Vector2 = rig.camera.unproject_position(marker.global_position)
	var centre: Vector2 = Vector2(get_viewport().get_visible_rect().size) * 0.5
	_check(at_marker.x < centre.x,
		"E1 world +Z lands LEFT of centre at PSX yaw %.0f (x %.1f < %.1f) — the yaw "
			% [CAM_PROBE_YAW, at_marker.x, centre.x] + "turns the way the ROM means")

	# The inverse conversions must return the pose the forward ones produced; a mismatched
	# pair drifts further from the player's camera on every cast.
	var psx_back := Vector3(
		ExMateriaPlatform.PsxMagnitude.deg_to_angle(-rig.rotation_degrees.x),
		ExMateriaPlatform.PsxMagnitude.deg_to_angle(rig.rotation_degrees.y),
		0.0)
	_check(is_equal_approx(fposmod(psx_back.y, 4096.0), fposmod(CAM_PROBE_YAW, 4096.0))
			and absf(psx_back.x) < 0.001,
		"E1 the inverse conversion round-trips the pose (%s -> %s)"
			% [_v3(Vector3(0.0, CAM_PROBE_YAW, 0.0)), _v3(psx_back)])
	_check(is_equal_approx(
			ExMateriaPlatform.CameraCalibration.ortho_size_to_zoom(rig.camera.size), 4096.0),
		"E1 zoom round-trips through CameraCalibration (size %.4f)" % rig.camera.size)

	rig.end_effect_takeover()
	marker.queue_free()
	track.queue_free()


## E6. The ABSOLUTE-yaw path through a real cast: a ROM keyframe naming an absolute PSX yaw
## must arrive as its exact degree equivalent, the short way. A wrong turn is silent.
func _run_camera_yaw_arm(rig: CameraController) -> void:
	var dir: String = ExMateriaEffects.EffectsContent.effect_dir(
		"E%03d" % CAM_YAW_PROBE["vfx_id"])
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		print("[AbilityVfx] ARM E6 YAW: SKIPPED — no content at " + dir)
		return
	await _await_quiet_frame()
	var pre_rotation: Vector3 = rig.rotation_degrees
	var pre_position: Vector3 = rig.global_position
	var action := Action.new()
	action.unique_name = CAM_YAW_PROBE["unique_name"]
	action.vfx_name = CAM_YAW_PROBE["vfx_name"]
	action.vfx_id = CAM_YAW_PROBE["vfx_id"]
	_check(_playback.play_action_vfx_at(
			_caster, _caster.global_position + Vector3(0, 1.0, 0), action) != null,
		"E6 the yaw probe spawned a cast")
	var track: EffectCameraTrack = _playback.camera_track()

	var extreme: float = 0.0      # signed, largest-magnitude wrapped yaw delta seen
	var best_landing: float = 999.0
	var subsystem_yaw_at_landing: float = 0.0
	var elapsed: float = 0.0
	while elapsed < CAM_YAW_SAMPLE_SECONDS:
		await get_tree().process_frame
		elapsed += get_tree().root.get_process_delta_time()
		if track == null or not track.is_driving():
			continue
		var delta: float = fposmod(
			rig.rotation_degrees.y - pre_rotation.y + 180.0, 360.0) - 180.0
		if absf(delta) > absf(extreme):
			extreme = delta
		# Where the host yaw sits against the keyframe's absolute PSX yaw, in degrees.
		var landing: float = absf(fposmod(
			rig.rotation_degrees.y
			- ExMateriaPlatform.PsxMagnitude.angle_to_deg(CAM_YAW_TARGET_PSX)
			+ 180.0, 360.0) - 180.0)
		if landing < best_landing:
			best_landing = landing
			subsystem_yaw_at_landing = track.last_psx_angles.y

	print(("[AbilityVfx] ARM E6 YAW extreme_delta=%+.2f deg (expected %+.2f) "
		+ "closest_to_PSX_%.0f=%.3f deg  subsystem_yaw_there=%.1f")
		% [extreme, CAM_YAW_EXPECTED_DELTA, CAM_YAW_TARGET_PSX, best_landing,
			subsystem_yaw_at_landing])
	_check(absf(extreme - CAM_YAW_EXPECTED_DELTA) <= CAM_YAW_EPSILON,
		"E6 a real DIRECT yaw keyframe turned the host rig %+.2f deg, the short way, "
			% extreme + "as the ROM's %.0f asks (expected %+.2f +/- %.1f)"
			% [CAM_YAW_TARGET_PSX, CAM_YAW_EXPECTED_DELTA, CAM_YAW_EPSILON])
	_check(best_landing <= CAM_YAW_EPSILON,
		"E6 and it landed on the degree equivalent of PSX %.0f (%.3f deg off, <= %.1f) "
			% [CAM_YAW_TARGET_PSX, best_landing, CAM_YAW_EPSILON]
		+ "— the yaw is consumed RAW, not negated")
	_check(is_equal_approx(fposmod(subsystem_yaw_at_landing, 4096.0),
			fposmod(CAM_YAW_TARGET_PSX, 4096.0)),
		"E6 and the SUBSYSTEM said so too (%.1f PSX) — the host did not arrive there "
			% subsystem_yaw_at_landing + "on its own")

	var waited: float = 0.0
	while waited < CAM_RELEASE_TIMEOUT and track != null and track.is_driving():
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
	if track != null and track.is_driving():
		track.release()
	_check((rig.rotation_degrees - pre_rotation).length() <= CAM_RESTORE_EPSILON
			and (rig.global_position - pre_position).length() <= CAM_RESTORE_EPSILON,
		"E6 and the turn was given back (rot %s -> %s)"
			% [_v3(pre_rotation), _v3(rig.rotation_degrees)])


## E4. The camera against the FRAMEBUFFER, no cast — a live spell repaints the frame
## whether or not the camera moved. No `_is_disturbance` either (see arm D); the arm is its
## own control, since a disturbance does not undo itself on `end_effect_takeover()`.
func _run_camera_pixels(rig: CameraController) -> void:
	var track := EffectCameraTrack.new(rig)
	add_child(track)
	# Against a quiescent frame: baseline during a decaying cast puts particle churn into
	# BOTH readings, and even the release that should read zero reads tens of thousands.
	var quiet_seconds := await _await_quiet_frame()
	var baseline := await _grab()
	_check(quiet_seconds >= 0.0,
		"E4 the frame went quiet before measuring (settled in %.1fs)" % quiet_seconds)
	_check(rig.begin_effect_takeover(), "E4 the rig accepts the pixel-arm takeover")
	# Same pose the rig already holds, shifted two tiles: only the camera can have
	# repainted anything.
	track.apply_pose(CAM_PIXEL_OFFSET_PSX,
		Vector3(ExMateriaPlatform.PsxMagnitude.deg_to_angle(-rig.rotation_degrees.x),
			0.0, 0.0),
		ExMateriaPlatform.CameraCalibration.ortho_size_to_zoom(rig.camera.size))
	await get_tree().process_frame
	var moved_image := await _grab()
	var moved := _changed_pixels(baseline, moved_image)
	moved_image.save_png("user://ability-vfx-camera-moved.png")
	track.release()
	await get_tree().process_frame
	var returned := _changed_pixels(baseline, await _grab())
	print("[AbilityVfx] ARM E4 PIXELS moved=%d/%d px returned=%d px"
		% [moved, _sampled_total, returned])
	print("[AbilityVfx] screenshot user://ability-vfx-camera-moved.png")
	_check(moved > CAM_MIN_MOVED_PX,
		"E4 driving the rig repainted the frame (%d changed px must be > %d)"
			% [moved, CAM_MIN_MOVED_PX])
	_check(returned <= CAM_RETURN_TOLERANCE_PX,
		"E4 releasing it put the frame back (%d changed px must be <= %d) — which a "
			% [returned, CAM_RETURN_TOLERANCE_PX]
		+ "desktop disturbance would not do")
	track.queue_free()


## Block until two consecutive frames match within the return tolerance. Returns seconds
## waited, or -1.0 if it never settled.
func _await_quiet_frame() -> float:
	var waited: float = 0.0
	var previous := await _grab()
	while waited < CAM_QUIET_TIMEOUT:
		await get_tree().process_frame
		waited += get_tree().root.get_process_delta_time()
		var current := await _grab()
		if _changed_pixels(previous, current) <= CAM_RETURN_TOLERANCE_PX:
			return waited
		previous = current
	return -1.0


## Something for a camera move to move. See `CAM_LANDMARKS`.
func _add_camera_landmarks() -> Array[Node3D]:
	var mesh := BoxMesh.new()
	mesh.size = CAM_LANDMARK_SIZE
	var made: Array[Node3D] = []
	for i in CAM_LANDMARKS.size():
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Distinct per landmark, so a MIRRORED view is not pixel-identical to a correct one
		# — a change count over a symmetric arrangement could not tell them apart.
		material.albedo_color = Color.from_hsv(float(i) / float(CAM_LANDMARKS.size()), 0.85, 0.95)
		var box := MeshInstance3D.new()
		box.mesh = mesh
		box.material_override = material
		add_child(box)
		box.global_position = CAM_LANDMARKS[i]
		made.append(box)
	return made


func _free_all(nodes: Array[Node3D]) -> void:
	for node: Node3D in nodes:
		if is_instance_valid(node):
			node.queue_free()


func _v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


# --- scoring -------------------------------------------------------------------

func _check(passed: bool, description: String) -> void:
	_checks += 1
	print("[AbilityVfx] %s %s" % ["PASS" if passed else "FAIL", description])
	if not passed:
		_failures.append(description)


func _fail(reason: String) -> void:
	_checks += 1
	print("[AbilityVfx] FAIL " + reason)
	_failures.append(reason)


func _finish(_ran: bool) -> void:
	print("[AbilityVfx] %d checks, %d failed" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("[AbilityVfx] RESULT PASS")
	else:
		print("[AbilityVfx] RESULT FAIL")
		for f: String in _failures:
			push_error("AbilityVfx: " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)
