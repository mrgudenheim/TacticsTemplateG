shader_type spatial;
// Ordered replacement, NOT a ROM ABR mode. Retain scene testing, never write depth.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, compositor_layer;
// psx-prim: textured — source texel times normalized modulation.
// Vault: [[Display Space Blend Fold]]
#define EFFECT_REPLACE
#define EFFECT_STP_ALPHA 1.0
#include "res://addons/exmateria_effects/render/effect_particle_fold.gdshaderinc"
