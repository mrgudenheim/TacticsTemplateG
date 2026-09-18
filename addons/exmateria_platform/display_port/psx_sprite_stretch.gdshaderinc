// Sprite-stretch globals — the DECLARATION seam for the per-taxonomy billboard-WIDTH
// multipliers (ADR-0044). Declaration only: no function, no math, nothing to call.
//
// `pixel_aspect.gdshaderinc` states the rule this file exists to obey — *"Never redeclare
// this at a call site — include this seam so there is exactly one declaration to
// scrub."* That rule had a seam for pixel aspect and none for the stretches, so the
// stretch names were declared inside `addons/exmateria_battlefield/`: a shader in one
// addon asking the HOST for a name that a DIFFERENT addon writes.
//
// The writer is `PSXDisplay` (this directory): `_apply_cursor_stretch` and
// `_apply_fx_stretch` push these two, from `render.psx_*_stretch` Tune tunables. So the
// port declares what the port pushes, which is what ADR-0171 dec. 1 described the port
// as doing all along — *"pushes the result to global shader parameters it does not
// declare"* was the anomaly, not the design.
//
// 🔴 THIS DOES NOT REMOVE THE HOST REQUIREMENT, and nothing short of abandoning global
// uniforms could. A `global uniform` resolves against the consuming project's
// `project.godot [shader_globals]` block and a missing one is SILENT outside the editor
// -- it compiles and reads 0 (ADR-0238, correcting ADR-0169 dec. 4). What it buys is that the requirement is ONE addon's
// documented contract instead of two, and that a new battlefield shader cannot quietly
// add an install step by declaring a name of its own.
//
// ⚠️ `unit_stretch` is the taxonomy's third member and is STILL not here — it has its
// own seam, `unit_stretch.gdshaderinc`, added at #744. The reason is this note's
// original one, which survives the change: adding it HERE would charge every includer of
// this file — all of them `Battlefield`'s — for a name none of them uses, and a global
// uniform a consumer has not declared reads 0 with no error anywhere (ADR-0238). One seam
// per taxonomy keeps that true.
//
// 🔴 WHAT THIS NOTE GOT WRONG, RECORDED RATHER THAN QUIETLY FIXED. It read *"declared at
// its host call sites (`assets/shaders/unit_sprite_body.gdshaderinc`,
// `src/ui3/shaders/formation_unit.gdshader`), neither of which is inside an addon"*.
// Both halves were false. The declarations were in `unit.gdshader` and
// `unit_additive.gdshader`, not in the body include; and `src/ui3/shaders/formation_unit
// .gdshader` does not exist in this tree at all. Nothing could have told a reader: a
// prose path reference rots with no diagnostic. Then #744 moved the unit shaders into an
// addon and `check_addon_portability.py`'s GLOBAL-UNIFORM arm went red — a guard finding
// the truth two comment errors had covered.

// EFFECTS taxonomy. 1.0 = native art.
global uniform float psx_fx_stretch;
// CURSOR taxonomy. 1.0 = native art; scrubbed in the F3 Display debug panel.
global uniform float psx_cursor_stretch;
