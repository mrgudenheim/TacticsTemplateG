extends RefCounted

## **Why a cell is marked** — a placement-zone role, plus the cursor.
##
## ADR-0118 dec. 1's ninth schema row and the kernel's fourth code member, admitted
## by [ADR-0196](../../../docs/adr/0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
## dec. 6/7. `src/strategy/` (`Battle`) decides which cells wear which marking;
## `Battlefield` paints it, through `map.highlights.paint(cell, kind)`.
##
## 🔴 IT DOES NOT NAME AN APPEARANCE. The look lives in `TileOverlayConfig`, and
## `Tile.gd`'s own comment insists the two are decoupled — *"FFT's color meanings
## are decoupled from our placement semantics"*. That is why this is `CellMarking`
## and not the `HighlightType` it was called for three loop passes: the enum is a
## classification, and the first non-placement, non-cursor marking would have made
## the old name a lie a third time.
##
## **Why the schema and not the addon.** ADR-0193 dec. 3 put the `NONE` coordinate in
## the kernel on the argument that *"the kernel is where both sides can name it"*, and
## a marking is the same kind of thing: a value vocabulary two systems must agree on.
## Any home inside `Battlefield` means a host compiles against `Battlefield` in order
## to say *"contested"* — which is exactly the coupling ADR-0164 dec. 4 criterion 1
## exists to remove, and `tools/check_lattice_publish.py` now measures.
##
## ⚠️ **`TileHighlights` was the destination both prior declines assumed, and it is
## structurally wrong.** `TileHighlights.gd` already depends on `Tile`, while `Tile.gd`
## uses the enum at its own declaration — so hosting it there re-creates the
## `Tile.gd → TileHighlights.gd → Tile.gd` cycle ADR-0170 dec. 4 diagnosed and
## ADR-0166 dec. 1 closed by deleting the reverse edge. Both declines
## ([ADR-0193](../../../docs/adr/0193-the-highlight-is-a-publish-with-an-address-and-the-sentinel-belongs-to-the-schema.md)
## dec. 2, ADR-0195 dec. 6) priced that structural blocker as a re-spelling COUNT,
## and the count was not even stable — 43 / 43 / 47 / 39 across four artifacts.
## ADR-0196 dec. 5 is the rule that stops it recurring: a re-spelling count is never
## grounds to decline, and a deferral must name the PASS that owns the resolution.
##
## `SELECTED` IS THE MARKING THE RENAME ANTICIPATED. `HighlightType` became
## `CellMarking` because *"the first non-placement, non-cursor marking would have made
## the old name a lie a third time"* — and a latched march pick is exactly that: not a
## deployment role, and not where the cursor is. It used to borrow `CURSOR_ACTIVE`, on the
## argument that this was the one paint already meaning "this tile, right now". The
## argument was about SEMANTICS and it was fine; what it could not survive was two writers
## putting the same value in one slot, because then nothing downstream could tell which of
## them had written it — and the cursor's restore-on-leave erased the pick every time the
## player walked away from it (`CursorConfirmEndToEndTest`, red one commit ago).
##
## Spelling follows the schema's own precedent, `DepthMode.Mode`. Keyed to the same
## noun as the member it ships beside, `TerrainCell` — both addressed by the
## `Vector2i` cell ADR-0166 dec. 3 made the one spelling of a cell's identity.

## 🔴 THE INTEGER VALUES ARE WRITTEN OUT, and they are `Tile.HighlightType`'s
## declaration order verbatim. ADR-0196 dec. 6 moves the enum with its VALUES
## unchanged; leaving them implicit would make a future re-ordering — for example to
## group the placement roles together, which the ADR's own prose accidentally does —
## a silent renumbering. `TileOverlayConfig` keys a `Dictionary` by these and derives
## each tunable slug from the member NAME.
##
## 🔴 AND 3 IS A HOLE. `PLACEMENT_CONTESTED = 3` was the deployment march's objective
## tile — a game-original concept with no FFT equivalent — retired by ADR-0258 along
## with the march itself. Closing the gap by renumbering 4/5/6 down is exactly the
## silent renumbering the paragraph above forbids, so the hole stays and 3 is not
## reused. `TileOverlayConfig.param_slug` was `Kind.keys()[value]`, which is only
## correct while the values are DENSE; ADR-0258 dec. 4 moved it to `Kind.find_key`
## so the slug derivation no longer depends on that.
enum Kind {
	NONE = 0,                   ## Not marked.
	PLACEMENT_PLAYER = 1,       ## Friendly — the viewing team may deploy here.
	PLACEMENT_ENEMY = 2,        ## Enemy — the viewing team may not.
	# 3 — was PLACEMENT_CONTESTED, the deployment march's objective (ADR-0258). Not reused.
	CURSOR_ACTIVE = 4,          ## The cell the cursor is on.
	PLACEMENT_UNAVAILABLE = 5,  ## Already claimed.
	SELECTED = 6,               ## Picked and LATCHED — the cursor has moved on.
}
