shader_type canvas_item;

uniform vec4[16] palette_colors : source_color; // palette of 16 colors each

void fragment() {
	// Calculate local UV normalized to the atlas region (0.0 to 1.0)
    vec2 local_uv = (UV - REGION_RECT.xy) / REGION_RECT.zw;
    
    // Convert local UV to global atlas UV space
    vec2 atlas_uv = REGION_RECT.xy + local_uv * REGION_RECT.zw;
    
    // Sample the texture using the atlas_uv
    vec4 color = texture(TEXTURE, atlas_uv);
    
    // swap palette
    vec4 new_color = palette_colors[int(round(color.x * 255.0))];
    COLOR = new_color;
}
