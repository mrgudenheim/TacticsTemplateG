class_name ExMateriaSchema
extends RefCounted

## The whole public surface of `addons/exmateria_schema`, and the only name it
## puts in your project.
##
## Godot has no package scope: a `class_name` is engine-global, so every one an
## addon declares lands in YOUR global scope — and when you declare a colliding
## one, the ADDON's file is what fails to parse, pointing your error at a file
## you did not write.
##
## 🔴 THIS ADDON DECLARED SIX, AND EVERY ONE OF THEM IS GENERIC ENGLISH: `Fold`,
## `DepthMode`, `ColorStack`, `ColorRecipe`, `CellMarking`, `TerrainCell`. By the
## collision risk that motivated the whole exercise these are WORSE than the
## thirty `exmateria_battlefield` shed under ADR-0211 — `Fold` in particular is a
## word any project doing compositing, layout or card games has its own reason to
## want. ADR-0211 dec. 8 deferred this addon on the grounds that a façade here
## *"would wrap a namespace in a namespace"*; ADR-0212 dec. 3 overturns that.
##
## 🔴 AND "NOTHING PRELOADS IN" WAS NEVER THE PRECONDITION (ADR-0212 dec. 2).
## Sixteen host `.gd` scripts used to `preload` a `res://` path into this addon,
## which read like a blocker and was not: every one was already
## `const <LocalName> = preload("res://addons/exmateria_schema/…")`, so the
## migration rewrote the right-hand side to `= ExMateriaSchema.<Name>` — the same
## edit, not a prerequisite for it. `exmateria_sound` reads 48 such preloads and
## shipped a façade regardless. Complete-close describes scope; it has never
## gated a façade in this repo.
##
## A script constant is a full type — annotation, `is` check, `.new()`:
##
##     var cell: ExMateriaSchema.TerrainCell = lattice.cell_at(grid)
##
## and a consumer may alias one back to a bare local name, which is what keeps
## every existing use site spelled the way it was (ADR-0211 dec. 4):
##
##     const TerrainCell = ExMateriaSchema.TerrainCell
##
## 🔴 AN ALIAS IS A PER-CLASS DECLARATION, NOT A PER-FILE ONE. Where a script
## EXTENDS another that already aliases a name, the child must NOT repeat it —
## GDScript refuses a member that already exists in the parent, and the parse
## error takes the whole child out. Four files in this package inherit one that
## way and say so in a comment.
##
## **This list IS the supported surface.** If a script is not named here it is
## internal, whatever its visibility says — and `tools/check_addon_globals.py`
## holds both directions: nothing else in this addon may declare a global, and
## nothing named here may dangle.
##
## 🔴 THE SHADER `#include` CHANNEL IS NOT HERE (ADR-0212 dec. 5).
## `ot_depth.gdshaderinc` and `color_stack.gdshaderinc` are `#include`
## targets a shader names by path. A `.gdshaderinc` declares no `class_name`, so
## it carries none of the collision hazard this file exists for, and no GDScript
## constant can route a preprocessor include.
##
## Nothing here is instantiated. `ExMateriaSchema.new()` gives you an empty
## RefCounted; the class exists to be a namespace, not an object.


# --- the compositing key ---------------------------------------------------

## The ENTIRE display-space fold module — three statics and no object:
## `add()` decorates a carrier (a no-op off-fork), `owns()` answers whether the
## fold is available in THIS BUILD, and `shader(folded, fallback)` is the two-way
## pick that hangs off `owns()` (ADR-0074, ADR-0191).
## 🔴 THIS CONSTANT USED TO COST STOCK-GODOT LOADING, AND #721 PAID IT OFF.
## `Fold.gd` held `const FOLD_LAYER := preload(".../fold_layer.tres")`, a
## `CompositorRenderLayer` stock does not have, so preloading `Fold.gd` here took
## this whole file down on stock and with it every member behind the façade —
## 3 of 4 loaded there before, 0 after (ADR-0212 dec. 8, which ACCEPTED that).
## `FOLD_LAYER` is now a lazy `static var`, so the façade and all six members
## compile on stock; the one thing that still does not load there is
## `fold_layer.tres` itself, which is why `plugin.cfg` still says
## `engine="fork"`. See ADR-0191 dec. 14.
## Host use: `addons/exmateria_cutscene/screen/ScenarioDarkScreen.gd` and
## `addons/exmateria_ui/detail/AbilityPickerMenu.gd` pick a fold for their own surfaces.
## The heaviest namers are **SIBLING NAMERS** (ADR-0212 dec. 7), and since extraction #7
## (#1225) there are four rather than two: `addons/exmateria_effects/render/EngineFoldCompositor.gd`
## and `addons/exmateria_effects/callbacks/EffectCallback.gd` route every folded prim
## through it — both were `src/effects/` paths until the move — alongside
## `addons/exmateria_battlefield/cursor/TileCursorCompositor.gd` and
## `addons/exmateria_battlefield/overlay/TileOverlayCompositor.gd`.
const Fold = preload("res://addons/exmateria_schema/compositing_key/Fold.gd")

## Single source of truth for PSX Ordering-Table depth modes + calibration — the
## per-primitive bias that decides a prim's OT bucket, and the ordering the fold
## is GIVEN rather than computes (ADR-0009, ADR-0074).
## Host use: `src/units/Unit.gd` and `src/projectiles/ProjectileMeshBuilder.gd` bias their
## own prims. The **SIBLING NAMERS** (ADR-0212 dec. 7) are
## `addons/exmateria_effects/render/OTDepthPrimOrder.gd`, a `src/effects/` path until
## extraction #7 (#1225) moved it, and
## `addons/exmateria_battlefield/overlay/TileOverlayCompositor.gd`.
const DepthMode = preload("res://addons/exmateria_schema/compositing_key/DepthMode.gd")


# --- the colour model ------------------------------------------------------

## The CPU source of truth for one consumer's colour transform — an ordered list
## of colour layers, the byte-exact DDA that evaluates each layer's progress, and
## the bounded uniform arrays `color_stack.gdshaderinc` folds (ADR-0067).
## Host use: `addons/exmateria_cutscene/vm/ScenarioVM.gd` drives one per tint opcode and
## `tests/ColorStackTest.gd` is its arithmetic home. The two COMBAT-EFFECT owners are
## **SIBLING NAMERS** (ADR-0212 dec. 7) since extraction #7 (#1225) moved them out of
## `src/effects/`: `addons/exmateria_effects/subsystem/PaletteSubsystem.gd` and
## `addons/exmateria_effects/subsystem/ScreenSubsystem.gd` each own one, as does
## `addons/exmateria_battlefield/assembly/MapComposer.gd`.
const ColorStack = preload("res://addons/exmateria_schema/colour_model/ColorStack.gd")

## One colour **recipe** — FFT's 11 PSX `Color` modes reduced to two shapes,
## affine `{scale, bias}` and luma `{div, delta5, source}`, with `luma_div == 0`
## as the free discriminator. The pure core of ADR-0067.
## Host use: `addons/exmateria_cutscene/screen/ScenarioColorTint.gd` authors them and
## `tests/ColorStackTest.gd` is their arithmetic home. The **SIBLING NAMERS** (ADR-0212
## dec. 7) are `addons/exmateria_effects/overlay/ScreenEffectOverlay.gd`, which builds them
## and was a `src/effects/` path until extraction #7 (#1225),
## `addons/exmateria_battlefield/assembly/MapComposer.gd` and
## `addons/exmateria_battlefield/texturing/MapIlluminationDDA.gd`.
const ColorRecipe = preload("res://addons/exmateria_schema/colour_model/ColorRecipe.gd")


# --- the lattice's value types ---------------------------------------------

## One **terrain cell** — the value answer to "what is at (x, z)?", and the
## payload the `Lattice` port hands out instead of the `Tile` node it reads it
## off (ADR-0118 dec. 1's eighth schema row, ADR-0164 dec. 2).
## Host use: `src/core/ValidationUtils.gd` and `src/gpu/DistanceFieldGenerator.gd`;
## the **SIBLING NAMER** is `addons/exmateria_battlefield/lattice/Lattice.gd`,
## which is the port that returns it.
const TerrainCell = preload("res://addons/exmateria_schema/lattice/TerrainCell.gd")

## The **lattice port's vocabulary** — the six value-typed verbs a consumer
## annotates with, so the annotation can stay while the reach goes free
## (gl-ADR-0332 dec. 1). The split is `Lattice.gd`'s own: its six PUBLIC verbs
## name no `Tile`, its seven private ones all do.
## Host use: none yet; the **SIBLING NAMERS** are
## `addons/exmateria_battlefield/lattice/Lattice.gd`, which implements it, and
## `addons/exmateria_cutscene`'s camera, weather and VM, which annotate with it.
const TerrainQuery = preload("res://addons/exmateria_schema/lattice/TerrainQuery.gd")


# --- the cursor vocabulary ---------------------------------------------------

## The CURSOR PORT's vocabulary — three `Vector2i` signals and a `Vector2i` cell, the
## members a host reads off a roam cursor. ADR-0332's third route, taken a second time
## (gl-ADR-0363), so the annotation can stay while the reach goes free.
## Host use: none yet; the **SIBLING NAMERS** are
## `addons/exmateria_battlefield/cursor/CursorRig.gd`, which implements it, and
## `addons/exmateria_ui`'s formation map host and detail transition, which annotate with it.
## 🔴 THIS IS THE ONLY MEMBER OF THIS FAÇADE THAT IS NOT A `RefCounted`, and it is a
## `Node` because `CursorRig` is one and GDScript has single inheritance. "Nothing here is
## instantiated" is still true of it: a bare `CursorQuery` answers `Vector2i.ZERO` for
## every cell and emits nothing, and no file in this package constructs one.
const CursorQuery = preload("res://addons/exmateria_schema/cursor/CursorQuery.gd")

## **Why a cell is marked** — a placement-zone role, plus the cursor. It does NOT
## name an appearance: `Battle` decides which cells wear which marking and
## `Battlefield` paints it (ADR-0118 dec. 1's ninth schema row, ADR-0196 dec. 6/7).
## Host use: `src/scenes/GambitBattle.gd` decides; the **SIBLING NAMERS** are
## `addons/exmateria_battlefield/overlay/TileHighlights.gd`, which paints, and
## `addons/exmateria_battlefield/lattice/Tile.gd`.
const CellMarking = preload("res://addons/exmateria_schema/lattice/CellMarking.gd")

## `WORLD.BIN`'s game-variable store — Campaign's save data in the ROM's own encoding,
## 684 bytes over three regions that tile it exactly (u32 / BIT / NIBBLE by index).
## Moved here from `src/world_map/` by gl-ADR-0330 because it is named by THREE systems —
## `Campaign`, `World Map` and `Cutscene`'s event VM — and the 182 per-node event scripts
## address these variables BY INDEX, as do the battle side's `event_set_script_variable`
## and the BC opcodes. A value addressed by index from three systems is shared vocabulary,
## which is what this addon is for.
## 🔴 IT IS HERE BECAUSE A TYPE CANNOT BE PORTED. `check_addon_portability.py` arm 5's own
## remedy note is the ruling: *"Move the shared symbol into `addons/exmateria_schema/` — the
## shipped precedent and the shape — or invert the reach so the host passes the value in.
## Naming it through a PORT is NOT open here: a port publishes a signature soft-bound at
## call time, and a TYPE is bound at parse time."* The injection already existed
## (`ScenarioPlayerScene.gd` calls `set_variable_store`); what was left was the ANNOTATION,
## and widening it to `Node` would have turned the guard green by deleting the claim
## (ADR-0148). It is kernel-clean on its own terms: 97 lines, `extends RefCounted`, and it
## reaches nothing at all.
const WorldMapVariables = preload("res://addons/exmateria_schema/campaign_state/WorldMapVariables.gd")


# --- the unit-sprite vocabulary --------------------------------------------
#
# Four value sets a caller used to learn by compiling against the sprite rig
# (ADR-0215 dec. 2, named by ADR-0217 dec. 7). A caller of one of these learns a
# VALUE SET, not a contract — no ordering, no invariant, no error mode — which is
# why re-classifying them removes crossing traffic without re-pointing a call.
# Each follows the kernel's own `DepthMode.Mode` / `CellMarking.Kind` form: a
# subject noun, then the kind of thing it classifies.
#
# 🔴 THE THREE BEHAVIOUR-BEARING HOSTS KEEP THEIR CLASS NAMES AND THEIR
# BEHAVIOUR (`SpriteLayerManager` 888 lines, `AnimationStateController` 369,
# `UnitMaterial` 57), and each then names the kernel for its own internal control
# flow, which ADR-0139 permits. Only the enum moved.

## **Which way a unit is turned** — the four world cardinals, on the canonical
## raw-PSX world wheel `0x0=E, 0x4=S, 0x8=W, 0xC=N`, NOT the sprite-pose index.
## The snap itself (`snap_angle_to_cardinal`) is behaviour and stayed with the rig.
## Host use: `src/units/Unit.gd` holds a unit's `current_facing` and converts it to
## world radians for the facing arrow; `src/gpu/GPUVisualBridge.gd` packs it for the
## combat compute path.
const Facing = preload("res://addons/exmateria_schema/unit_vocabulary/Facing.gd")

## **Which of a unit sprite's three composed layers** — body, weapon, effect
## (ADR-0019: one mesh, three sampled layers). `SpriteLayer` rather than the bare
## word because `colour_model/ColorStack.gd` in this same addon already declares
## `class Layer`, so the bare spelling collided inside the destination.
## Host use: `addons/exmateria_ui/formation/FormationScene.gd` disables two of them for the roster
## pose. `addons/exmateria_sprite_rig/render/UnitDisplay.gd` drives all three layers per
## frame and is a **sibling namer** (ADR-0212 dec. 7): a valid host use of the kernel —
## an addon depending on the kernel is the layering working — but a different fact from a
## `src/` use, and #744's move is what turned this citation from one into the other. The
## file did not change; it crossed a root.
const SpriteLayer = preload("res://addons/exmateria_schema/unit_vocabulary/SpriteLayer.gd")

## **Which pump advances a unit's animation clock** — exactly one owner per unit,
## so a unit can never ride two clocks (ADR-0083). `ClockOwner` rather than the bare
## word, which names no subject at all.
## Host use: `addons/exmateria_cutscene/vm/ScenarioVM.gd` — a **sibling namer**
## (ADR-0212 dec. 7), where the scenario layer moved (`8fbec7af1`, extraction #9
## pass 6) — claims and releases units across the scenario pump, and
## `src/units/Unit.gd` exposes the owner as `clock_owner`.
const ClockOwner = preload("res://addons/exmateria_schema/unit_vocabulary/ClockOwner.gd")

## **Which blend a unit sprite is drawn with** — the question a consumer actually
## has (ADR-0189 dec. 3); `render_mode` must sit in the entry shader, so the file
## count is an implementation detail and the variant is the vocabulary. The shader
## table itself is the rig's, not the kernel's.
## Host use: `addons/exmateria_cutscene/vm/ScenarioVM.gd` — a **sibling namer**
## (ADR-0212 dec. 7), where the scenario layer moved (`8fbec7af1`, extraction #9
## pass 6) — switches a dying unit to the additive fade, and
## `addons/exmateria_ui/formation/FormationScene.gd`, the other **sibling namer**,
## asks for the flat ortho variant.
const UnitMaterialVariant = preload("res://addons/exmateria_schema/unit_vocabulary/UnitMaterialVariant.gd")

## **What a unit is currently doing** — BOTH halves of the activity taxonomy,
## `Display` (what the animation layer plays) and `Logical` (what the engine
## thinks), published as one member because they come from the same YAML rows
## and exist only to be translated into each other (ADR-0217 dec. 8).
## 🔴 THIS ONE IS GENERATED. `tools/gen_activity_taxonomy.py` emits it from
## `tools/activity_taxonomy.yaml` as one of six targets; the other five are
## `Battle`'s constants, its GLSL twin, its dispatch shell, the rig's display
## enum and a machine-owned region of cluster 18. Editing the file is a no-op
## that vanishes on the next run — edit the YAML.
## Host use: `src/gpu/ActivityTranslator.gd`'s dispatch shell names it on four
## emitted lines. ⚠️ IT IS THE ONLY HOST NAMER TODAY AND THAT IS THE DESIGN, NOT
## AN OMISSION: the rest of the tree still reaches the display half through the
## rig's own generated enum and the logical half through `Battle`'s constants —
## 227 lines that #740 deliberately does not touch. #744/#746 drain them.
const UnitActivity = preload("res://addons/exmateria_schema/unit_vocabulary/UnitActivity.gd")


# --- the unit role vocabulary ----------------------------------------------
#
# ADR-0118 dec. 1's ELEVENTH row (ADR-0280 dec. 3), and the first whose producer
# is a TIER rather than a system. It shares `unit_vocabulary/` with the tenth
# row's five members and is NOT one of them: their producer is `Sprite Rig`,
# this one's is the `rules` tier.

## **Which combat archetype a unit is** — `ANY`, `MELEE`, `RANGED`, `MAGE`,
## `HEALER`, `HYBRID` — the value set the gambit AI filters targets by. FFT has
## no roles; they are this project's archetypes, so the file holds an enum, an
## enum->string table, the enum's members and a two-line predicate, and NO
## derivation. `addons/exmateria_almanac`'s `JobDatabase.get_job_role` is what
## decides a unit's role and it stayed in the `rules` tier.
## Host use: `src/gpu/GambitEncoder.gd` packs the filter, `src/gpu/RolloutPlaybook.gd`
## and `src/gpu/GambitCellSynth.gd` read it, `addons/exmateria_ui/UIGambitEditor.gd` populates
## its dropdown from `get_all_roles()` and `src/units/Unit.gd` exposes a unit's own.
## The **SIBLING NAMERS** are `addons/exmateria_almanac/jobs/JobDatabase.gd`,
## which produces it, and that addon's `gambits/Gambit.gd` and
## `gambits/TargetSelector.gd`, which render and apply it.
const UnitRole = preload("res://addons/exmateria_schema/unit_vocabulary/UnitRole.gd")


# --- the unit progression vocabulary ---------------------------------------
#
# ADR-0118 dec. 1's TWELFTH row (ADR-0294 dec. 2), and the second whose producer
# is the `rules` tier rather than a system. It shares `unit_vocabulary/` with the
# tenth row's five members and the eleventh's one, and is NOT one of them: the
# tenth's producer is `Sprite Rig`, the eleventh answers *which archetype*, and
# these three answer *which slot*, *which curve* and *which sign* about the
# progression record a unit carries.
#
# 🔴 `UnitProgression` ITSELF DID NOT MOVE AND IS NOT ADMISSIBLE. It names five
# databases by static class access and would fail ADR-0139 dec. 4(a)'s sink veto
# on every one of them; ADR-0241 dec. 3's measurement (41 of its 53 functions
# touch a database, so there is no injection point to cut at) is untouched by this
# row and stays good. What left is the value sets it happened to nest — the same
# shape the tenth row found nested in an 888-line Node.
#
# 🔴 THREE MEMBERS, ONE ROW, AND THAT IS A RECORDED CHOICE. ADR-0196 gave the cell
# marking its own row beside the terrain cell, so the precedent for splitting
# exists; ADR-0215's amendment declined it for the tenth row's four. Declined here
# too, and for that ADR's reason: one decision, one set of published names, one
# directory. All three cross the SAME boundary on the SAME lines — every one of
# them is reached from `Character.gd`'s ENTD materialization seam.

## **Which of a unit's five equipment slots** — right hand, left hand, head, body,
## accessory. The layout the `equipment` dictionary is keyed by, never what fills
## it. Lifted out of `UnitProgression` by #1123 and left in the almanac then,
## because the destination on the table was the CATALOGUE and that reach would
## have inverted a declared dependency; the kernel inverts nothing.
## Host use: `src/ui3/detail/` and `src/ui3/formation/` render a unit's five
## slots, `src/units/Unit.gd` and `src/gpu/` read the weapon out of one. The
## **SIBLING NAMERS** are `addons/exmateria_almanac/progression/UnitProgression.gd`,
## which re-exports it and owns the dictionary, `that addon's items/EquipCandidates.gd`,
## which matches ROM equip legality on the slot names, and
## `addons/exmateria_catalogue/identity/Character.gd`, which seeds all five.
const EquipSlot = preload("res://addons/exmateria_schema/unit_vocabulary/EquipSlot.gd")

## **Which base-stat curve a unit grows on** — `MALE`, `FEMALE`, `MONSTER`. The
## row selector into the per-unit-type base stat table; the TABLE stays in the
## almanac (`progression/BaseStatsDatabase.gd`) and so does the arithmetic over it
## (`progression/StatCalculator.gd`), both of which would fail the sink veto here.
## Host use: `src/audio/SfxRouter.gd` keys three death-cry slugs off it,
## `src/units/Unit.gd` and `addons/exmateria_ui/formation/FormationScene.gd` ask whether a unit
## is female. The **SIBLING NAMERS** are
## `addons/exmateria_almanac/progression/UnitProgression.gd` and the catalogue's
## `identity/Character.gd` / `seeding/AllTemplatesSeeder.gd`, which pick one from a
## job plus an authored gender.
const BaseStatType = preload("res://addons/exmateria_schema/unit_vocabulary/BaseStatType.gd")

## **Which sign a unit was born under** — the twelve tropical signs, FFT's hidden
## thirteenth, the stored month→boundary table and the lookup that indexes it.
## `zodiac_from_birthday` travels with the enum because it is ADR-0273 dec. 1's
## `table` and not its `rule`: delete the function and the twelve rows still hold
## the whole answer.
## Host use: `addons/exmateria_ui/UIUnitNameplate.gd` picks the info panel's zodiac glyph from
## the resulting int. The **SIBLING NAMERS** are
## `addons/exmateria_almanac/progression/UnitProgression.gd`, which re-exports the
## enum and stores a unit's own, and the catalogue's `identity/Character.gd` and
## `identity/UnitBirthdays.gd`, which derive one at the materialization seam.
const Zodiac = preload("res://addons/exmateria_schema/unit_vocabulary/Zodiac.gd")
