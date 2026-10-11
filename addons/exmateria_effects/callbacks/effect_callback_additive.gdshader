shader_type spatial;
// compositor-exempt: off-fork-fallback effect_callback_fold.gdshader — routed through the compositor on Forward+ via that twin
// (EffectCallback loads that compositor_layer variant when CompositorAutopilot owns compositing). This
// in-scene blend_add file is the Mobile/stock fallback only, so it is not a Forward+ lock-in blocker.
// display-space: folds-on-fork effect_callback_fold.gdshader
// (callbacks fold on the fork; the pick is EffectCallback.blend_shader -> Fold.shader.) PSX blends in DISPLAY space and this in-scene
// file blends in LINEAR — correct only because it is the off-fork path.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Unified PSX Ordering-Table depth (ADR-0009): per-face centroid in CUSTOM0
// (AVSZ4-baked), STANDARD mode.
// Vault: [[Effect Callback Mesh]]
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

uniform sampler2D effect_texture : filter_nearest, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);  // x, y, w, h (normalized)
uniform bool use_texture = false;
uniform bool use_psx_brightness = true;  // false for callbacks with own brightness tables

// Shared PSX color calibration globals (tunable via ShaderCalibrationPanel)
const float PSX_OUTPUT_LEVEL = 2.2;  // was the deleted psx_brightness global (ADR-0074 endgame);
                                     // the non-fold fallback keeps its own output level.

// PAR (ADR-0036): Pattern 1, full-stretch. Every callback shares this shader
// and builds a world-vertex ArrayMesh — either at world target positions
// (TrailProjectile ribbons) or at camera-axis offsets from camera_pos+cam_fwd*N
// (ScreenGrid/WarpedGrid/SpiralMesh/RadialRing screen overlays). Both want
// uniform clip.x stretch: world-anchored meshes follow the stretched world,
// and camera-pinned meshes fill 4:3 display by stretching their 16:15-authored
// layout. Pattern 2 would no-op the camera-pinned case (anchor near NDC 0)
// and misalign the world-anchored case (single anchor for many segments).
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	// Per-face centroid in CUSTOM0 (local space) -> MODELVIEW; STANDARD mode (0).
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);

	// PAR (Pattern 1, full-stretch, via the shared seam).
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_full(clip_pos);
}

void fragment() {
	float brightness = use_psx_brightness ? PSX_OUTPUT_LEVEL : 1.0;
	if (use_texture) {
		vec2 uv = uv_rect.xy + UV * uv_rect.zw;
		vec4 tex = texture(effect_texture, uv);
		// STP filtering: only render semi-transparent pixels (alpha ~0.5)
		// Discard: transparent (a < 0.01), opaque (a > 0.9), or black
		if (tex.a < 0.01 || tex.a > 0.9 || (tex.r < 0.01 && tex.g < 0.01 && tex.b < 0.01)) {
			discard;
		}
		// PSX texture blend: texel * vertex_color >> 7 (not >> 8).
		// psx_brightness (default 2.2) compensates for Godot normalizing 0x80 → 0.5.
		// Callbacks with own brightness tables set use_psx_brightness=false.
		ALBEDO = tex.rgb * COLOR.rgb * brightness;
		ALPHA = 1.0;
	} else {
		ALBEDO = COLOR.rgb * brightness;
		ALPHA = 1.0;
	}
	DEPTH = ot_computed_depth;
}
