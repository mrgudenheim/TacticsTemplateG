# ExMateria Schema — the shared kernel

The **published schemas** every extracted system encodes against, and nothing
else. When two systems have to agree on the shape of a payload, the agreement
lives here — once, in both languages it is spoken in — so neither side can drift
without the other noticing.

This addon installs nothing. It registers no autoload, no singleton, no editor
UI. Consumers reach its types through **one global name, `ExMateriaSchema`**, and
its shader seams by `#include`.

**Engine: the Godot 4.8 compositor fork** (`plugin.cfg` → `engine="fork"`, ADR-0194
dec. 7). **One file** is why: `compositing_key/fold_layer.tres` is a
`CompositorRenderLayer`, a class stock Godot does not have, so on stock the
resource does not load. Nothing else in the addon needs the fork to *parse*.

🔴 **That used to read "one member takes the other five with it", and #721 paid it
off.** `Fold.gd` held `const FOLD_LAYER := preload(…)` — a parse error on stock —
and the façade preloads all six members, so the error cascaded and the addon went
3-of-4 loading on stock 4.7.1 to 0-of-4 (ADR-0212 dec. 8 accepted that and filed the
repair). `FOLD_LAYER` is now a lazy `static var` behind a getter: the load happens at
first read, which only `Fold.add` reaches and only behind `Fold.owns()`. Measured by
staging this addon into a stranger project on stock 4.7.1 — **52 passed, 1 failed**,
the single red being `fold_layer.tres` itself. That red is irreducible and it is what
the `fork` declaration now rests on, alone.

The consequence that matters is not the count: `Fold.owns()` is now **reachable** on a
build without the primitive, and reports `false` there, which is the state the
kernel's two-shader fallback was always written for and never once reached
(ADR-0191 dec. 14). `tests/stranger/exmateria_schema/run.sh` boots stock once per run
and goes red if the fork's primitives ever appear there.

## Members

A member realises one row of the schema table in
[ADR-0118](../../docs/adr/0118-payloads-are-schemas-services-are-ports.md)
dec. 1. Five of the ten rows have code today; the other five are named there, with
the reason each is memberless.

### `exmateria_schema.gd` — the façade, and the addon's ONE global name

Not a member: it realises no schema. It is the addon's whole public surface, and
the only `class_name` it registers.

Godot has no package scope, so every `class_name` an addon declares lands in the
consumer's global scope — and when the consumer declares a colliding one, it is
the *addon's* file that fails to parse. This addon used to declare **six**, every
one of them generic English: `Fold`, `DepthMode`, `ColorStack`, `ColorRecipe`,
`CellMarking`, `TerrainCell`. By that measure they were worse than the thirty
`exmateria_battlefield` shed under ADR-0211, which is why ADR-0212 dec. 3
overturned dec. 8's deferral of this addon. The members below now declare none;
they are published as constants on the façade:

```gdscript
const TerrainCell = ExMateriaSchema.TerrainCell   # alias it back, or spell it long
var cell: ExMateriaSchema.TerrainCell = lattice.cell_at(grid)
```

`tools/check_addon_globals.py` holds both directions — nothing else here may
declare a global, and nothing the façade publishes may dangle.

### `compositing_key/` — where a primitive lands in the ordering table

| file | what it is |
|---|---|
| `DepthMode.gd` | the enum, the calibrated bias magnitudes, and the CPU port of `ot_depth()` |
| `ot_depth.gdshaderinc` | the same encoding in GLSL — every constant above re-declared as a uniform default |
| `Fold.gd` | display-space fold membership: `render_layer` + `render_layer_order`, stamped in one static call |
| `fold_layer.tres` | the single shared held-out layer resource every fold carrier joins |

### `lattice/` — what the map data says about one square

| file | what it is |
|---|---|
| `TerrainCell.gd` | the terrain facts at one grid cell: `grid` · `height` · `impassable` · `unselectable` · `pass_through_only` · `surface_type`, plus the `NONE` coordinate that means "not a cell" |
| `CellMarking.gd` | **why** a cell is marked — `NONE` · `PLACEMENT_PLAYER` · `PLACEMENT_ENEMY` · `PLACEMENT_CONTESTED` · `CURSOR_ACTIVE` · `PLACEMENT_UNAVAILABLE` |

The value `Battlefield`'s `Lattice` port answers with, so a `Tile` — a
`StaticBody3D` the addon owns — never crosses to a consumer
([ADR-0164](../../docs/adr/0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 2, field set fixed at six by
[ADR-0192](../../docs/adr/0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)
dec. 6). Unlike the two pairs below it has no shader half: there is nothing for
two sides to compute identically, only a payload for them to agree on.

`CellMarking.Kind` is the ninth row, admitted by
[ADR-0196](../../docs/adr/0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
dec. 6/7. `src/strategy/` (`Battle`) decides which cells wear which marking;
`Battlefield` paints it, through `map.highlights.paint(cell, kind)`. It lives here
rather than on `Tile` or `TileHighlights` because a host had to compile against
`Battlefield` in order to say *"contested"* — ADR-0164 dec. 4 criterion 1's largest
namer, now measured by `tools/check_lattice_publish.py`. It names **why** a cell is
marked, never what it looks like; the look is `TileOverlayConfig`'s, and `Tile.gd`'s
own comment insists the two are decoupled.

⚠️ Riding `TerrainCell` as a nested enum was **rejected**, even though it is free of
the admission gate. `TerrainCell.NONE` is a terrain-cell value; a marking is not —
`TerrainCell`'s own docstring draws that line, ruling that *"`surface_type` is what
the map data says"* while placement policy stays in `Battle`. Hanging a marking there
to dodge the gate is the junk-drawer accretion ADR-0139 dec. 3 exists to prevent.

⚠️ `world_position` is deliberately **not** a field — it derives from a live node
transform and is the one fact that can go stale without terrain changing at all.
Ask the port: `world_position_at(x, z)`.

### `unit_vocabulary/` — the value sets a unit sprite is described with

| file | what it is |
|---|---|
| `Facing.gd` | **which way a unit is turned** — `NORTH` · `EAST` · `SOUTH` · `WEST`, the world wheel |
| `SpriteLayer.gd` | **which of a unit sprite's three composed layers** — `TYPE1` · `WEP1` · `EFF1` |
| `ClockOwner.gd` | **which pump advances a unit's animation clock** — `SELF` · `SCENARIO` · `COMBAT` |
| `UnitMaterialVariant.gd` | **which blend a unit sprite is drawn with** — `OPAQUE` · `ADDITIVE` · `FLAT` |
| `UnitActivity.gd` | **what a unit is currently doing** — both halves: `Display` (14 members, what the animation layer plays) and `Logical` (10, what the engine thinks). 🔴 **GENERATED — edit the YAML.** |

Admitted by
[ADR-0215](../../docs/adr/0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)
dec. 2 and named by
[ADR-0217](../../docs/adr/0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md)
dec. 7. A caller of one of these learns a **value set**, not a contract — no
ordering, no invariant, no error mode — and until this pass, learning one meant
compiling against `Sprite Rig`: a host had to name an 888-line Node in order to say
*"weapon layer"*, or a 369-line one to say *"south"*. Re-classifying them removes the
crossing **without re-pointing a call**, which is what makes the member scan a valid
instrument for the extraction's P1.

🔴 **`UnitActivity.gd` IS MACHINE-OWNED AND THE OTHER FOUR ARE NOT.** It is one of
**six** targets `tools/gen_activity_taxonomy.py` emits from `tools/activity_taxonomy.yaml`
(ADR-0217 dec. 8, issue #740); the other five are `Battle`'s `LOGICAL_ACTIVITY_*`
constants, their GLSL twin, the dispatch shell that translates one half into the other,
the rig's own display enum, and a region of context cluster 18. A hand edit to it
survives until the next run and then vanishes with no diagnostic. It carries **both**
halves because they are generated from the same rows and exist only to be translated
into each other — publishing one here and leaving the other in `Battle` would put a
single source of truth across a package boundary, which is ADR-0196's argument for
`CellMarking` applied unchanged.

🔴 **The behaviour did NOT move, and that is the whole shape of the change.**
`SpriteLayerManager`, `AnimationStateController`, `AnimationClock` and `UnitMaterial`
keep their class names and every line of their behaviour — the snap, the frame
loads, the accumulator, the shader table — and each now names the kernel for its own
internal control flow, which ADR-0139 permits. This group has no shader half: there
is nothing for two sides to compute identically, only a value set for them to agree
on.

🔴 **The subject noun is carried, and one of the three reasons is measured.** The
bare words `Layer`, `Owner` and `Variant` are ADR-0212's own examples of the
collision hazard, and `ExMateriaSchema.Layer` tells a stranger nothing. `Layer` was
not hypothetical either way — `colour_model/ColorStack.gd` **already declares
`class Layer`**, so the bare spelling would have collided inside this addon. And
`Variant` is Godot's own type name: `addons/exmateria_ui/formation/FormationScene.gd` annotates
seven live values with the builtin, so a naming file aliasing the bare tail there
would silently re-type them.

🔴 **THE INTEGER VALUES ARE WRITTEN OUT in all four**, as `CellMarking.Kind` does.
These values are stored, compared and — for `SpriteLayer` — mirrored by hand in
Python (`tools/parse_weapon_wep1_anim_ids.py` hardcodes `WEP1_LAYER = 1`, where no
import can follow a rename). Left implicit, a later re-ordering is a silent
renumbering with nothing red in between.

### `colour_model/` — how a colour transform is expressed and packed

| file | what it is |
|---|---|
| `ColorRecipe.gd` | FFT's 11 PSX `Color` modes reduced to two shapes, `affine` and `luma` |
| `ColorStack.gd` | the ordered layer stack, the byte-exact DDA, and the bounded uniform packing |
| `color_stack.gdshaderinc` | the unpacking half — the four uniform arrays `ColorStack._pack` writes |

Each pair is **one encoding in two languages**. `ColorStackGpuParityTest` renders
the GLSL half and asserts it byte-matches the GDScript half; that test is the
reason the two halves may not live in different addons.

## What gets in

[ADR-0139](../../docs/adr/0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
is the gate, and it is a list, not a property:

1. **The file realises a named published schema.** To add a member you add a
   schema first — a payload and the two systems it crosses between, in an ADR.
   A file move cannot do it.
2. **Zero outbound edges** into any system, `content` or `platform` bucket. A
   member that reached into a system would drag that system behind every
   consumer.
3. **Never an autoload.** An ambient global you ask for an answer is a *port*
   (ADR-0118 dec. 2), and a port is not a schema.

A member **may compute** — exactly the computation both sides must perform
identically, which is what a codec is. What it may not compute is *which* recipe
or *when*: that is the driver's, and rule 2 enforces it, because policy needs a
system to decide against.

Reach is explicitly **not** the test. `DebugConfig` and `Tune` outreach every
member here and neither is a schema;
[ADR-0146](../../docs/adr/0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md)
dec. 3 turned down `pixel_aspect.gdshaderinc`, which 16 shaders across six buckets
include, for the same reason: it has a CPU *writer*, not a CPU *counterpart*, so
there is nothing for two sides to disagree about.

`plugin.gd`, `plugin.cfg` and `exmateria_schema.gd` are the addon's Godot
scaffolding and its public surface. They realise no schema and are not
members — the source instrument books them outside the `schema` bucket for
exactly that reason.

## Promotion

The kernel is promoted with the **first system promoted**, never on its own
schedule (ADR-0139 dec. 10): a released addon cannot depend on a path inside the
host, so the kernel ships as that release's dependency. A package with no
consumer is what ADR-0121 dec. 7 exists to prevent.
