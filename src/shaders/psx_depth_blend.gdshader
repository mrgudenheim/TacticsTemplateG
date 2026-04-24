shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D sprite_texture : filter_nearest;

#include "res://src/shaders/psx_depth_common.gdshaderinc"

void vertex() {
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec3 cam_dir = normalize(INV_VIEW_MATRIX[3].xyz - world_pos);
	float bias = depth_bias_custom;
	if (depth_mode == 1) bias = bias_pull_8;
	else if (depth_mode == 2) bias = bias_fixed_front;
	else if (depth_mode == 3) bias = bias_fixed_back;
	else if (depth_mode == 4) bias = bias_fixed_16;
	else if (depth_mode == 5) bias = bias_pull_16;
	else if (depth_mode == 6) bias = bias_unit;
	else if (depth_mode == 7) bias = bias_tile_overlay;
	vec4 clip_pos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + cam_dir * bias, 1.0);
	computed_depth = clip_pos.z / clip_pos.w;
}

void fragment() {
	vec4 col = texture(sprite_texture, UV) * COLOR;
	if (col.a < 0.01 || (col.r < 0.01 && col.g < 0.01 && col.b < 0.01)) {
		discard;
	}
	ALBEDO = col.rgb;
	ALPHA = 0.5;
	DEPTH = computed_depth;
}
