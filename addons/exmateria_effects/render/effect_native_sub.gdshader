shader_type spatial;
// IN-SCENE twin of effect_fold_sub — ONE WORD apart: no `compositor_layer`, so the engine renders this
// in-scene and Godot subtracts it into the Forward+ LINEAR HDR buffer instead of the display-space fold
// scratch. Body + rationale in effect_particle_native.gdshaderinc, which owns the sRGB->linear pow the
// linear target needs and the fold must not have. ADR-0191 dec. 6.
//
// IT IS THE PRODUCTION OFF-FORK ROUTE (#1352), not only the #7916 compare side. A build without the
// `compositor_layer` primitive cannot compile effect_fold_sub at all, so CompositorAutopilot selects this
// set from the BUILD predicate and EngineFoldCompositor materializes the carriers in-scene. Before
// that, the autopilot stood down off-fork and the transparent particles silently drew NOTHING while the
// opaque pass kept drawing — no shader error, no missing-material warning, nothing to grep for.
// On the fork the same selection is still reachable by hand (the Effect Studio render-layer button), so
// the muddy native-blend result can be held against the display-space fold. Routing it did NOT delete
// that comparison: the toggle is now an OVERRIDE on top of the predicate.
// compositor-exempt: off-fork-fallback effect_fold_sub.gdshader — the in-scene half of a routed/not-routed PAIR; the fold twin carries the Forward+ path.
// display-space: folds-on-fork effect_fold_sub.gdshader
// (this file is the off-fork half of that pair.) PSX blends in DISPLAY space and this in-scene file
// blends in LINEAR. The per-sprite colour is corrected by the pow in the body; the BLEND cannot be —
// see the native include's "what this does not buy" note. Correct only because it is the off-fork path.
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub;

#define EFFECT_STP_ALPHA 1.0
#include "res://addons/exmateria_effects/render/effect_particle_native.gdshaderinc"
