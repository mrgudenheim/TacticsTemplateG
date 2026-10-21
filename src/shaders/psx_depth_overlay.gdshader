shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// Colored tile overlay. Multiplies surface by overlay_color.
// overlay_opacity controls tint strength (0 = no change, 1 = full tint).

uniform vec4 overlay_color : source_color = vec4(0.0, 0.0, 1.0, 1.0);
uniform float overlay_opacity : hint_range(0.0, 1.0) = 0.4;
uniform vec3 depth_position = vec3(0.0, 0.0, 0.0);

#include "res://src/shaders/psx_depth_common.gdshaderinc"

void vertex() {
	// Sorts at `depth_position`, not at the mesh origin.
	computed_depth = psx_depth(
		depth_position, PROJECTION_MATRIX, VIEW_MATRIX,
		INV_VIEW_MATRIX[3].xyz, depth_mode, depth_bias_custom);
}

void fragment() {
	ALBEDO = overlay_color.rgb;
	ALPHA = overlay_opacity;
	DEPTH = computed_depth;
}
