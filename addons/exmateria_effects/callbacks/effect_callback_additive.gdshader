shader_type spatial;
// IN-SCENE twin of effect_callback_fold — ONE WORD apart: no `compositor_layer`, so the engine draws
// this in-scene and Godot blends it into the Forward+ LINEAR HDR buffer instead of the display-space
// fold scratch. Body + shared uniforms in effect_callback_body.gdshaderinc; this file owns the
// sRGB->linear pow the linear target needs and the fold must not have (ADR-0191 dec. 6).
//
// It is the production route on every build that does not fold — stock, Mobile, GL Compatibility —
// not only a comparison arm. Before #1450 it wrote raw display texels into the linear target with no
// pow at all, the same error class `3970479f3` measured for the particle family at raw |err| 73/255
// against linearized 2/255.
//
// ⚠️ WHAT THIS DOES NOT BUY: PARITY. The pow fixes each callback's OWN colour. The BLEND is still
// Godot's: Forward+/Mobile blend in linear space, so `(a^g + b^g)^(1/g) != a + b` and overlapping
// adds read dimmer than the fold. Compatibility writes sRGB directly (OUTPUT_IS_SRGB), so it skips
// the linearization below. The honest claim is "visible, and per-callback colour-correct".
// ADR-0191 "Not claimed".
// Vault: [[Effect Callback Mesh]]
// compositor-exempt: off-fork-fallback effect_callback_fold.gdshader — routed through the compositor
// on Forward+ via that twin (EffectCallback loads that compositor_layer variant when the build folds).
// This in-scene blend_add file is the Mobile/stock fallback only, so it is not a Forward+ lock-in blocker.
// display-space: folds-on-fork effect_callback_fold.gdshader
// (callbacks fold on the fork; the pick is EffectCallback.blend_shader -> Fold.shader.) PSX blends in
// DISPLAY space and this in-scene file blends in LINEAR — correct only because it is the off-fold path.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

#include "res://addons/exmateria_effects/callbacks/effect_callback_body.gdshaderinc"

// The sRGB->linear exponent, a uniform rather than a literal for the reason
// effect_particle_native.gdshaderinc and tile_overlay.gdshaderinc already record against the real
// game: pow(2.2) OVER-DARKENED relative to the ROM, and the right value is a per-look tunable, not a
// constant of the universe. 2.2 is the legacy default — the exact exponent effect_particle_opaque
// has always used — so this path starts where the shaders the user can already see correctly start.
uniform float srgb_gamma = 2.2;

void fragment() {
	// The CLAMP mirrors the fold scratch, it is not a stylistic saturate: the scratch is
	// R8G8B8A8_UNORM (FoldSurface._make_scratch) so the hardware clamps the shaded colour there,
	// which is also what the PSX does before the ABR step. Without it this half would feed the blend
	// a magnitude the fold never sees.
	//
	// The pow is on the FINISHED product, not on the texel alone: the fold twin writes
	// `texel * gouraud * PSX_OUTPUT_LEVEL` into a display-space scratch and Pass C converts THAT to
	// linear, so this half lands the same colour only by linearizing the same finished product.
	// Linearizing the texel alone would leave the display gain applied in the wrong space.
	vec3 display_color = clamp(callback_display_color(UV, COLOR.rgb), vec3(0.0), vec3(1.0));
	ALBEDO = OUTPUT_IS_SRGB ? display_color : pow(display_color, vec3(srgb_gamma));
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
