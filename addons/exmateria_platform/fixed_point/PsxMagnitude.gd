extends RefCounted
## The ONE home for PSX continuous-magnitude ↔ game-unit conversions (ADR-0091).
##
## Published as `ExMateriaPlatform.PsxMagnitude`. It declares no `class_name` of its
## own: this addon puts exactly ONE name in a consumer's project (ADR-0212 dec. 1),
## and a consumer aliases it back to a bare local spelling (ADR-0211 dec. 4):
##
##     const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
##
## It was `class_name PsxMagnitude` under `src/effects/` until extraction #7
## (gl-ADR-0295 dec. 3, #1220), and both halves of that changed for the same reason:
## nothing in this file reaches `Effects`, so it was never the effects runtime's to
## hold — while *Units* meaning measurement collides with `Unit` the combatant, and
## **Magnitude** is ADR-0091's own filename word and this file's own first sentence.
## `Magnitude` appeared as an identifier in three lines tree-wide and as a global in
## none. The pair now reads `ExMateriaPlatform.PsxNum` /
## `ExMateriaPlatform.PsxMagnitude` — same prefix, same shape, one noun each.
##
## FFT stores spatial quantities in PSX fixed-point conventions: 4096 = one full
## turn, 28 world units per map tile, and the radial-velocity / acceleration
## divisors that fall out of the 20.12 fixed-point integrator. The game speaks
## radians and ~1-unit-per-tile Godot space, so those magnitudes convert at the
## boundary — but the conversion is **proven, not invented**: this module ports
## the byte-validated mapping already in `tools/parse_effect.py`
## (`convert_position`/`velocity`/`accel`/`angle`) and the `EmitterChannel` cache
## derivation, verbatim. Nothing new is computed; the numbers stop being
## copy-pasted across five-plus files.
##
## Both directions live here: raw→game for reads/rendering, game→raw for the
## studio round-trip and byte-exact writes. Pure and stateless — no nodes, no
## calibration (the *calibrated* camera mappings live in `CameraCalibration`, one layer
## up, to keep this module's charter as clean as `PsxNum`'s). This is the
## MAGNITUDE axis; sign/chirality (the Y-flip, ADR-0052/0057) is a separate axis
## applied by the caller.
##
## Charter split (ADR-0091 §2): `PsxNum` owns the *discrete* opcode encodings (the
## 12-bit facing wheel, byte packing); `PsxMagnitude` owns the *continuous* magnitude↔
## game conversions. The universal bases (`4096` full turn, `28` units/tile) live
## once — declared in `PsxNum` and referenced here — never re-declared.
## Vault: [[Isometric Coordinate System]]

# ---------------------------------------------------------------------------
# Universal bases — shared with PsxNum so 4096 and 28 live in exactly one place.
# ---------------------------------------------------------------------------

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4). This file is a SIBLING inside the
## same addon since #1220, and the alias is still how it names one: `preload`ing the
## path directly would give the addon a second way to spell its own members.
const PsxNum = ExMateriaPlatform.PsxNum

## One full turn in PSX angle units (4096 = 360°). Identical to PsxNum.TURN_12BIT
## (0x1000) — the facing wheel and the continuous angle scale are the same base.
const FULL_TURN := PsxNum.TURN_12BIT

## FFT world units spanned by one map tile. Shared with PsxNum.UNITS_PER_TILE.
const UNITS_PER_TILE := PsxNum.UNITS_PER_TILE

# ---------------------------------------------------------------------------
# Effects-specific divisors — derived once here (parse_effect.py comments).
# ---------------------------------------------------------------------------

## Radial velocity: `radial * 8 / 4096 / 28 = radial / 14336` Godot units/frame
## (parse_effect.py VELOCITY_DIVISOR).
const RADIAL_VELOCITY_DIVISOR := 14336.0

## Acceleration / drag / gravity / homing strength: `accel / 4096 / 28 = accel /
## 114688` (parse_effect.py ACCEL_DIVISOR = FIXED_POINT_SCALE * UNITS_PER_TILE).
const ACCEL_DIVISOR := float(FULL_TURN) * float(UNITS_PER_TILE)

# ---------------------------------------------------------------------------
# Angle — 4096 = 360° = TAU rad.
# ---------------------------------------------------------------------------

## Raw PSX angle (0..4096 = 0..360°) → radians.
static func angle_to_rad(raw) -> float:
	return float(raw) * TAU / float(FULL_TURN)


## Radians → raw PSX angle (game→raw write side).
static func rad_to_angle(rad: float) -> float:
	return rad * float(FULL_TURN) / TAU


## Raw PSX angle → degrees.
static func angle_to_deg(raw) -> float:
	return float(raw) * 360.0 / float(FULL_TURN)


## Degrees → raw PSX angle (game→raw write side).
static func deg_to_angle(deg: float) -> float:
	return deg * float(FULL_TURN) / 360.0


# ---------------------------------------------------------------------------
# Tiles / positions — 28 FFT world units per Godot tile.
# ---------------------------------------------------------------------------

## Raw FFT world-unit magnitude → Godot units (one tile per 28). The caller
## applies any Y-flip (chirality, a separate axis).
static func tile_to_game(raw) -> float:
	return float(raw) / float(UNITS_PER_TILE)


## Godot units → raw FFT world-unit magnitude (game→raw write side).
static func game_to_tile(v: float) -> float:
	return v * float(UNITS_PER_TILE)


# ---------------------------------------------------------------------------
# Radial velocity — / 14336.
# ---------------------------------------------------------------------------

## Raw radial velocity → Godot units/frame.
static func radial_velocity_to_game(raw) -> float:
	return float(raw) / RADIAL_VELOCITY_DIVISOR


## Godot units/frame → raw radial velocity (game→raw write side).
static func game_to_radial_velocity(v: float) -> float:
	return v * RADIAL_VELOCITY_DIVISOR


# ---------------------------------------------------------------------------
# Acceleration / drag / homing — / 114688.
# ---------------------------------------------------------------------------

## Raw acceleration/drag/gravity/homing magnitude → Godot units/frame². The caller
## applies any Y-flip (chirality).
static func accel_to_game(raw) -> float:
	return float(raw) / ACCEL_DIVISOR


## Godot units/frame² → raw acceleration magnitude (game→raw write side).
static func game_to_accel(v: float) -> float:
	return v * ACCEL_DIVISOR
