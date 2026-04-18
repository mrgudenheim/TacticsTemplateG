// Common uniforms, varyings, and vertex function for STP effect particle shaders.

uniform sampler2D effect_texture : filter_nearest, repeat_disable;
uniform vec2 texture_size = vec2(128.0, 256.0);

uniform vec2 corner_tl;
uniform vec2 corner_tr;
uniform vec2 corner_bl;
uniform vec2 corner_br;
uniform vec4 uv_rect_data;  // x, y, w, h (normalized)
uniform int depth_mode = 0;
uniform vec3 color_modulate = vec3(1.0);
uniform bool debug_depth = false;
uniform float depth_scale = 1.0;
uniform float bias_pull_8 = 3.0;
uniform float bias_pull_16 = 6.0;
uniform float bias_fixed_front = 100.0;
uniform float bias_fixed_back = -100.0;
uniform float bias_fixed_16 = 80.0;

varying vec4 uv_rect;
varying float tile_center_depth;
// Precomputed biased depths for each mode (computed in vertex shader
// where PROJECTION_MATRIX/VIEW_MATRIX are available)
varying float depth_mode_1; // PULL_FORWARD_8
varying float depth_mode_2; // FIXED_FRONT
varying float depth_mode_3; // FIXED_BACK
varying float depth_mode_4; // FIXED_16
varying float depth_mode_5; // PULL_FORWARD_16

void vertex() {
	uv_rect = uv_rect_data;

	vec2 top = mix(corner_tl, corner_tr, UV.x);
	vec2 bottom = mix(corner_bl, corner_br, UV.x);
	vec2 corner = mix(top, bottom, UV.y);

	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);

	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec3 cam_dir = normalize(INV_VIEW_MATRIX[3].xyz - world_pos);

	vec4 clip_pos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
	tile_center_depth = clip_pos.z / clip_pos.w;

	// Precompute biased depths for all modes: shift position toward camera
	vec4 c1 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + cam_dir * bias_pull_8 * depth_scale, 1.0);
	depth_mode_1 = c1.z / c1.w;
	vec4 c2 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + cam_dir * bias_fixed_front, 1.0);
	depth_mode_2 = c2.z / c2.w;
	vec4 c3 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + cam_dir * bias_fixed_back, 1.0);
	depth_mode_3 = c3.z / c3.w;
	vec4 c4 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + cam_dir * bias_fixed_16, 1.0);
	depth_mode_4 = c4.z / c4.w;
	vec4 c5 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos + cam_dir * bias_pull_16 * depth_scale, 1.0);
	depth_mode_5 = c5.z / c5.w;

	const float PSX_SCALE = 1.0 / 28.0;
	VERTEX.x = corner.x * PSX_SCALE;
	VERTEX.y = -corner.y * PSX_SCALE;
	VERTEX.z = 0.0;
}

vec3 depth_to_heatmap(float depth) {
	float d_inv = 1.0 - depth;
	if (d_inv < 0.5)
		return mix(vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), d_inv * 2.0);
	else
		return mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), (d_inv - 0.5) * 2.0);
}

float compute_particle_depth(int mode) {
	if (mode == 1) return depth_mode_1;  // PULL_FORWARD_8
	if (mode == 2) return depth_mode_2;  // FIXED_FRONT
	if (mode == 3) return depth_mode_3;  // FIXED_BACK
	if (mode == 4) return depth_mode_4;  // FIXED_16
	if (mode == 5) return depth_mode_5;  // PULL_FORWARD_16
	return tile_center_depth;            // STANDARD (mode 0)
}
