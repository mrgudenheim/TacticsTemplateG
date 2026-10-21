extends RefCounted

## **What a gambit's action IS** — attack, wait, move, use an ability, retreat — and the
## control-verb names of the four that have one. A value set and its enum→string table,
## and nothing that decides anything.
##
## ADR-0118 dec. 1's **thirteenth** schema row, admitted by
## [gl-ADR-0377](../../../docs/adr/0377-the-almanac-stays-and-stops-being-named-by-system-addons-because-who-may-name-a-package-is-not-where-it-lives.md)
## dec. 11 on `UnitRole`'s test, which is the one in this directory that matters:
## *"an `enum`, an enum→string table, a list of the enum's members and a two-line
## predicate: a caller learns a **value set**, not a contract."* That is exactly what is
## here, and `UnitRole` was admitted by **ADR-0280 dec. 3** — the same ADR whose dec. 1
## keeps `gambits/` in the almanac. Moving a gambit's VOCABULARY down into the kernel is
## not moving the gambit, and ADR-0280 has already drawn that line once.
##
## 🔴 THE ADMISSION GATE IS SATISFIED BY MEASUREMENT, NOT BY ANALOGY. ADR-0139 dec. 3
## admits a row when it CROSSES a boundary. `Gambit.ActionKind` is named on 16 lines and
## `KIND_TO_VERB` on 3 inside `addons/exmateria_ui` alone — three files in a sibling
## addon — which is why `abilities/AbilitySlot.gd` is NOT here beside it: that one is
## named on 4 lines in one file and its own name crosses nothing, so the refusal recorded
## in `EquipSlot.gd` still holds for it and was re-measured before this row was written.
##
## 🔴 NOTHING HERE IS DERIVED. `ABILITY` carries no verb ON PURPOSE — an ability is not a
## control verb, it is an id — so neither table below names it (`VERB_TO_KIND` is five of eight, `KIND_TO_VERB` seven) and a
## caller that wants a word for `ABILITY` is asking the wrong question. The decision of
## WHICH kind a gambit takes, the legacy-save migration that reads these names
## (`action_from_name`), and `_to_string` all stay in `addons/exmateria_almanac/gambits/`,
## which re-exports this file and keeps every call site in the tree spelled as it was.

## MOVE_TO_TILE is APPENDED (map #1537, #1542) so every existing int position holds still and
## no save migrates. It is the absolute-tile walk — `MOVE` is the unit-anchored one.
## BEST is appended the same way (ADR-0403): the ROM AI's "the best action, if one
## beats staying put, else fall through" row (ROM_ENEMY_AI.md §8.1). Template-only — no player verb names it.
## ELEMENTAL is appended the same way (ADR-0407 dec. 4): the Geomancer's
## terrain-resolved command, one verb that casts whichever learned Elemental ability the caster's
## tile produces — the first verb that is not one ability id. The ROM's name; not "Geomancy".
enum Kind { ATTACK, WAIT, MOVE, ABILITY, RETREAT, MOVE_TO_TILE, BEST, ELEMENTAL }

## Control-verb → kind. Five of eight: abilities are not verbs, they carry an id.
const VERB_TO_KIND := {
	"Attack": Kind.ATTACK,
	"Wait": Kind.WAIT,
	"Move": Kind.MOVE,
	"Retreat": Kind.RETREAT,
	"Elemental": Kind.ELEMENTAL,
}

## Kind → control verb: the same five, plus `MOVE_TO_TILE` and `BEST`, for the same reason: prose
## and the read-only enemy view must name the row, and neither may be parsed back INTO a kind.
##
## 🔴 `MOVE_TO_TILE` IS IN THIS MAP AND NOT IN `VERB_TO_KIND`, AND THE ASYMMETRY IS THE POINT.
## This direction is kind → words, so prose can name a tile walk instead of falling through to
## the "Wait" default and lying about what the unit is doing. The other direction is words →
## kind, and nothing may parse a string INTO a tile walk: a Directive carries a cell that no
## verb name can supply, so a round trip through a name would produce a MOVE_TO_TILE aimed at
## (-1, -1). `GambitOptions.action_verbs()` lists its four verbs explicitly rather than walking
## this map, so the surface's `Do` list does not grow a row for it either.
const KIND_TO_VERB := {
	Kind.MOVE_TO_TILE: "Move",
	Kind.ATTACK: "Attack",
	Kind.WAIT: "Wait",
	Kind.MOVE: "Move",
	Kind.RETREAT: "Retreat",
	Kind.BEST: "Best",
	Kind.ELEMENTAL: "Elemental",
}
