// The centred PSX frame (gl-ADR-0382) — the shader half of `DisplayPort.frame_rect`, which
// spells the same arithmetic in GDScript. Keep the two identical.
//
// The base viewport is wider than the PSX's 256x240 (16:15) frame; the frame sits CENTRED in it
// at full height. A screen-space shader that normalises FRAGCOORD or SCREEN_UV by VIEWPORT_SIZE
// is normalising by the viewport, which was the frame only while the viewport was 1024x960.
// Anything PSX-authored in screen space reads these helpers instead.

#ifndef NATIVE_FRAME_GDSHADERINC
#define NATIVE_FRAME_GDSHADERINC

const float NATIVE_FRAME_ASPECT = 256.0 / 240.0;

// The frame's rect in framebuffer px: (origin.x, origin.y, width, height).
vec4 native_frame_px(vec2 viewport_size) {
	float w = min(viewport_size.x, viewport_size.y * NATIVE_FRAME_ASPECT);
	float x = floor((viewport_size.x - w) * 0.5);
	return vec4(x, 0.0, w, viewport_size.y);
}

// A framebuffer px position → the frame's own 0..1 UV (outside the frame: <0 or >1).
vec2 native_frame_uv(vec2 frag_xy, vec2 viewport_size) {
	vec4 f = native_frame_px(viewport_size);
	return (frag_xy - f.xy) / f.zw;
}

// A framebuffer px position → px measured from the frame's own top-left corner.
vec2 native_frame_local_px(vec2 frag_xy, vec2 viewport_size) {
	return frag_xy - native_frame_px(viewport_size).xy;
}

// A full-screen quad's NDC x (-1..1 over the FRAME) → NDC x over the viewport, so a quad
// authored to "fill the screen" fills the frame instead.
float native_frame_ndc_x(float frame_ndc_x, vec2 viewport_size) {
	vec4 f = native_frame_px(viewport_size);
	float left = f.x / viewport_size.x * 2.0 - 1.0;
	float right = (f.x + f.z) / viewport_size.x * 2.0 - 1.0;
	return mix(left, right, frame_ndc_x * 0.5 + 0.5);
}

#endif
