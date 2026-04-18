// https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html

shader_type spatial;
render_mode unshaded, depth_draw_opaque;

// palette anim vars
uniform sampler2D albedo_texture_color_indicies : source_color, filter_nearest;
uniform vec4[256] palettes_colors : source_color; // 16 palettes of 16 colors each, TODO should this be an instance uniform?

// uv anim vars
uniform vec2[32] canvas_pos;
uniform vec2[32] canvas_size;
uniform vec2[32] frame_pos;
uniform float[32] frame_idx;

const int NUM_PALETTES = 16;

uniform bool debug_depth = false;

varying float face_center_depth;

void vertex() {
	vec4 centroid_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	face_center_depth = centroid_clip.z / centroid_clip.w;
}

void fragment() {
	// uv animation
	vec2 new_uv = UV;
	for (int anim_idx = 0; anim_idx < canvas_pos.length(); anim_idx++) {
		if (canvas_size[anim_idx] != vec2(0.0, 0.0)) {
			for (int palette_idx = 0; palette_idx < NUM_PALETTES; palette_idx++) { // check if UV fall within any of the palette areas
				vec2 palette_offset = vec2(float(palette_idx) / float(NUM_PALETTES), 0.0);
				vec2 palette_canvas_pos = canvas_pos[anim_idx] + palette_offset;
				vec2 canvas_max_pos = palette_canvas_pos + canvas_size[anim_idx];
				if (UV.x >= palette_canvas_pos.x && UV.x < canvas_max_pos.x && UV.y >= palette_canvas_pos.y && UV.y < canvas_max_pos.y) {
					vec2 relative_pos = UV - palette_canvas_pos;
					vec2 frame1_pos_palette = frame_pos[anim_idx] + palette_offset;
					vec2 frame_offset = vec2(frame_idx[anim_idx] * canvas_size[anim_idx].x, 0.0);
					new_uv = frame1_pos_palette + relative_pos + frame_offset;
				}
			}
		}
	}

	// palette animation/swap
	if (COLOR.rgb != vec3(0.0, 0.0, 0.0)) {
		vec4 new_color = palettes_colors[int(round(texture(albedo_texture_color_indicies, new_uv).r * 255.0))];
		if (new_color.a < 0.5) {
			discard;
		}
		ALBEDO.rgb = new_color.rgb;
	}
	else {
		ALBEDO.rgb = COLOR.rgb;
	}
	if (debug_depth) {
		// Reversed-Z: 1.0=near(blue), 0.0=far(red)
		vec3 dc;
		float d_inv = 1.0 - face_center_depth;
		if (d_inv < 0.5)
			dc = mix(vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), d_inv * 2.0);
		else
			dc = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), (d_inv - 0.5) * 2.0);
		ALBEDO = dc;
	}
	DEPTH = face_center_depth;
}