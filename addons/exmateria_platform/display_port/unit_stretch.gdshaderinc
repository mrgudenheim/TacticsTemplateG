// UNIT sprite-stretch global — the DECLARATION seam for the billboard-WIDTH multiplier
// the UNIT taxonomy applies (ADR-0044). Declaration only: no function, no math.
//
// Same rule and same writer as `psx_sprite_stretch.gdshaderinc` beside it: `PSXDisplay`
// in this directory pushes it (`live_unit_stretch` -> `RenderingServer
// .global_shader_parameter_set(&"unit_stretch", …)`, backed by the
// `render.unit_stretch` tunable), so the port declares what the port pushes.
//
// 🔴 A SEPARATE FILE, NOT A THIRD LINE IN THE SIBLING SEAM, AND THAT IS THE SIBLING'S
// OWN ARGUMENT. Its note says adding this name there "would charge every includer of
// this file — all of them `Battlefield`'s — for a name none of them uses", and a
// `global uniform` a consumer has not declared in `[shader_globals]` silently reads 0,
// with no compile error to catch it (ADR-0238). Splitting per taxonomy keeps that true: a
// battlefield shader still pays for exactly the two stretches it reads.
//
// #744 is why this exists now. That note also said the name was declared "at its host
// call sites … neither of which is inside an addon" — true when written, false the
// moment the unit shaders moved into `addons/exmateria_sprite_rig/`, at which point
// `check_addon_portability.py`'s GLOBAL-UNIFORM arm went red on two lines a system
// was declaring. The note named the follow-up ("those two call sites adopting this
// seam is the natural follow-up"); the move is what forced it.

// UNIT taxonomy. 1.0 = native art; scrubbed in the F3 Display and Alignment panels.
global uniform float unit_stretch;
