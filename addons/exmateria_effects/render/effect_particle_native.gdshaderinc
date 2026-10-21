// IN-SCENE half of the effect-particle body — the twin of effect_particle_fold.gdshaderinc, included
// by effect_native_{add,mix,sub}. Everything above the colour line is SHARED and lives one level down
// in effect_particle_stp.gdshaderinc (uniforms, the billboard vertex, stp_sample, ot_computed_depth);
// the two halves are one expression apart and this file owns that expression.
//
// WHY IT IS A SEPARATE FILE AND NOT A FLAG. The fold half writes the RAW display texel into the
// display-space scratch. This half writes into Godot's LINEAR Forward+ HDR target, whose return leg is
// the pipeline's tonemap + sRGB encode, so it must linearize first. A `srgb_to_linear ? pow(..) : ..`
// ternary shared by both is exactly what was deleted in the 2026-07-31 fold-colour audit, and it could
// not come back: `tools/check_no_pow_in_fold.py` fails on any `pow(` in the #include closure of a
// `compositor_layer` entry shader, correctly — a pow inside a fold is a colour-space round trip with
// no return leg (the gold-box bug class). Splitting the file is the guard's forcing function, and it
// is the shape `addons/exmateria_battlefield/overlay/` already uses one addon over:
// tile_overlay_clut.gdshaderinc (shared, raw) + tile_overlay.gdshaderinc (in-scene, owns the pow).
//
// The FRAGMENT is duplicated rather than shared because it has to be: ALPHA / ALBEDO / DEPTH are
// fragment-scope builtins, so no helper function in the shared include can assign them. The three
// lines the two halves have in common are the floor, not drift.
//
// WHERE THE POW SITS, AND WHY IT IS NOT THE OPAQUE SHADER'S PLACEMENT. effect_particle_opaque does
// `pow(texel) * COLOR`. This file does `pow(texel * COLOR)`, and the difference is load-bearing on
// THIS path: EngineFoldCompositor bakes POOL_GOURAUD_GAIN (2.2) into every carrier's COLOR.rgb, so
// COLOR here is not the near-unity modulation the opaque path carries. The fold twin writes
// `texel * COLOR` into a display-space scratch and Pass C converts that FINISHED product to linear —
// so the in-scene half lands the same colour on screen only if it linearizes the same finished
// product. Linearizing the texel alone would leave the gouraud gain applied in the wrong space.
//
// THE CLAMP MIRRORS THE SCRATCH, it is not a stylistic saturate. The fold scratch is
// R8G8B8A8_UNORM (FoldSurface._make_scratch), so the hardware clamps `texel * COLOR` to [0,1] before
// the blend — which is also what the PSX does, clamping the shaded colour (texel*gouraud)>>7 to
// 0..255 before the ABR step. Without the clamp this half would feed the blend a magnitude the fold
// never sees.
//
// ⚠️ WHAT THIS DOES NOT BUY: PARITY. The pow fixes each sprite's OWN colour. The BLEND is still
// Godot's: Forward+/Mobile blend in linear space — `(a^g + b^g)^(1/g) != a + b`, so overlapping
// adds read dimmer than the fold, and blend_sub clamps differently. Compatibility writes sRGB
// directly (OUTPUT_IS_SRGB), so it must skip the linearization below. Its native blending still
// does not establish fold/PSX parity (ordering, precision and clipping remain different).
// The honest claim is "visible, and per-sprite colour-correct". ADR-0191 "Not claimed".
// Vault: [[Display Space Blend Fold]]

#include "res://addons/exmateria_effects/render/effect_particle_stp.gdshaderinc"

// The sRGB->linear exponent, a uniform rather than a literal for the reason tile_overlay.gdshaderinc
// already records against the real game: pow(2.2) OVER-DARKENED relative to the ROM, and the right
// value is a per-look tunable, not a constant of the universe. 2.2 is the legacy default — the exact
// exponent effect_particle_opaque has always used — so this path starts where the one shader the user
// can already see correctly starts.
uniform float srgb_gamma = 2.2;

void fragment() {
	vec4 col = stp_sample(UV);
	vec3 display_color = clamp(col.rgb * COLOR.rgb, vec3(0.0), vec3(1.0));
	ALBEDO = OUTPUT_IS_SRGB ? display_color : pow(display_color, vec3(srgb_gamma));
	ALPHA = EFFECT_STP_ALPHA;
	DEPTH = ot_computed_depth;
}
