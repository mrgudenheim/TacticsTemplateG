// Shared body of the effect-callback mesh pair — everything the fold twin
// (effect_callback_fold.gdshader) and the in-scene twin (effect_callback_additive.gdshader) have in
// common: the uniforms the producer sets, the PSX display gain, the PAR vertex, and the textured/
// untextured colour the PSX would have shaded. The two entry shaders are one expression apart, and
// each owns that expression.
//
// WHY THE COLOUR EXPRESSION IS NOT SHARED. The fold twin writes the RAW display texel into the
// display-space fold scratch (Pass C converts the finished product back ONCE, there is no tonemap
// after it). The in-scene twin writes into Godot's LINEAR Forward+ HDR target, whose return leg is
// the pipeline's tonemap + sRGB encode, so it must linearize first. A `srgb ? pow(..) : ..` ternary
// shared by both is exactly the shape the 2026-07-31 fold-colour audit deleted from the particle
// family, and it cannot come back: `tools/check_no_pow_in_fold.py` fails on any `pow(` in the
// #include closure of a `compositor_layer` entry shader — a pow inside a fold is a colour-space
// round trip with no return leg (the gold-box bug class). The split is that guard's forcing
// function, and it is the shape the particle family already uses one directory over
// (effect_particle_stp.gdshaderinc shared/raw + effect_particle_native.gdshaderinc owning the pow).
//
// The FRAGMENT is duplicated rather than shared because it has to be: ALBEDO / ALPHA / DEPTH are
// fragment-scope builtins, so no helper here can assign them. The three lines the two halves have in
// common are the floor, not drift.
//
// Unified PSX Ordering-Table depth (ADR-0009): per-face centroid in CUSTOM0 (AVSZ4-baked),
// STANDARD mode (0).
// Vault: [[Effect Callback Mesh]]
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// === Uniforms — IDENTICAL on both twins, because the producer swaps only `.shader` ===
// EffectCallback._create_cb_mesh keeps one _material across the swap, so every name its per-frame
// set_shader_parameter() calls use has to exist on whichever twin is bound. Declaring them here
// rather than twice makes that parity structural instead of a thing to keep in sync by hand
// (CallbackFoldRoutingTest still asserts it, and asserts the ONLY difference is the in-scene
// half's colour-space knob).
uniform sampler2D effect_texture : filter_nearest, repeat_disable;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);  // x, y, w, h (normalized)
// use_texture / use_psx_brightness: static per-producer traits set at material-build — material
// configuration, not ADR-0074's forbidden data-driven axis branching.
uniform bool use_texture = false;
// Explicit byte/255 vertex storage -> PSX byte/128 modulation (opt-in producer).
uniform float gouraud_scale = 1.0;
uniform bool use_psx_brightness = true;  // false for callbacks with own brightness tables

// Retired psx_brightness global's display-space gain (ADR-0074 endgame); exact-retired 2.2 =
// net-neutral. Named PSX_OUTPUT_LEVEL to agree across both twins (ADR-0191 dec. 6).
const float PSX_OUTPUT_LEVEL = 2.2;

// PAR (ADR-0036): Pattern 1, full-stretch. Every callback shares this shader and builds a
// world-vertex ArrayMesh — either at world target positions (TrailProjectile ribbons) or at
// camera-axis offsets from camera_pos+cam_fwd*N (ScreenGrid/WarpedGrid/SpiralMesh/RadialRing screen
// overlays). Both want uniform clip.x stretch: world-anchored meshes follow the stretched world, and
// camera-pinned meshes fill 4:3 display by stretching their 16:15-authored layout. Pattern 2 would
// no-op the camera-pinned case (anchor near NDC 0) and misalign the world-anchored case (single
// anchor for many segments).
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	// Per-face centroid in CUSTOM0 (local space) -> MODELVIEW; STANDARD mode (0).
	ot_computed_depth = ot_depth(CUSTOM0.xyz, PROJECTION_MATRIX, MODELVIEW_MATRIX, 0);

	// PAR (Pattern 1, full-stretch, via the shared seam).
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_full(clip_pos);
}

// === The DISPLAY-SPACE colour, which is what the PSX shaded ===
// Returns `(texel * gouraud) >> 7` for the textured case and the gouraud colour itself for the
// untextured one — in DISPLAY space, unclamped. The fold twin writes it straight into the scratch
// (whose R8G8B8A8_UNORM format does the clamp in hardware, the same clamp the PSX does to the
// shaded colour before the ABR step); the in-scene twin clamps it explicitly to mirror that, then
// linearizes the FINISHED product so it lands the same colour the fold does.
//
// The STP discard lives here rather than in either twin: it is a coverage rule, not a colour rule,
// and it must be bit-identical on both routes or the two halves disagree about which pixels exist.
vec3 callback_display_color(vec2 frag_uv, vec3 gouraud) {
	float brightness = (use_psx_brightness ? PSX_OUTPUT_LEVEL : 1.0) * gouraud_scale;
	if (!use_texture) {
		return gouraud * brightness;
	}
	vec2 uv = uv_rect.xy + frag_uv * uv_rect.zw;
	vec4 tex = texture(effect_texture, uv);
	// STP filtering: only semi-transparent pixels (alpha ~0.5) survive.
	// Discard: transparent (a < 0.01), opaque (a > 0.9), or black.
	if (tex.a < 0.01 || tex.a > 0.9 || (tex.r < 0.01 && tex.g < 0.01 && tex.b < 0.01)) {
		discard;
	}
	// PSX texture blend: texel * vertex_color >> 7 (not >> 8). PSX_OUTPUT_LEVEL (2.2) compensates
	// for Godot normalizing 0x80 -> 0.5. Callbacks with own brightness tables set
	// use_psx_brightness=false.
	return tex.rgb * gouraud * brightness;
}
