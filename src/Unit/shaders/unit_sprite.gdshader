shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform vec4[16] palette_colors : source_color; // palette of 16 colors each
uniform vec3 unit_tint = vec3(0.0, 0.0, 0.0);

uniform bool alpha_scissor = true;
uniform float scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float fold_height : hint_range(-10.0, 10.0) = 0.004; // look right? above the tile highlight
uniform float z_factor : hint_range(-10.0, 10.0) = 2.22; // looks right in orthographic

varying vec3 v_orig_local_pos;
varying mat4 v_modelview_matrix;

void vertex() {
    v_orig_local_pos = VERTEX;
    v_modelview_matrix = MODELVIEW_MATRIX;

    // 2. Standard billboard matrix calculation:
    mat4 billboard_matrix = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0], 
        INV_VIEW_MATRIX[1], 
        INV_VIEW_MATRIX[2], 
        MODEL_MATRIX[3]
    );
    
    MODELVIEW_MATRIX = billboard_matrix;
}

void fragment() {
    // Standard texture mapping
    vec4 tex = texture(sprite_texture, UV);
	int palette_index = int(round(tex.x * 255.0));
	tex = palette_colors[palette_index];
    vec4 col = tex * COLOR;
	ALBEDO = clamp(col.rgb + unit_tint, vec3(0.0), vec3(1.0));
    
    // Handle sprite alpha transparency cutout
    if (alpha_scissor) {
        ALPHA = tex.a;
        ALPHA_SCISSOR_THRESHOLD = scissor_threshold;
    }

    vec3 rotated_pos = v_orig_local_pos;
    if (v_orig_local_pos.y < fold_height) { // bend local points below fold_height to be horizontally flat
        float new_z = fold_height - rotated_pos.y;
        rotated_pos = vec3(rotated_pos.x, fold_height, new_z * z_factor);
    }
    vec3 modified_pos = (v_modelview_matrix * vec4(rotated_pos, 1.0)).xyz; // transform local coordinate to view-space
    vec4 clip_pos = PROJECTION_MATRIX * vec4(modified_pos, 1.0); // Project the view-space coordinate into Clip Space
    float ndc_depth = clip_pos.z / clip_pos.w; // Compute normal device depth
    DEPTH = (ndc_depth * 0.5) + 0.5;
}