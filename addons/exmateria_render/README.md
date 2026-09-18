# ExMateria Render — the fold bracket and one port

The **userland half of the display-space fold**, and the PSX display port — the
port only until extraction #3's loop pass 6, when it leaves for the `platform`
addon ([ADR-0171](../../docs/adr/0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md); see `display_port/` below).
Nothing else. `Render` is the smallest system in the package — **684 lines**
against `Campaign`'s 1,180 — and that is the finding, not an accident of what was
ready to move first ([ADR-0147](../../docs/adr/0147-renders-seam-is-the-fold-bracket-and-one-port.md)).

> **705 -> 672 in the epilogue**, all deletion: the two debug panels declared
> nothing and are gone ([ADR-0151](../../docs/adr/0151-an-addon-reaches-no-system-and-a-declarative-panel-is-not-built.md)),
> and four PAR constants had zero readers
> ([ADR-0152](../../docs/adr/0152-a-psx-compromise-is-a-policy-the-bracket-is-given.md)).
> `Render` scores **7 of an achievable 8** on the ten goals — `python3
> tools/score_goals.py`, register at `docs/GOALS.tsv`
> ([ADR-0149](../../docs/adr/0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md)).
>
> **672 -> 684 since**, and the growth is the point: `FoldSurface`'s two passes were collapsed
> onto one shared implementation: 36 fewer lines of CODE (190 -> 154 non-comment), 48 more lines
> of comment naming the seam. The `Campaign` figure moved on trunk, not here.

This addon installs nothing on its own. See `plugin.gd` for why the one autoload
it contains is still registered by the host.

## Members

### `exmateria_render.gd` — the façade, and the addon's ONE global name

`class_name ExMateriaRender`, publishing one constant: `ExMateriaRender.FoldSurface`.
Godot has no package scope, so every `class_name` an addon declares lands in a
consumer's global scope — and when they declare a colliding one, it is the
**addon's** file that fails to parse. This addon already declared exactly one, and
[ADR-0212](../../docs/adr/0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1 records why that was never the invariant: the one name was `FoldSurface`,
unbranded and not a namespace, so it collided as readily as any of the thirty
`exmateria_battlefield` shed under [ADR-0211](../../docs/adr/0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md).
A consumer aliases it back to a bare local spelling:

```gdscript
const FoldSurface = ExMateriaRender.FoldSurface
```

`tools/check_addon_globals.py` holds both directions — nothing else here may
declare a global, and nothing published may dangle.

### `fold_bracket/` — the two userland passes around the engine's fold

| file | what it is |
|---|---|
| `FoldSurface.gd` | Pass A (POST_OPAQUE seed) and Pass C (PRE_TRANSPARENT resolve), installed on a camera via a `Compositor`. One `FullscreenPass` implementation; each pass is an adapter supplying five values — stage, shader, source, destination, quantization |
| `foldsurface_seed.glsl` | Pass A — opaque scene colour → a game-owned display-space texture |
| `foldsurface_resolve.glsl` | Pass C — the engine-owned target → the colour layer, display→linear + quantize to `FoldSurface.quantize_levels`, for **every pixel** (there is no coverage mark: the PSX framebuffer was 15-bit screen-wide) |

**The 5-bit crush is a policy, not a constant.** `FoldSurface.quantize_levels`
defaults to `31.0` — the PSX RGB555 framebuffer — and `0.0` resolves at full
precision. It is a PSX *compromise* rather than vocabulary, so goal #8 asks that it
be switchable; it stays PSX by default because `Render` IS the PlayStation look, and
changing it is a **known drop** owed to the E1 register (ADR-0152, ADR-0150).

**Pass B is the engine's**, and this addon does not write it. The carriers that
draw into it belong to the systems that produce them (`UI` 7, `Battlefield` 4,
`Effects` 4, `Sprite Rig` 1) — **`Render` declares `compositor_layer` on nothing.**
A renderer that also produced into its own pass is what ADR-0129 dec. 4's *"a
producer keeps its own shader"* exists to prevent.

**The fold's protocol is not here either.** `Fold.add`, `Fold.FOLD_LAYER`,
`DepthMode.render_layer_order_for` and the shared `fold_layer.tres` live in
`addons/exmateria_schema/compositing_key/` — a kernel schema three other systems
already encode against without naming `Render` once. `FoldSurface` depends on
that encoding exactly as its consumers do.

### `display_port/` — PAR, the sprite stretches, and gamma

| file | what it is |
|---|---|
| `PSXDisplay.gd` | the `pixel_aspect` / `psx_*_stretch` / `texel_blend_gamma` global-shader-parameter port, coalesced over `Tune` |

**This is the addon's entire published surface** — 26 of the 27 inbound system
lines land on it, from four systems (`UI` 21, `Cutscene` 2, `Battlefield` 2,
`Battle` 1). It is an autoload: `extends Node`, no `class_name`, five signals.

> **This member is leaving, and the sentence above is what gave it away**
> ([ADR-0171](../../docs/adr/0171-the-display-port-is-platforms-and-render-is-the-fold-bracket.md),
> resolving [#575](https://github.com/timbermania/fft-monorepo/issues/575)). A system's
> addon whose *entire* published surface is one port reached by eight buckets is not
> publishing a system — it is hosting a port. `PSXDisplay` is booked to the `platform`
> bucket on its **shape** (an autoload with I/O and mutable state, coalescing `Tune` and
> pushing globals it does not declare — `Tune`'s own shape, ADR-0139 dec. 12), never on
> the reach count, which ADR-0139 dec. 2 refutes as an admission test.
>
> It relocates at extraction #3's loop **pass 6**, as the fourth item beside ADR-0169
> dec. 2's three, and is renamed **`DisplayCalibration`** by a follow-up ticket — the name
> `PSXDisplay` names a system the file is leaving and promises a display abstraction it
> does not have. What remains here is the fold bracket: **447 lines, one production
> consumer**, and `Render` stays one of the eleven.

### `debug/` — one declined visualiser

| file | what it is |
|---|---|
| `depth_debug.gdshader` | a solid-colour billboard through the OT depth seam, for `DepthDebugScene` |

`depth_debug.gdshader` is reached only from a declined scene; `docs/RESIDUE.tsv`
carries it as `declined`. It travels with its system and is not deleted
(ADR-0142 dec. 8).

**The two debug panels that used to live here are deleted** (ADR-0151).
`DisplayDebugPanel` and `ShaderCalibrationPanel` were three `TuneField` rows over
slugs their owners already bind — `DebugConfig` binds `debug.show_depth` and
`render.psx_dither_enabled`, `PSXDisplay` binds `render.texel_blend_gamma` — so they
declared nothing, and ADR-0068 dec. 9 already renders every registered slug on the
F3 Registry page. A hand-built panel is for **bespoke** UI; a panel that is only
`TuneField` rows is the generated surface, written by hand.

## What does not get in

`Render` owns **no shader library**. `BLUEPRINT.md` §10 predicted the walk would
hand one back; all five entries it names are booked elsewhere — `ot_depth` and
`color_stack` are the kernel's, `par` and `dither` are `platform`'s, and
`screen_blend` is `Cutscene`'s. See ADR-0147 dec. 4.

The one thing that plausibly belonged here and does not is
`EngineFoldCompositor.gd`: it polls `EffectMultiMeshPool` by node **name**, calls
`get_active_effect_buckets` by **string**, and reads a ten-field dictionary and a
five-field run record. An addon holding it would depend on the game that consumed
it. It is `Effects`', with the six carrier shaders and `ColorTimelineModel`
(ADR-0200 decs. 1 and 11; ADR-0147 decs. 1 and 3).

## What still reaches back into the host

**Nothing.** `Render` reaches zero systems and is reached through one symbol — a
sink, which is the shape an extracted addon should have. Goal #5 is met and
`tools/check_addon_portability.py` keeps it that way. That one symbol is now
`ExMateriaRender`, and after ADR-0212 dec. 9 the portability report names the
**folder** rather than the type on such a row; `#722` restores per-name
resolution by teaching arm 1 to read through `const X = ExMateriaRender.Y`.

It was five lines until ADR-0151: `BaseDebugPanel` ×2 and `TuneField` ×3, both
`Debug`'s, both inside the two debug panels. The answer did **not** need #393's
*"does `Debug` extract?"* — ADR-0113 as amended by ADR-0140 dec. 7/8 had already
prescribed the mechanism, and the panels turned out to declare nothing at all.

`Tune` is still named, and that is deliberate: the classifier books it
`platform`, a port is what a portable addon is allowed to reach (ADR-0139
dec. 12, ADR-0140 dec. 9), and reaching one is not a crossing.
