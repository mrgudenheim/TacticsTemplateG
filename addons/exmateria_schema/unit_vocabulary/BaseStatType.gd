extends RefCounted

## **Which base-stat curve a unit grows on** — `MALE`, `FEMALE`, `MONSTER`. The
## row selector into the per-unit-type base stat table, and nothing else: it says
## which curve, never what is on it.
##
## ADR-0118 dec. 1's **twelfth** schema row, admitted by
## [ADR-0294](../../../docs/adr/0294-the-catalogues-progression-debt-is-a-vocabulary-and-the-kernel-is-where-a-value-set-lives.md)
## dec. 2, alongside [EquipSlot] and [Zodiac].
##
## 🔴 THE TABLE IS NOT HERE AND MUST NOT COME. `progression/BaseStatsDatabase.gd`
## holds the curves and `progression/StatCalculator.gd` applies them; both are the
## almanac's, both are ROM data, and both would fail ADR-0139 dec. 4(a)'s sink
## veto the moment they named a `JsonAsset`. What crosses a boundary is the three
## words — a caller learns a **value set**, not a contract (ADR-0215 dec. 2's
## test, which the tenth row established and this passes the same way).
##
## Host use: `src/audio/SfxRouter.gd` keys three death-cry slugs off it,
## `src/units/Unit.gd` and `addons/exmateria_ui/formation/FormationScene.gd` ask whether a
## unit is female, `src/debug/UnitAnimationViewerPanel.gd` sets it, and
## `src/scenes/ProgressionTester.gd` / `src/scenes/GambitScenarioBoot.gd` seed it.
## The **SIBLING NAMERS** are `addons/exmateria_almanac/progression/UnitProgression.gd`,
## which re-exports it and stores a unit's own, and
## `addons/exmateria_catalogue/identity/Character.gd` and
## `seeding/AllTemplatesSeeder.gd`, which pick one from a job plus an authored
## gender.
##
## 🔴 THE INTEGER VALUES ARE THE STORED ONES. `UnitProgression.base_stat_type` is
## an `@export`, so this enum's ordinals are written into every saved Resource and
## a re-ordering here silently re-reads every unit on disk as a different sex —
## the same reason `Facing.Direction` and `CellMarking.Kind` spell theirs out.

enum Type {
	MALE = 0,
	FEMALE = 1,
	MONSTER = 2,
}
