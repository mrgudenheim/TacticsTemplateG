extends RefCounted

## **Which way a unit is turned** — the four world cardinals, and nothing else.
##
## Part of ADR-0118 dec. 1's **tenth** schema row — the unit-sprite vocabulary —
## admitted by
## [ADR-0215](../../../docs/adr/0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)
## dec. 2 and named by ADR-0217 dec. 7. It used to be nested in a 369-line Node
## (`AnimationStateController`), which meant a caller compiled against the sprite
## rig's animation state machine in order to say *"south"* — 52 uses, and a
## caller of them learns a **value set**, not a contract.
##
## 🔴 THIS IS THE WORLD WHEEL, NOT THE SPRITE-POSE INDEX. The two disagree and
## conflating them is a shipped bug this repo has already paid for. The PSX
## 12-bit angle truncates to a cardinal as `(angle >> 10) & 3` on the CANONICAL
## raw-PSX world wheel `0x0=E, 0x4=S, 0x8=W, 0xC=N` (CCW) — the same wheel the
## scenario spawn seed, the camera yaw and the yellow facing arrow use. The PSX
## *sprite-pose* index numbers its cardinals differently (`CinematicPoseLUT`
## `cardinal_idx 0=S, 1=E, …`), and mapping truncate 0→SOUTH once made
## `current_facing` disagree with the arrow and made the combat render fallback
## pick the perpendicular cardinal at E/S. The snap itself is behaviour and stays
## with the rig (`AnimationStateController.snap_angle_to_cardinal`); only the
## value set is here.
##
## Spelling follows the kernel's own precedent, `DepthMode.Mode` /
## `CellMarking.Kind`: a subject noun, then the kind of thing it classifies. The
## bare word `Facing` is the noun; `Direction` is the classification.

## The four world cardinals, in the declaration order the sprite rig has always
## used. 🔴 THE INTEGER VALUES ARE WRITTEN OUT because this enum is stored and
## compared across a package boundary and a later re-ordering would otherwise be
## a silent renumbering — the same reason `CellMarking.Kind` spells its out.
enum Direction {
	NORTH = 0,  ## +X
	EAST = 1,   ## +Z
	SOUTH = 2,  ## -X
	WEST = 3,   ## -Z
}


## Each cardinal's PSX 12-bit world angle, indexed BY `Direction`'s own integers —
## the canonical raw-PSX wheel this file's docstring spells out (`0x0=E, 0x4=S,
## 0x8=W, 0xC=N`), scaled to 12 bits.
##
## Here because it is a VALUE SET, which is the line this file already draws: the
## snap (`AnimationStateController.snap_angle_to_cardinal`) is behaviour and stays
## with the rig; the table a cardinal indexes is vocabulary. It arrives at #744
## because `UnitDisplay` reached `Battle`'s `Unit._CARDINAL_TO_12BIT` for it, which
## is one of ADR-0215 P3a's 27 — a painter compiling against the combat unit in
## order to say *"south is 0x400"*.
##
## 🔴 THIS IS THE THIRD COPY IN THE TREE and the other two are not touched here.
## `src/units/Unit.gd:391` and `src/scenarios/ScenarioVM.gd:4318` each declare
## their own (the latter as a Dictionary), both agreeing with this one today.
## Collapsing them is a host edit in two systems this ticket does not open; #744's
## PR files it. Until then, a change here that is not made there is a silent
## divergence, which is why the values are written out rather than derived.
const CARDINAL_TO_12BIT: Array[int] = [0xC00, 0x000, 0x400, 0x800]
