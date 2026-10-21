class_name ExMateriaRender
extends RefCounted

## The whole public surface of `addons/exmateria_render`, and the only name it
## puts in your project.
##
## Godot has no package scope: a `class_name` is engine-global, so every one an
## addon declares lands in YOUR global scope — and when you declare a colliding
## one, the ADDON's file is what fails to parse, pointing your error at a file
## you did not write.
##
## 🔴 THIS ADDON ALREADY DECLARED EXACTLY ONE, AND THAT WAS NEVER THE INVARIANT
## (ADR-0212 dec. 1). The one name was `FoldSurface` — unbranded, and not a
## namespace, so it collided as readily as any of the thirty
## `exmateria_battlefield` shed under ADR-0211. What makes an addon safe is that
## its surviving name is brand-prefixed and named after its folder, which is why
## the fix here is a façade and not the cheaper-looking rename: a namespace
## holding one constant is uniform rather than silly, and it costs three alias
## lines against the rename's three call-site updates. The rename would have
## bought a name that cannot grow.
##
## A script constant is a full type — annotation, `is` check, `.new()`:
##
##     var surface: ExMateriaRender.FoldSurface = ...
##
## and a consumer may alias one back to a bare local name, which is what keeps
## every existing use site spelled the way it was (ADR-0211 dec. 4):
##
##     const FoldSurface = ExMateriaRender.FoldSurface
##
## **This list IS the supported surface.** If a script is not named here it is
## internal, whatever its visibility says — and `tools/check_addon_globals.py`
## holds both directions: nothing else in this addon may declare a global, and
## nothing named here may dangle.
##
## 🔴 THIS IS THE SYMBOL SURFACE, NOT THE COUPLING SURFACE (ADR-0211 dec. 3,
## ADR-0212 dec. 4). Four host files name a `res://` path into this addon and
## none of them is a symbol reach: one `preload`s `debug/depth_debug.gdshader` as
## a **Shader resource**, and three are plain **String** constants naming the two
## `.glsl` stages for a compute pipeline. That axis is `check_lattice_scene.py`'s
## criterion 4 (ADR-0205), and "not published here" never means "nothing depends
## on it".
##
## 🔴 AND THE SHADER `#include` CHANNEL IS NOT HERE EITHER (ADR-0212 dec. 5). A
## `.gdshaderinc` declares no `class_name`, so it carries none of the collision
## hazard this file exists for, and no GDScript constant can route a
## preprocessor include.
##
## Nothing here is instantiated. `ExMateriaRender.new()` gives you an empty
## RefCounted; the class exists to be a namespace, not an object.

# --- the fold bracket: the addon's one published type ----------------------

## The display-space fold's userland Pass A / Pass C bracket around the engine's
## held-out fold pass (ADR-0074, ADR-0080). A caller constructs one and hands it
## a `Camera3D`; it installs the two `CompositorEffect`s and keeps them alive.
## Also the home of `quantize_levels`, the PSX RGB555 crush a consumer may turn
## off — a policy the bracket is GIVEN rather than a constant welded into its
## GLSL (ADR-0152).
## Host use, and the live one is now a **SIBLING NAMER** (ADR-0212 dec. 7):
## `addons/exmateria_effects/render/EngineFoldCompositor.gd` holds `var _fold_surface`
## and builds one in `setup()`. It was a `src/effects/` path until extraction #7
## (#1225) moved the compositor into `addons/exmateria_effects`, which is the whole
## point of the label — the relationship is an ADDON consumer's, declared in that
## addon's `plugin.cfg` `deps=` and staged by `tests/stranger/shared/rig.sh`, not a
## host file's. `tests/FoldSurfaceTest.gd` drives both passes and is a host test.
const FoldSurface = preload("res://addons/exmateria_render/fold_bracket/FoldSurface.gd")
