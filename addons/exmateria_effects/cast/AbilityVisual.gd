extends RefCounted
## What this addon needs to know about an ability in order to pick its VISUALS —
## and nothing else. A host's answer to `CastHost.ability_visual()`.
##
## This is the addon's whole ability vocabulary. It names no database, no record
## dictionary and no ROM table: four fields and one predicate, all of them about
## what the cast should LOOK like. A host whose ability data is a generated ROM
## table fills one in; so does a host whose ability data is three hand-written
## rows in a test.
##
## 🔴 ADR-0364. `cast/EffectManager.gd` used to read `ExMateriaAlmanac.AbilityDatabase`
## directly, which put a 20,830-line generated ROM table in this addon's `deps=`
## in exchange for FIVE fields — and put two GITIGNORED generated `.gd` files in
## the closure any installer has to fetch. The reach is now a host capability at
## the seam that already carries `actors()` and `arena_bounds()`.

const _Self = preload("res://addons/exmateria_effects/cast/AbilityVisual.gd")

## FFT element NAME → the element id every TRAP/particle handler in this addon
## takes. Published because a host whose ability data spells elements the ROM's
## way needs this exact table to answer `ability_visual()`; a host with its own
## element enum maps straight to the id and never reads it.
const ELEMENT_NAME_TO_ID: Dictionary = {
	"Fire": 1, "Lightning": 2, "Ice": 3, "Wind": 4, "Earth": 5,
	"Water": 6, "Holy": 7, "Dark": 8,
}

## Formulas that play a "break" visual (TRAP handler 21) instead of hit clouds.
## 🔴 ADR-0364 dec. 1 — "which formulas use the break visual" is a VISUAL fact,
## so it is this addon's to own. It was `AbilityDatabase.is_break_visual_formula`,
## four ints inside the ability database, and reading it was one of the two call
## sites that made the almanac a dependency. Read it through
## `plays_break_visual()`; callers route on the predicate, not on the number.
const BREAK_VISUAL_FORMULAS: Array[int] = [37, 43, 44, 46]

## Diagnostics only — the `[TRAP_ROUTE]` line under `EffectsDebug.particle()`.
## Nothing routes on it, so a host with no display name may leave it empty.
var display_name: String = ""

## The FFT damage formula id. Routing reads it through `plays_break_visual()`;
## it is carried verbatim so the debug line can print what it decided from.
var formula: int = 0

## 0 = no element. See `ELEMENT_NAME_TO_ID`.
var element_id: int = 0

## Which charging pose this ability casts from — 1 is spell charge lines,
## 2 is the orbital summon orbs, everything else is standard charge particles.
var charging_pose_id: int = 0

var _present: bool = false


## The host HAS this ability and these are its visuals.
static func of(display_name: String, formula: int, element_id: int,
		charging_pose_id: int) -> _Self:
	var v := _Self.new()
	v.display_name = display_name
	v.formula = formula
	v.element_id = element_id
	v.charging_pose_id = charging_pose_id
	v._present = true
	return v


## The host has NO such ability — an unknown id, or a host that answers no
## ability questions at all. Charge VFX declines to spawn; a trap cast falls to
## the generic hit clouds. Both are exactly what an id absent from the ability
## database did before this seam existed.
static func absent() -> _Self:
	return _Self.new()


func is_empty() -> bool:
	return not _present


## True when this ability plays the break visual instead of a damage number.
func plays_break_visual() -> bool:
	return formula in BREAK_VISUAL_FORMULAS


## Convenience for a host whose ability record carries FFT element NAMES (the
## ROM's spelling) as a list: the first named element wins, an empty list is 0.
## A host with a single element enum does not need this.
static func element_id_from_names(names: Array) -> int:
	if names.is_empty():
		return 0
	return int(ELEMENT_NAME_TO_ID.get(str(names[0]), 0))
