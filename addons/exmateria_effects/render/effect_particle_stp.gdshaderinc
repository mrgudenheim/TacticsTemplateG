// STP (semi-transparent polygon) particle include. Production:
// effect_particle_opaque / _fold / _native; tools/probe_shaders copies are
// reference-only since #227. Depth: unified PSX Ordering-Table model (ADR-0009).
// Per-instance packing (ADR-0040 dec. 2; writer:
// EffectParticleRenderer._write_instance): basis = 8 corners + depth_mode,
// [3] = world origin, INSTANCE_CUSTOM = uv_rect, COLOR = rgb + semi_trans_on.
// vault: .vaults/comments/exmateria_effects/stp-packing.md
// Vault: [[Effect MultiMesh Pool]]
#include "res://addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc"

// === Shared uniforms ===
// NO source_color to match GL Compatibility behavior
uniform sampler2D effect_texture : filter_nearest, repeat_disable;
uniform vec2 texture_size = vec2(128.0, 256.0);

// Paletted path (ADR-0022): use_palette=true -> effect_texture is
// indexed-grayscale (R=G=B=index*17, A=255); color from palette_texture at row
// palette_row. Default off -> effect_texture is RGBA-baked.
uniform bool use_palette = false;
uniform sampler2D palette_texture : filter_nearest, hint_default_transparent;
// palette_rows is the ACTUAL CLUT row count, not 16: TRAP1 is 16 rows, the
// tile cursor's RANGETILE is 9. A fixed /16.0 sampled the wrong row for the
// cursor. Default 16.0 keeps trap and the RGBA path byte-identical.
uniform float palette_rows = 16.0;
// palette_row is PER-INSTANCE (ADR-0045): COLOR.a * 15; use_palette only.

uniform bool srgb_to_linear = true;
// psx_brightness left this include (ADR-0074 endgame); the fold is structurally
// RAW, gain baked into COLOR by the fold compositor. Probe copies carry a
// local const. Re-declaring it here fails check_no_psx_brightness_in_fold.py.
// texel_blend_gamma left the same way (ADR-0290 dec. 3): production fold is
// RAW, NO pow here; the four probe copies carry a local const 1.4.
// vault: .vaults/comments/exmateria_effects/stp-gamma-history.md

// PAR (ADR-0036 dec. 2, Pattern 2 anchor-only) through the shared seam
// (ADR-0060) the battlefield map/overlay/unit shaders also read.
#include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"
// Sprite stretch (ADR-0044): EFFECTS billboard-width, 1.0 = native. Declared
// by the port that pushes it (ADR-0220 dec. 1 / ADR-0190 dec. 3), not here - an
// undeclared global reads 0 silently (ADR-0238); the seam's psx_cursor_stretch
// twin is that case, nothing here reads it.
#include "res://addons/exmateria_platform/display_port/psx_sprite_stretch.gdshaderinc"

// === Varyings ===
varying vec4 uv_rect;
varying float v_palette_row;  // ADR-0045: per-instance palette row (trap), from COLOR.a

// === Vertex (billboard + corner interpolation) ===
void vertex() {
	// Unpack per-instance corners + depth_mode from the MODEL_MATRIX basis
	// (billboarding rebuilds MODELVIEW, so the basis is otherwise unused).
	vec2 corner_tl = vec2(MODEL_MATRIX[0][0], MODEL_MATRIX[0][1]);
	vec2 corner_tr = vec2(MODEL_MATRIX[0][2], MODEL_MATRIX[1][0]);
	vec2 corner_bl = vec2(MODEL_MATRIX[1][1], MODEL_MATRIX[1][2]);
	vec2 corner_br = vec2(MODEL_MATRIX[2][0], MODEL_MATRIX[2][1]);
	int depth_mode = int(MODEL_MATRIX[2][2] + 0.5);

	uv_rect = INSTANCE_CUSTOM;
	v_palette_row = COLOR.a * 15.0;

	vec2 top = mix(corner_tl, corner_tr, UV.x);
	vec2 bottom = mix(corner_bl, corner_br, UV.x);
	vec2 corner = mix(top, bottom, UV.y);

	// Billboard: face the camera at the per-instance origin - MODEL_MATRIX[3]
	// still carries it even though the basis is repurposed.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);

	const float PSX_SCALE = 1.0 / 28.0;
	VERTEX.x = corner.x * PSX_SCALE;
	VERTEX.y = -corner.y * PSX_SCALE;
	VERTEX.z = 0.0;

	// Unified OT depth: per-object path (world origin + VIEW), biased by depth_mode.
	ot_computed_depth = ot_depth(MODEL_MATRIX[3].xyz, PROJECTION_MATRIX, VIEW_MATRIX, depth_mode);

	// PAR Pattern 2 via the seam: anchor tracks the map; the corner offset
	// stretches by psx_fx_stretch (ADR-0044; 1.0 = native).
	vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, psx_fx_stretch);
}

// === STP semi-transparent sampling ===
// STP sampling: sample effect_texture via uv_rect; when use_palette=true the
// indexed-grayscale texel is replaced by palette_texture at (index,
// v_palette_row) BEFORE the STP discard rules run.
vec4 stp_sample(vec2 frag_uv) {
	vec2 uv_origin = uv_rect.xy;
	vec2 uv_size = uv_rect.zw;
	vec2 uv = uv_origin + frag_uv * uv_size;

	vec4 col = texture(effect_texture, uv);

	if (use_palette) {
		int idx = int(col.r * 15.0 + 0.5);
		vec2 palette_uv = vec2(
			(float(idx) + 0.5) / 16.0,
			(v_palette_row + 0.5) / palette_rows
		);
		col = texture(palette_texture, palette_uv);
	}

	// STP=1 -> alpha=128 -> a~0.5; drop transparent, opaque, and black pixels.
	if (col.a < 0.01 || col.a > 0.9 || (col.r < 0.01 && col.g < 0.01 && col.b < 0.01)) {
		discard;
	}

	return col;
}
