class_name ExMateriaEffects
extends RefCounted

## The whole public surface of the addon: one const per public type (annotation,
## `is`, `.new()`, static calls), nothing instantiated - a namespace. A consumer
## may alias a const back to a bare local name (ADR-0211 dec. 4).
## A colliding `class_name` in your project fails THIS addon's parse, pointing at
## a file you did not write - the folder-named façade is the fix (ADR-0212 dec. 1).
## Surface changes are policed symbol-wise, not coupling-wise: `check_lattice_scene.py`
## criterion 4 (path), `check_addon_install.py` axis B (install), the shader
## `#include` channel (ADR-0211 dec. 3, ADR-0212 decs. 4-5).
## vault: .vaults/comments/exmateria_effects/facade-census.md



# --- the file model: what a parsed E###.BIN is -----------------------------

## The parsed effect - emitters, timeline, curves, subsystem keyframes, frameset header.
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")

## One emitter's configuration, pre-converted to Godot units by the parser.
const EffectEmitter = preload("res://addons/exmateria_effects/file_model/EffectEmitter.gd")

## FFT curve data: 160 samples, normalised 0-1, one slot of the ROM's shared 15-slot curve table.
const EffectCurve = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")

## The **curve explode** (ADR-0089 curve-ownership amendment dec. 2): what load
## does to the shared 15-slot table, so editing one emitter's curve cannot
## silently move another's.
const CurveExplode = preload("res://addons/exmateria_effects/file_model/CurveExplode.gd")

## Emitter start/stop timing - when an emitter begins and stops spawning.
const TimelineData = preload("res://addons/exmateria_effects/file_model/TimelineData.gd")

## Parsed palette-subsystem keyframes - channels 0-2 of the ADR-0067 unified colour stack.
const PaletteData = preload("res://addons/exmateria_effects/file_model/PaletteData.gd")

## Parsed screen-subsystem keyframes - the background gradient behind the map.
const ScreenData = preload("res://addons/exmateria_effects/file_model/ScreenData.gd")

## Parsed camera-subsystem keyframes - angle, position and zoom.
const CameraData = preload("res://addons/exmateria_effects/file_model/CameraData.gd")

## The RGBA TGA codec the BIN's texture section decodes to and encodes from -
## dependency-free, no `res://` paths, no ExMateria coupling. Published because
## `3c6c3941a` moved it here ON THE ARGUMENT that `file_model/` owns both directions
## of the E###.BIN format, and the façade is how that model is exposed: its eight host
## callers were left naming `file_model/TextureTga.gd` by path, which is criterion 4
## debt (ADR-0205). Publishing pays all eight at once (#1565).
const TextureTga = preload("res://addons/exmateria_effects/file_model/TextureTga.gd")


# --- the cast: an effect while it is running -------------------------------

## One running effect - manager, renderer, subsystems, controls, as a `Node3D`
## you add to a scene.
const EffectInstance = preload("res://addons/exmateria_effects/cast/EffectInstance.gd")

## Which E###.BIN fields each callback id DECLARES - the schema the studio reads to badge
## callback-backed spans. Published rather than booked as debt (#1573): its only consumers
## outside this addon are `src/effects/studio/EffectScoreModel.gd` and `EmitterProjector.gd`,
## PRODUCTION host files, and `src/effects/studio/` is a permanent declared `stays` for
## extraction #7 (ADR-0286 dec. 4) - so this is a host consumer naming an addon type
## forever, which is exactly what a façade const is for, not a test poking an internal.
const CallbackSchemaRegistry = preload("res://addons/exmateria_effects/callbacks/CallbackSchemaRegistry.gd")

## Content-root resolution for callers initializing EffectInstance. Host use:
## the in-addon `cast/EffectManager.gd` (spell/cinematic/item spawn) and the
## Effect Studio's `src/effects/studio/EffectStudioPaths.gd` (#1391).
const EffectsContent = preload("res://addons/exmateria_effects/install/EffectsContent.gd")

## Per-battle scene, live actor slots and optional cast context.
## Host use: `src/gpu/CombatCastHost.gd` extends it to translate the game's state.
const CastHost = preload("res://addons/exmateria_effects/install/CastHost.gd")

## The addon's whole ability vocabulary, self-contained since ADR-0364 cut the
## `exmateria_almanac` dep — what `CastHost.ability_visual()` answers.
## Host use: `src/gpu/CombatCastHost.gd` builds one per lookup out of the
## almanac's `AbilityView`.
const AbilityVisual = preload("res://addons/exmateria_effects/cast/AbilityVisual.gd")

## The ability SEQUENCE PLAN — which parts of an ability play, in what order, for a
## caster/target pair: the Chemist hand-over/throw selector, whether 0xD9 launches a
## projectile, and when the held E### is released (ITEM_USE_EXECUTION.md §5-§7).
## Host use: `src/gpu/CombatLoop.gd` (item routing) and `src/scenes/EffectViewerScene.gd`
## (the ability stage).
const AbilitySequence = preload("res://addons/exmateria_effects/cast/AbilitySequence.gd")

## Spell, trap, item and charge-VFX spawning, cleanup polling and the cast
## lifecycle (ADR-0018). The battle context
## arrives as a `CastHost`; the host's stage, roster and logging never enter
## the addon as game types.
## Host use: `src/gpu/CombatLoop.gd` binds it as `EffectManagerClass` and owns
## the only production instance, constructed over `CombatCastHost`.
const EffectManager = preload("res://addons/exmateria_effects/cast/EffectManager.gd")

## The timeline phase constants - `FOR_EACH`, the wind-down, and the execution
## model every subsystem keys its channels by.
const EffectPhase = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")

## The effect clock - fixed 30 Hz frames under the time-scale pacing curve. Hosts read
## `paced_vsyncs` to size a window on the effect's own clock (the kernel's cinematic timer).
const EffectTimeline = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")

## The **derived effect end** - the frame the real engine would REAP the cast,
## which is NOT the last authored keyframe.
const EffectEndModel = preload("res://addons/exmateria_effects/cast/EffectEndModel.gd")


# --- the subsystems: the four channel runtimes -----------------------------

## Runtime processor for palette-subsystem keyframes - map and unit tinting.
## No production namer today: test-only host use is a real host use (ADR-0211 dec. 5).
const PaletteSubsystem = preload("res://addons/exmateria_effects/subsystem/PaletteSubsystem.gd")

## Runtime processor for the SCREEN channel - the background gradient,
## mirroring the PSX applier `FUN_80090258 @0x80090258`.
## No production namer today: test-only tests plus the exmateria_schema façade
## as sibling (ADR-0212 dec. 7).
const ScreenSubsystem = preload("res://addons/exmateria_effects/subsystem/ScreenSubsystem.gd")

## Runtime processor for the CAMERA channel - angle / position / zoom keyframes
## (`advance_camera_tracks` 0x801ad198). No production namer outside the addon: test-only
## host use (`CinematicPacedLengthTest`, N18) is a real host use (ADR-0211 dec. 5).
const CameraSubsystem = preload("res://addons/exmateria_effects/subsystem/CameraSubsystem.gd")

## One phase's worth of cursor + channel state for a subsystem.
## No outside code namer: the surface's counted reach was a `PhaseBlock` in a
## host docstring - the 21st row (ADR-0295 dec. 1).
const PhaseBlock = preload("res://addons/exmateria_effects/subsystem/PhaseBlock.gd")


# --- the render path -------------------------------------------------------

## The live engine-fold combat compositor - Forward+ only, the display-space
## compositor.
const EngineFoldCompositor = preload("res://addons/exmateria_effects/render/EngineFoldCompositor.gd")

## The render ROUTER, this addon's fourth autoload since #1453. It probes the
## build, derives the route, keeps the compositor pinned to the live camera
## across scene changes, and owns the comparison override. Published because a
## HOST TEST names it: `tests/EffectParticleOffForkRouteTest.gd` stands one up to
## drive `_route_native` and `set_native_blend` across states the live autoload
## cannot be put into. Eight other sites reach the same node by NODE path and
## needed nothing here, which is also why the move kept the name (ADR-0349 dec. 8).
## Host use: `tests/EffectParticleOffForkRouteTest.gd` constructs one per section.
const CompositorAutopilot = preload("res://addons/exmateria_effects/render/CompositorAutopilot.gd")

## The transparent-prim staging every display-space compositor producer shares.
## Outside reach is one in-addon test namer - whether the surface reads 20 or 21
## is ADR-0295 dec. 1's call.
const UnifiedPrimStager = preload("res://addons/exmateria_effects/render/UnifiedPrimStager.gd")


# --- the TRAP family -------------------------------------------------------

## A TRAP handler lifted into E### form, in memory (ADR-0369): the EffectData the
## ordinary runtime and the Effect Studio open as a `TRAP_*` document.
const TrapLift = preload("res://addons/exmateria_effects/trap/TrapLift.gd")


# --- the cinematic camera --------------------------------------------------

## Resolves the effect camera's base YAW so the focused unit is not hidden -
## the Godot heir to the ROM's `calc_facing_angles` (`0x801aac28`).
const CinematicFacingResolver = preload("res://addons/exmateria_effects/camera/CinematicFacingResolver.gd")
