shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;
}
