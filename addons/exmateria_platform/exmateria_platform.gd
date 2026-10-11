class_name ExMateriaPlatform
extends RefCounted

## The whole public surface of `addons/exmateria_platform`, and the only name it
## puts in your project.
##
## Godot has no package scope: a `class_name` is engine-global, so every one an
## addon declares lands in YOUR global scope — and when you declare a colliding
## one, the ADDON's file is what fails to parse, pointing your error at a file
## you did not write.
##
## 🔴 THIS ADDON DECLARED `DisplayPort`, WHICH IS THE NAME OF A HARDWARE
## STANDARD. Three bare globals, none brand-prefixed, one of them a word a
## consumer has an ordinary reason to want. That is the collision hazard
## ADR-0211 shed thirty of from `exmateria_battlefield`, and ADR-0212 dec. 1
## rules that the fix is the FOLDER-NAMED façade rather than a count: what makes
## an addon safe is that its surviving name is brand-prefixed and named after its
## folder, not that there happens to be one of it.
##
## A script constant is a full type — annotation, `is` check, `.new()`, and the
## static calls these three are almost entirely made of:
##
##     var facing := ExMateriaPlatform.PsxNum.warp_facing(f)
##
## and a consumer may alias one back to a bare local name, which is what keeps
## every existing use site spelled the way it was (ADR-0211 dec. 4):
##
##     const PsxNum = ExMateriaPlatform.PsxNum
##
## **This list IS the supported surface.** If a script is not named here it is
## internal, whatever its visibility says — `display_port/PSXDisplay.gd` is the
## clearest case: it is the autoload the port half of this addon soft-binds to,
## the HOST registers it in `project.godot [autoload]`, and it declares no
## `class_name` of its own. `tools/check_addon_globals.py` holds both directions:
## nothing else in this addon may declare a global, and nothing named here may
## dangle.
##
## 🔴 THIS IS THE SYMBOL SURFACE, NOT THE COUPLING SURFACE (ADR-0211 dec. 3,
## ADR-0212 dec. 4). On the symbol axis this addon is a COMPLETE CLOSE — zero
## host `.gd` scripts `preload` or `load` a `res://` path into it. That is not
## the same as "nothing depends on it".
##
## 🔴 AND THE SHADER `#include` CHANNEL IS NOT HERE (ADR-0212 dec. 5). Around
## twenty `#include "res://addons/exmateria_platform/…"` lines reach in from the
## host's `assets/shaders/` and from `exmateria_battlefield` — `pixel_aspect`,
## `psx_dither`, `psx_camera_angle`, `psx_sprite_stretch`. A `.gdshaderinc`
## declares no `class_name`, so it carries none of the collision hazard this file
## exists for, and no GDScript constant can route a preprocessor include. Stated
## aloud so the close above is not read wider than the axis it was measured on.
##
## Nothing here is instantiated. `ExMateriaPlatform.new()` gives you an empty
## RefCounted; the class exists to be a namespace, not an object.


# --- the two ports: a signature an installed addon carries -----------------

## The tunable registry's port signature — six verbs (`bind`, `bind_update`,
## `on_update`, `get_value`, `set_value`, `on_any_change`), soft-bound to the
## host's `Tune` autoload by node path at call time, with a defined ABSENT
## behaviour per verb (ADR-0175 dec. 2). An `[autoload]` line can only be written
## by the consuming game's `project.godot`, so this converts a
## host-project-configuration dependency into an addon-presence one.
## Host use, and the heaviest of it is a **SIBLING NAMER**:
## `addons/exmateria_battlefield/overlay/TileOverlayConfig.gd` and
## `addons/exmateria_battlefield/camera/PlayerCamera.gd` bind sixteen tunables
## each; `tests/TunePortTest.gd` drives the absent path.
const TunePort = preload("res://addons/exmateria_platform/tunables/TunePort.gd")

## The display-calibration port signature — `NO_STRETCH` plus the live mirrors an
## addon reads instead of naming the autoload beside it, whose fallbacks are the
## IDENTITY values so a consumer with no calibration gets geometry unmodified
## rather than a `null` in a `maxf` (ADR-0175 dec. 2). It also carries the PSX
## framing geometry that is NOT soft-bound to anything — `NATIVE_VIEWPORT_HEIGHT`
## and `VERTICAL_DATUM_PX`, the 256x240 frame height and FFT's low optical-centre
## datum — because the two rigs that frame a tile sit on opposite sides of the
## host/addon line and this is the only file both may name.
## 🔴 `DisplayPort` IS THE NAME OF A HARDWARE STANDARD, which is the single
## clearest reason this façade exists.
## Host use, and all three live namers are **SIBLING NAMERS**:
## `addons/exmateria_battlefield/cursor/TileCursor.gd` divides one mirror by the
## other, `addons/exmateria_battlefield/camera/PlayerCamera.gd` takes the
## camera-angle push, and `addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd`
## takes the camera-angle READ that #848 added (ADR-0234); `tests/TunePortTest.gd`
## covers the absent path for all four members.
const DisplayPort = preload("res://addons/exmateria_platform/display_port/DisplayPort.gd")

## The gameplay-event port signature — the SUBSCRIBE half of the host's `EventBus`,
## soft-bound by node path like its two siblings above (ADR-0175 dec. 2). Two verbs,
## `connect_unit_hp_changed` and `connect_unit_mp_changed`, added because extraction
## #8's `UIRosterBar` and `UIVitalsRoster` reached for exactly those two signals
## (#1274, ADR-0308 dec. 2).
## 🔴 SUBSCRIBE-ONLY, STATED AS AN ASYMMETRY. `EventBus` also publishes the three
## `emit_*` verbs and `unit_died`; no addon reaches them today so none is on the
## port, and the first addon that wants to RAISE a unit event adds `emit_*` here
## rather than going back to the identifier — which is #590's mistake read forward
## (ADR-0234). The absent branch is SILENCE, the right identity for a subscription:
## a consumer with no event bus gets a roster that still builds and draws.
## Host use: `tests/TunePortTest.gd` drives both the bound and the absent path.
const EventPort = preload("res://addons/exmateria_platform/event_port/EventPort.gd")

## The battle effect-SFX port signature — four verbs (`begin_effect`, `play_pair`,
## `end_effect`, `orphan_effect`), soft-bound to the host's `ExMateriaEffectSfx`
## autoload by node path like its three siblings above (ADR-0175 dec. 2). Added
## because `addons/exmateria_effects/cast/EffectInstance.gd` reached that identifier on
## eleven lines and could not use the node-path remedy its OWN three autoloads use: the
## autoload points into `addons/exmateria_sound/`, a package `Effects` does not ship, so
## arm 2b rules the node path closed to it and names a port as the answer.
## 🔴 THE ABSENT COLUMN IS THE ENGINE'S OWN NOT-READY BEHAVIOUR (`0` / `false` / two
## no-ops), not a degradation this port invented — read the file's header.
## Host use: `tests/TunePortTest.gd` drives both the bound and the absent path. Its only
## production namer is a **sibling namer** (ADR-0212 dec. 7) —
## `addons/exmateria_effects/cast/EffectInstance.gd`, eleven lines — which is a valid
## host use of the port and an ADDON consumer, and the two are staged differently. That
## is not incidental here: this port exists BECAUSE its consumer is an addon, so unlike
## its three siblings it has no host namer at all and is not expected to grow one.
const SfxPort = preload("res://addons/exmateria_platform/sfx_port/SfxPort.gd")

## The EVENT-SOUND router's port signature — seven verbs (`play_cue`,
## `play_system_by_id`, `play_bg`, `set_bg_volume`, `stop_bg_handle`,
## `stop_all_event_sound`, `emit_bg_sound_changed`), soft-bound to the host's
## `SfxRouter` autoload by node path like its siblings above (ADR-0175 dec. 2).
## 🔴 NOT `SfxPort` ABOVE — that one fronts `ExMateriaEffectSfx`, the BATTLE
## effect-SFX engine; this one fronts the EVENT SCRIPT's sound surface, and
## `SfxRouter` itself calls that engine, so this port sits ABOVE it and never beside
## it. The name is the autoload's own precisely because `SfxPort` was taken.
## Added because `addons/exmateria_cutscene` reached that identifier on seven lines
## and could not use the node-path remedy: the host's own `src/audio/SfxRouter` script
## is a HOST path no addon ships, so arm 2b rules the node path closed and names a
## port as the answer — the same finding that put `SfxPort` here.
## 🔴 THE ABSENT COLUMN IS THE ROUTER'S OWN MISS BEHAVIOUR (three `0`s and four
## no-ops), quoted from its own body, and the `0`s CHAIN: `play_bg` answering `0` is
## the handle `set_bg_volume` and `stop_bg_handle` already early-return on, so no call
## site needs a new branch. Read the file's header.
## Host use: `tests/TunePortTest.gd` drives both the bound and the absent path. Like
## `SfxPort` its production namers are **sibling namers** (ADR-0212 dec. 7) —
## `addons/exmateria_cutscene/vm/ScenarioWorld.gd` (six) and
## `dialogue/DialogueOverlay.gd` (one).
const SfxRouterPort = preload("res://addons/exmateria_platform/sfx_router_port/SfxRouterPort.gd")

## The music sequencer's port signature — two verbs (`fade_out`, `switch_track`),
## soft-bound to the host's `MusicPlayer` autoload by node path.
## It ships with `SfxRouterPort` above because the two are ONE reach family:
## `ScenarioWorld.gd:785` names both singletons in one comment and wraps both in one
## block. They are two FILES rather than one `AudioPort` because a two-node port has
## no single answer to "is it bound?", and half-bound is a real state — read the first
## red note in the file's header.
## ⚠️ `src/world_map/WorldMapMusicPort.gd` is a DIFFERENT thing despite the name: a
## host-tier, constructor-injected one-method port for the world-map theme. It stays
## where it is and neither file reaches the other.
## 🔴 BOTH ABSENT ANSWERS ARE `false` BECAUSE THE SEQUENCER'S OWN ARE — `fade_out` is
## documented "No-op (returns false) if nothing is playing"; both call sites are `void`
## and already discard the bool.
## Host use: `tests/TunePortTest.gd` drives both the bound and the absent path.
const MusicPort = preload("res://addons/exmateria_platform/music_port/MusicPort.gd")

## The dialled-in camera mapping: raw PSX zoom (4096 = 1.0×) ↔ Godot orthographic
## size, carrying `GODOT_CAMERA_SIZE = 12.6` — the value that makes PSX FFT tile
## coverage come out right at 4:3. It is HERE and not beside the fixed-point pair
## because that constant is a CALIBRATION, which is precisely what
## `PsxMagnitude` refuses by charter. It arrived from the effects runtime at
## extraction #7 (ADR-0290 dec. 5, #1220) under the name `CameraCalib`: 35 lines, no
## reach into `Effects` at all, so that directory was only ever its address of
## convenience. (The old path is named in the ADR, not here — a dead `src/` path in a
## CITE line is exactly what ADR-0210 dec. 1's rot arm is for, and it caught this row
## while this commit was being written.)
## Host use: `addons/exmateria_cutscene/camera/ScenarioCameraDirector.gd` and
## `addons/exmateria_cutscene/vm/ScenarioVM.gd` — both **sibling namers** (ADR-0212
## dec. 7), where the scenario layer moved (`8fbec7af1`, extraction #9 pass 6) —
## take the zoom mapping, `src/gpu/CinematicManager.gd` and
## `src/scenes/EffectViewerScene.gd` the ortho round-trip, plus the 21 former
## zoom pass-throughs that now name it directly.
const CameraCalibration = preload("res://addons/exmateria_platform/display_port/CameraCalibration.gd")


# --- the effect sound SCHEDULE ---------------------------------------------
#
# ADR-0318 dec. 3. The two files here are the one thing in this addon that BOTH
# `exmateria_effects` and `exmateria_sound` reach, and they are here because
# neither package may reach the other. Effects runs the walker to publish its
# sound-event stream; the audio package's offline SPU parity rig runs the same
# walker to prove our render matches PCSX. A copy in Effects would have FLIPPED
# the arrow rather than cut it — see the walker's own header.
#
# ⚠️ They stretch `tier="port"`: a stateful keyframe walker is a MODEL, not an
# adapter. ADR-0318 S1 says so in those words and does not pretend otherwise.

## Walks an effect's sound schedule and announces the moments — `sound_event(frame,
## phase, channel, sound_id)`, at an externally supplied 30 Hz tick. Makes no sound
## and, since ADR-0318 decs. 1/2, cannot name one: no FEDS bank, no `pair_idx`, and
## the gate is "is there a SCHEDULE", not "is there a bank". A cast with keyframes and
## no `feds.bin` runs its walker, publishes its events and is silent.
## Host use: `tests/stranger/exmateria_effects/no_sound_events.gd` drives it in a project
## with no audio package at all, which is the state the move exists for. Like `SfxPort`
## it has no host namer in production and is not expected to grow one — both its
## production namers are **sibling namers** (ADR-0212 dec. 7):
## `addons/exmateria_effects/cast/EffectInstance.gd` (the game's consumer) and
## `src/audio/SfxStressTest.gd`. The offline SPU parity rig at
## `exmateria-sound/workspace/harness/render_effect_sound.gd` is the third, in the other
## package, and `ExMateriaSound` re-exports the name the way it re-exports the vendored
## SPU's three.
const EffectSoundController = preload("res://addons/exmateria_platform/sound_schedule/EffectSoundController.gd")

## FFT's `lookup_sound_effect` (`0x801A32E8`): five integer modes over
## `sound_containers.json` resolving a timeline `sound_id` to the id a backend plays.
## Zero audio content — `exmateria_effects` owns the containers file and the Effect
## Studio edits it. The walker builds one internally; a consumer rarely needs its own.
## Host use: `src/effects/studio/SoundGhostProjector.gd` and
## `src/effects/studio/SoundContainerModel.gd` — the Effect Studio's score projection and
## its container editor, both real host namers. Its one **sibling namer** (ADR-0212
## dec. 7) is `addons/exmateria_effects/cast/EffectInstance.gd`, whose
## `studio_audition_container` drives a fresh resolver forward to make a container's mode
## audible (ADR-0318 dec. 8 — #1222 carries the move of that method itself).
const EffectSoundResolver = preload("res://addons/exmateria_platform/sound_schedule/EffectSoundResolver.gd")


# --- the fixed-point conventions -------------------------------------------

## The PSX numeric conventions of the FFT event-script interpreter in one place —
## two's-complement byte/half-word operands, low-byte-then-high-byte u16s, and
## the 12-bit clockwise facing wheel — as named, pure, static functions rather
## than bit math re-derived in every opcode handler (ADR-0013's drift rule).
## Host use: `addons/exmateria_cutscene/vm/ScenarioVM.gd` and
## `addons/exmateria_cutscene/vm/ScenarioDecode.gd` — both **sibling namers**
## (ADR-0212 dec. 7), where the scenario layer moved (`8fbec7af1`, extraction #9
## pass 6) — read operands through it, `addons/exmateria_cutscene/camera/ScenarioCameraDirector.gd`
## takes the facing wheel, and `tests/PsxNumTest.gd` is its single test home.
const PsxNum = preload("res://addons/exmateria_platform/fixed_point/PsxNum.gd")

## The CONTINUOUS half of the same charter split (ADR-0091 §2): 4096 = one full
## turn, 28 world units per map tile, and the radial-velocity / acceleration
## divisors that fall out of the 20.12 fixed-point integrator — both directions,
## pure, and deliberately free of calibration so its charter stays as clean as
## `PsxNum`'s. `PsxNum` owns the *discrete* opcode encodings; this owns the
## *continuous* magnitudes; the universal bases (4096, 28) are declared once in
## `PsxNum` and referenced here.
## It arrived from the effects runtime at extraction #7 (gl-ADR-0295 dec. 3, #1220)
## under the name `PsxUnits` — 122 lines with zero reach into `Effects` — renamed
## because *Units* meaning measurement collides with `Unit` the combatant while
## *Magnitude* is ADR-0091's own filename word. (The old path is in the ADR rather
## than here, for the reason the `CameraCalibration` row above records.)
## Host use is broad: `src/effects/`'s emitter/physics/trap files,
## `src/projectiles/Projectile3D.gd`, `src/units/UnitShadow.gd`,
## `addons/exmateria_cutscene/camera/ScenarioCameraDirector.gd` — a **sibling namer**
## (ADR-0212 dec. 7), where the scenario layer moved (`8fbec7af1`) — four studio unit
## files, and `tests/PsxMagnitudeTest.gd` as its golden-value parity home.
const PsxMagnitude = preload("res://addons/exmateria_platform/fixed_point/PsxMagnitude.gd")

## The SIGN axis, which is neither of the two above and which nothing owned before
## #1220: the PSX Y-down ↔ Godot Y-up 180°-about-X (ADR-0052/0057) and the camera
## `-pitch`. Both siblings refuse that axis in their own docstrings, so until this
## file got an address every caller applied it inline.
## It was `class_name PsxChirality`, described by its own header as a pure
## façade; ADR-0290 dec. 5 believed the header and folded it away, and gl-ADR-0295
## dec. 4 measured the call sites instead — **43 of its 85 are its own axis**, so
## the trio stays three names. The 42 pure-delegation sites were deleted with the
## pass-throughs and now name `PsxMagnitude` / `CameraCalibration` directly.
## Host use: `addons/exmateria_effects/cast/EffectInstance.gd`, `addons/exmateria_effects/camera/CinematicFacingResolver.gd`,
## `src/gpu/CinematicManager.gd`, `addons/exmateria_cutscene/camera/ScenarioCameraDirector.gd`,
## `src/scenes/EffectViewerScene.gd`, and `tests/PsxChiralityTest.gd` +
## `tests/CameraConvertParityTest.gd`.
## `addons/exmateria_battlefield/camera/PlayerCamera.gd` is a **sibling namer**
## (ADR-0212 dec. 7): a valid host use of the port, but an ADDON consumer, and the
## two are staged differently — its line is a comment citing
## `psx_angles_to_godot_rotation` as the conversion it deliberately does NOT route
## through, so this edge is documentary rather than a call.
const PsxChirality = preload("res://addons/exmateria_platform/fixed_point/PsxChirality.gd")


# --- the data-asset loader -------------------------------------------------

## The open/parse/error dance for the hand-authored and ROM-extracted JSON data
## assets, in one place, as statics on a RefCounted nobody instantiates. It was
## a file under `src/data/` until #809: a 64-line free-function loader with no
## host state, named by four files inside `exmateria_sprite_rig` — which made it
## goal #5 unmet on the TYPE axis for that addon and for every addon after it
## that wants to read a JSON asset. ADR-0217 dec. 16 ruled the file `platform`'s
## and ADR-0223 dec. 8 named the destination and the owning pass; ADR-0139's
## Alternatives name it BY NAME as a file the kernel's gate refuses, and
## `PsxNum` directly above is the shipped precedent for the same profile
## (ADR-0169 dec. 2).
## 🔴 IT IS NOT A BASE CLASS. Each data store keeps its own typed static cache
## and `_loaded` flag — GDScript per-subclass `static var` state does not inherit
## the way a shared cache would need — so only the I/O body lives here.
## Host use is the broadest of anything on this façade: **23 files in `src/` and
## 4 in `tests/`** alias it back, plus five inside `exmateria_sprite_rig`.
## `tests/JsonAssetTest.gd` is its test home.
const JsonAsset = preload("res://addons/exmateria_platform/json/JsonAsset.gd")


## The cull-proof full-screen NDC-quad base — `extends` this and call
## `_make_overlay_quad(name, mat)` to get one overlay quad that the frustum culler
## cannot silently drop.
## The fact it encodes is a GODOT fact, not a game one: a vertex shader that rewrites
## the corners to NDC (`POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0)`) moves them out of
## the mesh's own AABB, and Godot culls the mesh — an overlay that draws perfectly and
## is invisible. Every such quad must carry an oversized `custom_aabb`, and that recipe
## was copy-pasted across four effects before this base existed.
## ADR-0172 BOOKED the file `platform` and left it in the host's `src/core/`, so the
## bucket sat at two addresses; #1293 group 4 landed it here. The trigger was the
## stranger rig and a SIBLING NAMER: `addons/exmateria_ui/formation/FormationScreenIn.gd`
## line 1 is `extends` this class, which is a base class and not a reference that could be
## handed in or routed through a port, so the UI addon could not parse in a project that
## did not also ship `src/`. Reaching `tier="port"` is FREE (ADR-0202 dec. 2,
## `_walk_roots.PORTABLE_TIERS`), so that reach earns no burn-down row.
## 🔴 IT IS A BASE CLASS, which nothing else on this façade is — `extends
## ExMateriaPlatform.ScreenOverlayQuad` is the supported spelling and it parses, MEASURED
## against a bare-`class_name` control before any call site moved. `CULL_AABB` is public
## for the one consumer that needs the box without the quad (`ScenarioWeather`'s
## billboarded rain MultiMeshes), which is why the constant is shared rather than copied.
## Six subclasses: five in `src/scenarios/` and one SIBLING NAMER, `FormationScreenIn`
## in `exmateria_ui`.
## `tests/ScreenOverlayQuadTest.gd` is its test home.
const ScreenOverlayQuad = preload("res://addons/exmateria_platform/ndc_quad/ScreenOverlayQuad.gd")
