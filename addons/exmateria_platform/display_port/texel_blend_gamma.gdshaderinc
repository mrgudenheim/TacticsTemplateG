// The exponent a producer applies to a SAMPLED TEXEL, immediately before that texel is
// modulated and blended. Declaration only.
//
// 🔴 THE NAME IS THE DECISION, AND IT IS ADR-0328's. This file was `psx_gamma.gdshaderinc`
// until #1373. ADR-0240 dec. 5 deferred that rename on two grounds and only one of them
// has survived: *"block no goal-#7 row"* is now FALSE (extraction #8 made
// `addons/exmateria_ui/shaders/` an addon root, so the three `pow` sites became a
// `tier="system"` addon's own source and five of `UI`'s ten jargon lines are this name),
// and *"`gamma` is too generic a name to take as a project-wide global without an
// argument"* is TRUE — which is why the new name is not `gamma`. `[shader_globals]` is
// ONE FLAT NAMESPACE for the whole project, so the name has to survive being read next to
// a display gamma, a Godot environment adjustment and a future colour-management
// exponent. `texel_blend_gamma` names the operand (a sampled texel, not the framebuffer)
// and the moment (before the blend), which is the pair that actually discriminates:
// `tools/check_no_pow_in_fold.py` exists precisely because applying this exponent AFTER
// the blend, in the fold, is wrong — there is no tonemap there. The name now states the
// rule that guard enforces. It deliberately does NOT say `srgb`: the default is 1.4, and
// no sRGB decode has that exponent. This is a hand-calibrated blend exponent, not a
// colorimetric transform.
//
// Same rule as `psx_camera_angle.gdshaderinc` beside it: the seam is where the name is
// declared, so a call site includes rather than redeclares. `unit_stretch.gdshaderinc` in
// this directory is the precedent for a member of this port that carries no `psx_` prefix.
//
// The writer is `PSXDisplay._apply_gamma()` in this directory, bound to the
// `render.texel_blend_gamma` tunable — so the value a shader reads is whatever the F3
// calibration panel last scrubbed, not the 1.4 default. That is the whole reason this
// is a `global uniform` and not a `const`: a `const` freezes the knob.
//
// 🔴 IT LIVED IN THE HOST UNTIL EXTRACTION #8, AND THAT WAS A RECORDED OPEN ITEM, NOT AN
// OVERSIGHT. ADR-0220 dec. 4 declined to put `psx_gamma` (as it was then spelled) in this
// addon's `PROVIDED_GLOBALS` on a precise ground: dec. 1 says *the addon that DECLARES a
// global uniform provides it*, and the declaration was in `src/ui3/shaders/` — the HOST,
// which is not an addon, so there was nothing for `check_addon_portability.py` arm 4c to
// grade and no addon with standing to provide it. `plugin.gd` said so in those words
// ("DELIBERATELY NOT HERE"), and `README.md` claimed every `global uniform` declaration
// under `addons/` was in this one.
//
// Extraction #8's move (#1270) ended that premise rather than arguing with it. The two
// headers that declared the name — `formation_box.gdshaderinc`, `formation_orb.gdshaderinc`
// — are now `addons/exmateria_ui/shaders/`, and `UI` is a `tier="system"` addon, so arm 4b
// (*only a NON-system addon may declare one*, ADR-0190) fires the day those files land.
// The declaration had to go SOMEWHERE that is allowed to hold it, and the port is the only
// tier that is. Moving it here is the cheap direction of the same trade: the three readers
// gain one `#include` line, arm 4b and arm 4c both go green on their own rule rather than
// on an exemption, and dec. 4's open item closes because its condition was met.
//
// 🔴 THE THREE READERS ARE ALL IN `exmateria_ui` AND THERE ARE NO OTHERS. Re-measured over
// the tree at #1373: `formation_box.gdshader:22`, `formation_box_sub.gdshader:22`,
// `formation_orb.gdshader:26`, each a `pow(c.rgb, vec3(texel_blend_gamma))`. Everything
// else that once read it carries a LOCAL const instead (#1198, #1217 (c)) — the four
// `tools/probe_shaders/effect_particle_mode*` copies, renamed with this one so a single
// quantity keeps a single spelling — or never read it at all. The fold shaders
// deliberately do NOT apply it (`tools/check_no_pow_in_fold.py` reds them if they do:
// there is no tonemap after the fold, so the pow is wrong there).
//
// So this name is declared by the port, pushed by the port, and read by exactly one
// system. A later pass that moves `UI`'s three readers off it deletes this file and the
// `PROVIDED_GLOBALS` row together; until then the port owns the seam because the port is
// what may own it.

global uniform float texel_blend_gamma;   // pre-blend texel exponent (1.4)
