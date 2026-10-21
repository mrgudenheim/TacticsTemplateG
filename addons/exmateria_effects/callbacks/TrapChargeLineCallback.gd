extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## TRAP handler 4's spell charge lines (0x801b1c04) as an E### callback (ADR-0369): a
## screen-space overlay of 1-px additive gouraud LINE_G2s, ticked at 60 Hz. The maths is
## ChargeLineModel's — the ROM's own integers — and this node only drives it and draws it
## (SPELL_CHARGE_LINES.md, branch research/spell-charge-lines [S·D]):
##
##   * init (tick 1): the caster's head (the anchor raised by param_AE) is FROZEN, and
##     projected onto the screen ONCE, at the first draw — the lines never follow the unit
##     or the camera afterwards (§3, §4). SFX 0x1F starts. No line spawns on tick 1.
##   * every tick while the span is open: at most one spawn (50%, cap 10) on a 256-px
##     SCREEN circle, the angle accumulator starting at 0 (§5, §6).
##   * CLEANUP (the manager sets it two frames before the span ends; EffectInstance.release
##     sets it for a held charge) is the loader's phase 3: spawning stops and every line
##     runs out its own life. The callback stays active until the LAST line dies, then
##     stops SFX 0x1F — `is_active()` false is the "charge finished" the hand-off waits on.
##
## Two handler ticks per timeline frame (EffectTimeline.SECONDARY_TICKS_PER_FRAME): the
## engine ticks this handler every vsync, the E### timeline every other.
##
## The sparkles that ride with the lines (group 12) are an ordinary lifted emitter on their
## own timeline channel, not part of this callback.
##
## Emitter parameter block (CallbackSchemaRegistry "trap_charge_lines"):
##   callback_params.param_A8  ring radius, PSX SCREEN pixels  (256, params row 0)
##   callback_params.param_AA  line contraction time, ticks    (32)
##   callback_params.param_AC  max concurrent lines            (10)
##   callback_params.param_AE  convergence height, PSX units   (sprite height + 8; live 44)
##   color_curves r/g/b        line colour (the element RGB table at 0x801b84C0)
## Vault: [[Spell Charge Lines System]]
## Vault: [[Unit Sprite Height Table]]

const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const SfxRouterPort = ExMateriaPlatform.SfxRouterPort
const ChargeLineModel = preload("res://addons/exmateria_effects/callbacks/ChargeLineModel.gd")
const ChargeLineOverlay = preload("res://addons/exmateria_effects/callbacks/ChargeLineOverlay.gd")
const EffectTimeline = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")

## "Magic Charging": `SuzukiPlaySoundFindChannel(0x1f)` on init, stopped on the last tick.
const SFX_ID := 0x1F
const DEFAULT_RADIUS := ChargeLineModel.RADIUS
const DEFAULT_LINE_LIFE := ChargeLineModel.DURATION
const DEFAULT_MAX_LINES := ChargeLineModel.MAX_TRAILS
## `spritesheet_height(caster) + 8` — 44 for the captured Black Mage (§3).
const DEFAULT_HEIGHT := 44
## Above the 3D scene, under a HUD on layer >= 0.
const OVERLAY_LAYER := -1

var model = ChargeLineModel.new()
## [handler tick, "on" | "off", sfx id] — what this charge asked the sound router for.
var sfx_log: Array = []
var _started := false
## The caster's head, effect-local, frozen at init.
var _head_local := Vector3.ZERO
var _centre_projected := false
var _layer: CanvasLayer = null
var _overlay: Node2D = null
var _sfx_handle := 0
## The camera the one-time projection goes through; null = the viewport's live camera. A
## host whose rig can be mid-move at init (the Studio's Stop hand-back) hands the pose the
## rig is settling in, so the frozen centre is the one the charge would get at rest.
var projection_camera: Camera3D = null


func _param(key: String, fallback: int) -> int:
	if emitter_config == null:
		return fallback
	return int(emitter_config.callback_params.get(key, fallback))


func _rand() -> int:
	return (rng.randi() if rng != null else randi()) & 0x7FFF


func _on_init(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	_sfx_off()
	_frame_counter = 0
	model = ChargeLineModel.new()
	model.start(_line_rgb(), _param("param_A8", DEFAULT_RADIUS), _param("param_AA", DEFAULT_LINE_LIFE),
		_param("param_AC", DEFAULT_MAX_LINES))
	_head_local = anchor_target + Vector3(0.0,
		PsxMagnitude.tile_to_game(float(_param("param_AE", DEFAULT_HEIGHT))), 0.0)
	_centre_projected = false
	_started = true
	_sfx_on()
	state = State.ANIMATE


func cleanup() -> void:
	# Phase 3: stop spawning, let the living lines finish.
	model.finalize()
	state = State.CLEANUP


func force_cleanup() -> void:
	_sfx_off()
	_started = false
	model = ChargeLineModel.new()
	_centre_projected = false
	if _overlay != null:
		_overlay.prims = []
		_overlay.queue_redraw()
	state = State.INACTIVE


func is_active() -> bool:
	return _started and not model.is_done()


func active_line_count() -> int:
	return model.count()


## The caster's head the lines converge on, effect-local, frozen at init.
func frozen_point() -> Vector3:
	return _head_local


## The centre on screen once projected, else null.
func screen_centre() -> Variant:
	return _overlay.centre if _centre_projected and _overlay != null else null


func physics_step() -> void:
	for _i in range(EffectTimeline.SECONDARY_TICKS_PER_FRAME):
		if model.is_done():
			break
		model.step(_rand)
		if model.is_done():
			_sfx_off()
	_frame_counter += 1


func update_render() -> void:
	if not _started or model.is_done():
		_show(false)
		return
	_ensure_overlay()
	if not _centre_projected:
		var cam := projection_camera if is_instance_valid(projection_camera) \
			else (get_viewport().get_camera_3d() if is_inside_tree() else null)
		var head := global_transform * _head_local
		if cam == null or cam.is_position_behind(head):
			_show(false)
			return
		_overlay.centre = cam.unproject_position(head)
		_overlay.psx_px = ChargeLineOverlay.psx_pixel_size(get_viewport().get_visible_rect().size.y)
		_centre_projected = true
	_overlay.prims = model.prims()
	_show(is_visible_in_tree())
	_overlay.queue_redraw()


func _exit_tree() -> void:
	_sfx_off()


func _ensure_overlay() -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = OVERLAY_LAYER
	_overlay = ChargeLineOverlay.new()
	_layer.add_child(_overlay)
	add_child(_layer)


func _show(on: bool) -> void:
	if _layer != null:
		_layer.visible = on


func _sfx_on() -> void:
	sfx_log.append([model.ticks, "on", SFX_ID])
	_sfx_handle = SfxRouterPort.play_system_held(SFX_ID)


func _sfx_off() -> void:
	if not _started:
		return
	if sfx_log.is_empty() or sfx_log.back()[1] != "off":
		sfx_log.append([model.ticks, "off", SFX_ID])
	SfxRouterPort.stop_held(_sfx_handle)
	_sfx_handle = 0


## The line colour as the handler's u8 RGB (the emitter's colour curves: the element RGB).
func _line_rgb() -> PackedInt32Array:
	var c := _sample_colors()
	return PackedInt32Array([roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)])
