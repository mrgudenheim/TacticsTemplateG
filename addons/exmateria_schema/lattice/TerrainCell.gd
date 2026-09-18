extends RefCounted

## One **terrain cell** — the value answer to "what is at (x, z)?", and the payload
## the `Lattice` port hands out instead of the `Tile` node it reads it off.
##
## ADR-0118 dec. 1's eighth schema row and the kernel's third code member, admitted
## by ADR-0164 dec. 2. The field set is ADR-0192 dec. 6's **six**, not dec. 2's
## proposed eight:
##   • `grid` is one `Vector3i`, not `grid_x` / `grid_z` / `level` — the same key
##     ADR-0166 dec. 3 lands holder 4 and `PlacementTileSet.claimed_tiles` on, so
##     the cell's identity is spelled the way every `Dictionary` that holds one is
##     keyed. It was a `Vector2i` until ADR-0219 corrected the ARITY: the ROM
##     resolves a tile through `tile_ptr(x, z, level)` @ `0x80183fb4`, whose
##     `sltiu v0,a2,0x2` bounds-checks a THIRD coordinate we used to drop.
##   • `world_position` is NOT a field. It derives from a live node transform, so it
##     is the one fact that can go stale without terrain changing at all — ADR-0164
##     dec. 2 named it as such in its own 🔴. Ask the port: `world_position_at(x, z)`
##     is a scalar query, allocation-free and staleness-free, and every site that
##     read `get_tile(x, z).global_position` already holds `(x, z)`.
##
## 🔴 A cell is a SNAPSHOT. Today every tile is built once by
## `DynamicTerrainBuilder._create_tile` and never moves, so no snapshot can be
## stale; the day terrain mutates, a held cell lies about `height` / `impassable`.
## ADR-0164 dec. 2 accepted that cost explicitly — whoever makes terrain dynamic
## owns re-opening it.
##
## What is NOT here, deliberately: which surfaces a system refuses to deploy onto.
## `surface_type` is what the map data says; `["Water","Waterway","River","Sea",
## "Lava"]` is `Battle`'s placement policy and lives in
## `PlacementPolicy._is_valid_for_placement` (ADR-0192 dec. 6, ADR-0166
## dec. 1). Collapsing the three thin flags into a `placeable` bool would move that
## policy onto a type the shared kernel owns.

## The coordinate that is NOT a cell — "unplaced", "off-grid", "no destination".
##
## ONE sentinel, in the schema, because both sides need to spell it: ADR-0166 dec. 3
## puts a unit's absence state on a sentinel rather than a second `has_cell` field
## (ADR-0119 dec. 3 / ADR-0083: never two fields encoding one axis), and holder 3's
## claim maps and `Battle`'s "no destination" answer need the same value. A second
## constant named the same thing somewhere else would re-open exactly the "one type
## for one concept" question dec. 3 closed.
##
## `Vector3i.MIN` and not `(-1, -1, -1)`: `DynamicTerrainBuilder` offsets doodad
## tiles by a placement origin, so a small negative grid coordinate is a legal cell.
const NONE := Vector3i.MIN

## The number of terrain levels a column can hold. The ROM's own bound, read off
## `tile_ptr`'s `sltiu v0,a2,0x2` @ `0x8018400c` and confirmed by the stride: the
## terrain block after `0x8018F8CC` is exactly `0x1000` bytes = 2 levels x 256 slots
## x 8 bytes (ADR-0219). Anything asserting a level against this is checking OUR
## arithmetic, not the ROM's data — the scenario corpus supplies only `{0, 1}`
## across 634 unit-placement instructions (ADR-0219 P4).
const LEVEL_COUNT: int = 2

## The ground level — the one every column that exists at all has.
const GROUND_LEVEL: int = 0


## The cell key for the GROUND at (x, z).
##
## Spell a level-0 assumption with this rather than an inline `Vector3i(x, z, 0)`,
## so that `grep -rn "TerrainCell.ground("` is a census of every place the game
## says "I only deal in the ground plane" (ADR-0219 Consequences: "where a system
## genuinely only has one level, saying so explicitly is cheaper than the current
## implicit answer"). It is not a shorthand for `Lattice.ground_at`, which asks the
## map what the column's lowest tile IS; this asserts which one you mean.
static func ground(x: int, z: int) -> Vector3i:
	return Vector3i(x, z, GROUND_LEVEL)

## Grid coordinates, `(grid_x, grid_z, level)`. The cell's identity and the key
## every occupancy `Dictionary` uses (ADR-0166 dec. 3, ADR-0219 dec. 1).
##
## 🔴 `grid.z` IS A LEVEL INDEX — not a world Z, and not a height. The name
## collision with `Vector3` world coordinates is real and this is where it is
## written down: `.x` is grid X, `.y` is grid Z (unchanged from the `Vector2i`
## this replaced, which is why every existing read site stays correct), and `.z`
## is which of the column's up-to-`LEVEL_COUNT` tiles this is. `height` below
## remains the separate field world-Y derives from. Anything reading a cell key
## as a position is wrong.
var grid: Vector3i = Vector3i.ZERO

## Terrain height in FFT half-steps. Compared directly against a jump range by both
## the CPU distance field and the GPU mover, so it must stay integral.
var height: int = 0

## Terrain refuses traversal at all.
var impassable: bool = false

## Terrain may not be targeted/selected by the cursor.
var unselectable: bool = false

## A unit may walk THROUGH but not stop here.
var pass_through_only: bool = false

## What the map data calls this surface ("Grassy", "Water", "Stone Floor", …).
## Read once in `src/`, by `PlacementPolicy._is_valid_for_placement`.
var surface_type: String = "Unknown"


# No `grid_x` / `grid_z` accessors, and their absence is the decision rather than an
# omission: ADR-0192 dec. 6 rejects a cell whose identity is spelled differently from
# the key everything else is keyed on, and a read-only alias is still a second
# spelling — the first `Dictionary` lookup re-opens it. Read `cell.grid.x` /
# `cell.grid.y`, or pass `cell.grid` whole, which is what the callers want anyway.


func _to_string() -> String:
	return "TerrainCell(%d,%d L%d h=%d%s)" % [
		grid.x, grid.y, grid.z, height, " impassable" if impassable else ""]
