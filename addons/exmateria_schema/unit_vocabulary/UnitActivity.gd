extends RefCounted

## **What a unit is currently doing** — both halves of the activity
## taxonomy, published as one kernel member.
##
## THIS FILE IS GENERATED -- DO NOT EDIT.
## Source of truth: `tools/activity_taxonomy.yaml`
## Regenerate: `(cd tools && uv run python gen_activity_taxonomy.py)`
##
## Part of ADR-0118 dec. 1's **tenth** schema row — the unit-sprite
## vocabulary — admitted by ADR-0215 dec. 2 and named by ADR-0217 dec. 7;
## dec. 8 is why it is one member and not two. `Display` is what the
## ANIMATION layer should play and `Logical` is what the ENGINE thinks the
## unit is doing; they are generated from the same rows and exist only to
## be translated into each other, so a value vocabulary two systems must
## agree on is the kernel's.
##
## 🔴 `UnitActivity` HAS BEEN THIS TAXONOMY'S NAME BEFORE. The YAML's own
## vocabulary note records the CPU-side enum that `DisplayActivity`
## replaced as `UnitActivity`. The name is reused here on purpose
## (ADR-0217 dec. 7's subject-noun form), and no live symbol carried it
## when this landed, so nothing collides — but a reader meeting the word
## in ADR-0025 or ADR-0026 is meeting the retired one.

## What the animation layer should play. 🔴 REFERENCE MEMBERS BY NAME.
## The integers are declaration order — first occurrence in the YAML rows —
## and are NOT a contract; `addons/exmateria_sprite_rig/state/DisplayActivity.gd` is emitted
## from the same list, so the two agree by construction rather than by
## anyone keeping them in step.
enum Display {
	IDLE,
	WALKING,
	USING_ITEM,
	ATTACKING,
	SPELL_CASTING,
	SPELL_CHARGING,
	DYING,
	CELEBRATING,
	AWAITING_IMPACT,
	IDLE_LOW_HEALTH,
	DEAD,
	JUMPING,
	LANDING,
	GETTING_UP,
}

## What the engine thinks the unit is doing. 🔴 THE INTEGERS ARE WRITTEN
## OUT AND THEY ARE A CONTRACT: the GPU compute shader writes these values
## into `U_STATE`, and `src/gpu/shaders/combat_common.glslinc` +
## `src/gpu/GPUConstants.gd` carry the same numbers from the same rows.
## Renumbering here without a buffer-version bump is a silent
## wrong-activity bug with nothing red in between.
enum Logical {
	IDLE = 0,
	WALKING = 1,
	ACTING = 2,
	PREEMPTIVE_COUNTER = 3,
	SPELL_CHARGING = 4,
	WALKING_TO_CAST = 5,
	DYING = 6,
	CELEBRATING = 7,
	APPROACHING = 8,
	AWAITING_IMPACT = 9,
	RETREATING = 10,
}
