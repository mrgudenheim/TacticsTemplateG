shader_type spatial;
// Engine-fold twin of effect_callback_additive: compositor_layer routes callback ArrayMeshes into the
// 4.8-dev Pass B display scratch, else Pass C's coverage-discard clobbers them (E065 Shiva "spikes
// pierce the flash"). Loaded ONLY when Fold.owns(); stock/Mobile keeps additive; IDENTICAL uniforms +
// vertex/fragment so the .shader-only swap keeps _material. OCCLUSION: depth-test ENABLED on the shared
// opaque scene depth — a tube half-behind a wall clips PER-FRAGMENT though fold ORDER is one bucket.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, compositor_layer;
// psx-prim: textured — ALBEDO = texel * gouraud/128 (PSX (texel*color)>>7). ADR-0074 color-math clause.

// Unified PSX Ordering-Table depth (ADR-0009): per-face centroid in CUSTOM0, STANDARD mode 0.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform sampler2D effect_texture : filter_nearest, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);  // x, y, w, h (normalized)
// use_texture / use_psx_brightness: static per-producer traits set at material-build — material configuration, not ADR-0074's forbidden data-driven axis branching.
uniform bool use_texture = false;
uniform bool use_psx_brightness = true;  // false for callbacks with own brightness tables

// Retired psx_brightness global's display-space gain (ADR-0074 endgame); exact-retired 2.2 = net-neutral, named PSX_OUTPUT_LEVEL to agree with the in-scene twin (ADR-0191 dec. 6).
const float PSX_OUTPUT_LEVEL = 2.2;

// PAR (ADR-0036): Pattern 1, full-stretch — see effect_callback_additive.gdshader for the rationale.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);

	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	float brightness = use_psx_brightness ? PSX_OUTPUT_LEVEL : 1.0;
	if (use_texture) {
		vec2 uv = uv_rect.xy + UV * uv_rect.zw;
		vec4 tex = texture(effect_texture, uv);
		// STP filtering: only semi-transparent pixels (a ~0.5) survive; PSX blend is >>7, not >>8.
		if (tex.a < 0.01 || tex.a > 0.9 || (tex.r < 0.01 && tex.g < 0.01 && tex.b < 0.01)) {
			discard;
		}
		ALBEDO = tex.rgb * COLOR.rgb * brightness;
		ALPHA = 1.0;
	} else {
		ALBEDO = COLOR.rgb * brightness;
		ALPHA = 1.0;
	}
	DEPTH = ot_computed_depth;
}
