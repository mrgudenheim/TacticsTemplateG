shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// STP Semi-Trans Pass - PSX Mode 0: 50% back + 50% fore
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

	vec3 modulated = col.rgb * color_modulate;
	if (modulated.r < 0.01 && modulated.g < 0.01 && modulated.b < 0.01) {
		discard;
	}

	float d = compute_particle_depth(depth_mode);
	ALBEDO = debug_depth ? depth_to_heatmap(d) : modulated;
	ALPHA = 0.5;
	DEPTH = d;
}
