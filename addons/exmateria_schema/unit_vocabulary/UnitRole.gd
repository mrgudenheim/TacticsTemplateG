extends RefCounted

## **Which combat archetype a unit is** — the AI targeting vocabulary, and
## nothing else.
##
## ADR-0118 dec. 1's **eleventh** schema row, admitted by
## [ADR-0280](../../../docs/adr/0280-gambits-stays-in-the-almanac-and-the-tests-that-said-otherwise-were-measuring-a-kernel-vocabulary-in-the-wrong-package.md)
## dec. 3. It is the first row whose producer is a TIER rather than a system: the
## `rules` tier decides a role (`JobDatabase.get_job_role`), `Battle` packs it
## (`src/gpu/GambitEncoder.gd`) and `UI` populates a dropdown from it
## (`addons/exmateria_ui/UIGambitEditor.gd`).
##
## 🔴 NOTHING HERE IS DERIVED, WHICH IS WHY IT COULD MOVE. This file's own
## docstring used to open *"derived from job type"*, and that describes
## `JobDatabase.get_job_role` — a different file, in a different package, which
## stays there. What is here is an `enum`, an enum→string table, a list of the
## enum's members and a two-line predicate: a caller learns a **value set**, not
## a contract. That is the tenth row's test (`Facing`, `SpriteLayer`,
## `ClockOwner`, `UnitMaterialVariant`, `UnitActivity`) and this passes it the
## same way, which is why it shares their directory without joining their row —
## their producer is `Sprite Rig`, this one's is the `rules` tier.
##
## 🔴 FFT HAS NO ROLES. They are this project's AI archetypes, the same
## provenance ADR-0251 dec. 1 records for the gambits themselves — so this is
## neither a `table` of ROM facts nor a `rule` that computes what the ROM
## computes, and ADR-0273's two words could not name it. It left the almanac for
## that reason and not for its size.
##
## A role of `ANY` (-1) matches any role in targeting checks.

## Combat role enum
## -1 = ANY (matches all roles in targeting)
enum Role {
	ANY = -1,
	MELEE = 0,     ## Close combat fighters (Knight, Monk, Lancer, Samurai, Ninja)
	RANGED = 1,    ## Distance attackers (Archer, Thief)
	MAGE = 2,      ## Offensive spellcasters (Wizard, Time Mage, Summoner)
	HEALER = 3,    ## Support/healing (Chemist, Priest)
	HYBRID = 4     ## Mixed roles (Squire, Geomancer, Oracle, etc.)
}


## Get human-readable name for a role
static func get_role_name(role: Role) -> String:
	match role:
		Role.ANY:
			return "Any"
		Role.MELEE:
			return "Melee"
		Role.RANGED:
			return "Ranged"
		Role.MAGE:
			return "Mage"
		Role.HEALER:
			return "Healer"
		Role.HYBRID:
			return "Hybrid"
	return "Unknown"


## Get all valid roles (excluding ANY)
static func get_all_roles() -> Array[Role]:
	return [Role.MELEE, Role.RANGED, Role.MAGE, Role.HEALER, Role.HYBRID]


## Check if a unit role matches a target role filter
## ANY (-1) matches all roles
static func matches(unit_role: Role, filter_role: Role) -> bool:
	if filter_role == Role.ANY:
		return true
	return unit_role == filter_role
