@tool
extends Node3D
## Reusable wrapper for a single effect with its own manager, renderer, and controls
##
## Encapsulates:
## - EffectData loading
## - ParticleSubsystem (physics/animation)
## - EffectParticleRenderer (textured quads via individual MeshInstance3D)
## - Screen background color control (ScreenSubsystem)
## Vault: [[Effect Camera System]]
## Vault: [[Effect Execution Model]]
## Vault: [[Effect Frame Pacing]]
## Vault: [[Embedded MIPS Effect Code]]
## Vault: [[Transformed Pose System]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const ParticleSubsystem = preload("res://addons/exmateria_effects/subsystem/ParticleSubsystem.gd")

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxChirality = ExMateriaPlatform.PsxChirality

## The battle effect-SFX engine, reached through the platform PORT instead of the
## host's `ExMateriaEffectSfx` autoload identifier — eleven lines in this file, and the
## last of this addon's twenty-six arm-2 standalone-parse reaches (ADR-0308 dec. 1).
##
## 🔴 WHY THIS ONE IS A PORT AND THE TWO OVERLAY PORTS BELOW ARE NOT. All three
## identifiers were the same defect to arm 2, but arm 2b splits them: a node-path bind
## is free only when *"the autoload points at a script THIS addon ships"*. The host
## registers `TintedSurfaces` and `ScreenEffectOverlay` at
## `res://addons/exmateria_effects/…` paths, so this addon binds them itself.
## `ExMateriaEffectSfx` lives at `res://addons/exmateria_sound/runtime/…`, which this
## addon does not ship, and a node path there would only swap a parse error for a
## silent null — a quieter report of the same dependency. So it routes through the port
## tier, which is what a system addon is allowed to name (ADR-0139 dec. 9/12).
##
## The absent path needed no work at any of the eleven sites: `SfxPort`'s answers are
## the engine's own not-ready answers, and `_sfx_token == 0` is already this file's
## "no cast".
const SfxPort = ExMateriaPlatform.SfxPort


const EffectParticleRendererClass = preload("res://addons/exmateria_effects/render/EffectParticleRenderer.gd")
const ScreenSubsystemClass = preload("res://addons/exmateria_effects/subsystem/ScreenSubsystem.gd")
const PaletteSubsystemClass = preload("res://addons/exmateria_effects/subsystem/PaletteSubsystem.gd")
const CallbackManagerClass = preload("res://addons/exmateria_effects/callbacks/CallbackManager.gd")
const CameraSubsystemClass = preload("res://addons/exmateria_effects/subsystem/CameraSubsystem.gd")
const EffectSoundControllerClass = ExMateriaPlatform.EffectSoundController
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const SoundSubsystemClass = preload("res://addons/exmateria_effects/subsystem/SoundSubsystem.gd")
const EffectSoundScheduleClass = preload("res://addons/exmateria_effects/cast/EffectSoundSchedule.gd")
const EffectSoundResolverClass = ExMateriaPlatform.EffectSoundResolver

## This addon's two overlay autoloads, reached through their PORTS rather than as bare
## identifiers — a member may name no autoload at all (ADR-0308 dec. 1). Seven of this
## file's reaches were `TintedSurfaces` and `ScreenEffectOverlay`; the eleven that are
## `ExMateriaEffectSfx` go through `ExMateriaPlatform.SfxPort` instead, and the
## difference is not style. The two below point at scripts THIS addon ships, so the
## node-path bind inside them is free on arm 2b's stated grounds; `ExMateriaEffectSfx`
## points into `addons/exmateria_sound/`, which this addon does not ship, and for that
## one a node path would only swap a parse error for a silent null.
const TintedSurfacesPort = preload("res://addons/exmateria_effects/install/TintedSurfacesPort.gd")
const ScreenOverlayPort = preload("res://addons/exmateria_effects/install/ScreenOverlayPort.gd")

# Signals for external logging/UI
signal emitter_started(effect_name: String, emitter_idx: int, channel_idx: int, frame: int)
signal emitter_stopped(effect_name: String, emitter_idx: int, channel_idx: int, frame: int)

# Signals for game integration - three-stage reaction system
# Bit 6 (0x0040) = ABILITY_REACT - play reaction animation (early, when particles start)
# Bit 4 (0x0010) = HIT_REACT - apply damage/healing, show popups (when particles "hit")
# Bit 5 (0x0020) = REFRESH_TILE - end reaction animation, refresh unit state
signal ability_react_triggered(frame: int)
signal hit_reaction_triggered(frame: int)
signal refresh_tile_triggered(frame: int)
signal camera_started()
signal camera_finished()

# Action flags constants
const ACTION_FLAG_ABILITY_REACT = 0x0040  # Bit 6 - play reaction animation
const ACTION_FLAG_HIT_REACTION = 0x0010   # Bit 4 - apply damage, show popups
const ACTION_FLAG_REFRESH_TILE = 0x0020   # Bit 5 - end reaction, refresh state

# Exported properties for editor preview
@export_dir var effect_path: String = "":
	set(value):
		effect_path = value
		if Engine.is_editor_hint() and is_inside_tree():
			_reinitialize()
@export var pool_size: int = 512

# ADR-0037 dec. 7: cinematic spell EffectInstances opt OUT of the combat_visuals
# group so they keep playing while the rest of the world is frozen for the
# cinematic spotlight. Spawn-side sets this BEFORE add_child.
var is_cinematic: bool = false

# Public properties
var effect_name: String = ""

# Per-instance RNG (ADR-0070). Seeded once at spawn from a fresh entropy seed and
# re-applied on every reset() (loop restart / backward seek) by the timeline, so
# in-instance replay is bit-identical while each new cast still varies. Threaded
# into the particle subsystem + camera subsystem, and registered with the
# timeline for the re-seed.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_seed: int = 0

# Parked/scrub mode (Effect Studio, ADR-0069/0070). When true, _process stops
# pumping wall-clock time — the frame only advances via seek(), so the preview
# holds a parked frame until the Studio scrubs it. Default false = normal
# gameplay/combat playback.
var playback_paused: bool = false

# Looping control
var auto_loop: bool = true             # Auto-restart when loop_frames reached
var loop_frames: int = 300             # Frames until loop (default ~10s at 30fps)

# Internal state
var effect_data: EffectData
var manager: ParticleSubsystem
var sprite_renderer: Node3D
var callback_manager: Node3D = null  # CallbackManager for MIPS callbacks
var screen_controller = null  # ScreenSubsystem for background color
var palette_controller = null  # PaletteSubsystem for map tinting
var camera_controller = null   # CameraSubsystem for camera animation
var effect_timeline = null     # EffectTimeline — owns the clock, pumps the subsystems (ADR-0012)
var _sound_subsystem = null        # SoundSubsystem adapter wrapping _sound_controller
# Studio Solo/Mute: set-style Dictionary of muted sound lanes keyed "<phase>:<ci>". A trigger
# whose (from_phase, from_channel) lane is muted is dropped in _on_sound_event
# (phase-scoped so a lane's twins in the other phases stay audible; addon-safe).
var _muted_sound: Dictionary = {}
# Two INDEPENDENT emitter-hide sources feed the particle renderer and must not clobber
# each other: the F3 panel's per-emitter checkboxes and the Studio's Solo/Mute selection.
# The renderer's disabled_emitters is their UNION (see _push_emitter_filter) — either
# source hiding an emitter hides it.
var _panel_disabled_emitters: Dictionary = {}
var _studio_disabled_emitters: Dictionary = {}
# Timeline-driven FFT effect-sound (FEDS) playback. The EffectSoundController
# (exmateria-sound addon's class — name is the addon's concern) walks the sound-
# subsystem's keyframes, resolves each through the
# effect-flags config, and emits sound_event → ExMateriaEffectSfx.play_pair.
var _sound_loaded = null        # EffectSoundSchedule (this addon's, read off EffectData)
var _sound_controller = null    # EffectSoundController
var _sfx_token: int = 0         # ExMateriaEffectSfx cast token (for end_effect)
# Number of for-each (for_each) targets. Default 1 = single-target (faithful);
# set via set_target_count() before initialize() to schedule AoE per-target sounds.
var _target_count: int = 1

# Unit references for caster/target tinting (WeakRef to avoid keeping freed units alive)
var caster_unit: WeakRef = null
var target_unit: WeakRef = null

# Anchor markers parented to caster/target units for position tracking
var _origin_anchor: Node3D = null
var _target_anchor: Node3D = null

# Map center in Godot world coords (map_tiles / 2.0 per axis, Y=0)
# Used by CAMERA particle anchor — must match EFFECT_CTR camera source
var map_center_godot: Vector3 = Vector3.ZERO

func _ready() -> void:
	"""Auto-initialize if effect_path is set"""
	# ADR-0037: combat-visual — rides combat domain's pause axis via process_mode.
	# Cinematic spell EffectInstances opt OUT so they stay active while the rest
	# of combat_visuals is frozen for the cinematic spotlight (dec. 7).
	if not Engine.is_editor_hint() and not is_cinematic:
		add_to_group("combat_visuals")
	if effect_path != "":
		var path_name = effect_path.get_file()
		if path_name == "":
			path_name = effect_path.trim_suffix("/").get_file()
		initialize(path_name, effect_path, Vector3.ZERO, pool_size)


func _exit_tree() -> void:
	"""Clean up screen, map, and sound effects when removed from scene"""
	# Clean up anchor markers parented to units
	if _origin_anchor and is_instance_valid(_origin_anchor) and _origin_anchor.is_inside_tree():
		_origin_anchor.queue_free()
	_origin_anchor = null
	if _target_anchor and is_instance_valid(_target_anchor) and _target_anchor.is_inside_tree():
		_target_anchor.queue_free()
	_target_anchor = null

	# Return borrowed meshes to global pool
	if sprite_renderer and sprite_renderer.has_method("release_pool_meshes"):
		sprite_renderer.release_pool_meshes()

	# Disconnect from the manager's unified emitter signal surface (#30 step 5).
	if manager:
		if manager.emitter_started.is_connected(_on_timeline_emitter_started):
			manager.emitter_started.disconnect(_on_timeline_emitter_started)
		if manager.emitter_stopped.is_connected(_on_timeline_emitter_stopped):
			manager.emitter_stopped.disconnect(_on_timeline_emitter_stopped)
		if manager.action_flags_triggered.is_connected(_on_action_flags_triggered):
			manager.action_flags_triggered.disconnect(_on_action_flags_triggered)

	# Disconnect the sound subsystem and end the SFX cast so the engine
	# goes idle (stops driving the shared SPU). The ~25 ms already buffered plays
	# out as a natural tail.
	if _sound_controller and _sound_controller.sound_event.is_connected(_on_sound_event):
		_sound_controller.sound_event.disconnect(_on_sound_event)
	# Orphan (not end) the SFX cast: the visual is done, but let the dispatched
	# FEDS pairs finish their natural sequence + tail instead of cutting them.
	# The engine reaps the cast once its sound actually ends.
	if _sound_controller and not Engine.is_editor_hint():
		SfxPort.orphan_effect(_sfx_token)
	_sound_controller = null
	_sound_loaded = null

	# Disconnect callback manager signal and clear manager reference
	if callback_manager and callback_manager.child_spawn_requested.is_connected(_on_callback_child_spawn):
		callback_manager.child_spawn_requested.disconnect(_on_callback_child_spawn)
	if manager:
		manager.callback_manager = null

	# Emit camera_finished when removed from scene
	if camera_controller:
		camera_finished.emit()
		camera_controller = null

	if screen_controller and not Engine.is_editor_hint():
		ScreenOverlayPort.remove_layer(screen_controller.get_owner_id())
	if palette_controller and not Engine.is_editor_hint():
		TintedSurfacesPort.remove_layer(TintedSurfacesPort.SURFACE_MAP, palette_controller.get_owner_id())
		# Clean up unit tints for caster and target
		TintedSurfacesPort.remove_all_layers_for_owner(palette_controller.get_owner_id())


func _reinitialize() -> void:
	"""Reinitialize when effect_path changes in editor"""
	# Clear screen effect if active
	if screen_controller and not Engine.is_editor_hint():
		ScreenOverlayPort.remove_layer(screen_controller.get_owner_id())
	# Clear map tint effect if active
	if palette_controller and not Engine.is_editor_hint():
		TintedSurfacesPort.remove_layer(TintedSurfacesPort.SURFACE_MAP, palette_controller.get_owner_id())
		# Clear unit tints
		TintedSurfacesPort.remove_all_layers_for_owner(palette_controller.get_owner_id())

	# Return borrowed meshes before clearing renderer
	if sprite_renderer and sprite_renderer.has_method("release_pool_meshes"):
		sprite_renderer.release_pool_meshes()

	# Clear existing children
	for child in get_children():
		child.queue_free()
	sprite_renderer = null
	callback_manager = null  # Child node freed automatically
	manager = null
	effect_data = null
	screen_controller = null
	palette_controller = null
	camera_controller = null
	effect_timeline = null
	_sound_subsystem = null
	caster_unit = null
	target_unit = null
	# Clean up anchor markers (they're parented to units, not this node)
	if _origin_anchor and is_instance_valid(_origin_anchor):
		_origin_anchor.queue_free()
	_origin_anchor = null
	if _target_anchor and is_instance_valid(_target_anchor):
		_target_anchor.queue_free()
	_target_anchor = null

	# Reinitialize if path is set
	if effect_path != "":
		var path_name = effect_path.get_file()
		if path_name == "":
			path_name = effect_path.trim_suffix("/").get_file()
		call_deferred("initialize", path_name, effect_path, Vector3.ZERO, pool_size)


func initialize(name: String, data_path: String, anchor: Vector3, init_pool_size: int = 512) -> bool:
	"""Initialize effect instance with data from directory

	Args:
		name: Display name (e.g. "E001")
		data_path: Resource path to effect directory (e.g. "res://assets/effects/E001")
		anchor: World position for target anchor
		init_pool_size: Maximum particles

	Returns:
		true if initialization succeeded
	"""
	effect_name = name

	# Seed the per-instance RNG (ADR-0070) from fresh entropy, then capture that
	# seed so reset() can re-apply it for deterministic in-instance replay. Each
	# new cast gets a different seed, so gameplay still varies cast-to-cast.
	_rng.randomize()
	_rng_seed = _rng.seed

	# Load effect data
	effect_data = EffectData.load_from_directory(data_path)
	if effect_data == null:
		push_error("EffectInstance [%s]: Failed to load effect data from %s" % [name, data_path])
		return false

	if EffectsDebug.iteration():
		print("EffectInstance [%s]: Loaded %d emitters, %d curves" % [
			name, effect_data.emitters.size(), effect_data.curves.size()
		])

	# Initialize manager
	manager = ParticleSubsystem.new()
	manager.rng = _rng  # per-instance RNG (ADR-0070) — set BEFORE initialize forwards it to physics
	manager.initialize(effect_data, init_pool_size)

	# Set anchors (target = anchor position)
	manager.set_anchors(
		Vector3.ZERO,  # world
		Vector3.ZERO,  # cursor
		Vector3.ZERO,  # origin
		anchor         # target
	)

	# Initialize CAMERA anchor from map center
	# PSX: get_camera_position() returns map dimensions, * 14 = map center
	# CAMERA anchor and EFFECT_CTR both resolve to the same world position
	var cam_anchor = map_center_godot - global_position
	cam_anchor.y = -global_position.y  # Cancel effect Y so particle Y = purely emitter offset
	manager.anchor_camera = cam_anchor

	# Create particle renderer
	sprite_renderer = EffectParticleRendererClass.new()
	sprite_renderer.initialize(effect_data, init_pool_size)
	add_child(sprite_renderer)

	# Subscribe to the manager's unified emitter signal surface (#30 step 5).
	# The manager re-emits from its three inner phase controllers; nine
	# subscriptions collapse to three.
	manager.emitter_started.connect(_on_timeline_emitter_started)
	manager.emitter_stopped.connect(_on_timeline_emitter_stopped)
	manager.action_flags_triggered.connect(_on_action_flags_triggered)
	var has_timeline := manager.phase1_block != null \
		or manager.phase2_block != null \
		or manager.for_each_block != null

	# Spawn-drive is now the EffectTimeline (built below). The old "manual mode"
	# (no for-each timeline → start_emitter(0)) is gone: every real effect is
	# timeline-driven; the only timeline-less effects are 0-byte empty slots
	# (ADR-0012). `has_timeline` decides whether the timeline starts ticking.

	# Initialize callback manager if effect has MIPS callbacks
	if not effect_data.callback_slots.is_empty():
		callback_manager = CallbackManagerClass.new()
		callback_manager.initialize(effect_data, effect_data.callback_slots)
		callback_manager.child_spawn_requested.connect(_on_callback_child_spawn)
		add_child(callback_manager)
		manager.callback_manager = callback_manager

	# Initialize screen subsystem if screen data exists
	if effect_data.screen and not Engine.is_editor_hint():
		screen_controller = ScreenSubsystemClass.new()
		# Pass the map's default gradient TOP + BOTTOM baselines (the ColorStack folds
		# each separately — the screen is a gradient, not a flat tint). Phase boundaries
		# are not passed: the timeline resolves the phase and hands it to advance().
		screen_controller.initialize(effect_data.screen,
			ScreenOverlayPort.get_default_top(), ScreenOverlayPort.get_default_bottom())

	# Initialize palette subsystem if palette data exists (map tinting)
	if effect_data.palette and not Engine.is_editor_hint():
		palette_controller = PaletteSubsystemClass.new()
		palette_controller.initialize(effect_data.palette)
		# Forward any already-set unit targets so palette self-delivers unit tints
		# (ADR-0014). set_unit_targets() covers the reverse order.
		var _c = caster_unit.get_ref() if caster_unit else null
		var _t = target_unit.get_ref() if target_unit else null
		if _c or _t:
			palette_controller.set_units(_c, _t)

	# Initialize camera subsystem if camera data exists
	if effect_data.camera and effect_data.camera.has_active_keyframes() and not Engine.is_editor_hint():
		camera_controller = CameraSubsystemClass.new()
		camera_controller.rng = _rng  # deterministic camera shake for scrub (ADR-0070)
		var cam_p1_dur = 0
		var cam_spawn_delay = 0
		var cam_p2_start = 0
		if effect_data.timeline:
			cam_p1_dur = effect_data.timeline.phase1_duration
			cam_spawn_delay = effect_data.timeline.spawn_delay
			var cam_p2_delay = effect_data.timeline.phase2_delay
			cam_p2_start = cam_p1_dur + cam_p2_delay
		camera_controller.initialize(effect_data.camera, cam_p1_dur, cam_spawn_delay, cam_p2_start)
		# Detect pattern 2 (opcode 40 = for_each) for continuous camera timeline
		for op in effect_data.script_ops:
			if op is Dictionary and op.get("opcode") == 40:
				camera_controller.continuous_for_each = true
				break
		# Set initial reference position from anchor
		camera_controller.target_position = PsxChirality.godot_position_to_psx(anchor)
		camera_controller.cursor_position = PsxChirality.godot_position_to_psx(anchor)
		camera_controller.caster_position = PsxChirality.godot_position_to_psx(anchor)
		camera_started.emit()

	# Initialize timeline-driven effect sound (FEDS). Runtime-only — never
	# synthesize audio in the editor preview, and ExMateriaEffectSfx is not a @tool
	# autoload.
	if not Engine.is_editor_hint():
		_load_effect_sound()

	# Build the effect timeline: it owns the clock + fixed accumulator and pumps
	# the subsystems in order — particle → sound → color (screen, palette) →
	# camera (ADR-0012). Nulls are skipped, so a cast missing a subsystem type
	# is fine.
	effect_timeline = EffectTimelineClass.new()
	var _p1d := 0
	var _p2s := 0
	if effect_data.timeline:
		_p1d = effect_data.timeline.phase1_duration
		_p2s = _p1d + effect_data.timeline.phase2_delay  # single-target formula
	effect_timeline.setup(_p1d, _p2s, effect_data.time_scale)
	# Register the per-instance RNG so the timeline re-seeds it on reset() /
	# backward seek — the deterministic-replay contract (ADR-0070).
	effect_timeline.set_rng(_rng, _rng_seed)
	if _sound_controller:
		_sound_subsystem = SoundSubsystemClass.new(_sound_controller)
	effect_timeline.set_subsystems(
		[manager, _sound_subsystem, screen_controller, palette_controller, camera_controller])
	manager.timeline = effect_timeline  # back-ref for phase boundary reads (#30)
	if has_timeline:
		effect_timeline.start()

	return true


func _load_effect_sound() -> void:
	"""Build the sound walker's input from the ALREADY-LOADED `effect_data` and arm the
	addon's EffectSoundController. The single sound-setup seam, so the studio's
	edit→playback bridge (below) has one home and a test can drive it without the full
	particle/overlay init.

	🔴 THIS USED TO TAKE A DIRECTORY AND RE-PARSE IT (ADR-0318 dec. 6). `EffectJSONLoader.
	load_dir(effect_dir)` opened sound.json, sound_containers.json, timeline.json and
	feds.bin — the same four `EffectData.load_from_directory` had opened from the SAME
	argument a hundred lines above (`initialize()` is handed one `data_path` and passed
	it to both). Three re-points then put EffectData's objects back over the loader's,
	because ADR-0085's single-source rule requires the studio's edits to reach playback
	and a second parse is a stale copy by construction: each re-point repaired damage the
	line above it had done, and the FEDS one had to be given up on entirely — a
	structural verb REPLACES `data.feds_bank`, so `_live_feds_bank()` below reads through
	`effect_data` at fire time rather than trusting any re-point at all.

	Reading EffectData directly leaves nothing to re-point, and one fewer `preload` into
	`addons/exmateria_sound/`: the loader was one of the four whose absence is a
	parse-error cascade (#1354)."""
	_sound_loaded = EffectSoundScheduleClass.from_effect_data(effect_data)
	# ⚠️ `has_schedule()`, not `has_sound()` (ADR-0318 dec. 2). An effect with keyframes
	# and no `feds.bin` now arms its walker and publishes its events; `_on_sound_event`
	# below finds no bank and stays silent. Gating on the BANK here is what used to make
	# "no audio package" mean "no events" (#1354).
	if _sound_loaded.has_schedule():
		_sound_controller = EffectSoundControllerClass.new()
		_sound_controller.debug_log = false
		if _sound_controller.load_effect(_sound_loaded):
			_sound_controller.sound_event.connect(_on_sound_event)
			# Fresh SFX cast (re-seeds the entity; ends any prior cast's sound).
			_sfx_token = SfxPort.begin_effect()
			# pre_anchor_offset=0, vm_snapshot={} — PCSX parity-calibration
			# inputs that default to faithful in-game behaviour.
			_sound_controller.start(_target_count, 0, {})
		else:
			_sound_controller = null


func set_target_count(count: int) -> void:
	"""Set the number of for-each (for_each) targets, so AoE effects schedule
	per-target sounds. Call BEFORE initialize(). Defaults to 1 (single-target)."""
	_target_count = maxi(1, count)


func _on_sound_event(_frame: int, from_phase: String, from_channel: int,
		sound_id: int) -> void:
	"""A scheduled sound fired: dispatch it as a FEDS pair through the persistent SFX
	engine, IF there is a bank. sound_id is the resolver's output (the value
	ExMateriaEffectSfx/play_feds_pair wants for the chan+0x92 static seed); see
	CONTEXT.md "Audio" → SoundContainer + EffectSoundResolver.

	🔴 THE FEDS ARITHMETIC IS THIS SIDE'S, NOT THE WALKER'S (ADR-0318 dec. 1). `pair_idx
	= sound_id - 1` and the `num_pairs` bounds test used to happen inside the walker,
	which meant the walker had to hold a bank, which meant no bank was no EVENT rather
	than no SOUND. Both moved here. This handler is one of N: a backend that wants its
	own sounds connects to the same signal and never learns what a FEDS pair is."""
	# Studio Solo/Mute: drop the trigger if THIS (phase, channel) sound lane is muted. Keyed
	# "<phase>:<ci>" to match resolve_audibility — each phase has its own channels 0/1/2, so a
	# bare channel index would silence a lane's twins in the other phases (and break solo). The
	# addon's whole-channel walk stays untouched; a rescrub re-fires the rest.
	if _muted_sound.has("%s:%d" % [from_phase, from_channel]):
		return
	var bank = _live_feds_bank()
	if bank == null:
		return
	# The bounds test the walker used to make. `_play_pair_locked` makes it too and
	# `push_warning`s on a miss, so skipping it here would turn a silent, legitimate
	# "this effect has no bytes for that id" into console noise on every fire.
	var pair_idx: int = sound_id - 1
	if pair_idx < 0 or pair_idx >= bank.num_pairs:
		return
	SfxPort.play_pair(_sfx_token, bank, pair_idx, sound_id)


## The FEDS bank the audible path must use: `EffectData`'s when there is one, else the
## schedule's captured one. Read at PLAY time, never cached.
##
## `_load_effect_sound` captures `EffectData`'s bank into `_sound_loaded` ONCE, which is
## enough for a same-size byte patch (the studio mutates `raw` in place, so both names
## reach the edited bytes). It is NOT enough for a STRUCTURAL verb: insert / delete /
## un-rest / paint / drag / outro / prune, and undo of any of them, all REPLACE
## `data.feds_bank` with a freshly built object — that is what makes the snapshot undo
## exact (ADR-0085 2026-08-18b). The capture holds the old object, so from the first
## structural edit onward the studio drew one bank and Play sounded another, and every
## later param patch landed on the bank nobody was playing. (Before ADR-0318 dec. 6 the
## same one-time capture was spelled as a re-point over `EffectJSONLoader`'s second parse;
## deleting that parse removed the second copy, not the staleness of a captured handle.)
##
## Reading through `effect_data` at fire time makes the identity irrelevant: whatever the
## editor is holding NOW is what sounds, with no re-bind to remember on any new verb.
func _live_feds_bank():
	if effect_data and effect_data.feds_bank != null:
		return effect_data.feds_bank
	return _sound_loaded.feds_bank if _sound_loaded else null


# How long an audition cast stays open after its last fire before keying off — long
# enough for a natural decay, short enough that back-to-back auditions don't stack casts.
const AUDITION_RINGOUT_S := 2.0


func audition_container(index: int, fires: int = 6, spacing_ms: int = 380) -> void:
	"""Studio-only: HEAR a SoundContainer's Pick-mode alternation. A mode only diverges
	from the 2nd fire (every mode plays id_a first) and the live playthrough fires a
	container once, so changing the mode is otherwise silent in the previewer. This drives
	a FRESH resolver forward `fires` times (the resolver stays the single source of mode
	truth) and plays each resolved FEDS pair through the persistent SFX engine, spaced so
	the alternation is audible. No byte/timeline mutation — pure playback."""
	var feds_bank = _live_feds_bank()
	if feds_bank == null or _sound_loaded == null:
		return
	var containers = _sound_loaded.sound_containers
	if not (containers is Dictionary) or containers.is_empty():
		return
	var resolver = EffectSoundResolverClass.from_sound_containers(containers)
	resolver.reset_counters()
	var timeline_sid := index + 2
	# Audition opens its OWN short-lived cast: the instance's _sfx_token dies whenever a
	# ghost re-projection runs (SoundGhostProjector.render_pair panic()s the engine, which
	# ends ALL casts — playback survives only because seek/reset re-arm a fresh token via
	# _restart_sound_cast). play_pair on that dead token is a silent no-op; a fresh cast
	# is valid regardless. end_effect is a key-off (the tail rings out), not a cut.
	var tok: int = SfxPort.begin_effect()
	for fire in range(fires):
		var resolved: int = int(resolver.resolve(index, timeline_sid))
		var pair_idx := resolved - 1
		if resolved > 0 and pair_idx >= 0 and pair_idx < feds_bank.num_pairs:
			SfxPort.play_pair(tok, feds_bank, pair_idx, resolved)
		# Space the fires so successive sounds are distinct to the ear (the last fire
		# needs no trailing wait).
		if fire < fires - 1:
			await get_tree().create_timer(spacing_ms / 1000.0).timeout
	# Let the last fire ring out before keying the cast off (end_effect is a key-off; an
	# immediate one would clip a sustained tail). If the instance is freed mid-wait the
	# orphaned session is reclaimed by the next render/panic — no audible consequence.
	await get_tree().create_timer(AUDITION_RINGOUT_S).timeout
	SfxPort.end_effect(tok)


func audition_sound(resolved: int) -> void:
	"""Studio-only: HEAR one already-resolved sound id (a container's Sound slot entry)
	exactly once — the ▶ preview an author uses to tell bank entries apart while picking.
	Bypasses the container's mode/counter on purpose: this previews the ENTRY, not the
	selection logic (audition_container covers that). No byte/timeline mutation. Opens
	its own cast for the same dead-token reason as audition_container."""
	var feds_bank = _live_feds_bank()
	if feds_bank == null:
		return
	var pair_idx := resolved - 1
	if resolved > 0 and pair_idx >= 0 and pair_idx < feds_bank.num_pairs:
		var tok: int = SfxPort.begin_effect()
		SfxPort.play_pair(tok, feds_bank, pair_idx, resolved)
		await get_tree().create_timer(AUDITION_RINGOUT_S).timeout
		SfxPort.end_effect(tok)


func _process(delta: float) -> void:
	if not manager:
		return

	var _perf_enabled: bool = EffectsDebug.particle()
	var _tp0: int
	var _tp1: int
	var _tp2: int
	var _tp3: int
	if _perf_enabled:
		_tp0 = Time.get_ticks_usec()

	# Update anchor offsets from marker nodes (tracks unit movement)
	if _origin_anchor and is_instance_valid(_origin_anchor) and _target_anchor and is_instance_valid(_target_anchor):
		var origin_offset = _origin_anchor.global_position - global_position
		var target_offset = _target_anchor.global_position - global_position
		manager.set_anchors(target_offset, target_offset, origin_offset, target_offset)
		# Update CAMERA anchor from map center (same as EFFECT_CTR camera source)
		var cam_anchor = map_center_godot - global_position
		cam_anchor.y = -global_position.y  # Cancel effect Y so particle Y = purely emitter offset
		manager.anchor_camera = cam_anchor
		for emitter in manager.active_emitters:
			emitter.anchor_camera = cam_anchor

	# Set camera anchors before pumping — the camera subsystem reads them in advance().
	if camera_controller:
		if _target_anchor and is_instance_valid(_target_anchor):
			var target_psx = PsxChirality.godot_position_to_psx(_target_anchor.global_position)
			camera_controller.target_position = target_psx
			camera_controller.cursor_position = target_psx
		if _origin_anchor and is_instance_valid(_origin_anchor):
			camera_controller.caster_position = PsxChirality.godot_position_to_psx(_origin_anchor.global_position)

	# Pump the timeline: it owns the clock + fixed accumulator and advances every
	# subsystem (particle → sound → color → camera) per fixed 30 Hz frame (ADR-0012).
	# Parked (Effect Studio scrub, ADR-0070): skip the wall-clock pump so the frame
	# only advances via seek(); still fall through to render the parked frame.
	if not playback_paused:
		effect_timeline.tick(delta)

	# Update callback anchors and render
	if callback_manager:
		callback_manager.update_anchors(
			manager.anchor_origin, manager.anchor_target,
			manager.anchor_world, manager.anchor_cursor,
			manager.caster_facing_angle)
		callback_manager.update_render()

	# (Effect sound is a subsystem now — pumped inside tick() via the
	# SoundSubsystem adapter, which passes the controller's own fire_sub_tick.
	# No loop here.)

	# Check for auto-loop (never while parked — the Studio owns the frame via seek)
	if not playback_paused and auto_loop and loop_frames > 0 and effect_timeline.effect_frame >= loop_frames:
		reset()
		return

	if _perf_enabled:
		_tp1 = Time.get_ticks_usec()

	# Color subsystems self-deliver their overlay output inside their own advance()
	# now (ADR-0014); EffectInstance is no longer the courier. Screen → screen
	# overlay, palette → map + caster/target unit tint overlays, pushed during tick().

	# (Camera is a subsystem now — advanced inside tick(); its anchors were set
	# before tick(), and PlayerCamera reads its pose when in effect-camera mode.)

	if _perf_enabled:
		_tp2 = Time.get_ticks_usec()

	# Render: pass Particle objects directly (zero-alloc). Per-particle
	# frameset_idx + depth_mode live on each Particle (written by
	# ParticleAnimator.tick() during manager.advance), so the renderer reads
	# them straight off the particle without a manager handle.
	if sprite_renderer:
		sprite_renderer._effect_world_origin = global_position
		sprite_renderer.update_particles(manager.get_active_particles())

	if _perf_enabled:
		_tp3 = Time.get_ticks_usec()
		var total_ms = (_tp3 - _tp0) / 1000.0
		if total_ms > 4.0:
			var mgr_ms = (_tp1 - _tp0) / 1000.0
			var ctrl_ms = (_tp2 - _tp1) / 1000.0
			var render_ms = (_tp3 - _tp2) / 1000.0
			var pcount = manager.get_active_particles().size() if manager else 0
			print("[EFFECT_PERF] %.1fms total | mgr=%.1fms ctrl=%.1fms render=%.1fms | particles=%d frame=%d" % [
				total_ms, mgr_ms, ctrl_ms, render_ms, pcount, effect_timeline.effect_frame])


# --- Debug emitter filter (EffectViewer only — not a runtime control surface) ---

func set_debug_emitter_filter(disabled: Dictionary) -> void:
	"""Set the F3 panel's per-emitter hide set (the emitter checkboxes).

	Debug-only knob owned by the EffectViewer panel; the runtime never mutes
	emitters per cast. See CONTEXT.md "Subsystem" avoid list. Unioned with the
	Studio's Solo/Mute set — the two sources are independent (see apply_audibility)."""
	_panel_disabled_emitters = disabled
	_push_emitter_filter()


## Merge the panel and Studio emitter-hide sets onto the renderer. Fast path when the
## Studio set is empty (the universal non-Studio case): pass the panel set straight
## through. Otherwise union into a fresh dict so neither source's dict is mutated.
func _push_emitter_filter() -> void:
	if not sprite_renderer:
		return
	if _studio_disabled_emitters.is_empty():
		sprite_renderer.disabled_emitters = _panel_disabled_emitters
		return
	var merged: Dictionary = _panel_disabled_emitters.duplicate()
	for k in _studio_disabled_emitters:
		merged[k] = true
	sprite_renderer.disabled_emitters = merged


## Apply the Effect Studio Solo/Mute selection (debug-only). `audibility` is the whole
## EffectScoreModel.resolve_audibility result: `disabled_emitters` (particles, per-emitter
## render-skip) plus the per-lane exclusion filters `muted_screen` / `muted_palette`
## (routed to the subsystems) and `muted_sound` (applied per-channel at the trigger).
## Camera is display-only (no mute). The runtime never calls this — only the Studio host.
## Re-fold + re-deliver the read-live COLOUR subsystems (screen + palette) in place at the
## current frame (#255 authoring). For an edit whose channel is read-live
## (invalidates_sim=false), the once-per-frame guard would otherwise hold the stale folded
## output while the preview is parked; this reaches the live edit to the overlays with NO
## reset + re-pump (ADR-0070). The runtime never calls this — only the Studio host.
func redeliver_colors() -> void:
	if screen_controller:
		screen_controller.redeliver()
	if palette_controller:
		palette_controller.redeliver()


func apply_audibility(audibility: Dictionary) -> void:
	_studio_disabled_emitters = audibility.get("disabled_emitters", {})
	_push_emitter_filter()
	if screen_controller:
		screen_controller.set_muted(audibility.get("muted_screen", {}))
	if palette_controller:
		palette_controller.set_muted(audibility.get("muted_palette", {}))
	# Copy — the caller (host) holds this dict as its live selection; don't alias it.
	_muted_sound = audibility.get("muted_sound", {}).duplicate()


## Per-edge child-spawn suppression (ADR-0075). Sets the sim-side flag on the
## ParticleSubsystem, then DETERMINISTICALLY re-seeks the preview to the current playhead
## so the counterfactual cloud is re-derived in place (a simulation change can't be shown
## by re-filtering an already-simulated frame). `edge` is "death" or "midlife".
func set_child_edge_suppressed(parent_index: int, edge: String, suppressed: bool) -> void:
	if not manager:
		return
	manager.set_child_edge_suppressed(parent_index, edge, suppressed)
	# Re-derive the parked/scrubbed frame: seek(0) resets + re-pumps from 0 (backward),
	# then seek(f) forward-pumps to the current frame against the re-seeded RNG — the same
	# rescrub the free-camera re-acquire uses. The suppression survives the reset() inside.
	var f: int = get_effect_frame()
	seek(0)
	seek(f)


func is_child_edge_suppressed(parent_index: int, edge: String) -> bool:
	return manager.is_child_edge_suppressed(parent_index, edge) if manager else false


func get_emitter_count() -> int:
	"""Get number of emitters in this effect"""
	if manager:
		return manager.get_emitter_count()
	return 0


func get_active_particle_count() -> int:
	"""Get current active particle count"""
	if manager:
		return manager.get_active_particle_count()
	return 0


func get_effect_frame() -> int:
	"""Get current effect frame (the timeline owns the clock now)."""
	if effect_timeline:
		return effect_timeline.effect_frame
	return 0


func seek(frame: int) -> void:
	"""Deterministically seek the live effect to `frame` (ADR-0070). Forward
	scrub pumps forward; backward scrub reset()s + re-pumps from 0, reproducing
	the identical cloud via the re-seeded instance RNG. The Effect Studio's scrub
	surface routes here. Renders on the next _process pass."""
	if effect_timeline:
		# A BACKWARD seek is a replay from an earlier frame — the studio's Stop /
		# loop-restart / backward-scrub. Re-arm the sound cast so FEDS triggers fire
		# again on the re-pump: EffectTimeline.reset() only resets per-frame subsystem
		# state (SoundSubsystem.reset() is a no-op), and the controller restart + fresh
		# SFX entity (a FINISHED entity won't sequence again) live here, the token's
		# owner. Without this, replay is visually correct but silent. (refold()/rescrub()
		# deliberately does NOT re-arm sound — an authoring re-fold is not a replay.)
		if maxi(0, frame) < effect_timeline.effect_frame:
			_restart_sound_cast()
		effect_timeline.seek(frame)


func seek_silent(frame: int) -> void:
	"""Seek WITHOUT re-arming the sound cast — the Effect Studio's ping-pong REVERSE leg
	(ADR-0090). A backward seek reset()s and re-pumps from 0 (deterministic replay via the
	re-seeded RNG), exactly like seek(), but deliberately skips `_restart_sound_cast`: you
	can't play a sound backward, and re-arming FEDS on every reverse frame would be audible
	garbage. Audio fires on FORWARD legs only (those go through seek()). Same cost as a
	backward seek (O(absolute frame) — the accepted reverse-leg limitation)."""
	if effect_timeline:
		effect_timeline.seek(frame)


func refold() -> void:
	"""Re-fold the current frame in place after an authoring edit to a FOLDED channel
	(camera framing). `seek(get_effect_frame())` would be a same-frame no-op; rescrub()
	resets + re-pumps so the folded output recomputes without scrubbing away and back."""
	if effect_timeline:
		effect_timeline.rescrub()


func refresh_texture() -> void:
	"""Re-push the effect's texture sheet into the particle renderer after an authoring
	edit replaced it (#280, ADR-0199). The sheet is bound into the pool slot's shader
	material and the slot's `_effect_tex` field ONCE at the renderer's initialize(), so a
	`TextureChannel.replace` swap reaches the model but not the pixels on screen —
	`refold()` only rescrubs the timeline, it never touches materials. Same shape as
	`refresh_render_emitter_caches`; the studio host calls it on every texture import."""
	if sprite_renderer and sprite_renderer.has_method("refresh_texture"):
		sprite_renderer.refresh_texture()


func refresh_render_emitter_caches() -> void:
	"""Re-derive the particle renderer's per-emitter caches (colour curves, align_to_velocity)
	after an authoring edit to an emitter. Those caches are built once at the renderer's
	initialize() and would otherwise stay stale — a live colour-curve enable toggle or curve
	reassignment wouldn't show until the whole effect respawned. The studio host calls this on
	every emitter-channel edit (see EffectViewerScene.studio_apply_edit)."""
	if sprite_renderer and sprite_renderer.has_method("refresh_emitter_caches"):
		sprite_renderer.refresh_emitter_caches()


func set_paused(paused: bool) -> void:
	"""Park (true) or run (false) the wall-clock pump. Parked = the frame only
	moves via seek() — the Effect Studio's parked-document / transport model."""
	playback_paused = paused


func is_timeline_finished() -> bool:
	"""Check if all timeline phases have completed processing."""
	if not manager:
		return true
	if not effect_timeline or not effect_timeline.is_started():
		return true
	# Check all phase controllers
	if manager.phase1_block and not manager.phase1_block.is_finished():
		return false
	if manager.for_each_block and not manager.for_each_block.is_finished():
		return false
	if manager.phase2_block and not manager.phase2_block.is_finished():
		return false
	return true


func reset() -> void:
	"""Reset the effect (restart timeline, screen, map, and sound effects)"""
	# The timeline resets its clock + every subsystem (particle, color, camera, sound
	# adapter). Falls back to manager.reset() if the timeline wasn't built.
	if effect_timeline:
		effect_timeline.reset()
	elif manager:
		manager.reset()
	if callback_manager:
		callback_manager.reset()

	# Restart the sound timeline so FEDS keyframes replay on the next loop.
	_restart_sound_cast()


func _restart_sound_cast() -> void:
	"""Re-arm the effect's sound for a replay: end the prior cast (its tail rings out on
	the continuous SPU) and open a FRESH one — a finished entity won't sequence again —
	then restart the controller's keyframe walk so FEDS triggers fire from the top.
	Shared by reset() (in-game loop restart) and seek() (studio backward seek), the two
	replay entry points; the SFX token it manages is owned here."""
	if _sound_controller and not Engine.is_editor_hint():
		SfxPort.end_effect(_sfx_token)
		_sfx_token = SfxPort.begin_effect()
		_sound_controller.start(_target_count, 0, {})


func set_anchors(world: Vector3, cursor: Vector3, origin: Vector3, target: Vector3) -> void:
	"""Set all anchor positions for the effect"""
	if manager:
		manager.set_anchors(world, cursor, origin, target)


func set_unit_targets(caster, target) -> void:
	"""Set caster and target unit references for palette-subsystem tinting

	Uses WeakRef to avoid keeping freed units alive during async effect cleanup.
	Also extracts caster facing direction for OUTWARD_UNIT_ORIENTED velocity mode.

	Args:
		caster: Unit node casting the spell (or null)
		target: Unit node being targeted (or null)
	"""
	caster_unit = weakref(caster) if caster else null
	target_unit = weakref(target) if target else null
	# Palette self-delivers the caster/target unit tints (ADR-0014); hand it the refs.
	if palette_controller:
		palette_controller.set_units(caster, target)
	if manager and caster and is_instance_valid(caster) and target and is_instance_valid(target):
		var dir = target.global_position - caster.global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			# atan2(x, z) gives angle from +Z; PSX default facing is +X, so subtract PI/2
			manager.caster_facing_angle = atan2(dir.x, dir.z) - PI / 2.0


func attach_anchors_to_units(caster: Node3D, target: Node3D) -> void:
	"""Create Node3D markers parented to caster/target so anchors track unit movement.

	The markers sit at the unit's origin (local Vector3.ZERO). Each frame,
	_process() reads their global_position and pushes updated offsets into
	the ParticleSubsystem.
	"""
	if caster and is_instance_valid(caster):
		_origin_anchor = Node3D.new()
		_origin_anchor.name = "EffectOriginAnchor"
		caster.add_child(_origin_anchor)
		_origin_anchor.position = Vector3.ZERO
		if EffectsDebug.iteration():
			print("[EffectInstance] Origin anchor attached to %s at %s" % [caster.name, caster.global_position])

	if target and is_instance_valid(target):
		_target_anchor = Node3D.new()
		_target_anchor.name = "EffectTargetAnchor"
		target.add_child(_target_anchor)
		_target_anchor.position = Vector3.ZERO
		if EffectsDebug.iteration():
			print("[EffectInstance] Target anchor attached to %s at %s" % [target.name, target.global_position])


# --- Signal Handlers ---

func _on_timeline_emitter_started(emitter_idx: int, channel_idx: int, frame: int) -> void:
	"""Re-emit with effect name"""
	emitter_started.emit(effect_name, emitter_idx, channel_idx, frame)



func _on_timeline_emitter_stopped(emitter_idx: int, channel_idx: int, frame: int) -> void:
	"""Re-emit with effect name"""
	emitter_stopped.emit(effect_name, emitter_idx, channel_idx, frame)



func _on_action_flags_triggered(flags: int, _channel_idx: int, frame: int) -> void:
	"""Handle action_flags from timeline keyframes

	Three-stage reaction system:
	- Bit 6 (0x0040) ABILITY_REACT: Play reaction animation (early in effect)
	- Bit 4 (0x0010) HIT_REACT: Apply damage/healing, show popups (when particles "hit")
	- Bit 5 (0x0020) REFRESH_TILE: End reaction animation, refresh unit state
	"""
	if flags & ACTION_FLAG_ABILITY_REACT:
		ability_react_triggered.emit(frame)

	if flags & ACTION_FLAG_HIT_REACTION:
		hit_reaction_triggered.emit(frame)

	if flags & ACTION_FLAG_REFRESH_TILE:
		refresh_tile_triggered.emit(frame)


func _on_callback_child_spawn(emitter_index: int, pos: Vector3, frame: int) -> void:
	"""Forward child spawn requests from callbacks to ParticleSubsystem."""
	if manager:
		manager.spawn_child_from_callback(emitter_index, pos, frame)
