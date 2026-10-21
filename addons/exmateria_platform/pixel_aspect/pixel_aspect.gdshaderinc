// Unified PSX pixel-aspect (PAR) horizontal clip-space stretch — ONE seam.
//
// FFT authors its pixel art for the PSX's non-square pixels, so every battle
// mesh multiplies its clip-space X by a shared factor to reproduce the ~1.25x
// horizontal stretch on a modern square-pixel display. This is a SECOND
// per-mesh placement axis, applied in the vertex shader alongside the OT depth
// (ot_depth.gdshaderinc) — and a new consumer that silently forgets it
// drifts HORIZONTALLY out of alignment with the units/map. That recurring bug
// (unit shadow 2026-07-04; dialogue box/tail earlier) is exactly what routing
// every POSITION write through this one seam retires.
//
// Decision: docs/adr/0036 (PAR is per-content clip-space, not a global frame
// stretch) + docs/adr/0044 (per-taxonomy billboard width) + docs/adr/0060
// (every battle mesh applies PAR through this seam — the POSITION analogue of
// ADR-0009's DEPTH rule, enforced by tools/check_par_shaders.py). See the
// "Display and pixel aspect" cluster in CONTEXT.md.
//
// Usage (every battle shader that writes POSITION picks ONE pattern):
//
//   #include "res://addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc"
//
//   // Pattern 1 — FULL-STRETCH: flat, map-attached geometry that stretches
//   // WITH the map (terrain, map skirt, tile overlays, unit shadow, callback
//   // meshes). The whole clip-X scales by pixel_aspect.
//   void vertex() {
//     vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
//     POSITION = pixel_aspect_full(clip);
//   }
//
//   // Pattern 2 — ANCHOR-ONLY: billboards whose ANCHOR (object origin) tracks
//   // the PAR-stretched map but whose sprite FOOTPRINT stays native art (unit
//   // sprites, effect/projectile sprites, tile cursor). `stretch` is the
//   // per-taxonomy width multiplier (unit_stretch / psx_fx_stretch /
//   // psx_cursor_stretch, ADR-0044); pass 1.0 for a native-width billboard.
//   // Both clips are the BILLBOARDED vertex/anchor already in clip space.
//   void vertex() {
//     vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * <billboarded vertex>;
//     vec4 anchor_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
//     POSITION = pixel_aspect_anchor(vertex_clip, anchor_clip, <taxonomy_stretch>);
//   }
//
// The POSITION write must BE (contain) one of these helper calls — ADR-0060,
// enforced. Genuine screen-space passes that map quad corners straight to NDC
// (fullscreen overlays) opt out with a `// pixel-aspect-exempt: <reason>` comment.

// Project-wide horizontal PAR factor. ONE global drives every opt-in subsystem,
// so a single scrub in the F3 Display debug panel (PSXDisplay.live_par) moves
// the whole scene in unison. Never redeclare this at a call site — include this
// seam so there is exactly one declaration to scrub.
global uniform float pixel_aspect;

// Pattern 1 — full-stretch. For flat, map-attached geometry that stretches
// together WITH the map: scale clip-space X by pixel_aspect after MVP. Depth
// (clip.z / clip.w) is untouched, so the OT pipeline survives (ADR-0036).
vec4 pixel_aspect_full(vec4 clip) {
	clip.x *= pixel_aspect;
	return clip;
}

// Pattern 2 — anchor-only. The anchor (object origin projected to clip space)
// tracks the PAR-stretched map, while the sprite's own footprint offset from
// that anchor scales by the per-taxonomy `stretch` (1.0 = native art). With
// stretch == 1.0 this reduces algebraically to
//   vertex_clip.x + anchor_clip.x * (pixel_aspect - 1.0)
// — the native-width billboard form. See ADR-0044.
vec4 pixel_aspect_anchor(vec4 vertex_clip, vec4 anchor_clip, float stretch) {
	vec4 par_clip = vertex_clip;
	par_clip.x = anchor_clip.x * pixel_aspect + (vertex_clip.x - anchor_clip.x) * stretch;
	return par_clip;
}
