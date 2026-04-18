shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// STP Semi-Trans Pass - PSX Mode 3: back + 25% fore (subtle additive)
// Only renders STP=1 pixels (alpha=128), discards opaque (alpha=255)

#include "res://src/file_formats/vfx/shaders/effect_particle_common.gdshaderinc"

void fragment() {
	vec2 uv_origin = uv_rect.xy;
	vec2 uv_size = uv_rect.zw;
	vec2 uv = uv_origin + UV * uv_size;

	vec4 col = texture(effect_texture, uv);

	if (col.a < 0.01 || col.a > 0.9) {
		discard;
	}

	vec3 modulated = col.rgb * 0.25 * color_modulate;
	if (modulated.r < 0.01 && modulated.g < 0.01 && modulated.b < 0.01) {
		discard;
	}

	float d = compute_particle_depth(depth_mode);
	ALBEDO = debug_depth ? depth_to_heatmap(d) : modulated;
	ALPHA = 1.0;
	DEPTH = d;
}
