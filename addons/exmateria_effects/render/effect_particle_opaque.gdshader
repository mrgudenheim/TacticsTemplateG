shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// STP Opaque Pass: Renders STP=0 pixels only (alpha=255)
// No blend mode - fully opaque, writes to depth buffer
//
// ADR-0039: color_modulate from COLOR.rgb, semi_trans_on from COLOR.a > 0.5
// Vault: [[Display Space Blend Fold]]
// Vault: [[Effect MultiMesh Pool]]

#include "res://addons/exmateria_effects/render/effect_particle_stp.gdshaderinc"

void fragment() {
	vec2 uv_origin = uv_rect.xy;
	vec2 uv_size = uv_rect.zw;
	vec2 uv = uv_origin + UV * uv_size;

	vec4 col = texture(effect_texture, uv);

	// When semi_trans_on=true (normal): discard STP=1 pixels (alpha < 0.9) — they render in semi-trans pass
	// When semi_trans_on=false: render ALL non-black pixels as opaque (no semi-trans pass exists)
	bool semi_trans_on = COLOR.a > 0.5;
	float alpha_threshold = semi_trans_on ? 0.9 : 0.01;
	if (col.a < alpha_threshold || (col.r < 0.01 && col.g < 0.01 && col.b < 0.01)) {
		discard;
	}

	// Forward+/Mobile expect linear; Compatibility writes sRGB directly. Keep modulation
	// AFTER the texel conversion (unlike the native transparent carrier's calibrated gain).
	ALBEDO = ((srgb_to_linear && !OUTPUT_IS_SRGB) ? pow(col.rgb, vec3(2.2)) : col.rgb) * COLOR.rgb;
	// No ALPHA assignment = fully opaque, writes to depth buffer
	DEPTH = ot_computed_depth;  // unified OT depth (ADR-0009)
}
