// PSX-style depth sorting for any 3D object.
// Computes depth from the object's world position shifted toward the camera
// by a configurable bias, matching the PSX ordering table behavior.
//
// Usage: #include this file, then in vertex() paste: PSX_DEPTH_VERTEX
// In fragment(): write DEPTH = computed_depth;
//
// depth_mode values match VfxConstants.DepthMode:
//   0 = STANDARD (no bias)
//   1 = PULL_FORWARD_8
//   2 = FIXED_FRONT
//   3 = FIXED_BACK
//   4 = FIXED_16
//   5 = PULL_FORWARD_16
//   6 = UNIT (small forward bias for unit sprites/shadows)

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
