shader_type canvas_item;
render_mode unshaded;

// The battle's background gradient, which an effect can recolour. `ScreenBackground` hands
// this material to the addon's `ScreenEffectOverlay`, which writes four corner colours plus
// the ColorStack uniforms, so these uniform names must stay as they are.

// `ScreenEffectOverlay.set_corners` writes these as raw Vector3s, so `source_color` only
// documents what they hold; no conversion runs.
uniform vec3 color_tl : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_tr : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_bl : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 color_br : source_color = vec3(0.0, 0.0, 0.0);

#include "res://addons/exmateria_schema/colour_model/color_stack.gdshaderinc"

void fragment() {
	// UV: (0,0) = top-left, (1,1) = bottom-right of the TextureRect, which fills the window.
	vec3 top = mix(color_tl, color_tr, UV.x);
	vec3 bottom = mix(color_bl, color_br, UV.x);
	vec3 base = mix(top, bottom, UV.y);

	// Layer 0 is the background's tint slot: it leaves the gradient untouched until an
	// effect writes a colour into it.
	COLOR = vec4(color_apply(base, 0), 1.0);
}
