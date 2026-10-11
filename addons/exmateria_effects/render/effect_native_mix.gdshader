shader_type spatial;
// IN-SCENE twin of effect_fold_mix — ONE WORD apart: no `compositor_layer`, so the engine renders this
// in-scene and mixes in the Forward+ LINEAR HDR buffer instead of the display-space fold scratch. Body
// + rationale in effect_particle_native.gdshaderinc, which owns the sRGB->linear pow the linear target
// needs and the fold must not have. blend_mix is not add/sub, so it needs no compositor-exempt marker —
// check_compositor_routing.py inventories it rather than scoring it. ADR-0191 dec. 6.
//
// IT IS THE PRODUCTION OFF-FORK ROUTE (#1352), not only the #7916 compare side — see
// effect_native_add.gdshader for the mechanism and for what the in-scene path does and does not buy.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

#define EFFECT_STP_ALPHA 0.5
#include "res://addons/exmateria_effects/render/effect_particle_native.gdshaderinc"
