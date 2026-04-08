shader_type spatial;
render_mode blend_mul, unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D shadow_texture : filter_nearest;
uniform float depth_bias = 0.1;

varying float biased_depth;

void vertex() {
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec3 cam_dir = normalize(INV_VIEW_MATRIX[3].xyz - world_pos);
	vec3 biased_pos = world_pos + cam_dir * depth_bias;
	vec4 clip_pos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(biased_pos, 1.0);
	biased_depth = clip_pos.z / clip_pos.w;
}

void fragment() {
	vec4 col = texture(shadow_texture, UV);
	if (col.a < 0.01) {
		discard;
	}
	ALBEDO = vec3(1.0 - col.a);
	DEPTH = biased_depth;
}
