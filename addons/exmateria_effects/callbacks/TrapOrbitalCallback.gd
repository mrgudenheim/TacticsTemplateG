extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## TRAP handler 22's summon charge orbs (0x801b4234) as an E### callback (ADR-0369). Three
## rings of 10 sprites circle a centre FROZEN at init — the caster raised by param_A8 — at
## 120°: each ring's head is bright and its 9 trail slots replay its last positions,
## dimmer with age. The maths is ChargeOrbModel's — the ROM's own integers — ticked at
## 60 Hz, two handler ticks per timeline frame (EffectTimeline.SECONDARY_TICKS_PER_FRAME)
## (SUMMON_CHARGE_ORBS.md, branch research/spell-charge-lines [S·D]):
##
##   * init (tick 1): the centre is frozen, SFX 0x21 starts, 30 sprites are acquired.
##   * while the span is open: the ramp (radius, spin, brightness grow) then the orbit.
##   * CLEANUP (two frames before the span ends, or EffectInstance.release): the fixed
##     61-tick finale — a 240 flare that fades 4 a tick, spin +1 a tick, radius growing —
##     after which all 30 sprites are freed together and SFX 0x21 stops. `is_active()`
##     false is the "charge finished" the summon's hand-off waits on.
##
## Unlike every mesh callback this one draws SPRITES: it drives particles it acquired
## from the cast's ParticleSubsystem (EffectCallback.particle_host), setting each one's
## position and `color_scale` every physics step. They render through the ordinary
## sprite path with this emitter's animation and frameset group (its CLUT row).
##
## Emitter parameter block (CallbackSchemaRegistry "trap_orbital"):
##   callback_params.param_A8  orbit height above the anchor, PSX units   (24)
##   callback_params.param_AE  ring count                                 (3)
##   (param_AA / param_AC — the ramp and finale lengths — are the ROM's constants in
##   ChargeOrbModel; kept on the emitter for the Studio's rows, not read.)
## Vault: [[Summon Orb Orbital System]]

const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const SfxRouterPort = ExMateriaPlatform.SfxRouterPort
const ChargeOrbModel = preload("res://addons/exmateria_effects/callbacks/ChargeOrbModel.gd")
const EffectTimeline = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")

## "Summoning": `SuzukiPlaySoundFindChannel(0x21)` on init, stopped on the last tick.
const SFX_ID := 0x21
const SLOTS_PER_RING := ChargeOrbModel.SLOTS
const BRIGHTNESS_WEIGHTS := ChargeOrbModel.WEIGHTS

var model = ChargeOrbModel.new()
## [handler tick, "on" | "off", sfx id].
var sfx_log: Array = []
var _running := false
var _emitter_index := -1
var _rings := 0
## The ring centre, effect-local, frozen at init.
var _centre := Vector3.ZERO
var _particles: Array = []     # [ring * SLOTS_PER_RING + slot] -> Particle
var _sfx_handle := 0


func _param(key: String, fallback: int) -> int:
	if emitter_config == null:
		return fallback
	return int(emitter_config.callback_params.get(key, fallback))


func _on_init(emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	_release_particles()
	_sfx_off()
	_emitter_index = emitter_index
	_rings = clampi(_param("param_AE", ChargeOrbModel.RINGS), 1, ChargeOrbModel.RINGS)
	_centre = anchor_target + Vector3(0.0, PsxMagnitude.tile_to_game(float(_param("param_A8", 24))), 0.0)
	if particle_host != null:
		for i in range(_rings * SLOTS_PER_RING):
			var p = particle_host.acquire_driven_particle(emitter_index, _centre)
			if p == null:
				break
			p.color_scale = 0.0
			_particles.append(p)
	model = ChargeOrbModel.new()
	model.start()
	_running = true
	_sfx_on()
	state = State.ANIMATE


func cleanup() -> void:
	# The span is closing (or the game released the charge): the finale.
	model.finalize()
	state = State.CLEANUP


func force_cleanup() -> void:
	_release_particles()
	_sfx_off()
	_running = false
	state = State.INACTIVE


func _release_particles() -> void:
	for p in _particles:
		if p != null:
			p.deactivate()
	_particles.clear()


func is_active() -> bool:
	return _running


func driven_particle_count() -> int:
	return _particles.size()


## The frozen centre the rings circle (effect-local).
func frozen_point() -> Vector3:
	return _centre


func physics_step() -> void:
	if not _running:
		return
	for _i in range(EffectTimeline.SECONDARY_TICKS_PER_FRAME):
		if not model.step():
			# The finale's last tick ran: every sprite is freed on that same tick.
			_running = false
			_release_particles()
			_sfx_off()
			return
	_push_particles()


func _exit_tree() -> void:
	_sfx_off()


## PSX → Godot: the 180° turn about X (ADR-0052) — x stays, z flips; the ring is flat.
func _push_particles() -> void:
	for r in range(_rings):
		for j in range(SLOTS_PER_RING):
			var i := r * SLOTS_PER_RING + j
			if i >= _particles.size():
				return
			var p = _particles[i]
			var o: Vector2i = model.offset(r, j)
			# grey 0–255 with 128 the texture's own colour → the renderer's neutral 1.0.
			p.color_scale = float(model.grey(j)) / 128.0
			p.position = _centre + Vector3(PsxMagnitude.tile_to_game(float(o.x)), 0.0,
				-PsxMagnitude.tile_to_game(float(o.y)))


func _sfx_on() -> void:
	sfx_log.append([model.ticks, "on", SFX_ID])
	_sfx_handle = SfxRouterPort.play_system_held(SFX_ID)


func _sfx_off() -> void:
	if sfx_log.is_empty() or sfx_log.back()[1] == "off":
		return
	sfx_log.append([model.ticks, "off", SFX_ID])
	SfxRouterPort.stop_held(_sfx_handle)
	_sfx_handle = 0
