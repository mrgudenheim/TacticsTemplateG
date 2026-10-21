extends RefCounted

## The **lattice port's vocabulary** — the six value-typed verbs that answer
## "what is the ground doing at (x, z)?", and the type a consumer annotates with.
##
## ADR-0118 dec. 1's schema rows and the kernel's fifth code member, admitted by
## [gl-ADR-0332](../../../docs/adr/0332-the-lattice-vocabulary-is-separable-because-the-port-already-separated-it.md)
## dec. 1. It exists because a TYPE is bound at parse time, so a consumer that
## annotates `var lattice: Lattice` reaches the implementation's ADDON no matter how
## the value got there (gl-ADR-0330 dec. 2). Naming the vocabulary here lets the
## annotation stay and the reach go free (ADR-0202 dec. 2).
##
## 🔴 THE SPLIT IS THE FILE'S OWN, NOT ONE THIS IMPOSED. `Lattice.gd`'s thirteen
## members partition on the underscore: its **six public** verbs name only `Vector3i`,
## `int`, `bool`, `Vector3` and `TerrainCell`, and its **seven private** ones
## (`_tile_at`, `_tiles`, `_cell_of`, `_edge_vertices_match`, `_world_vertices`,
## `_init`, `_bind`) name `Tile` or `TileStore` — every one of them. This type is the
## first list; `Battlefield` keeps the second.
##
## 🔴 IT IS A CONTRACT, NOT A DECORATION. GDScript checks an override's signature
## against its parent, so a `Battlefield` verb that stopped answering with values
## would fail to PARSE rather than drift — measured, gl-ADR-0332 dec. 3 arm B.
##
## ⚠️ `Tile` IS A `StaticBody3D` AND NEVER CROSSES (ADR-0164 dec. 4 criterion 3,
## guarded at target 0 by `tools/check_lattice_doors.py`). That guard is why this
## type can exist: the port was already forbidden from handing out a node, so every
## signature here was ALREADY value-typed and nothing had to be widened to make it so
## (ADR-0148 — a widened annotation would have been the defect, not the remedy).
##
## The stubs below are the base of an implementation hierarchy, not a usable lattice:
## a bare `TerrainQuery` answers "nothing here" for every cell, which is the same
## answer `Lattice` gives when its store is unbound. The **SIBLING NAMER** that
## implements them is `addons/exmateria_battlefield/lattice/Lattice.gd`.

const TerrainCell = ExMateriaSchema.TerrainCell


## The terrain facts at one CELL, or `null`. The caller HOLDS a cell key and means
## that exact level — the only query that can address a bridge over a moat.
func terrain_at(_cell: Vector3i) -> TerrainCell:
	return null


## The GROUND of the column at (x, z) — its lowest present level — or `null`.
func ground_at(_x: int, _z: int) -> TerrainCell:
	return null


## Every cell of the column at (x, z), lowest level first. Empty if the column is.
func column_at(_x: int, _z: int) -> Array[TerrainCell]:
	return []


## The grid→world projection for `cell`, or `Vector3.ZERO` if there is no tile.
## A scalar rather than a field because it derives from a LIVE node transform and is
## the one fact that can go stale without terrain changing (ADR-0192 dec. 6).
func world_position_at(_cell: Vector3i) -> Vector3:
	return Vector3.ZERO


## Is the edge between two adjacent cells a CLIFF — must a unit jump it rather than
## walk it? `false` when either cell is absent: an edge to nothing is not an edge.
func is_cliff_edge(_a: Vector3i, _b: Vector3i) -> bool:
	return false


## The one-shot snapshot consumers index. Fresh cells, never cached.
func all_cells() -> Array[TerrainCell]:
	return []
