// Unified PSX colour-mode stack.
//
// FFT recolours the scene the same way everywhere — sepia cutscenes, poison tint,
// door-fade dim, lightning flash, combat screen tints — by transforming the FINAL
// colour on screen, AFTER the palette/texture lookup, over time. This is ONE model,
// not several; see docs/adr/0067-color-modes-are-one-model.md and the "Color modes"
// cluster in CONTEXT.md. This include is the colour analog of ot_depth.gdshaderinc.
//
// Usage — any shader that folds CLUT colour through the 11-mode stack routes here.
// That is NOT every shader: most families (map, most UI, effect particles) never
// touch this seam. Today there are FIVE real callers — unit, indexed_color,
// screen_background, formation_unit, and tests/color_stack_gpu_probe. The binding
// contract is enforced by tools/check_color_shaders.py: any shader that CALLS
// color_apply must reach this include through its #include chain. The guard is
// the real contract; this header is just how you satisfy it:
//   #include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"
//   void fragment() {
//       vec3 base = <indexed palette lookup | bilinear gradient | gradient×Gouraud>;
//       ALBEDO = color_apply(base, <surface_id>);
//   }
//
// The include is BASE-AGNOSTIC: each consumer computes its own base colour however
// it likes and hands it in, exactly as each depth consumer supplies its own
// representative point. Single-surface consumers (map, background, UI) pass
// surface_id = 0; unit shaders pass 0/1/2 for the winning body/weapon/effect
// sub-sprite (opaque painter's select, ADR-0019).
//
// The stack is a bounded ordered array of layers, folded in order with ONE
// operation: c = base; for each layer: c = mix(c, recipe(c), progress). There is NO
// compose-op enum — additive tint is affine scale=1, an absolute set is scale=0;
// every combine falls out of the layer's recipe. The CPU (ColorStack.gd, the source
// of truth) does ALL time + mode logic and hands the shader {recipe, progress, mask};
// the shader does zero time math and zero mode branches beyond affine-vs-luma.

// === The public contract (portable vec4/int arrays — Godot struct-uniform arrays
//     are unreliable). Authoritative packing lives in addons/exmateria_schema/colour_model/ColorStack.gd. ===
const int MAX_COLOR_LAYERS = 8;                  // ~3-4 real worst case + headroom
uniform vec4 color_layer_rgb0[MAX_COLOR_LAYERS]; // affine scale.xyz | luma delta5.xyz ; .w = progress
uniform vec4 color_layer_rgb1[MAX_COLOR_LAYERS]; // affine bias.xyz                     ; .w = luma div (0 ⇒ affine)
uniform int  color_layer_meta[MAX_COLOR_LAYERS]; // [2:0] surface mask · [3] recipe source (0=current,1=base; affine & luma)
uniform int  color_layer_count = 0;
uniform bool quantize = false;               // per-consumer 5-bit fidelity

// Evaluate one layer's recipe against the fold's input. `base` is the surface's base
// colour; `current` is the colour-so-far. Affine ignores base; luma picks its source.
// Mirrors ColorRecipe.apply — div==0 ⇒ affine, else luma. luma_out5 is the byte-exact
// 5-bit integer core (2R+3G+B)/div + delta, clamped 0..31 (227/227 vs the live CLUT).
vec3 color_recipe(int i, vec3 base, vec3 current) {
	vec4 r0 = color_layer_rgb0[i];
	vec4 r1 = color_layer_rgb1[i];
	float div = r1.w;
	if (div == 0.0) {
		// Affine: recipe(src) = src·scale + bias. Meta bit 3 selects the source
		// (0 = colour-so-far, modes 0/1; 1 = raw base, modes 4/5/9 — idempotent).
		bool affine_from_base = ((color_layer_meta[i] >> 3) & 1) == 1;
		vec3 asrc = affine_from_base ? base : current;
		return asrc * r0.xyz + r1.xyz;
	}
	// Luma: mix the source colour to one luminance in 5-bit space, add delta, clamp.
	bool from_base = ((color_layer_meta[i] >> 3) & 1) == 1;
	vec3 src = from_base ? base : clamp(current, vec3(0.0), vec3(1.0));
	ivec3 s5 = ivec3(round(clamp(src, vec3(0.0), vec3(1.0)) * 31.0));
	int lum = (2 * s5.r + 3 * s5.g + s5.b) / int(div);  // integer floor
	ivec3 delta5 = ivec3(round(r0.xyz));
	ivec3 o5 = clamp(ivec3(lum) + delta5, ivec3(0), ivec3(31));
	return vec3(o5) / 31.0;
}

// Fold the colour stack over a consumer's base colour for one surface. The layer's
// surface mask [2:0] gates whether it touches this surface_id (single-surface
// consumers pass 0 and their layers set bit 0). Quantize last (the final CLUT colour
// is the 5-bit byte-exactness endpoint), per-consumer.
vec3 color_apply(vec3 base, int surface_id) {
	vec3 c = base;
	int surface_bit = 1 << surface_id;
	for (int i = 0; i < color_layer_count; i++) {
		if ((color_layer_meta[i] & surface_bit) == 0) {
			continue;  // this layer does not touch the current surface
		}
		float progress = color_layer_rgb0[i].w;
		c = mix(c, color_recipe(i, base, c), progress);
	}
	if (quantize) {
		c = round(clamp(c, vec3(0.0), vec3(1.0)) * 31.0) / 31.0;
	}
	return c;
}
