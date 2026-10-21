extends RefCounted

## **What one gambit row IS, as a value** — the five fields a consumer reads off a gambit, and
## nothing that decides one.
##
## `cursor/CursorQuery.gd`'s shape (gl-ADR-0363 dec. 1).
## `addons/exmateria_almanac/gambits/Gambit.gd` `extends` this and keeps every DECISION:
## `action_from_name`'s legacy-save migration, `action_display_name`, `_to_string`, `to_dict`
## and `from_dict`. ADR-0280 dec. 1 holds — the gambit did not move, its SHAPE was named where
## reaching it is free.
##
## 🔴 `enabled` AND `parked_condition` ARE DELIBERATELY NOT HERE, and that is the rule this
## file is the worked example of: **a base type carries what CROSSES, not what exists**
## (gl-ADR-0377 dec. 22). Both are serialized by `Gambit.to_dict()` and both are read inside
## the almanac and by `src/gpu/`, but no `addons/exmateria_ui` file reads either off a gambit —
## measured with `strip_noncode`. Carrying them would put two more fields in the kernel to buy
## nothing, and the admission gate this effort enforced twice (dec. 11, dec. 14) asks what a
## caller LEARNS, not what the class holds.
##
## ⚠️ `conditions` IS `Array[GambitConditionQuery]` AND NOT `Array[GambitCondition]`, BECAUSE
## GDSCRIPT TYPED ARRAYS ARE INVARIANT. A single object field is covariant — `action_target`
## below happily holds a `TargetSelector` — but `Array[Derived]` cannot be assigned to
## `Array[Base]`, so every site that BUILDS a conditions array had to be re-typed to the base
## element. That is nine sites, named in gl-ADR-0377 dec. 22, and it is the one place this
## re-parent is not free.

const _GambitConditionQuery = preload("res://addons/exmateria_schema/gambit_query/GambitConditionQuery.gd")
const _TargetSelectorQuery = preload("res://addons/exmateria_schema/gambit_query/TargetSelectorQuery.gd")
const _ActionKind = preload("res://addons/exmateria_schema/unit_vocabulary/ActionKind.gd")

## What the row does when it fires.
var action_kind: _ActionKind.Kind = _ActionKind.Kind.WAIT

## The ability id when `action_kind` is `ABILITY`; `-1` otherwise.
var ability_id: int = -1

## Who the ACTION is aimed at.
var action_target: _TargetSelectorQuery = null

## Who the CONDITIONS are evaluated against.
var condition_target: _TargetSelectorQuery = null

## Every predicate that must hold, ANDed. Empty means unconditional.
var conditions: Array[_GambitConditionQuery] = []
