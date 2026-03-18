shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform vec3 unit_tint = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec4 tex = texture(sprite_texture, UV);
	vec4 col = tex * COLOR;
	if (col.a < 0.5) {
		discard;
	}
	ALBEDO = clamp(col.rgb + unit_tint, vec3(0.0), vec3(1.0));
}
