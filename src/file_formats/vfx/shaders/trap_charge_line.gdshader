shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float bias_pull_8 = 3.0;

varying float computed_depth;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam_dir = normalize(INV_VIEW_MATRIX[3].xyz - world_pos);
	vec4 clip_pos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + cam_dir * bias_pull_8, 1.0);
	computed_depth = clip_pos.z / clip_pos.w;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;
	DEPTH = computed_depth;
}
