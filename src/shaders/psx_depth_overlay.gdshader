shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// Colored tile overlay. Multiplies surface by overlay_color.
// overlay_opacity controls tint strength (0 = no change, 1 = full tint).

uniform vec4 overlay_color : source_color = vec4(0.0, 0.0, 1.0, 1.0);
uniform float overlay_opacity : hint_range(0.0, 1.0) = 0.4;

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
	ALBEDO = overlay_color.rgb;
	ALPHA = overlay_opacity;
	DEPTH = computed_depth;
}
