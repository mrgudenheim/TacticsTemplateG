# ExMateria Platform

The `platform` tier's address. Six files behind one façade, and the thing they have in common is
that **every bucket needs some of them and none of them belongs to a system**:
pixel aspect, ordered dither, PSX fixed-point number conventions, the
display-calibration port that pushes the CPU half of the first two, and the two
**port signatures** an installed addon names instead of this project's autoloads.

Created at extraction #3's loop pass 6 —
[ADR-0169](../../docs/adr/0169-platform-ships-to-its-own-address-and-shipping-a-file-is-not-shipping-a-shader.md)
dec. 1 (the address) and dec. 2 (what moves when), plus
[ADR-0171](../../docs/adr/0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md)
dec. 3 (`PSXDisplay` joins that step).

| | |
|---|---|
| `pixel_aspect/pixel_aspect.gdshaderinc` | the horizontal PAR clip-space stretch every `POSITION`-writing battle shader includes |
| `dither/psx_dither.gdshaderinc` | the ordered dither pattern; its CPU writer is `src/debug/DebugConfig.gd` |
| `exmateria_platform.gd` | `class_name ExMateriaPlatform` — **the façade, and the addon's only global name**; publishes the four below as constants |
| `fixed_point/PsxNum.gd` | `ExMateriaPlatform.PsxNum` — the PSX fixed-point conventions, named by symbol and by no path |
| `display_port/PSXDisplay.gd` | the autoload the host registers at `project.godot`; pixel aspect (world and UI), three per-taxonomy sprite stretches, gamma |
| `display_port/DisplayPort.gd` | `ExMateriaPlatform.DisplayPort` — the four members of that autoload an addon may name, soft-bound by node path |
| `display_port/psx_sprite_stretch.gdshaderinc` | the DECLARATION seam for `psx_fx_stretch` + `psx_cursor_stretch` (ADR-0044's taxonomy) |
| `display_port/psx_camera_angle.gdshaderinc` | the DECLARATION seam for `psx_camera_angle`, the per-frame yaw the port pushes |
| `tunables/TunePort.gd` | `ExMateriaPlatform.TunePort` — the six verbs of the tunable registry an addon may name, soft-bound by node path |
| `ndc_quad/ScreenOverlayQuad.gd` | `ExMateriaPlatform.ScreenOverlayQuad` — the cull-proof full-screen NDC-quad BASE CLASS: a vertex shader that remaps corners to NDC moves them out of the mesh AABB and Godot culls it, so every such quad needs an oversized `custom_aabb`. Six subclasses, five in `src/scenarios/` and `FormationScreenIn` in `exmateria_ui`; `extends ExMateriaPlatform.ScreenOverlayQuad` is the supported spelling |
| `event_port/EventPort.gd` | `ExMateriaPlatform.EventPort` — the SUBSCRIBE half of the host's `EventBus`, soft-bound by node path; two verbs, and the `emit_*` direction is deliberately absent (#1274) |

The subdirectory names are the fact each file encodes rather than the file's own
name, which is what makes ADR-0146 dec. 2's `ls` test answerable here. It also
lets [ADR-0129](../../docs/adr/0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)
dec. 10 — *"only `par` wants a longer name (`pixel_aspect`)"* — be honoured by
the address today without renaming the file, which is
[#583](https://github.com/timbermania/fft-monorepo/issues/583)'s work along with
the `PSXDisplay` → `DisplayCalibration` rename (ADR-0171 dec. 4).

## 🔴 Shipping these files is not shipping what they need

**This addon does not carry the host, and six of its files declare a
`[shader_globals]` name.** A `global uniform` is `check_addon_portability.py`
arm 2's defect in the other language — *"the name is the host's
`project.godot`"* — and the engine is **quieter** about it, which is worse. A
missing autoload name is a parse error in one file. A missing `global uniform` is
nothing at all outside the editor: `shader_language.cpp` gates the check on
`Engine::is_editor_hint()`, so the shader compiles, the name reads its type's zero
and the engine warns once per material at DRAW time. A `pixel_aspect` of `0.0` collapses
every vertex's clip-space x — a blank screen, with no error anywhere
(ADR-0238, correcting ADR-0169 dec. 4).

**Every `global uniform` declaration under `addons/` is in THIS addon**, and that is
enforced rather than hoped for: `check_addon_portability.py` **arm 4b** reds any
addon that is one of the eleven systems and declares one (ADR-0190). Before that,
`addons/exmateria_battlefield/` declared four names — three that `PSXDisplay.gd`
pushes and one that nothing pushed at all.

`PSXDisplay.gd` pushes six by name from the CPU side — `pixel_aspect`, `texel_blend_gamma`,
`psx_cursor_stretch`, `unit_stretch`, `psx_fx_stretch`, `psx_camera_angle` — and
every one of them is now declared here too. `texel_blend_gamma` was the exception until
extraction #8 (#1270) and is the reason arm 4 reads BOTH sides: a declaration scan
alone cannot see a name the CPU half pushes by string literal (ADR-0171 dec. 5).
Arm 4 reports both sides; it is DEBT while the addon has no `project.godot` of its
own and turns RED the day it gets one.

⚠️ **"read by 22 shader files" was never 22 of anything**, and this paragraph said it
for months. Re-measured at #1217: `texel_blend_gamma`'s readers are **three**, all
`pow(c.rgb, vec3(texel_blend_gamma))` in what is now `addons/exmateria_ui/shaders/`
(`formation_box.gdshader:22`, `formation_box_sub.gdshader:22`,
`formation_orb.gdshader:26`). The `tools/probe_shaders/effect_particle_mode*` copies
that used to read it carry a local `const float texel_blend_gamma = 1.4;` instead.

## 🔴 Enabling this plugin IS the install step

Installing this addon requires **seven** `[shader_globals]` entries — one for each
`global uniform` the files above declare. **You do not paste them.**
`plugin.gd`'s `const PROVIDED_GLOBALS` is the single source, and `_enter_tree()`
writes every one the consuming project does not already declare, with this
project's types and defaults. Copy the addon in, open the project, **enable the
`exmateria_platform` plugin**, reload.

That is [ADR-0220](../../docs/adr/0220-the-addon-that-declares-a-global-uniform-provides-it.md)
dec. 1: *the addon that DECLARES a `global uniform` PROVIDES it*. Composed with
arm 4b — only the kernel and this port may declare one — it says **only this port
provides**, so one array closes the name for every consumer instead of once per
consumer. The five that used to be pasted were provided by
`addons/exmateria_battlefield/plugin.gd` instead, off declarations that live here;
`exmateria_sprite_rig` does not contain that addon and could not compile its unit
shaders at all (dec. 2).

⚠️ **It is an ENABLE-time write.** A project that copies the addon in and never
enables the plugin still gets nothing, which is why the sequence above says
*enable* and *reload*. If you would rather declare them by hand, the entries are
in `plugin.gd`; the `has_setting` guard means a name you declare yourself is never
overwritten and is not removed on disable.

**Now guarded, and it was not before.** `check_addon_portability.py` **arm 4c**
(ADR-0220 dec. 3) reds any `global uniform` whose *declaring* addon does not
provide it — keyed on the declaring addon, not on "provided by anything", because
`pixel_aspect` was provided by the wrong addon for an entire extraction and read green.
`addons/exmateria_platform/tests/PlatformProvidesTest.gd` is the oracle beside it
(dec. 5): the arm's predicate is a string appearing in `plugin.gd`, so the test
CALLS `provide_into` and its seventh arm diffs `PROVIDED_GLOBALS` against the
`global uniform` lines read out of these `.gdshaderinc` files at runtime, in both
directions.

🔴 **`texel_blend_gamma` used to be the one name the port pushes and does not provide, and
extraction #8 ended that.** This section read: *"its declarations are the host's —
`src/ui3/shaders/formation_box.gdshaderinc:27`, `formation_orb.gdshaderinc:20` and
`addons/exmateria_effects/render/effect_particle_stp.gdshaderinc:56` — so under dec. 1
it is nobody's here to provide. Declare it yourself when you adopt the UI3 formation
shaders."* Two things were wrong with that by the time it was read:

* **The third site had already gone.** `effect_particle_stp.gdshaderinc` dropped its
  declaration at #1217 (c); the file's own comment says so. Two sites, not three —
  a count that stayed in prose after the tree moved underneath it.
* **The other two stopped being the host's at #1270.** `src/ui3/shaders/` is
  `addons/exmateria_ui/shaders/` now, and `UI` is `tier="system"`, which arm 4b
  forbids from declaring. So the name moved to `display_port/texel_blend_gamma.gdshaderinc`
  and the two ex-host headers `#include` it.

ADR-0220 dec. 4 recorded the gap as **open** rather than taking it quietly, and what
closed it was its own stated condition being met — the declaration leaving the host —
not a later decision overruling it. You no longer declare anything yourself: enabling
this plugin provides all seven.

The dependency is **documented-and-accepted, not designed away**, and ADR-0190
dec. 4 says why: `psx_camera_angle` changes every frame and is read by every map
surface, so a `ShaderMaterial` parameter would mean a per-material push on a
rebuild-heavy path — exactly what a global uniform exists to avoid. Goal #5's
shader half is met **as an install step, not as zero dependencies**. ⚠️ dec. 4
wrote that step as a five-name block for a human to paste; ADR-0220 keeps the
step and changes who performs it, and the block is seven names because
`unit_stretch` joined this addon at #744 and `texel_blend_gamma` at #1270, both after dec. 4
was written.

## `exmateria_platform.gd` — the façade, and the addon's ONE global name

`class_name ExMateriaPlatform`, publishing `PsxNum`, `TunePort`, `DisplayPort`
and `EventPort` as constants. Godot has no package scope, so every `class_name` an
addon declares lands in a consumer's global scope — and when they declare a
colliding one, it is the **addon's** file that fails to parse. This addon
declared three bare globals, and **`DisplayPort` is the name of a hardware
standard**:
[ADR-0212](../../docs/adr/0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1 rules that the invariant is the folder-named façade, not a count. A
consumer aliases the names back to their bare local spellings:

```gdscript
const TunePort = ExMateriaPlatform.TunePort
```

`tools/check_addon_globals.py` holds both directions — nothing else here may
declare a global, and nothing published may dangle. The `.gdshaderinc` seams
below are a **different channel** and stay reachable only by `#include` path: a
shader include declares no `class_name`, so it carries none of the collision
hazard the façade exists for (ADR-0212 dec. 5).

## The two port signatures, and why they are verbs

`TunePort` and `DisplayPort` exist because an `[autoload]` line can only be
written by the **consuming game's** `project.godot`. That is an install step, not
an interface, so an addon naming `Tune.` or `PSXDisplay.` does not parse where the
addon is installed and the host script is not —
`tools/check_addon_portability.py` arm 2's whole subject, and 78 lines of it at
`6d63f6fbe`. Each port signature is a script an installed addon carries — published on
`ExMateriaPlatform` since ADR-0212 dec. 1 — resolving
its singleton by **node path at call time**
([ADR-0175](../../docs/adr/0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 2, built by
[ADR-0187](../../docs/adr/0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md)).
It converts a host-project-**configuration** dependency into an addon-**presence**
dependency, which is vendorable; arm 5 counts what is left.

**Two classes and not one**, because there are two autoloads and a signature that
forwards both `bind` and `live_fx_stretch` is a namespace rather than a port.

🔴 **Absent is not the same answer for every verb.** The difference is whether the
call carries a literal: `bind` and `bind_update` do, `get_value` now carries a
required `fallback`, and `on_update` carries neither — it reads the default its
matching `bind` registered — so with no registry it is a **no-op** and the owner's
own member default stands. Applying `null` is the failure the absent path exists
to prevent. `tests/TunePortTest.gd` is the guard, and it manufactures the absent
case by renaming the autoload node, which is what `_resolve()` actually looks up.

Both façades reject on `has_method` rather than on `null`: a non-`@tool` autoload
is instantiated **in the editor** as a placeholder that answers to the name and
carries none of the script's methods, and both are named from `@tool` scripts.
Neither ever caches a negative resolution — a `_static_init` that ran before the
autoload was up would otherwise poison the whole session, silently.

## What is not here yet

`src/core/ScreenOverlayQuad.gd` LANDED here at #1293 group 4 — ADR-0172 booked it
`platform` and left it at the host address, and `addons/exmateria_ui/formation/FormationScreenIn.gd`
`extends` it, so the UI addon could not parse in a project shipping no `src/`. Reaching
`tier="port"` is free (ADR-0202 dec. 2), so that reach earns no burn-down row.

`src/core/Tune.gd` is `platform`'s classifier row and stays in the host for now.
ADR-0169 dec. 2 left it behind for **collision, not cost** — the file was being
rewritten on another branch — so the `platform` bucket still sits at two addresses
until it lands. Both rows key on path and both are inside the walk, so no
instrument reads a rebooking (ADR-0146 dec. 5's hole does not reopen). `TunePort`
does not change that: it is the registry's **signature**, and the registry itself
is still the host's.
