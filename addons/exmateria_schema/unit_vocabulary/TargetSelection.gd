extends RefCounted

## **How a gambit picks who it acts on** — which pool to draw from, which team to keep, and
## which of the survivors to choose. Three value sets that describe a SELECTION, and nothing
## that performs one.
##
## ADR-0118 dec. 1's **fourteenth** schema row, admitted by
## [gl-ADR-0377](../../../docs/adr/0377-the-almanac-stays-and-stops-being-named-by-system-addons-because-who-may-name-a-package-is-not-where-it-lives.md)
## dec. 13 on `UnitRole`'s test — *"a caller learns a **value set**, not a contract"* — the same
## test ADR-0280 dec. 3 used for the first gambit vocabulary to come down here. The DECISION did
## not move: `addons/exmateria_almanac/gambits/TargetSelector.gd` still resolves a pool against a
## battlefield, still carries `self_()`, `triggering()`, `enemies()`, `friendlies()` and
## `from_dict`, and re-exports these three so no call site in the tree changed.
##
## 🔴 THREE ENUMS IN ONE FILE, WHICH IS THE COHESION RULE RATHER THAN AN EXCEPTION. `Zodiac.gd`
## beside it carries an enum, a boundary table and a lookup: a file here is one VOCABULARY, not
## one `enum`. These three are one — `team_filter` means something only under a `TEAM_FILTER`
## pool, and a resolution picks among whatever the first two leave — so splitting them would
## publish three façade rows that must always be installed together.
##
## ADR-0139 dec. 3's admission gate, measured: inside `addons/exmateria_ui`, `PoolType` is named
## on 26 lines, `ResolutionStrategy` on 12 and `TeamFilter` on 9 — four files in a sibling
## addon, nineteen of them in `GambitProse.gd` alone.
##
## ⚠️ THE ADR-0285 PARAGRAPH BELOW TRAVELLED WITH THE VALUES ON PURPOSE. It explains what
## `NEAREST_FIRST` and `NEAREST_ONLY` MEAN, which is a fact about the vocabulary; the Pass 2
## rank loop it describes stays in `src/gpu/shaders/`, and the sentence the player reads stays
## in `addons/exmateria_ui/GambitProse.gd`.

## Pool type: defines which units to consider
enum PoolType {
	SELF,           ## Only the actor
	TRIGGERING,     ## The unit that triggered the gambit (set during evaluation)
	SPECIFIC_UNITS, ## Named units from a list
	TEAM_FILTER,    ## All units matching team + optional role filter
	NAMED_UNIT,     ## ONE unit, by battle-local index — Directive-only (map #1537, #1541)
}

## Resolution strategy: how to pick one unit from multiple candidates.
##
## === DEPTH IS A RESOLUTION, AND THAT IS WHY THERE IS NO NEW FIELD (ADR-0285) ================
##
## [constant NEAREST_FIRST] and [constant NEAREST_ONLY] run the IDENTICAL search — same path
## metric, same self-skip, same KO filter. They differ in HOW MANY candidates the pool is
## willing to offer: the first hands the slot's conditions rank 0, then rank 1, then rank 2…
## until one passes; the second hands them rank 0 and stops. So the condition FILTERS a pool
## under `NEAREST_FIRST` and GATES one unit under `NEAREST_ONLY`, and the sentence the player
## reads changes from *"an ally who is hurt"* to *"the nearest ally, if they are hurt"*.
##
## 🔴 [constant NEAREST_FIRST] WAS CALLED `NEAREST`, AND THE RENAME IS THE POINT OF THE TICKET.
## It is the member that is NOT "the nearest" — it is the pool search that merely STARTS there,
## and the kernel has always walked past rank 0 for it (`stage_compute.glsl`, Pass 2's rank
## loop). The surface's `Nearest Ally` row was that value under a label describing only its
## first guess, which is the exact defect ADR-0285 removes; leaving the domain member called
## `NEAREST` would have rebuilt that defect one layer down, where no screen test can see it.
## The int positions do not move, so the rename is free and no save migrates.
enum ResolutionStrategy {
	## Closest by PATH cost — travel distance, level-aware, walls counted — as the FIRST
	## guess, not the only one. The kernel retries ranks 1, 2, 3… (`search_pool`) when
	## rank 0 fails the slot's conditions, so this names the whole team as a pool that
	## happens to be walked in proximity order. The `To` column spells it `Ally` / `Foe`.
	NEAREST_FIRST,
	MOST_CRITICAL,  ## Lowest HP percentage
	HIGHEST_STAT,   ## Highest value of specified stat
	LOWEST_STAT,    ## Lowest value of specified stat
	FIRST_IN_ROSTER, ## First in roster order
	## The nearest by the SAME metric as [constant NEAREST_FIRST], and nobody else. Pass 2's
	## retry guard does not list this pool's GPU types, so a rank-0 candidate who fails the
	## condition ends the slot for the tick. The `To` column spells it `Nearest Ally` /
	## `Nearest Foe`. APPENDED, never inserted: `to_dict`/`from_dict` serialise the int.
	NEAREST_ONLY,
	## ADR-0381 `Proximity ▸ Farthest` — the most distant unit by the same metric, and nobody
	## else: a GATE like [constant NEAREST_ONLY].
	FARTHEST_ONLY,
	## ADR-0381 `Proximity ▸ In range` — a FILTER: any unit the row's own action reaches, walked
	## nearest first like [constant NEAREST_FIRST].
	IN_RANGE,
	## ADR-0381 `Health ▸ Lowest` — the lowest CURRENT HP in raw points (not a percentage; the
	## old [constant MOST_CRITICAL] saves migrate here, dec. 10). A GATE; ties resolve nearest.
	LOWEST_HP,
	## ADR-0381 `Health ▸ Highest` — the highest current HP, raw. A GATE; ties resolve nearest.
	HIGHEST_HP,
	## ADR-0381 `Status ▸ X` — a FILTER: any unit that HAS the selector's `status_id`, nearest
	## first. `&"ko"` is KO (the one status that admits the dead, dec. 3).
	STATUS,
	## ADR-0381 `Status ▸ Afflicted` — a FILTER: any unit carrying a status the row's own ability
	## REMOVES (KO included when it revives), nearest first.
	AFFLICTED,
	## ADR-0381 `Job ▸ X` — a FILTER: any unit on the side in the selector's `job_id`, nearest
	## first. The list is the jobs present in the battle.
	JOB,
	## ADR-0381 `Name ▸ X` — ONE named unit, by DURABLE identity (the selector's `unit_ref`, a
	## catalogue slug), resolved to the battle index at encode. A pool of one: nothing to walk.
	NAME,
	## THE ROM AI's [Focus] (ROM_ENEMY_AI.md §8.1) — the actor's own focus unit, the one its policy
	## hunts or protects, either side and KO'd included; with none, the nearest viable foe. Read off
	## the actor at evaluation, so the row holds no unit. [constant TeamFilter.ANY] only.
	FOCUS,
	## THE ROM AI's [Nearest healer] — the nearest ally (not the actor) with an ability that heals
	## an ally's HP, and not one already beside it. A FILTER over [constant TeamFilter.FRIENDLY].
	NEAREST_HEALER,
	## `HP ▸ below N%` — a FILTER: any living unit on the side whose HP percent is under the
	## selector's `hp_percent`, nearest first. The ROM AI's triage lines (Critical, under half).
	HP_BELOW,
}

## Team filter for TEAM_FILTER pool type
enum TeamFilter {
	FRIENDLY,  ## Same team as actor
	ENEMY,     ## Opposite team from actor
	ANY        ## Any team
}
