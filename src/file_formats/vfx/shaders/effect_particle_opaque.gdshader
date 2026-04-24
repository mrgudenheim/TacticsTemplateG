shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// STP Opaque Pass: Renders STP=0 pixels only (alpha=255)
// No blend mode - fully opaque, writes to depth buffer

#include "res://src/file_formats/vfx/shaders/effect_particle_common.gdshaderinc"

uniform bool semi_trans_on = true;

void fragment() {
	vec2 uv_origin = uv_rect.xy;
	vec2 uv_size = uv_rect.zw;
	vec2 uv = uv_origin + UV * uv_size;

	vec4 col = texture(effect_texture, uv);

	// When semi_trans_on=true (normal): discard STP=1 pixels (alpha < 0.9) — they render in semi-trans pass
	// When semi_trans_on=false: render ALL non-black pixels as opaque (no semi-trans pass exists)
	float alpha_threshold = semi_trans_on ? 0.9 : 0.01;
	if (col.a < alpha_threshold) {
		discard;
	}

	// Apply color curve modulation, then discard if result is black
	vec3 modulated = col.rgb * color_modulate;
	if (modulated.r < 0.01 && modulated.g < 0.01 && modulated.b < 0.01) {
		discard;
	}

	float d = compute_particle_depth(depth_mode);
	ALBEDO = debug_depth ? depth_to_heatmap(d) : modulated;
	DEPTH = d;
}
