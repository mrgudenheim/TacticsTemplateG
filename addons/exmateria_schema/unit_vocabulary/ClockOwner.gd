extends RefCounted

## **Which pump advances a unit's animation clock** — exactly one owner per unit,
## so a unit can never ride two clocks.
##
## Part of ADR-0118 dec. 1's **tenth** schema row — the unit-sprite vocabulary —
## admitted by
## [ADR-0215](../../../docs/adr/0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)
## dec. 2 and named by ADR-0217 dec. 7. It is the value the hosts that OWN the
## pumps have to say — `ScenarioVM`, `NavigatorMain`, `GPUArena`, `ScenarioWorld`
## — and saying it used to mean compiling against the sprite rig's clock, 38 uses
## across a boundary. `AnimationClock` keeps its class name and stays the sole
## owner of time (the delta→frames accumulator, the tick-vs-delta mode, the
## walk-speed multiplier, ADR-0020/ADR-0025); only the value set moved.
##
## The scenario→battle transition is a single SCENARIO→COMBAT handoff
## (`NavigatorMain._go_live`), and `AnimationClock.tick_based` is the derived
## predicate `owner != SELF` — ADR-0083 folded the old standalone flag into the
## owner so the two cannot drift.
##
## 🔴 `ClockOwner`, NOT THE BARE WORD `Owner`. ADR-0212's own examples of the
## collision hazard are generic English nouns, and `ExMateriaSchema.Owner` names
## no subject at all.


## Who pumps this unit's clock. 🔴 THE INTEGER VALUES ARE WRITTEN OUT so a later
## re-ordering cannot silently renumber a value that crosses a package boundary.
enum Kind {
	SELF = 0,      ## Delta-driven; `Unit._process` pumps `tick(delta)` (free-roam smoothness).
	SCENARIO = 1,  ## The `ScenarioVM` body pump owns it (openers, cutscenes, deployment breathe).
	COMBAT = 2,    ## The `CombatLoop` tick owns it (live combat, `GPUArena`).
}
