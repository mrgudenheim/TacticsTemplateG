shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform vec4[16] palette_colors : source_color; // palette of 16 colors each
uniform vec3 unit_tint = vec3(0.0, 0.0, 0.0);
uniform bool billboard_enabled = false;

#include "res://src/shaders/psx_depth_common.gdshaderinc"

void vertex() {
	if (billboard_enabled) {
		mat4 modified_model_view = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], // Camera X (Right vector)
			INV_VIEW_MATRIX[1], // Camera Y (Up vector)
			INV_VIEW_MATRIX[2], // Camera Z (Forward vector)
			MODEL_MATRIX[3]     // Keeps the object's original 3D position
		);
		MODELVIEW_MATRIX = modified_model_view;
		// Fix normals so lighting doesn't break
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	
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
	vec4 tex = texture(sprite_texture, UV);
	int palette_index = int(round(tex.x * 255.0));
	tex = palette_colors[palette_index];
	vec4 col = tex * COLOR;
	if (col.a < 0.5) {
		discard;
	}
	ALBEDO = clamp(col.rgb + unit_tint, vec3(0.0), vec3(1.0));
	DEPTH = computed_depth;
}
