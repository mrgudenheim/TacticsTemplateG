extends Node

## The **cursor port's vocabulary** — where the player's roam cursor is, and the three intents
## the player expresses on it. The type a consumer annotates with.
##
## ADR-0332's third route, taken a second time: a symbol whose consumed surface is already
## value-typed does not need to MOVE, it needs its SIGNATURES named where reaching them is free.
## `addons/exmateria_battlefield/cursor/CursorRig.gd` `extends` this and keeps its behaviour;
## `addons/exmateria_ui`'s two annotation sites bind `ExMateriaSchema.CursorQuery` and the
## reach goes free (ADR-0202 dec. 2). gl-ADR-0363 dec. 1.
##
## 🔴 THE CONSUMED SURFACE IS FOUR MEMBERS AND ALL FOUR ARE VALUE-TYPED. Measured across
## `addons/exmateria_ui` with `score_goals.strip_noncode`: `cursor_moved`, `cursor_confirmed`
## and `cursor_inspected`, each carrying one `Vector2i`, and `grid_pos: Vector2i`. Nothing was
## widened to achieve that (ADR-0148) — `CursorRig` was already forbidden from handing out a
## node, because ADR-0164 dec. 4 criterion 1 made it the PUBLISHED cursor and `TileCursor` and
## `CursorController` lost their `class_name`s to keep them off the surface.
##
## 🔴 WHY THIS IS THE ONLY ROUTE HERE, AND A PORT IS NOT. `exmateria_ui` does not construct,
## locate or call a static on a cursor — the rig ARRIVES BY ARGUMENT
## (`FormationMapHost.bind_map`, `FormationDetailTransition.mount_over_map`). There is nothing
## for an install port to forward: the only reason the addon spells `CursorRig` at all is the
## parameter and field ANNOTATIONS, and a type is bound at parse time no matter how the value
## got there (gl-ADR-0330 dec. 2). That is the case gl-ADR-0335 dec. 1 recorded `Cutscene` did
## NOT have — *"zero of the seven is a type annotation"* — and it is why this map's last line
## pair is paid differently from its first ten.
##
## 🔴 THIS IS THE KERNEL'S FIRST `Node`, AND THAT IS THE PRICE. Every other published member of
## `addons/exmateria_schema` is a `RefCounted`, and the façade's own docstring says *"Nothing
## here is instantiated."* That stays TRUE OF THIS FILE in the sense it was written: a bare
## `CursorQuery` is not a usable cursor — it answers `Vector2i.ZERO` for every cell and emits
## nothing — and nothing in this package instantiates one. It must `extend Node` because
## `CursorRig` does, and GDScript has single inheritance, so a `RefCounted` base could not be
## its parent. The alternative was leaving `Battlefield` as permanent declared debt for two
## annotation sites; gl-ADR-0363 dec. 2 prices both.
##
## ⚠️ IT IS A CONTRACT, NOT A DECORATION. GDScript checks an override's signature against its
## parent, so a `Battlefield` cursor that stopped answering `Vector2i` would fail to PARSE
## rather than drift — measured, gl-ADR-0363 dec. 3 arm B.
##
## The **SIBLING NAMER** that implements this is
## `addons/exmateria_battlefield/cursor/CursorRig.gd`.

## The player moved the cursor — by device or by a host's `move_to`. `TileCursor`'s own
## `cursor_stepped` (device-only) is NOT here: no consumer outside `Battlefield` reads it, and a
## vocabulary is the members that CROSS.
signal cursor_moved(grid_pos: Vector2i)

## The player confirmed on the cell.
signal cursor_confirmed(grid_pos: Vector2i)

## The player asked to inspect the cell.
signal cursor_inspected(grid_pos: Vector2i)


## The cursor's current grid cell. `Vector2i.ZERO` where no cursor is bound — the same value a
## fresh cursor reports, so a host cannot tell "unbound" from "at origin" and must not try to.
##
## 🔴 THE STORAGE IS THE IMPLEMENTATION'S, WHICH IS WHY THIS READS THROUGH A VERB. GDScript
## refuses a member that "already exists in parent class", so a base declaring `var grid_pos`
## and a `CursorRig` re-declaring it with its own getter is a PARSE ERROR — the way ADR-0332
## dec. 3's arm C closed on contact. The property lives here so the consumer's spelling does
## not change; the ANSWER is an overridable verb.
var grid_pos: Vector2i:
	get:
		return _grid_pos()


## The implementation's answer for [member grid_pos]. A bare `CursorQuery` has no cursor, so it
## answers the origin. Override this, never `grid_pos`.
func _grid_pos() -> Vector2i:
	return Vector2i.ZERO
