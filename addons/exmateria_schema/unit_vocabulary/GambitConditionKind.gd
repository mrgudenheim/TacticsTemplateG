extends RefCounted

## **What a gambit condition TESTS, how it compares, and over what range** — three value sets,
## and nothing that evaluates one.
##
## ADR-0118 dec. 1's **fifteenth** schema row, admitted by
## [gl-ADR-0377](../../../docs/adr/0377-the-almanac-stays-and-stops-being-named-by-system-addons-because-who-may-name-a-package-is-not-where-it-lives.md)
## dec. 14 on `UnitRole`'s test — *"a caller learns a **value set**, not a contract"* — the third
## gambit vocabulary to come down here after `ActionKind` and `TargetSelection`. Evaluating a
## condition against a battlefield stays in `addons/exmateria_almanac/gambits/GambitCondition.gd`,
## which re-exports all three, along with every factory (`always`, `target_hp_below`, …) and
## `from_dict`.
##
## ADR-0139 dec. 3's admission gate, measured: `Type` was named outside the almanac in FOUR files
## — `addons/exmateria_ui/UIGambitEditor.gd` (deleted since, N32) and `detail/GambitOptions.gd`, plus `src/gpu/`'s
## `GambitEncoder.gd` and `GambitCellSynth.gd` — `Comparator` in three and `RangeType` in one.
## They travel together for `TargetSelection.gd`'s cohesion reason: a `comparator` and a
## `threshold` mean nothing except under a `Type` that reads a number, and `RangeType` only
## under the two range rows.
##
## ⚠️ `RangeType` ALONE WOULD NOT HAVE BEEN ADMITTED — one namer in one sibling file is the
## measurement that keeps `abilities/AbilitySlot.gd` out of this directory (gl-ADR-0377 dec. 11).
## It is here as part of a vocabulary, not on its own account, and that distinction is the
## difference between a cohesion rule and a loophole.

enum Type {
	SELF_HP,        ## Check self HP percentage
	ALLY_HP,        ## Check if any ally meets HP condition
	ENEMY_HP,       ## Check if any enemy meets HP condition
	SELF_MP,        ## Check self MP percentage
	ENEMY_IN_RANGE, ## Check if enemy is in attack/spell range
	ALLY_IN_RANGE,  ## Check if ally is in heal range
	ENEMY_COUNT,    ## Check number of enemies
	ALLY_COUNT,     ## Check number of allies
	ALWAYS,         ## Always true (fallback)

	# New condition types for expanded gambit system
	HAS_STATUS,     ## Unit has status X
	MISSING_STATUS, ## Unit doesn't have status X
	HP_MISSING,     ## Unit missing at least N HP
	IN_RANGE_OF,    ## Unit in range of specific ability

	# Target-agnostic types (used by new UI - apply to trigger target)
	TARGET_HP,       ## Check target's HP percentage
	TARGET_MP,       ## Check target's MP percentage
	TARGET_IN_RANGE, ## Check if target is in range of actor

	# The four the kernel has always answered but nobody could ask (#1102).
	# APPENDED, never inserted: `to_dict` serialises `type` as its ORDINAL, so a
	# saved gambit list re-reads every earlier member by position.
	IS_KO,           ## Target is KO'd — down on the field, not removed from it
	IS_ALIVE,        ## Target is not KO'd
	TARGET_DISTANCE, ## Tiles between actor and target (Manhattan), vs `threshold`

	# THE ROM AI's four (research/working_documents/ROM_ENEMY_AI.md §8.1). PERIL asks about the
	# SUBJECT; the other three ask about the ACTOR — its personality and its side — whatever the
	# candidate. APPENDED, like the rest (PERIL was WANTS_RETREAT: same ordinal, Retreat policy
	# split out into its own `Policy is` rows).
	AI_POLICY,       ## The actor plays policy `threshold` (an AI_POLICY_* code): `Policy is X`
	PERIL,           ## The subject is Frog or Critical with team support (`State:Peril`)
	SUPPORT_HEAVY,   ## A medic: helpful abilities >= 77/128, not its side's least supportive
	OFF_ANCHOR,      ## The actor has a stay-near tile, is off it, and the tile is free
	# ADR-0407 dec. 5. APPENDED, like the rest.
	MY_SURFACE,      ## The actor's tile is of terrain group `threshold` (its Elemental's id)
}

enum Comparator {
	LESS_THAN,
	GREATER_THAN,
	EQUALS
}

enum RangeType {
	MELEE,  ## Adjacent (distance <= 1)
	SPELL   ## Within spell range
}
