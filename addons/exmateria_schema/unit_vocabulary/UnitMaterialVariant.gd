extends RefCounted

## **Which blend a unit sprite is drawn with** — the question a consumer actually
## has when it asks for a unit material.
##
## Part of ADR-0118 dec. 1's **tenth** schema row — the unit-sprite vocabulary —
## admitted by
## [ADR-0215](../../../docs/adr/0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)
## dec. 2 and named by ADR-0217 dec. 7. Every unit sprite in the game — battle,
## formation roster, cutscene — is drawn by one compositor, and what differs
## between them is the blend. `render_mode` has to sit in the entry shader because
## Godot has no runtime blend switch, so there are three shader files and the
## consumer's real question is *which variant*, not *which file* (ADR-0189 dec. 3).
##
## 🔴 THE SHADER TABLE IS **NOT** HERE, AND THAT IS THE POINT. The three entry
## shaders are the sprite rig's own files, and `UnitMaterial` — which keeps its
## class name, its `for_variant` and its `shader_for` — is the only thing that
## maps a variant to one. A kernel member with an address into a system's asset
## tree would break ADR-0139's rule 2 (zero outbound edges) and would put the
## kernel in the business of deciding *which* rather than naming *what*.

## The blend a consumer is asking for. 🔴 THE INTEGER VALUES ARE WRITTEN OUT so a
## later re-ordering cannot silently renumber a value that keys the rig's shader
## table across a package boundary.
enum Kind {
	OPAQUE = 0,    ## Battle + formation body: depth-writing, on the OT depth ladder.
	ADDITIVE = 1,  ## The dead-unit fade ({43}): blend_add, so a palette ramp to black dissolves.
	FLAT = 2,      ## The flat ortho UI (formation/roster): no OT depth, no PAR anchor stretch.
}
