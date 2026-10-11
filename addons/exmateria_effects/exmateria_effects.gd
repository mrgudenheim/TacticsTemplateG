class_name ExMateriaEffects
extends RefCounted

## The whole public surface of `addons/exmateria_effects` - the only name it
## puts in your project. A constant is a full type (annotation, `is`, `.new()`,
## static calls); a consumer may alias one back to a bare local name
## (ADR-0211 dec. 4), which keeps every use site spelled as it was.
## Nothing here is instantiated: a namespace, not an object.
## 🔴 A colliding `class_name` fails the ADDON's parse, pointing at a file you
## did not write - the folder-named façade is the fix, not a count (ADR-0212 dec. 1).
## 🔴 SYMBOL surface, not coupling surface (ADR-0211 dec. 3, ADR-0212 dec. 4):
## path channel = `check_lattice_scene.py` criterion 4, install channel =
## `check_addon_install.py` axis B, the shader `#include` channel moves no names
## (ADR-0212 dec. 5). The census, the namers and the open 20-vs-21 question live
## in the vault, not here.
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


# --- the cast: an effect while it is running -------------------------------

## One running effect - manager, renderer, subsystems, controls, as a `Node3D`
## you add to a scene.
const EffectInstance = preload("res://addons/exmateria_effects/cast/EffectInstance.gd")

## Content-root resolution for callers initializing EffectInstance. Host use:
## the in-addon `cast/EffectManager.gd` (spell/cinematic/item spawn) and the
## Effect Studio's `src/effects/studio/EffectStudioPaths.gd` (#1391).
const EffectsContent = preload("res://addons/exmateria_effects/install/EffectsContent.gd")

## Per-battle scene, live actor slots and optional cast context.
## Host use: `src/gpu/CombatCastHost.gd` extends it to translate the game's state.
const CastHost = preload("res://addons/exmateria_effects/install/CastHost.gd")

## What the addon needs to know about an ability to pick its visuals — the whole
## answer to `CastHost.ability_visual()`, and the addon's entire ability
## vocabulary since ADR-0364 cut the `exmateria_almanac` dep.
## Host use: `src/gpu/CombatCastHost.gd` builds one per lookup out of the
## almanac's `AbilityView`.
const AbilityVisual = preload("res://addons/exmateria_effects/cast/AbilityVisual.gd")

## Spell, trap, item and charge-VFX spawning, cleanup polling and the cast
## lifecycle — extracted from the combat loop at ADR-0018. The battle context
## arrives as a `CastHost`; the host's stage, roster and logging never enter
## the addon as game types.
## Host use: `src/gpu/CombatLoop.gd` binds it as `EffectManagerClass` and owns
## the only production instance, constructed over `CombatCastHost`.
const EffectManager = preload("res://addons/exmateria_effects/cast/EffectManager.gd")

## The timeline phase constants - `FOR_EACH`, the wind-down, and the execution
## model every subsystem keys its channels by.
const EffectPhase = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")

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

## One phase's worth of cursor + channel state for a subsystem.
## 🔴 No outside namer today: the move's counted reach was a `PhaseBlock` in a
## host DOCSTRING, not code - the surface's 21st row (ADR-0295 dec. 1).
const PhaseBlock = preload("res://addons/exmateria_effects/subsystem/PhaseBlock.gd")


# --- the render path -------------------------------------------------------

## The live engine-fold combat compositor - Forward+ only, the only
## display-space compositor since the raw-RD GLSL one was retired.
const EngineFoldCompositor = preload("res://addons/exmateria_effects/render/EngineFoldCompositor.gd")

## The transparent-prim staging every display-space compositor producer shares.
## 🔴 Outside reach is comments in sibling compositors plus one in-addon test
## namer - whether the surface reads 20 or 21 is ADR-0295 dec. 1's call.
const UnifiedPrimStager = preload("res://addons/exmateria_effects/render/UnifiedPrimStager.gd")


# --- the TRAP family -------------------------------------------------------

## The TRAP particle system - hit clouds, charge particles, sprite effects,
## with the PSX particle physics.
const TrapEffect = preload("res://addons/exmateria_effects/trap/TrapEffect.gd")

## Spell charge lines (PSX TRAP handler 4) - a ring contracting toward the
## caster's head.
const TrapChargeLineEffect = preload("res://addons/exmateria_effects/trap/TrapChargeLineEffect.gd")

## The orbital summon orb (PSX TRAP handler 22) - three concentric rings of
## ten particles orbiting the caster.
const TrapOrbitalEffect = preload("res://addons/exmateria_effects/trap/TrapOrbitalEffect.gd")


# --- the cinematic camera --------------------------------------------------

## Resolves the effect camera's base YAW so the focused unit is not hidden -
## the Godot heir to the ROM's `calc_facing_angles` (`0x801aac28`).
const CinematicFacingResolver = preload("res://addons/exmateria_effects/camera/CinematicFacingResolver.gd")
