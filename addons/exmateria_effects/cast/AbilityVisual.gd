extends RefCounted
## What this addon needs to know about an ability in order to pick its VISUALS —
## and nothing else: what the cast should LOOK like, and the order its visual
## parts play in (the ability SEQUENCE fields, ITEM_USE_EXECUTION.md §8.2). A host's answer to `CastHost.ability_visual()`; it names
## no database, no record dictionary and no ROM table (ADR-0364).

const _Self = preload("res://addons/exmateria_effects/cast/AbilityVisual.gd")

## FFT element NAME → the element id the TRAP/particle handlers take. A host
## that spells elements the ROM's way needs this table to answer
## `ability_visual()`.
const ELEMENT_NAME_TO_ID: Dictionary = {
	"Fire": 1, "Lightning": 2, "Ice": 3, "Wind": 4, "Earth": 5,
	"Water": 6, "Holy": 7, "Dark": 8,
}

## Formulas that play the "break" visual (TRAP handler 21) instead of hit
## clouds — a VISUAL fact, so this addon owns it (ADR-0364 dec. 1). Route on
## `plays_break_visual()`, not on the number.
const BREAK_VISUAL_FORMULAS: Array[int] = [37, 43, 44, 46]

## Diagnostics only — the `[TRAP_ROUTE]` line under `EffectsDebug.particle()`;
## nothing routes on it.
var display_name: String = ""

## FFT damage formula id; routing goes through `plays_break_visual()`, the raw
## value is kept for the `[TRAP_ROUTE]` debug line.
var formula: int = 0

## 0 = no element. See `ELEMENT_NAME_TO_ID`.
var element_id: int = 0

## The ability's element BYTE (`range_data.element`: Fire 0x80 ... Dark 0x01), every bit it
## sets. The charge lines tint by its first set bit in the ROM's order
## (`TrapLift.TrapChargeLineColours.index_for_element_byte`), which `element_id` cannot
## answer. 0 = none, or a host that skipped `with_element_byte`.
var element_byte: int = 0

## Which charging pose this ability casts from — 1 is spell charge lines,
## 2 is the orbital summon orbs, everything else is standard charge particles.
var charging_pose_id: int = 0

## --- The ability SEQUENCE (ITEM_USE_EXECUTION.md §8.2) — set by `with_sequence`. ---

## The E###.BIN that plays "the part after release": the effect word & 0x1FF.
## -1 = the ability plays no effect file (an engine-only projectile or swing).
var effect_index: int = -1

## The effect word's 0x800 bit: the effect is loaded and HELD, and released when
## the projectile lands (handler 20) instead of when the action starts — unless the
## item is handed over, which has no projectile (§6).
var deferred: bool = false

## The execution anim id (`DAT_80093E11[ability*3]`). 1 = the Chemist selector:
## hand over (0x39) when the target is self or an orthogonal neighbour, else throw
## (0x4C). Any other value is the anim itself. -1 = unknown.
var anim_id: int = -1

## The projectile anim_type SEQ opcode 0xD9 launches: 0x10 = the item/throw icon
## (handler 20), 6 = Throw Stone. -1 = none fixed by the ability.
var projectile_type: int = -1

## --- The weapon strike (WEAPON_STRIKE_AND_CLASS_E.md §2) — set by `with_strike`. ---

## The ability id the ROM executes (a class-E family is an id range: Jump, Charge+N,
## Accumulate, the reactions). -1 = the host did not say, and `AbilitySequence.plan`
## knows no family.
var ability_id: int = -1

## flags1 & 0x04 (`weapon_strike`) and flags1 & 0x20 (`weapon_range`): either keeps the
## caster's equipped weapon as the action weapon (0x8018B34C) — the weapon an anim-0
## ability swings. Neither = bare hands, except for Attack and Charge.
var weapon_strike: bool = false
var weapon_range: bool = false

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


## Attach the ability SEQUENCE fields (§8.2) to a visual built by `of`. Returns
## self so a host can chain it; a host that knows no sequence data skips it and
## gets the defaults (no effect file, not deferred, no projectile).
func with_sequence(p_effect_index: int, p_deferred: bool, p_anim_id: int,
		p_projectile_type: int) -> _Self:
	effect_index = p_effect_index
	deferred = p_deferred
	anim_id = p_anim_id
	projectile_type = p_projectile_type
	return self


## Attach the weapon-strike fields (§2) to a visual built by `of`. Returns self; a host
## that skips it gets no family and a bare-hands swing rule.
func with_strike(p_ability_id: int, p_weapon_strike: bool, p_weapon_range: bool) -> _Self:
	ability_id = p_ability_id
	weapon_strike = p_weapon_strike
	weapon_range = p_weapon_range
	return self


## Attach the element byte to a visual built by `of`. Returns self.
func with_element_byte(p_element_byte: int) -> _Self:
	element_byte = p_element_byte
	return self


## The host has NO such ability (an unknown id, or a host that answers no
## ability questions at all). Charge VFX declines to spawn; a trap cast falls
## to the generic hit clouds.
static func absent() -> _Self:
	return _Self.new()


func is_empty() -> bool:
	return not _present


## True when this ability plays the break visual instead of a damage number.
func plays_break_visual() -> bool:
	return formula in BREAK_VISUAL_FORMULAS


## FFT element NAMES (the ROM's spelling) as a list: the first named element
## wins, an empty list is 0.
static func element_id_from_names(names: Array) -> int:
	if names.is_empty():
		return 0
	return int(ELEMENT_NAME_TO_ID.get(str(names[0]), 0))
