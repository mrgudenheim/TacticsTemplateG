shader_type spatial;
render_mode unshaded, cull_disabled;

// The screen-wide background gradient an effect can recolour.
// The addon's `ScreenEffectOverlay` searches the current Camera3D for a child named exactly
// `ScreenBackground` and writes four corner colours plus the ColorStack uniforms into its
// `material_override`, so both the name and these uniform names must stay as they are.
// It writes `DEPTH` rather than leaving the quad at NDC 0, because under `gl_compatibility`
// NDC z spans [-1, 1] with near POSITIVE, so a quad at 0 sits at the MID-plane.

// `ScreenEffectOverlay.set_corners` writes these as raw Vector3s, so `source_color` only
// documents what they hold; no conversion runs.
uniform vec3 color_tl : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_tr : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_bl : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_br : source_color = vec3(0.0, 0.0, 0.0);

#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

// A WINDOW depth in [0, 1], not NDC — do not route through `psx_window_depth`. Not 0.0: a
// buffer cleared to the far value plus a strict GREATER test would reject the quad.
const float BACKGROUND_DEPTH = 0.00001;

void vertex() {
	// Straight to NDC corners, bypassing MVP, so the mesh fills the screen at any zoom or
	// pose. The z only has to survive clipping; `fragment()` sets the real depth.
	POSITION = vec4(sign(VERTEX.xy), 0.0, 1.0);
}

void fragment() {
	// SCREEN_UV: (0,0) = top-left, (1,1) = bottom-right.
	vec3 top = mix(color_tl, color_tr, SCREEN_UV.x);
	vec3 bottom = mix(color_bl, color_br, SCREEN_UV.x);
	vec3 base = mix(top, bottom, SCREEN_UV.y);

	// Layer 0 is the background's tint slot: it leaves the gradient untouched until an
	// effect writes a colour into it.
	ALBEDO = color_apply(base, 0);
	DEPTH = BACKGROUND_DEPTH;
}
