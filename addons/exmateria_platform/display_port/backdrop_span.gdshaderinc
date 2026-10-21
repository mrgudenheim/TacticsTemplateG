// The backdrop span (gl-ADR-0382 dec. 9) — the shader half of `DisplayPort.backdrop_span`.
//
// A backdrop is drawn across the WHOLE viewport, not only the centred frame, so the side
// margins read as more of the same screen. Its quad is sized to the span: the content's own
// native-px rect widened left and right by the margin. The quad's UV therefore runs over the
// span, and `backdrop_span_px` maps it back to the content's native px — 0..256 over the frame,
// negative in the left margin, past 256 in the right. A pattern computed from those px (a tile,
// a gradient, a spotlight) continues across the margin with the same phase and scale, so the
// seam at the frame edge is not there to see.
//
// `span` is the Rect2 `DisplayPort.backdrop_span` returns, packed (x, y, w, h). The default
// a material carries when nobody set it is the 256x240 frame itself, so an unset span draws
// exactly what the frame-sized quad drew.

#ifndef BACKDROP_SPAN_GDSHADERINC
#define BACKDROP_SPAN_GDSHADERINC

// The quad's UV (0..1 over the span) → the content's native px.
vec2 backdrop_span_px(vec2 uv, vec4 span) {
	return span.xy + uv * span.zw;
}

// A fixed image with no tiling of its own (the 320x240 title backdrop): fold a native px that
// lies outside [0, w) back into the image's outer BAND px on that side, mirror-wise and back
// again (ping-pong), so the edge band continues outward as its own reflection. Continuous at
// the edge — the px beside the edge is the edge texel — and at every bounce. `band` is how deep
// into the image the reflection may reach: keep it clear of anything that must not be seen
// mirrored (lettering). band = w mirrors the whole image.
float backdrop_mirror_px(float x, float w, float band) {
	if (x >= 0.0 && x < w) {
		return x;
	}
	float d = x < 0.0 ? -x : x - w;
	float p = mod(d, 2.0 * band);
	float t = p < band ? p : 2.0 * band - p;
	return x < 0.0 ? t : w - t;
}

#endif
