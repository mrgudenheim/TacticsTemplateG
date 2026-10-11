shader_type spatial;
// Monomorphic effect-particle fold — SUBTRACTIVE (PSX ABR10). Body + rationale in
// effect_particle_fold.gdshaderinc; this wrapper fixes only the blend and the layer. ADR-0191 dec. 6.
render_mode unshaded, cull_disabled, depth_draw_never, blend_sub, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.
// Vault: [[Display Space Blend Fold]]

#define EFFECT_STP_ALPHA 1.0
#include "res://addons/exmateria_effects/render/effect_particle_fold.gdshaderinc"
