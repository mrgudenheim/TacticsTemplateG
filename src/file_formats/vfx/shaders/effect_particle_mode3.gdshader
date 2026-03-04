shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

// STP Semi-Trans Pass - PSX Mode 3: back + 25% fore (subtle additive)
// Only renders STP=1 pixels (alpha=128), discards opaque (alpha=255)

uniform sampler2D effect_texture : filter_nearest, repeat_disable;
uniform vec2 texture_size = vec2(128.0, 256.0);

uniform vec2 corner_tl;
uniform vec2 corner_tr;
uniform vec2 corner_bl;
uniform vec2 corner_br;
uniform vec4 uv_rect_data;
uniform float z_bias = 0.0;

varying vec4 uv_rect;
varying float tile_center_depth;

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

	vec4 clip_pos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	tile_center_depth = clip_pos.z / clip_pos.w * 0.5 + 0.5;

	const float PSX_SCALE = 1.0 / 28.0;
	VERTEX.x = corner.x * PSX_SCALE;
	VERTEX.y = -corner.y * PSX_SCALE;
	VERTEX.z = 0.0;
}

void fragment() {
	vec2 uv_origin = uv_rect.xy;
	vec2 uv_size = uv_rect.zw;
	vec2 uv = uv_origin + UV * uv_size;

	vec4 col = texture(effect_texture, uv);

	if (col.a < 0.01 || col.a > 0.9 || (col.r < 0.01 && col.g < 0.01 && col.b < 0.01)) {
		discard;
	}

	ALBEDO = col.rgb * 0.25;
	ALPHA = 1.0;
	DEPTH = tile_center_depth + z_bias;
}
