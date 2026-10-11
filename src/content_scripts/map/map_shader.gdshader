// https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html

shader_type spatial;
render_mode unshaded, depth_draw_opaque;

const int NUM_PALETTES = 16;
const float USABLE_TEXTURE_WIDTH = 240.0 / 256.0;

// palette anim vars
uniform sampler2D albedo_texture_color_indicies : source_color, filter_nearest;
uniform vec4[256] palettes_colors : source_color; // 16 palettes of 16 colors each, TODO should this be an instance uniform?

// uv anim vars
uniform vec2[32] canvas_pos;
uniform vec2[32] canvas_size;
uniform vec2[32] frame_pos;
uniform float[32] frame_idx;

#include "res://src/shaders/psx_window_depth.gdshaderinc"

// Supplies the `color_layer_*` and `quantize` uniforms an effect writes when it tints
// the map, and the `color_apply()` that applies them. Keep in sync with
// `src/Unit/shaders/unit_sprite.gdshader`, which tints unit sprites the same way.
#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

uniform bool debug_depth = false;

// ==== PSX per-vertex lighting (MapLighting, decoded from the map's own mesh
// resource at ROM pointer 0x64) ====
//
// THE LIGHT SPACE IS THE MESH'S OWN MODEL SPACE, NOT WORLD SPACE. FFT stores normals
// and light directions in one coordinate system and TacticsG carries the normals
// through untouched, so the dot product is taken against the raw `NORMAL` attribute
// before any model matrix. That also makes the lighting immune to a chunk's
// `mirror_xyz` and to node placement — mirroring a chunk for layout must not relight
// it.
//
// `light_gains` are GAINS, not colours: components above 1.0 are normal (MAP062's key
// light is 2.37, 2.07, 1.87). Nothing clamps until the final pixel.
uniform bool lighting_enabled = false;
// A/B toggle for debugging only. TRUE is the faithful path and the default; see the
// dark-valley note on `v_diffuse`.
uniform bool lighting_per_vertex = true;
uniform vec3 ambient_light = vec3(1.0);
uniform vec3 light_gains[3];
uniform vec3 light_directions[3];

varying float face_center_depth;
varying float hide_polygon;

// Lit once per VERTEX, as the PS1 did, and interpolated across the face. Lighting per
// PIXEL instead puts a dark band across any face straddling two lights: at mid-face both
// dot products clamp to 0 and the pixel drops to ambient between two bright corners.
varying vec3 v_diffuse;
// Only read when `lighting_per_vertex` is false, i.e. the debug comparison path.
varying vec3 v_normal;

// Sum the three lights against a normal, each clamped at 0 - a light behind the
// surface contributes nothing. Shared by both paths so only the sample rate differs.
vec3 psx_diffuse(vec3 n) {
	vec3 lit = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		float d = dot(n, light_directions[i]);
		if (d > 0.0) {
			lit += light_gains[i] * d;
		}
	}
	return lit;
}

void vertex() {
	v_normal = NORMAL;
	v_diffuse = psx_diffuse(normalize(NORMAL));

	vec4 centroid_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	face_center_depth = psx_window_depth(centroid_clip.z / centroid_clip.w);

	hide_polygon = 0.0;
	// see MapData.DirectionFlag
	int hidden_bitflags = int(round(CUSTOM0.a));
	if (CAMERA_DIRECTION_WORLD.x == 0.0 && CAMERA_DIRECTION_WORLD.z == 0.0 && hidden_bitflags != 0) { // hide all hideable if camera faces directly up or down
		hide_polygon = 1.0;
	} else if ((hidden_bitflags & 1) == 1 && CAMERA_DIRECTION_WORLD.x <= 0.0 && CAMERA_DIRECTION_WORLD.z <= 0.0) { // hide NORTHEAST flagged polygons
		hide_polygon = 1.0;
	} else if ((hidden_bitflags & 2) == 2 && CAMERA_DIRECTION_WORLD.x >= 0.0 && CAMERA_DIRECTION_WORLD.z <= 0.0) { // hide NORTHWEST flagged polygons
		hide_polygon = 1.0;
	} else if ((hidden_bitflags & 4) == 4 && CAMERA_DIRECTION_WORLD.x <= 0.0 && CAMERA_DIRECTION_WORLD.z >= 0.0) { // hide SOUTHEAST flagged polygons
		hide_polygon = 1.0;
	} else if ((hidden_bitflags & 8) == 8 && CAMERA_DIRECTION_WORLD.x >= 0.0 && CAMERA_DIRECTION_WORLD.z >= 0.0) { // hide SOUTHWEST flagged polygons
		hide_polygon = 1.0;
	}
}

void fragment() {
	// hide obstructing polygons
	if (hide_polygon != 0.0) {
		discard;
	}

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
					float frame_row = floor(frame_idx[anim_idx] * canvas_size[anim_idx].x / (USABLE_TEXTURE_WIDTH / float(NUM_PALETTES)));
					float frame_vert_offset = frame_row * canvas_size[anim_idx].y;
					float frame_horz_offset = mod(frame_idx[anim_idx] * canvas_size[anim_idx].x, (USABLE_TEXTURE_WIDTH / float(NUM_PALETTES)));
					vec2 frame_offset = vec2(frame_horz_offset, frame_vert_offset);
					new_uv = frame1_pos_palette + relative_pos + frame_offset;
				}
			}
		}
	}

	// palette animation/swap
	// COLOR here is a SWITCH, not shading: a non-black vertex colour selects the
	// textured/palette path, black selects the untextured "black polygon" path.
	if (COLOR.rgb != vec3(0.0, 0.0, 0.0)) {
		vec4 new_color = palettes_colors[int(round(texture(albedo_texture_color_indicies, new_uv).r * 255.0))];
		if (new_color.a < 0.5) {
			discard;
		}
		// TINT FIRST, THEN LIGHT. The effect palette track is a CLUT REWRITE: the PSX
		// changes the palette entry and the polygon is lit THROUGH the modified entry.
		// Folding the tint after the lighting multiply gives a tint that barely moves a
		// dark face and blows out a bright one.
		vec3 base = color_apply(new_color.rgb, 0);
		if (lighting_enabled) {
			vec3 diffuse = lighting_per_vertex ? v_diffuse : psx_diffuse(normalize(v_normal));
			// The only clamp in the model: pixel = texture x (ambient + SUM gain *
			// max(0, N.L)), saturated at the end. Do not add an `ambient x 1.5` fudge —
			// that compensates for clamping gains to white, which this does not do.
			base = clamp(base * (ambient_light + diffuse), vec3(0.0), vec3(1.0));
		}
		ALBEDO.rgb = base;
	}
	else {
		// Untextured flat-colour polygons carry no palette index and no normal, so there
		// is nothing to tint or light.
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