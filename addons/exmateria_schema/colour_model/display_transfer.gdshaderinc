// Display<->linear transfer function, decided ONCE.
//
// The in-scene battle render is authored in DISPLAY (sRGB) space. The final ALBEDO must
// be in whatever space the active renderer's output stage expects:
//   * Forward+ / Mobile (OUTPUT_IS_SRGB == false): the target is linear HDR; ALBEDO must
//     be linear, and the pipeline's tonemap + sRGB-encode on output restores the display
//     value. So the shader pre-converts display->linear: pow(c, 2.2).
//   * Compatibility / gl_compatibility (OUTPUT_IS_SRGB == true): the frame is written in
//     sRGB and is NOT re-encoded on output, so ALBEDO is the display value verbatim.
//     Pre-converting leaves the frame one gamma step too dark — the off-fork darkness
//     bug this include exists to kill.
//
// OUTPUT_IS_SRGB is a Godot BUILT-IN spatial-shader bool constant (declared in
// servers/rendering/shader_types.cpp "constants"; mapped to SHADER_IS_SRGB for GLES3 in
// material_storage.cpp). Compile-time: no uniform, no shader_globals registration, no
// runtime cost, no per-build file divergence. TRUE on gl_compatibility, FALSE on Forward+.
//
// These two helpers are the sanctioned route for a target-dependent display<->linear step.
// Call them instead of a raw pow(c, vec3(2.2)) / pow(c, vec3(1.0/2.2));
// tools/check_no_unguarded_srgb_pow.py enforces it (ADR-0370). On the 4.8 fork's Forward+
// OUTPUT_IS_SRGB is a constant false, so each helper folds to the pow it replaced and the
// fork's output does not move.
//
// DO NOT use them for a GENUINE colour-space conversion that must run on every target:
// the nine-slice palette nearest-match turns a DECODED (linear) texel into display space,
// and screen_background turns a `source_color` Color uniform (delivered linearized) back
// into display space for the dither, on every renderer. Those stay raw pows with a
// `// srgb-pow-exempt:` marker.

// c is a DISPLAY-space colour. Return the value to write to ALBEDO on this target:
// the display value verbatim when the output is sRGB, its linear form otherwise.
vec3 display_to_linear(vec3 c) {
	return OUTPUT_IS_SRGB ? c : pow(c, vec3(2.2));
}

// Target-dependent inverse of display_to_linear, for a value the renderer's OWN output
// space put in linear. No site needs it yet; it is here so the pair stays symmetric.
vec3 linear_to_display(vec3 c) {
	return OUTPUT_IS_SRGB ? c : pow(c, vec3(1.0 / 2.2));
}
