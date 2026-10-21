extends RefCounted

## **What a gambit aims at, as a value** — the five fields a consumer reads off a target
## selector, and nothing that resolves one.
##
## ADR-0332's third route, taken for the same reason `cursor/CursorQuery.gd` was
## (gl-ADR-0363 dec. 1): a symbol whose consumed surface is already value-typed does not need
## to MOVE, it needs its SIGNATURES named where reaching them is free.
## `addons/exmateria_almanac/gambits/TargetSelector.gd` `extends` this and keeps every verb —
## `self_()`, `triggering()`, `enemies()`, `friendlies()`, `from_dict()`, `to_dict()` and the
## battlefield resolution — so the DECISION stays in the `rules` tier and only the SHAPE is here.
##
## 🔴 EVERY FIELD IS VALUE-TYPED, AND FOUR OF THE FIVE ARE KERNEL ENUMS ALREADY. `pool_type`,
## `team_filter` and `resolution` came down at gl-ADR-0377 dec. 13 and `role_filter` at
## ADR-0280 dec. 3; `unit_names` is `Array[String]`. So this type introduces no new vocabulary —
## it names shapes the kernel already owns, which is what makes it a query surface rather than
## a second model.
##
## ⚠️ `stat_name` AND `include_ko` ARE DELIBERATELY NOT HERE. They are serialized by
## `TargetSelector.to_dict()` and read by the kernel encoder, but NO consumer outside the
## almanac reads them off a selector — measured with `strip_noncode` across `addons/` and
## `src/`. A base type carries what CROSSES, not what exists (gl-ADR-0377 dec. 22).

const _TargetSelection = preload("res://addons/exmateria_schema/unit_vocabulary/TargetSelection.gd")
const _UnitRole = preload("res://addons/exmateria_schema/unit_vocabulary/UnitRole.gd")

## Which set of units to draw from.
var pool_type: _TargetSelection.PoolType = _TargetSelection.PoolType.SELF

## Which side to keep. Only meaningful under `TEAM_FILTER`.
var team_filter: _TargetSelection.TeamFilter = _TargetSelection.TeamFilter.FRIENDLY

## Which archetype to keep, or `ANY`.
var role_filter: _UnitRole.Role = _UnitRole.Role.ANY

## Named units, under `SPECIFIC_UNITS`.
var unit_names: Array[String] = []

## Which of the drawn units to act on.
var resolution: _TargetSelection.ResolutionStrategy = _TargetSelection.ResolutionStrategy.NEAREST_FIRST
