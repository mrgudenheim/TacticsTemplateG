shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform vec4[16] palette_colors : source_color; // palette of 16 colors each
uniform vec3 unit_tint = vec3(0.0, 0.0, 0.0);
uniform bool billboard_enabled = false;

#include "res://src/shaders/psx_depth_common.gdshaderinc"

// An effect recolours a unit by changing the colours in its palette. `TintedSurfaces`
// writes those changes into the `color_layer_*` uniforms below, keyed by the unit's
// `char_body` instance id, and `color_apply()` applies them to each texel.
// A unit is only keyed in once `UnitSpritesManager.bind_tint_surface` registers it;
// until then the layer arrays are empty and `color_apply()` returns its input unchanged.
// The map is recoloured the same way, in `src/content_scripts/map/map_shader.gdshader`.
#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

// Which of the unit's THREE parts this material paints — body, weapon or effect sprite.
// `color_apply()` tests each colour change against `1 << color_surface_id`, so the three
// must be given DISTINCT ids, or a change meant for one of them recolours all three.
// `UnitSpritesManager.SURFACE_BODY/WEAPON/EFFECT` sets this per material. The default of
// 0 is for materials never registered at all, such as the status icon on `unit.tscn`.
uniform int color_surface_id : hint_range(0, 2) = 0;

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
	
	computed_depth = psx_depth(
		MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX,
		INV_VIEW_MATRIX[3].xyz, depth_mode, depth_bias_custom);
}

void fragment() {
	vec4 tex = texture(sprite_texture, UV);
	int palette_index = int(round(tex.x * 255.0));
	tex = palette_colors[palette_index];
	vec4 col = tex * COLOR;
	if (col.a < 0.5) {
		discard;
	}
	// ORDER MATTERS: the effect's colours REPLACE the palette entry, then `unit_tint` is
	// added on top of the result. On the PSX an effect edits the palette itself and
	// everything downstream reads the edited colour, which is also why `TintedSurfaces`
	// asks for quantize=true — the palette is 5 bits per channel. `unit_tint` is
	// TacticsG's own highlight and was never in that palette, so it cannot go first.
	ALBEDO = clamp(color_apply(col.rgb, color_surface_id) + unit_tint, vec3(0.0), vec3(1.0));
	DEPTH = computed_depth;
}
