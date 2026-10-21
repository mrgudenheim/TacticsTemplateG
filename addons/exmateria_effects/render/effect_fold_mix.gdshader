shader_type spatial;
// Monomorphic effect-particle fold — 50/50 MIX (PSX ABR00). Body + rationale in
// effect_particle_fold.gdshaderinc; this wrapper fixes the blend, the layer, and the ALPHA the mix
// blend needs. ADR-0191 dec. 6.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.
// Vault: [[Display Space Blend Fold]]

#define EFFECT_STP_ALPHA 0.5
#include "res://addons/exmateria_effects/render/effect_particle_fold.gdshaderinc"
