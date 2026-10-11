extends RefCounted

## **Which sign a unit was born under** — the twelve tropical signs plus FFT's
## hidden thirteenth, the month→boundary table that maps a birthday onto them,
## and the lookup that reads it. A unit-level personal attribute like brave and
## faith.
##
## ADR-0118 dec. 1's **twelfth** schema row, admitted by
## [ADR-0294](../../../docs/adr/0294-the-catalogues-progression-debt-is-a-vocabulary-and-the-kernel-is-where-a-value-set-lives.md)
## dec. 2, alongside [EquipSlot] and [BaseStatType].
##
## 🔴 `zodiac_from_birthday` COMES WITH THE ENUM BECAUSE IT IS A BANK, NOT A
## DRIVER. ADR-0273 dec. 1's two words are the test: a `table` is *"a bank. Every
## answer it returns is STORED — a ROM table, a projection of one, or a fixed
## vocabulary"*, and a `rule` *"COMPUTES what the ROM computes rather than
## stores"*. `_ZODIAC_MONTH` below is twelve stored rows of FFT's own boundaries
## and the function INDEXES them with a wrap; delete the function and the whole
## answer is still sitting there, which is the discriminator
## `ShopAvailabilityDatabase` was ruled on. It is the same shape ADR-0280 dec. 3
## admitted for `UnitRole` — an enum, a table over it, and a short accessor — and
## it touches no database, so ADR-0139 dec. 4(a)'s sink veto passes with an
## outbound edge count of **0**.
##
## 🔴 THE NAME KEEPS ITS `zodiac_` PREFIX INSIDE A FILE CALLED `Zodiac`, AND THE
## STUTTER IS DELIBERATE. `UnitRole.get_role_name` / `get_all_roles` crossed the
## same boundary spelled the same way. A respelling is never the reason for a move
## (ADR-0196), and keeping it makes every call site and every test a byte-for-byte
## match on the symbol.
##
## Host use: the sign is consumed as a plain `int` — `addons/exmateria_ui/UIUnitNameplate.gd`
## picks the CLUT cell for the info panel's zodiac glyph. The **SIBLING NAMERS**
## are `addons/exmateria_almanac/progression/UnitProgression.gd`, which re-exports
## [Sign] and stores a unit's own, and the catalogue's
## `identity/Character.gd` and `identity/UnitBirthdays.gd`, which derive one at the
## materialization seam.
##
## 🔴 THE INTEGER VALUES ARE THE STORED ONES, for [BaseStatType]'s reason:
## `UnitProgression.zodiac` is an `@export var … : int` holding one of these.

## The tropical zodiac. SERPENTARIUS (12) is FFT's hidden thirteenth sign and is
## never date-derived — it is assigned only by special cases.
enum Sign {
	ARIES = 0,
	TAURUS = 1,
	GEMINI = 2,
	CANCER = 3,
	LEO = 4,
	VIRGO = 5,
	LIBRA = 6,
	SCORPIO = 7,
	SAGITTARIUS = 8,
	CAPRICORN = 9,
	AQUARIUS = 10,
	PISCES = 11,
	SERPENTARIUS = 12,
}

# The tropical-zodiac boundary each calendar month straddles, indexed by month−1
# (Jan..Dec). Entry `[start_day, sign]` = the day the NEW sign begins that month
# and which sign it is (this enum's order); a birthday BEFORE `start_day` belongs
# to the previous month's sign. The calendar wraps (a sign spans two months), so a
# straight day scan can't be monotonic in month number — this per-month table is.
# FFT's standard boundaries, validated against the ROM's own uniques: Ramza
# (12/30 → Capricorn, the info-panel oracle), Agrias (6/22 → Cancer), Delita
# (3/18 → Pisces), Algus (5/11 → Taurus).
const _ZODIAC_MONTH := [
	[20, Sign.AQUARIUS],     # Jan — before the 20th is Capricorn (Dec's sign)
	[19, Sign.PISCES],       # Feb — before the 19th is Aquarius
	[21, Sign.ARIES],        # Mar — before the 21st is Pisces
	[20, Sign.TAURUS],       # Apr
	[21, Sign.GEMINI],       # May
	[22, Sign.CANCER],       # Jun
	[23, Sign.LEO],          # Jul
	[23, Sign.VIRGO],        # Aug
	[23, Sign.LIBRA],        # Sep
	[23, Sign.SCORPIO],      # Oct
	[23, Sign.SAGITTARIUS],  # Nov
	[22, Sign.CAPRICORN],    # Dec — before the 22nd is Sagittarius (Nov's sign)
]


## Derive the tropical zodiac sign (this enum, 0..11) from an ENTD birthday.
## `month` is 1..12; the ENTD sentinels (0 = unset, 254 = Random, 255 = None) and
## any out-of-range value have no fixed sign, so they return -1 (the caller keeps
## the unit's existing/default zodiac). Pure — FFT's own birthday→sign boundaries.
static func zodiac_from_birthday(month: int, day: int) -> int:
	if month < 1 or month > 12 or day < 1 or day > 31:
		return -1
	var start_day: int = _ZODIAC_MONTH[month - 1][0]
	if day >= start_day:
		return _ZODIAC_MONTH[month - 1][1]
	# Before this month's cutoff → the previous month's sign (Jan wraps to Dec).
	return _ZODIAC_MONTH[(month + 10) % 12][1]
