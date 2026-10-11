// FOLD half of the effect-particle body — included by the three `compositor_layer` entry shaders
// effect_fold_{add,mix,sub} (ADR-0191 dec. 6, on the cursor_fold_* pattern that has shipped since
// #229). Each entry is a render_mode line, its markers, and this include.
//
// Its IN-SCENE twin is effect_particle_native.gdshaderinc, included by effect_native_{add,mix,sub}.
// The two are one expression apart — the ALBEDO line — and everything above it is SHARED one level
// down in effect_particle_stp.gdshaderinc (uniforms, the billboard vertex, stp_sample,
// ot_computed_depth). This file was that shared body for all six until #1352 split the colour space
// out; see the native file's header for why a flag could not do the job.
//
// WHY SIX FILES AND NOT ONE: `render_mode` is COMPILE-TIME. The blend (add / mix / sub) and layer
// membership (`compositor_layer` or not) can only be chosen by declaring them, so two files per blend
// is the floor.
//
// THE FOLD/NATIVE SPLIT IS NOW A ROUTE, not only the #7916 compare toggle (#1352). EngineFoldCompositor
// selects the native set when native_blend = true, and CompositorAutopilot sets that from the BUILD
// predicate: a build without the `compositor_layer` primitive cannot fold, so it renders the twins
// in-scene instead of standing down — which is what made transparent effect particles silently vanish
// off-fork. On the fork the same toggle is still the manual comparison the demo wants. Both sets are
// Forward+ — deliberately NOT the Mobile fallback (effect_callback_additive), which would confound
// "clamped vs native blend" with "Forward+ vs Mobile". Same renderer, only the layer differs.
//
// OCCLUSION (2026-07-27): depth-test ENABLED (depth_test_disabled dropped), depth_draw_never KEPT. The
// engine fold pass binds the shared opaque scene depth (render_forward_clustered.cpp: framebuffer =
// fold color + rb->get_depth_texture(), LOADed) and tests DEPTH with GREATER_OR_EQUAL (reversed-Z).
// `DEPTH = ot_computed_depth` is the same reversed-Z NDC the opaque scene writes, so a folded prim
// behind a unit or wall is culled per-fragment; depth_draw_never means effects still fold against EACH
// OTHER in render_layer_order (OTDepthPrimOrder), not against depth.
//
// COLOUR — display-space RAW (PSX ABR: dst ± src·gouraud/128). The fold scratch is display-space sRGB
// with no tonemap after, so the texel is used RAW: NO pow(texel_blend_gamma). The old
// `srgb_to_linear ? pow(..) : col.rgb` ternary was structurally dead here and was removed so the
// raw-display contract cannot regress on a stray flag flip; `tools/check_no_pow_in_fold.py` walks this
// file's #include closure and enforces it. Mirrors the gold-box fix (formation_box_fold) and
// feedback_hud_sprite_additive_fold. The pow the IN-SCENE twin needs lives in that twin's own file,
// outside this closure — the same shape as tile_overlay_clut.gdshaderinc / tile_overlay.gdshaderinc.
// COLOR.rgb already carries the pool-envelope -> display-gouraud gain (ADR-0074 endgame): the ÷255->÷128
// scale that used to be `* psx_brightness` here is baked into COLOR by EngineFoldCompositor
// (POOL_GOURAUD_GAIN), so this fragment is a clean texel x gouraud/128 with NO global uniform —
// psx_brightness is off the fold contract (check_no_psx_brightness_in_fold.py).
// [particle fold-color audit 2026-07-31: pow proved inactive, the fold is a scalar multiply.]
// Vault: [[Display Space Blend Fold]]
//
// EFFECT_STP_ALPHA is the one value the six do not share, and it is not a knob: it is what each blend
// mode needs from ALPHA.
//   blend_add / blend_sub -> 1.0. Godot's blend_sub is color_blend_op = REVERSE_SUBTRACT with
//     alpha_blend_op = ADD (src_alpha = SRC_ALPHA, dst_alpha = ONE), so COLOR subtracts while ALPHA
//     still ACCUMULATES the coverage mask, which is what Pass C's coverage-discard reads. The clean
//     compositor_layer engine therefore drops the spike's forced coverage-alpha override.
//   blend_mix -> 0.5. ALPHA drives the colour blend's SRC_ALPHA / ONE_MINUS_SRC_ALPHA (0.5·src +
//     0.5·dst); Godot's blend_mix alpha_blend_op = ADD keeps ALPHA positive for covered fragments, so
//     coverage survives without the spike's dropped coverage-alpha override.
// It is DECLARED BY EACH STUB and has no default here on purpose: an `#ifndef ... 1.0` fallback would
// let a new entry that forgot the define compile clean and silently render at the wrong alpha, which
// is the silent-wrong-frame failure this whole subsystem exists to stop having. With no default, a
// missing define is an undeclared identifier — a compile error ShaderCompileTest catches. The rule
// spans BOTH halves: effect_particle_native.gdshaderinc declares no default either.

#include "res://addons/exmateria_effects/render/effect_particle_stp.gdshaderinc"

void fragment() {
	vec4 col = stp_sample(UV);
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = EFFECT_STP_ALPHA;
	DEPTH = ot_computed_depth;
}
