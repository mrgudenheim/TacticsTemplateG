// Unified PSX Ordering-Table depth.
//
// FFT draws the battle scene back-to-front via a PSX Ordering Table (OT):
// every primitive — terrain face, unit sprite, effect particle, overlay —
// gets one OT bucket from the projected Z of a single representative point,
// plus a per-primitive DepthMode bias. This is ONE model, not several; see
// docs/adr/0009-ordering-table-depth-is-one-model.md and the "Rendering
// depth" cluster in CONTEXT.md.
//
// Usage (every battle shader that writes DEPTH):
//   #include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"
//   void vertex() { ot_computed_depth = ot_depth(<point>, PROJECTION_MATRIX, <to_view>, <mode>); }
//   void fragment() { DEPTH = ot_computed_depth; }
//
// Pick three things at the call site:
//   • <point> + <to_view> — by where the point lives:
//       per-face centroid in CUSTOM0 (LOCAL): (CUSTOM0.xyz, MODELVIEW_MATRIX)  — the map / multi-face meshes
//       object origin MODEL_MATRIX[3].xyz (WORLD): (MODEL_MATRIX[3].xyz, VIEW_MATRIX) — single-node sprites/particles/overlays
//   • <mode> — the DepthMode selector. The include does NOT declare it, because
//     mode choice is per-shader policy:
//       fixed-mode shaders pass a LITERAL (e.g. 7 for a tile overlay, 0 for terrain);
//       variable-mode shaders (particles) declare their own `uniform int depth_mode`
//       and pass it (set per draw via DepthMode.apply()).
//
// `to_view` is whatever matrix brings `point` into view space: MODELVIEW for a
// LOCAL point, VIEW for a WORLD point. The function multiplies proj * to_view *
// point, so the caller picks the pairing; the function stays space-agnostic.
//
// REVERSED-Z: Godot Forward+ writes DEPTH with near/front = 1.0, far/behind
// = 0.0 — the INVERSE of FFT's OT convention (higher bucket = drawn first =
// behind). That inversion is the single most error-prone fact here, so it
// lives in exactly one place: this function. No call site reasons about it.
//
// CAMERA NOTE (why bias is a calibration, not a derivation): our combat
// camera is TRUE orthographic, so shifting a point toward the camera by a
// world distance d is exactly d * PROJECTION_MATRIX[2][2] in reversed-Z NDC
// (no cam_dir needed). FFT's camera, by contrast, has no ortho mode — it
// APPROXIMATES ortho with a distant perspective projection, so its OT bucket
// spacing is Z-dependent. There is therefore no exact bucket->world mapping
// between the two; ot_units_per_bucket is an empirical anchor tuned in
// DepthDebugScene, NOT a closed-form constant. Do not "fix" it with a formula.

// === Calibration + bias magnitudes (authoritative values in addons/exmateria_schema/compositing_key/DepthMode.gd;
//     these defaults mirror them and are pushed by DepthMode.apply()). ===
// Godot world-units per PSX OT bucket. Anchor: 8 buckets ~= 1.5 tiles, and
// 1 tile = 1 Godot unit (= FFT_UNITS_PER_TILE = 28 FFT units). Tuned in DepthDebugScene.
uniform float ot_units_per_bucket = 0.19;
// Project-specific sub-bucket nudges (NOT ROM particle modes): "slightly in
// front of the thing under me", far smaller than PULL_FORWARD_8.
uniform float ot_unit_forward = 0.13;         // UNIT: sprite just in front of its tile (DepthMode.UNIT_FORWARD authoritative)
uniform float ot_tile_overlay_forward = 0.05; // TILE_OVERLAY: between tile surface and unit
uniform float ot_shadow_forward = 0.05;       // SHADOW: unit's ground shadow, one hair behind the sprite
uniform float ot_map_skirt_back = -0.02;      // MAP_SKIRT: border geometry just behind textured map
// Fixed-mode absolute reversed-Z slots (near/front ~ 1.0, far/behind ~ 0.0).
uniform float ot_fixed_front = 0.9999; // FIXED_FRONT
uniform float ot_fixed_16 = 0.9990;    // FIXED_16 (just behind FIXED_FRONT)
uniform float ot_fixed_back = 0.0001;  // FIXED_BACK

// === Vertex -> fragment carrier (flat depth: same value across the primitive) ===
varying float ot_computed_depth;

// Compute the reversed-Z DEPTH for a primitive's representative point.
// `to_view` brings `point` into view space (MODELVIEW for a local CUSTOM0
// point, VIEW for a world object point). mode values match DepthMode.Mode:
// 0 STANDARD, 1 PULL_FORWARD_8, 2 FIXED_FRONT, 3 FIXED_BACK, 4 FIXED_16,
// 5 PULL_FORWARD_16, 6 UNIT, 7 TILE_OVERLAY, 8 MAP_SKIRT, 9 SHADOW.
float ot_depth(vec3 point, mat4 proj, mat4 to_view, int mode) {
	// Fixed modes: absolute OT slots — ignore the point entirely.
	if (mode == 2) return ot_fixed_front;
	if (mode == 3) return ot_fixed_back;
	if (mode == 4) return ot_fixed_16;

	// Base depth: project the representative point (reversed-Z NDC).
	vec4 clip = proj * to_view * vec4(point, 1.0);
	float base = clip.z / clip.w;

	// Relative modes: shift toward camera by a world distance, then (for our
	// ortho camera) add distance * PROJECTION_MATRIX[2][2]. Reversed-Z: a
	// toward-camera (forward) shift ADDS to DEPTH.
	float world_bias = 0.0;
	if (mode == 1) world_bias = 8.0 * ot_units_per_bucket;   // PULL_FORWARD_8
	else if (mode == 5) world_bias = 16.0 * ot_units_per_bucket; // PULL_FORWARD_16
	else if (mode == 6) world_bias = ot_unit_forward;        // UNIT
	else if (mode == 7) world_bias = ot_tile_overlay_forward; // TILE_OVERLAY
	else if (mode == 8) world_bias = ot_map_skirt_back;      // MAP_SKIRT (negative = behind)
	else if (mode == 9) world_bias = ot_shadow_forward;      // SHADOW (co-sorts with the unit's point)
	// mode 0 STANDARD: world_bias stays 0.

	float ndc_depth = base + world_bias * proj[2][2];
	// Compatibility projects Z into [-1, 1], but fragment DEPTH is [0, 1].
	// Convert AFTER bias so its magnitude scales too. This is a range conversion,
	// not a reversed-Z inversion; the fixed depth-buffer slots above are already [0, 1].
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return ndc_depth * 0.5 + 0.5;
#else
	return ndc_depth;
#endif
}
