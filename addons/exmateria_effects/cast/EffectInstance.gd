@tool
extends Node3D
## Reusable wrapper for a single effect with its own manager, renderer, and controls
## Vault: [[Effect Camera System]]
## Vault: [[Effect Execution Model]]
## Vault: [[Effect Frame Pacing]]
## Vault: [[Embedded MIPS Effect Code]]
## Vault: [[Transformed Pose System]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const ParticleSubsystem = preload("res://addons/exmateria_effects/subsystem/ParticleSubsystem.gd")
const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")

## ADR-0212 dec. 1 — alias a published member back so every use site stays
## spelled the way it was (ADR-0211 dec. 4).
const PsxChirality = ExMateriaPlatform.PsxChirality

## The battle effect-SFX engine, reached through the platform PORT instead of the
## host's `ExMateriaEffectSfx` autoload identifier (ADR-0308 dec. 1). The two
## overlay ports below differ: a node-path bind is free only when the autoload
## points at a script THIS addon ships. `ExMateriaEffectSfx` lives in
## `addons/exmateria_sound/`, which this addon does not ship, and a node path
## there would only swap a parse error for a silent null (ADR-0139 dec. 9/12).
## `SfxPort`'s not-ready answers are the engine's own; `_sfx_token == 0` is
## this file's "no cast".
const SfxPort = ExMateriaPlatform.SfxPort


const EffectParticleRendererClass = preload("res://addons/exmateria_effects/render/EffectParticleRenderer.gd")
const ScreenSubsystemClass = preload("res://addons/exmateria_effects/subsystem/ScreenSubsystem.gd")
const PaletteSubsystemClass = preload("res://addons/exmateria_effects/subsystem/PaletteSubsystem.gd")
const CallbackManagerClass = preload("res://addons/exmateria_effects/callbacks/CallbackManager.gd")

## The render ROUTE, through a port rather than a bare autoload identifier — the same ruling the two
## overlay ports below carry (ADR-0308 dec. 1), and the reason this file can name the router at all.
## Its absent answer is the build fact, so a consumer with the addon and no router still gets the
## right side (ADR-0349 dec. 3).
const RoutePort = preload("res://addons/exmateria_effects/install/RoutePort.gd")
const CameraSubsystemClass = preload("res://addons/exmateria_effects/subsystem/CameraSubsystem.gd")
const EffectSoundControllerClass = ExMateriaPlatform.EffectSoundController
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const EffectEndModelClass = preload("res://addons/exmateria_effects/cast/EffectEndModel.gd")
const SoundSubsystemClass = preload("res://addons/exmateria_effects/subsystem/SoundSubsystem.gd")
const EffectSoundScheduleClass = preload("res://addons/exmateria_effects/cast/EffectSoundSchedule.gd")
const EffectSoundResolverClass = ExMateriaPlatform.EffectSoundResolver

## This addon's two overlay autoloads, reached through their PORTS: both point at
## scripts THIS addon ships, so the node-path bind inside them is free (ADR-0308
## dec. 1; contrast `SfxPort` above, whose target the addon does not ship).
const TintedSurfacesPort = preload("res://addons/exmateria_effects/install/TintedSurfacesPort.gd")
const ScreenOverlayPort = preload("res://addons/exmateria_effects/install/ScreenOverlayPort.gd")

signal emitter_started(effect_name: String, emitter_idx: int, channel_idx: int, frame: int)
signal emitter_stopped(effect_name: String, emitter_idx: int, channel_idx: int, frame: int)

signal ability_react_triggered(frame: int)
signal hit_reaction_triggered(frame: int)
signal refresh_tile_triggered(frame: int)
signal camera_started()
signal camera_finished()
## A held effect started playing (`play_held()`). ITEM_USE_EXECUTION.md §6: the PSX
## `effect_system_state` 1 -> 2 edge.
signal released()

const ACTION_FLAG_ABILITY_REACT = 0x0040  # Bit 6 - play reaction animation
const ACTION_FLAG_HIT_REACTION = 0x0010   # Bit 4 - apply damage, show popups
const ACTION_FLAG_REFRESH_TILE = 0x0020   # Bit 5 - end reaction, refresh state
const ACTION_FLAG_CASTER_SLOT = 0x0008    # Bit 3 - act on the caster slot, not the targets

## Which units an action keyframe (0x40 / 0x20) applies to — `action_scope()`.
enum ActionScope {
	ALL_TARGETS,  ## every target at once (outer-phase lane, 0x08 clear)
	PER_TARGET,   ## one target per for_each child, each on its own beat (0x08 clear)
	CASTER,       ## the caster slot alone (0x08 set, either lane)
}

## The phase lane (EffectPhase.*) and the flags of the latest action-flag keyframe, set
## before its emits.
var _action_lane: String = ""
var _action_flags: int = 0

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

# HELD: loaded but not playing — PSX `effect_system_state` 1 (ITEM_USE_EXECUTION.md
# §6). Set BEFORE initialize(); the instance then loads its data, textures and
# subsystems but starts no clock, arms no sound and claims no camera until
# play_held(). Released, it is indistinguishable from an instance spawned unheld, so
# the camera snapshot a host takes on camera_started is the camera AT RELEASE —
# the SLOT_COPY source PSX takes two loops after release (§4.5).
var held: bool = false
var _has_timeline: bool = false

var effect_name: String = ""

# Per-instance RNG (ADR-0070). Seeded once at spawn from fresh entropy and
# re-applied on every reset() (loop restart / backward seek) by the timeline,
# so in-instance replay is bit-identical while each new cast still varies.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_seed: int = 0

# Parked/scrub mode (Effect Studio, ADR-0069/0070). When true, _process stops
# pumping wall-clock time — the frame only advances via seek(), so the preview
# holds a parked frame until the Studio scrubs it. Default false = normal
# gameplay/combat playback.
var playback_paused: bool = false

var auto_loop: bool = true             # Auto-restart when loop_frames reached
var loop_frames: int = 300             # Frames until loop (default ~10s at 30fps)

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
var _sfx_token: int = 0         # baked-SFX cast token (for end_effect)
## This effect's id (`E117`), taken from `data_path` at initialize. The audible path
## addresses the baked corpus with it; no bank is parsed to make a sound.
var _effect_id: String = ""
# The for_each LANES the host asked for (N36; `set_for_each_lanes`): one unit per target in
# the host's hit-stamp order and each lane's start, in frames after phase 1 (lane 0's = 0).
# Empty = the single-target document. `_lane_count` is what initialize() granted.
var _lane_units: Array = []   # WeakRef per lane
var _lane_offsets: PackedInt32Array = PackedInt32Array()
var _lane_count: int = 1

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
	# They are exempt from the CINEMATIC axis only: `cinematic_visuals` is the group a host's
	# stop still freezes them by (a Space stop inside a cinematic halts its effect too, N37).
	if not Engine.is_editor_hint():
		add_to_group("cinematic_visuals" if is_cinematic else "combat_visuals")
	if effect_path != "":
		var path_name = effect_path.get_file()
		if path_name == "":
			path_name = effect_path.trim_suffix("/").get_file()
		initialize(path_name, effect_path, Vector3.ZERO, pool_size)


func _exit_tree() -> void:
	"""Clean up screen, map, and sound effects when removed from scene"""
	if _origin_anchor and is_instance_valid(_origin_anchor) and _origin_anchor.is_inside_tree():
		_origin_anchor.queue_free()
	_origin_anchor = null
	if _target_anchor and is_instance_valid(_target_anchor) and _target_anchor.is_inside_tree():
		_target_anchor.queue_free()
	_target_anchor = null

	if sprite_renderer and sprite_renderer.has_method("release_pool_meshes"):
		sprite_renderer.release_pool_meshes()

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

	if callback_manager and callback_manager.child_spawn_requested.is_connected(_on_callback_child_spawn):
		callback_manager.child_spawn_requested.disconnect(_on_callback_child_spawn)
	if manager:
		manager.callback_manager = null

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
	if screen_controller and not Engine.is_editor_hint():
		ScreenOverlayPort.remove_layer(screen_controller.get_owner_id())
	if palette_controller and not Engine.is_editor_hint():
		TintedSurfacesPort.remove_layer(TintedSurfacesPort.SURFACE_MAP, palette_controller.get_owner_id())
		TintedSurfacesPort.remove_all_layers_for_owner(palette_controller.get_owner_id())

	if sprite_renderer and sprite_renderer.has_method("release_pool_meshes"):
		sprite_renderer.release_pool_meshes()

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
	if _origin_anchor and is_instance_valid(_origin_anchor):
		_origin_anchor.queue_free()
	_origin_anchor = null
	if _target_anchor and is_instance_valid(_target_anchor):
		_target_anchor.queue_free()
	_target_anchor = null

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
	var data := EffectData.load_from_directory(data_path)
	if data == null:
		push_error("EffectInstance [%s]: Failed to load effect data from %s" % [name, data_path])
		return false
	# The effect's ID, free from the path we were handed. THIS is what the audible path
	# needs now: a baked render is addressed by name, not by a parsed opcode bank, so the
	# play path does no parsing at all. `res://assets/effects/E117` -> `E117`.
	return initialize_from_data(name, data, anchor, init_pool_size, data_path.get_file())


func initialize_from_data(name: String, data: EffectData, anchor: Vector3,
		init_pool_size: int = 512, effect_id: String = "") -> bool:
	"""Initialize from an EffectData already in memory — the seam for a document with
	no E### directory (a TRAP handler lifted into E### form, ADR-0369). `effect_id`
	addresses the baked SFX corpus; an id with no baked pairs plays silent."""
	effect_name = name

	# Seed the per-instance RNG (ADR-0070) from fresh entropy, then capture that
	# seed so reset() can re-apply it for deterministic in-instance replay. Each
	# new cast gets a different seed, so gameplay still varies cast-to-cast.
	_rng.randomize()
	_rng_seed = _rng.seed

	_effect_id = effect_id if not effect_id.is_empty() else data.name
	effect_data = data

	if EffectsDebug.iteration():
		print("EffectInstance [%s]: Loaded %d emitters, %d curves" % [
			name, effect_data.emitters.size(), effect_data.curves.size()
		])

	manager = ParticleSubsystem.new()
	manager.rng = _rng  # per-instance RNG (ADR-0070) — set BEFORE initialize forwards it to physics
	manager.initialize(effect_data, init_pool_size)

	manager.set_anchors(
		Vector3.ZERO,  # world
		Vector3.ZERO,  # cursor
		Vector3.ZERO,  # origin
		anchor         # target
	)
	_lane_count = 1
	if _lane_offsets.size() > 1 and spawns_for_each_children(data):
		manager.set_for_each_lanes(_lane_offsets)
		_lane_count = manager.for_each_lane_count()
	# Phase 2 opens after the LAST lane starts (0x801A4838), so every clock shifts by it.
	var lane_shift: int = _lane_offsets[_lane_count - 1] if _lane_count > 1 else 0

	# Initialize CAMERA anchor from map center
	# PSX: get_camera_position() returns map dimensions, * 14 = map center
	# CAMERA anchor and EFFECT_CTR both resolve to the same world position
	var cam_anchor = map_center_godot - global_position
	cam_anchor.y = -global_position.y  # Cancel effect Y so particle Y = purely emitter offset
	manager.anchor_camera = cam_anchor

	sprite_renderer = EffectParticleRendererClass.new()
	sprite_renderer.initialize(effect_data, init_pool_size)
	add_child(sprite_renderer)

	manager.emitter_started.connect(_on_timeline_emitter_started)
	manager.emitter_stopped.connect(_on_timeline_emitter_stopped)
	manager.action_flags_triggered.connect(_on_action_flags_triggered)
	var has_timeline := manager.phase1_block != null \
		or manager.phase2_block != null \
		or manager.for_each_block != null

	# ADR-0012: every real effect is timeline-driven (timeline-less = 0-byte
	# empty slots); `has_timeline` decides whether the timeline starts ticking.

	if not effect_data.callback_slots.is_empty():
		callback_manager = CallbackManagerClass.new()
		# ONE read of the route per cast (ADR-0349 dec. 2), here, at the top of the cast — not per
		# callback and not per frame. Every callback in this cast then draws on the same side as the
		# particle producer for the cast's whole lifetime, which is the property that was missing:
		# `EngineFoldCompositor` routed on the autopilot's `native_blend` while each callback took its
		# own `Fold.owns()`, so with the comparison override on, one frame carried both.
		callback_manager.rng = _rng
		callback_manager.initialize(effect_data, effect_data.callback_slots, RoutePort.is_native())
		callback_manager.child_spawn_requested.connect(_on_callback_child_spawn)
		add_child(callback_manager)
		manager.callback_manager = callback_manager
		callback_manager.set_particle_host(manager)

	if effect_data.screen and not Engine.is_editor_hint():
		screen_controller = ScreenSubsystemClass.new()
		# Pass the map's default gradient TOP + BOTTOM baselines (the ColorStack folds
		# each separately — the screen is a gradient, not a flat tint). Phase boundaries
		# are not passed: the timeline resolves the phase and hands it to advance().
		screen_controller.initialize(effect_data.screen,
			ScreenOverlayPort.get_default_top(), ScreenOverlayPort.get_default_bottom())

	if effect_data.palette and not Engine.is_editor_hint():
		palette_controller = PaletteSubsystemClass.new()
		palette_controller.initialize(effect_data.palette)
		# Forward any already-set unit targets so palette self-delivers unit tints
		# (ADR-0014). set_unit_targets() covers the reverse order.
		var _c = caster_unit.get_ref() if caster_unit else null
		var _t = target_unit.get_ref() if target_unit else null
		if _c or _t:
			palette_controller.set_units(_c, _t)

	if effect_data.camera and effect_data.camera.has_active_keyframes() and not Engine.is_editor_hint():
		camera_controller = CameraSubsystemClass.new()
		camera_controller.rng = _rng  # deterministic camera shake for scrub (ADR-0070)
		var cam_p1_dur = 0
		var cam_spawn_delay = 0
		var cam_p2_delay = 0
		if effect_data.timeline:
			cam_p1_dur = effect_data.timeline.phase1_duration
			cam_spawn_delay = effect_data.timeline.spawn_delay
			cam_p2_delay = effect_data.timeline.phase2_delay
		# The hit counter is the target table's size: every unit the cast hits, whether or not
		# this document fans its PARTICLES out per target (the camera search, 0x801ACB08, walks
		# the table either way). The camera's windows are spawn_delay apart, as the ROM's are;
		# the particle lanes are the kernel's stride apart (#1753).
		camera_controller.initialize(effect_data.camera, cam_p1_dur, cam_spawn_delay, cam_p2_delay,
			maxi(1, _lane_units.size()))
		camera_controller.map_center = PsxChirality.godot_position_to_psx(map_center_godot)
		camera_controller.target_position = camera_controller.world_position_to_psx(anchor)
		camera_controller.cursor_position = camera_controller.world_position_to_psx(anchor)
		camera_controller.caster_position = camera_controller.world_position_to_psx(anchor)
		if not held:
			camera_started.emit()

	# Initialize timeline-driven effect sound (FEDS). Runtime-only — never
	# synthesize audio in the editor preview, and ExMateriaEffectSfx is not a @tool
	# autoload. A held effect arms it at play_held(): `SfxPort.begin_effect()` ends
	# whatever cast is sounding, and a held effect is not sounding yet.
	if not Engine.is_editor_hint() and not held:
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
		_p2s = _p1d + effect_data.timeline.phase2_delay + lane_shift
	effect_timeline.setup(_p1d, _p2s, effect_data.time_scale)
	# Register the per-instance RNG so the timeline re-seeds it on reset() /
	# backward seek — the deterministic-replay contract (ADR-0070).
	effect_timeline.set_rng(_rng, _rng_seed)
	if _sound_controller:
		_sound_subsystem = SoundSubsystemClass.new(_sound_controller)
	effect_timeline.set_subsystems(
		[manager, _sound_subsystem, screen_controller, palette_controller, camera_controller])
	manager.timeline = effect_timeline  # back-ref for phase boundary reads (#30)
	_has_timeline = has_timeline
	if has_timeline and not held:
		effect_timeline.start()

	return true


func is_held() -> bool:
	return held


## Start a HELD effect (PSX `effect_release_held`, `effect_system_state` 1 -> 2): arm its
## sound, hand its camera to the host (camera_started), start its clock, and emit
## `released`. A no-op on an effect that is not held. Not `release()`, which ENDS a
## kept-open TRAP charge (ADR-0369) — the opposite edge.
func play_held() -> void:
	if not held:
		return
	held = false
	if not Engine.is_editor_hint():
		_load_effect_sound()
	if camera_controller:
		camera_started.emit()
	if _has_timeline and effect_timeline:
		effect_timeline.start()
	released.emit()


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
			_start_sound_walk()
		else:
			_sound_controller = null


## Start the sound walk: one for_each context per lane, each on its lane's offset, so every
## target hears its own for_each sounds (N36). pre_anchor_offset = 0 and vm_snapshot = {} are
## PCSX parity-calibration inputs that default to faithful in-game behaviour.
func _start_sound_walk() -> void:
	var offsets := _lane_offsets.slice(0, _lane_count) if _lane_count > 1 else PackedInt32Array()
	_sound_controller.start(_lane_count, 0, {}, offsets)


## Give the document one for_each LANE per target (N36): `units` in the host's hit-stamp
## order (the kernel's; the ROM's target-table order is not verified), `offsets` each lane's start in frames after phase 1, lane 0's
## 0 — the stride the kernel stamps the targets' hits with. Call BEFORE initialize(). The ROM
## plays the for_each phase once per target: `outer_phases_timeline_tick` (0x801A4838) spawns
## a child per target-table entry (0x801BAD10), and each child runs
## `for_each_phase_timeline_tick` (0x801A3408) on its own slot (ctx+0x26) — its emitters,
## its sounds, its keyframe actions. Only a document whose root spawns children (opcode 41)
## fans out; an opcode-40 root plays its one lane (`spawns_for_each_children`).
##
## Lane k's particles anchor at `units[k]`; its for_each sounds play on its offset; its
## ACTION keyframes (0x10 / 0x20 / 0x40) stay lane 0's to emit — the host fans them out to
## every hit unit on the kernel's own clock (CombatLoop._fan_out), so each lands on its
## target's stamp without a second copy.
func set_for_each_lanes(units: Array, offsets: PackedInt32Array) -> void:
	_lane_units.clear()
	for u in units:
		_lane_units.append(weakref(u) if u != null else null)
	_lane_offsets = offsets.duplicate()


## The for_each lanes this document plays (1 unless the host fanned it out).
func for_each_lane_count() -> int:
	return _lane_count


## True when `data`'s root spawns a for_each child per target: its script runs opcode 41
## (`outer_phases_timeline_tick` 0x801A4838, the spawner). An opcode-40 root runs the for_each
## tick itself, on one slot.
static func spawns_for_each_children(data) -> bool:
	for op in data.script_ops:
		if op is Dictionary and int(op.get("opcode", -1)) == 41:
			return true
	return false


func _on_sound_event(_frame: int, from_phase: String, from_channel: int,
		sound_id: int) -> void:
	"""A scheduled sound fired: dispatch it as a FEDS pair through the persistent SFX
	engine, IF there is a bank. sound_id is the resolver's output (the value
	the sequencer wanted for the chan+0x92 static seed, retired with it); see
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
	if _effect_id.is_empty():
		return
	# The bounds test the walker used to make, asked of the BAKED MANIFEST rather than of
	# a parsed header's `num_pairs`. Same purpose — keep a legitimate "this effect has no
	# bytes for that id" silent instead of console noise on every fire — but it now asks
	# what is actually playable rather than what a bank declares.
	var pair_idx: int = sound_id - 1
	if pair_idx < 0 or not SfxPort.has_pair(_effect_id, pair_idx):
		return
	SfxPort.play_pair(_sfx_token, _effect_id, pair_idx, sound_id)


## The FEDS bank the audible path must use: `EffectData`'s when there is one, else the
## schedule's captured one. Read at PLAY time, never cached: a same-size byte patch
## reaches the edited bytes through either name, but a structural edit (insert /
## delete / paint / drag / undo, …) REPLACES `data.feds_bank` with a fresh object
## (that is what makes the snapshot undo exact, ADR-0085) — a captured handle would
## keep the old bank. Read through `effect_data` at fire time, whatever the editor
## holds now is what sounds.
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
	if _effect_id.is_empty() or _sound_loaded == null:
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
		if resolved > 0 and pair_idx >= 0 and SfxPort.has_pair(_effect_id, pair_idx):
			SfxPort.play_pair(tok, _effect_id, pair_idx, resolved)
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
	if _effect_id.is_empty():
		return
	var pair_idx := resolved - 1
	if resolved > 0 and pair_idx >= 0 and SfxPort.has_pair(_effect_id, pair_idx):
		var tok: int = SfxPort.begin_effect()
		SfxPort.play_pair(tok, _effect_id, pair_idx, resolved)
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

	if _origin_anchor and is_instance_valid(_origin_anchor) and _target_anchor and is_instance_valid(_target_anchor):
		var origin_offset = _origin_anchor.global_position - global_position
		var target_offset = _target_anchor.global_position - global_position
		manager.set_anchors(target_offset, target_offset, origin_offset, target_offset)
		var cam_anchor = map_center_godot - global_position
		cam_anchor.y = -global_position.y  # Cancel effect Y so particle Y = purely emitter offset
		manager.anchor_camera = cam_anchor
		for emitter in manager.active_emitters:
			emitter.anchor_camera = cam_anchor
	_push_lane_targets()

	# Set camera anchors before pumping — the camera subsystem reads them in advance().
	if camera_controller:
		if _target_anchor and is_instance_valid(_target_anchor):
			var target_psx = camera_controller.world_position_to_psx(_target_anchor.global_position)
			camera_controller.target_position = target_psx
			camera_controller.cursor_position = target_psx
		if _origin_anchor and is_instance_valid(_origin_anchor):
			camera_controller.caster_position = camera_controller.world_position_to_psx(_origin_anchor.global_position)

	# Pump the timeline: it owns the clock + fixed accumulator and advances every
	# subsystem (particle → sound → color → camera) per fixed 30 Hz frame (ADR-0012).
	# Parked (Effect Studio scrub, ADR-0070): skip the wall-clock pump so the frame
	# only advances via seek(); still fall through to render the parked frame.
	if not playback_paused:
		effect_timeline.tick(delta)

	if callback_manager:
		callback_manager.update_anchors(
			manager.anchor_origin, manager.anchor_target,
			manager.anchor_world, manager.anchor_cursor,
			manager.caster_facing_angle)
		callback_manager.update_render()


	# Check for auto-loop (never while parked — the Studio owns the frame via seek)
	if not playback_paused and auto_loop and loop_frames > 0 and effect_timeline.effect_frame >= loop_frames:
		reset()
		return

	if _perf_enabled:
		_tp1 = Time.get_ticks_usec()

	# Color subsystems self-deliver their overlays inside advance() (ADR-0014).


	if _perf_enabled:
		_tp2 = Time.get_ticks_usec()

	# Pass Particles directly: frameset_idx + depth_mode live on each Particle
	# (written by ParticleAnimator.tick()), so no manager handle is needed.
	if sprite_renderer:
		sprite_renderer._effect_world_origin = global_position
		sprite_renderer.sprite_zoom_q12 = camera_controller.sprite_zoom_q12 if camera_controller else 4096.0
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


## Apply the Effect Studio Solo/Mute selection (debug-only). `audibility` is the whole
## EffectScoreModel.resolve_audibility result: `disabled_emitters` (particles, per-emitter
## render-skip) plus the per-lane exclusion filters `muted_screen` / `muted_palette`
## (routed to the subsystems) and `muted_sound` (applied per-channel at the trigger).
## Camera is display-only (no mute). The runtime never calls this — only the Studio host.
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


func release() -> void:
	"""End a HELD effect — a TRAP charge the game keeps open until the cast ends (ADR-0369):
	stop every timeline channel and put the callbacks into their fade. Live particles
	finish their lives; is_finished() turns true once everything is gone."""
	if manager:
		manager.stop_spawning()
	if callback_manager:
		callback_manager.release_all()


func is_finished() -> bool:
	"""The cast is over — the engine's REAP, EffectEndModel's rule. A 3-phase root (one
	that branches on opcode 30, 0x801A2C7C) stays in its opcode-41 loop until the ROM
	timeline bound T, and its camera plays to T, however early its particles die (E005:
	gone ~f128-139, T = 140); only then is it done, once past the last spawn with no
	particle and no active callback. Any other root keeps the quiescence answer: timeline
	over (or released), no particle, no active callback (ParticleSubsystem.is_quiescent)."""
	if manager == null:
		return true
	var bound := timeline_bound()
	if bound <= 0:
		return manager.is_quiescent()
	var frame := get_effect_frame()
	if frame < bound:
		return false
	if callback_manager and callback_manager.has_active_callbacks():
		return false
	return EffectEndModelClass.settled(manager, frame)


## The ROM timeline bound T of a 3-phase root (EffectEndModel.timeline_bound), 0 for any
## other root.
func timeline_bound() -> int:
	return EffectEndModelClass.timeline_bound(effect_data)


func set_paused(paused: bool) -> void:
	"""Park (true) or run (false) the wall-clock pump. Parked = the frame only
	moves via seek() — the Effect Studio's parked-document / transport model."""
	playback_paused = paused


func seed_rng(seed_value: int) -> void:
	"""Replace the spawn-time entropy seed with `seed_value` and rewind to it (ADR-0070): a
	host that must draw the SAME stream in every process — the Effect Studio's charge dry
	run and its posed playback (N26) — seeds the instance after initialize. The live cast
	keeps its entropy seed, so gameplay still varies cast to cast."""
	_rng_seed = seed_value
	_rng.seed = seed_value
	if effect_timeline:
		effect_timeline.set_rng(_rng, _rng_seed)


func is_timeline_finished() -> bool:
	"""Check if all timeline phases have completed processing."""
	if not manager:
		return true
	if not effect_timeline or not effect_timeline.is_started():
		return true
	if manager.phase1_block and not manager.phase1_block.is_finished():
		return false
	if not manager.for_each_finished():
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
		_start_sound_walk()


## Follow each for_each lane's unit (N36): its emitters anchor at it, live, and the camera's
## ALL_TARGETS source is the centroid of every lane's unit (0x801AB1D4's 0x180 arm averages
## the target table).
func _push_lane_targets() -> void:
	_push_camera_targets()
	if _lane_count <= 1:
		return
	var sum := Vector3.ZERO
	var n := 0
	for k in _lane_count:
		var ref = _lane_units[k] if k < _lane_units.size() else null
		var unit = ref.get_ref() if ref != null else null
		if unit == null or not is_instance_valid(unit):
			continue
		manager.set_lane_target(k, unit.global_position - global_position)
		sum += unit.global_position
		n += 1
	if camera_controller and n > 0:
		camera_controller.all_targets_position = camera_controller.world_position_to_psx(sum / n)


## The camera's target table (gl-ADR-0410): each target's PSX position, so a for_each
## TARGET keyframe found for target k frames unit k.
func _push_camera_targets() -> void:
	if camera_controller == null or _lane_units.size() <= 1:
		return
	var positions: Array = []
	for k in _lane_units.size():
		var ref = _lane_units[k]
		var unit = ref.get_ref() if ref != null else null
		if unit != null and is_instance_valid(unit):
			positions.append(camera_controller.world_position_to_psx(unit.global_position))
		else:
			positions.append(camera_controller.target_position)
	camera_controller.target_positions = positions


## The units of the target table, hit order (the host's lanes; [] for a one-target document).
func lane_units() -> Array:
	var out: Array = []
	for ref in _lane_units:
		out.append(ref.get_ref() if ref != null else null)
	return out


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



func _on_timeline_emitter_started(emitter_idx: int, channel_idx: int, frame: int) -> void:
	"""Re-emit with effect name"""
	emitter_started.emit(effect_name, emitter_idx, channel_idx, frame)



func _on_timeline_emitter_stopped(emitter_idx: int, channel_idx: int, frame: int) -> void:
	"""Re-emit with effect name"""
	emitter_stopped.emit(effect_name, emitter_idx, channel_idx, frame)



## Which units the action keyframe just emitted (ABILITY_REACT 0x40, REFRESH_TILE 0x20)
## applies to. Both ROM dispatchers read bit 0x08 first:
##   * 0x08 set: the CASTER slot alone (0x801BADB0), in either lane —
##     `dispatch_unit_triggers_and_register_callback` (0x801A3D30) and
##     `process_keyframe_actions` (0x801A31A8) both branch on `param_1 & 8`. The Dances
##     (E089-E094) carry 0x28 on phase1: it refreshes the dancer only; each target is
##     refreshed by its own for_each 0x20.
##   * 0x08 clear, for_each lane: once PER TARGET — `for_each_phase_timeline_tick`
##     (0x801A3408) hands its child's own target slot (ctx+0x26) to 0x801A31A8, whose 0x40
##     arm reacts that one unit (`apply_unit_ability_reaction` 0x80068B54) and whose 0x20
##     arm refreshes it (`refresh_unit_tile_state`). The children start `child_spawn_delay`
##     apart, so each target acts on its own beat — the stride the kernel stamps its hits
##     with (for_each_delay).
##   * 0x08 clear, outer-phase lane: 0x801A3D30's 0x40 / 0x20 arms loop the WHOLE target
##     table at 0x801BAD10 — every target on the one frame.
## The document plays one for_each lane per target (`set_for_each_lanes`), but only lane 0
## (the first target's) emits its actions; the host fans them out on the kernel's clock.
func action_scope() -> ActionScope:
	if _action_flags & ACTION_FLAG_CASTER_SLOT:
		return ActionScope.CASTER
	if _action_lane == EffectPhaseClass.PHASE_FOR_EACH:
		return ActionScope.PER_TARGET
	return ActionScope.ALL_TARGETS


func _on_action_flags_triggered(flags: int, _channel_idx: int, frame: int) -> void:
	"""Handle action_flags from timeline keyframes

	Three-stage reaction system:
	- Bit 6 (0x0040) ABILITY_REACT: Play reaction animation (early in effect)
	- Bit 4 (0x0010) HIT_REACT: Apply damage/healing, show popups (when particles "hit")
	- Bit 5 (0x0020) REFRESH_TILE: End reaction animation, refresh unit state
	"""
	# A fanned-out lane k >= 1 plays its target's keyframes, but the actions are lane 0's to
	# emit: the host fans lane 0's out to every hit unit on the kernel's clock (set_for_each_lanes).
	# Returned before the writes below, so action_scope() only ever describes lane 0's keyframe.
	if manager and manager.last_action_lane > 0:
		return
	_action_lane = manager.last_action_phase if manager else ""
	_action_flags = flags
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
