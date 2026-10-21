shader_type spatial;
render_mode unshaded, cull_disabled;

// Solid-color billboard for DepthDebugScene: renders a quad through the unified
// OT depth seam (ADR-0009) so the calibration constants can be eyeballed.
// Per-object path (world origin + VIEW); depth_mode set per material.
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform vec4 debug_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int depth_mode = 0;

void vertex() {
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, depth_mode);
}

void fragment() {
	ALBEDO = debug_color.rgb;
	DEPTH = ot_computed_depth;
}
