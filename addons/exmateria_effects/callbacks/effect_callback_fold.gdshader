shader_type spatial;
// Engine-fold twin of effect_callback_additive — ONE WORD apart: `compositor_layer` routes callback
// ArrayMeshes into the 4.8-dev Pass B display scratch, else Pass C's coverage-discard clobbers them
// (E065 Shiva "spikes pierce the flash"). Loaded ONLY when the build folds; stock/Mobile keeps the
// additive twin. Body + rationale in effect_callback_body.gdshaderinc, which both twins share; the
// one expression they do NOT share is the colour line below, and this half's is RAW — see that file's
// "why the colour expression is not shared". IDENTICAL uniforms either way, so the .shader-only swap
// keeps _material.
// OCCLUSION: depth-test ENABLED on the shared opaque scene depth — a tube half-behind a wall clips
// PER-FRAGMENT though fold ORDER is one bucket.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

#include "res://addons/exmateria_effects/callbacks/effect_callback_body.gdshaderinc"

void fragment() {
	// DISPLAY-SPACE RAW. The fold scratch is display-space sRGB with no tonemap after it, so the
	// shaded colour goes in as-is: NO pow. The scratch's R8G8B8A8_UNORM format clamps it, which is
	// also what the PSX does to (texel*gouraud)>>7 before the ABR step. The pow the IN-SCENE twin
	// needs lives in that twin's own file, outside this closure — enforced by
	// tools/check_no_pow_in_fold.py, which walks exactly this #include closure.
	ALBEDO = callback_display_color(UV, COLOR.rgb);
	ALPHA = 1.0;
	DEPTH = ot_computed_depth;
}
