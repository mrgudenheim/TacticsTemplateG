shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : filter_nearest;

#include "res://src/shaders/psx_depth_common.gdshaderinc"

void vertex() {
	computed_depth = psx_depth(
		MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX,
		INV_VIEW_MATRIX[3].xyz, depth_mode, depth_bias_custom);
}

void fragment() {
	vec4 col = texture(sprite_texture, UV) * COLOR;
	if (col.a < 0.5) {
		discard;
	}
	ALBEDO = col.rgb;
	DEPTH = computed_depth;
}
