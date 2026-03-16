shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// STP Opaque Pass: Renders STP=0 pixels only (alpha=255)
// No blend mode - fully opaque, writes to depth buffer

#include "res://src/file_formats/vfx/shaders/effect_particle_common.gdshaderinc"

void fragment() {
	vec2 uv_origin = uv_rect.xy;
	vec2 uv_size = uv_rect.zw;
	vec2 uv = uv_origin + UV * uv_size;

	vec4 col = texture(effect_texture, uv);

	if (col.a < 0.9 || (col.r < 0.01 && col.g < 0.01 && col.b < 0.01)) {
		discard;
	}

	ALBEDO = col.rgb * color_modulate;
	DEPTH = tile_center_depth + z_bias;
}
