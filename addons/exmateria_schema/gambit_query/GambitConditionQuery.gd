extends RefCounted

## **What a gambit condition tests, as a value** — the seven fields a consumer reads off a
## condition, and nothing that evaluates one.
##
## `cursor/CursorQuery.gd`'s shape (gl-ADR-0363 dec. 1).
## `addons/exmateria_almanac/gambits/GambitCondition.gd` `extends` this and keeps every
## factory (`always`, `target_hp_below`, …), `to_dict`/`from_dict` and the evaluation itself.
##
## 🔴 ALL SEVEN FIELDS ARE VALUE-TYPED AND THREE ARE KERNEL ENUMS ALREADY — `type`,
## `comparator` and `range_type` came down at gl-ADR-0377 dec. 14. The other four are a
## `float`, two `StringName`s and an `int`. No new vocabulary is introduced here.

const _GambitConditionKind = preload("res://addons/exmateria_schema/unit_vocabulary/GambitConditionKind.gd")

## What the condition tests.
var type: _GambitConditionKind.Type

## How it compares, for the rows that read a number.
var comparator: _GambitConditionKind.Comparator

## The number compared against — a percentage or a count.
var threshold: float

## Which range, for the two range rows.
var range_type: _GambitConditionKind.RangeType

## The status the row names, for the status rows.
var status_id: StringName = &""

## The ability the row names, for `IN_RANGE_OF`.
var ability_name: StringName = &""

## An absolute HP amount, for `HP_MISSING`.
var hp_amount: int = 0
