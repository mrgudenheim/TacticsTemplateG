// PSX-style depth sorting for any 3D object.
// Computes depth from the object's world position shifted toward the camera
// by a configurable bias, matching the PSX ordering table behavior.
//
// Usage: #include this file, then
//   void vertex() {
//       computed_depth = psx_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX,
//           VIEW_MATRIX, INV_VIEW_MATRIX[3].xyz, depth_mode, depth_bias_custom);
//   }
//   void fragment() { DEPTH = computed_depth; }
//
// Pass a different first argument when the sort point is not the object
// origin — psx_depth_overlay passes its `depth_position` uniform.
//
// The bias is a shift of the sort POINT through the world, applied before
// projection, so it means the same world distance under either camera
// projection. The camera is orthographic by default but there is a live
// perspective toggle (camera_controller.on_orthographic_toggled, wired to
// battle_manager's OrthographicCheckBox), so the bias must not be expressed
// as a fixed offset in NDC.
//
// depth_mode values match VfxConstants.DepthMode:
//   0 = STANDARD (no bias — falls through to depth_bias_custom)
//   1 = PULL_FORWARD_8
//   2 = FIXED_FRONT
//   3 = FIXED_BACK
//   4 = FIXED_16
//   5 = PULL_FORWARD_16
//   6 = UNIT (small forward bias for unit sprites/shadows)
//   7 = TILE_OVERLAY

// The [-1,1] -> [0,1] window-depth conversion, and why it is needed.
#include "res://src/shaders/psx_window_depth.gdshaderinc"

uniform int depth_mode : hint_range(0, 7) = 0;
uniform float depth_bias_custom = 0.0;

uniform float bias_pull_8 = 3.0;
uniform float bias_pull_16 = 6.0;
uniform float bias_fixed_front = 100.0;
uniform float bias_fixed_back = -100.0;
uniform float bias_fixed_16 = 80.0;
uniform float bias_unit = 0.1;
uniform float bias_tile_overlay = 0.05;

varying float computed_depth;

// World-unit shift toward the camera for a depth mode. Modes outside 1..7 use
// the caller's custom bias, which defaults to 0 — that is mode 0 STANDARD.
float psx_depth_bias(int mode, float custom_bias) {
	if (mode == 1) return bias_pull_8;
	if (mode == 2) return bias_fixed_front;
	if (mode == 3) return bias_fixed_back;
	if (mode == 4) return bias_fixed_16;
	if (mode == 5) return bias_pull_16;
	if (mode == 6) return bias_unit;
	if (mode == 7) return bias_tile_overlay;
	return custom_bias;
}

// Depth for one primitive's representative point. `cam_pos` is the camera's
// world position (INV_VIEW_MATRIX[3].xyz); the point is shifted toward it by
// the mode's bias, then projected.
float psx_depth(vec3 world_pos, mat4 proj, mat4 view, vec3 cam_pos, int mode, float custom_bias) {
	vec3 cam_dir = normalize(cam_pos - world_pos);
	float bias = psx_depth_bias(mode, custom_bias);
	vec4 clip_pos = proj * view * vec4(world_pos + cam_dir * bias, 1.0);
	return psx_window_depth(clip_pos.z / clip_pos.w);
}
