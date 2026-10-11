shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// PAR (ADR-0036): Pattern 2, anchor-only. The trap charge-line effect is
// anchored to the caster's world position; the line cluster's geometry is
// authored in world space relative to that anchor. We PAR the anchor's clip.x
// so the cluster tracks the stretched caster, but the lines themselves keep
// their authored layout (additive blend, no native pixel aspect to preserve —
// the anchor stretch just keeps them centered over the unit).
// Vault: [[Display Space Blend Fold]]
// Vault: [[Effect Callback Mesh]]
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"

void vertex() {
	// Pattern 2, anchor-only, via the shared seam. stretch 1.0 = native width:
	// the lines keep their authored layout while the anchor tracks the stretch.
	vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;
}
