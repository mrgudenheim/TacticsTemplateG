extends RefCounted
## PSX numeric conventions of the FFT event-script interpreter, in one place.
##
## The event-script opcodes ScenarioVM re-implements encode their operands with a
## handful of fixed PSX conventions: two's-complement byte/half-word operands, a
## u16 stored low-byte-then-high-byte, and a 12-bit clockwise facing wheel. Those
## conventions were re-derived inline in every handler that touched them (a
## `(facing << 10) & 0xFFF` here, a `(lo | hi << 8)` there) — the same drift risk
## the project retired for bit-packed flag fields (ADR-0013). This module is their
## single home: each convention is a named, pure, static function, defined once and
## tested once (PsxNumTest), so the opcode handlers read as intent — "warp facing to
## a cardinal", "pack the split unit id" — instead of transcribed bit math.
##
## Pure and stateless: no nodes, no `map_size_z`, no calibration. Depth-flip
## (ADR-0052) takes `size_z` as an argument rather than reading VM state, so it too
## is a pure two-argument function; ScenarioVM keeps the state + warning around it.

# ---------------------------------------------------------------------------
# Sign extension — PSX operands are two's-complement
# ---------------------------------------------------------------------------

## Sign-extend the low 8 bits of `b` (a PSX signed byte, e.g. Map Darkness R/G/B).
static func s8(b: int) -> int:
	b &= 0xFF
	return b - 0x100 if b >= 0x80 else b


## Sign-extend the low 16 bits of `v` (a PSX signed half-word, e.g. Display Message
## X/Y screen offsets, Sprite Move deltas).
static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


# ---------------------------------------------------------------------------
# Byte packing — the disassembler splits a u16 into low/high param fields
# ---------------------------------------------------------------------------

## Reassemble a little-endian u16 from its low and high bytes. The event
## disassembler (`tools/disasm_event.py`) splits chunk_unit_id across the `Units`
## (low) and `Multi` (high) params per event_instructions.json; the real bytecode stores
## one u16 LE. Reading only the low byte silently drops the high byte for the
## scenario-1 rows where `Multi != 0`.
static func u16_lohi(lo: int, hi: int) -> int:
	return (lo & 0xFF) | ((hi & 0xFF) << 8)


# ---------------------------------------------------------------------------
# The 12-bit facing wheel — 0x1000 = one full clockwise turn
# ---------------------------------------------------------------------------
#
# FFT stores unit facing as a 12-bit clockwise angle: 0x000 = EAST, 0x400 = SOUTH,
# 0x800 = WEST, 0xC00 = NORTH (quantizer FUN_8008c1e4). Different opcodes address it
# through different-width operand fields, so each gets a named lift here.

const TURN_12BIT := 0x1000  ## one full turn on the wheel
const EAST_12BIT := 0x000
const SOUTH_12BIT := 0x400
const WEST_12BIT := 0x800
const NORTH_12BIT := 0xC00


## Wrap an angle into [0, 0x1000).
static func wrap12(a: int) -> int:
	return a & 0xFFF


## Quantize an angle down to the nearest cardinal (mask 0xC00 — 2 bits).
static func cardinal12(a: int) -> int:
	return a & 0xC00


## Quantize an angle to the wheel's 16-step grid (mask 0xF00 — the rotate ops write
## facing on this grid).
static func octant12(a: int) -> int:
	return a & 0xF00


## Warp Unit (0x24) `Facing` field (2 bits, 0..3) → 12-bit angle. The ROM spawn-init
## writer (0x80087c1c, `sll;sra` = `<< 10`) sets the raw world angle directly from
## this field: 0->EAST, 1->SOUTH, 2->WEST, 3->NORTH.
static func warp_facing_to_12bit(field: int) -> int:
	return wrap12((field & 0x3) << 10)


## Forward world-heading (dx, dz) → 12-bit ORIENTATION angle. A Walk To knows its real
## travel heading, so it sets the orientation source of truth (`Unit.facing_angle`) straight
## from the heading — the ADR-0057-faithful forward arrow. Do NOT derive the angle from the
## `FacingDirection` enum (`_CARDINAL_TO_12BIT[heading_facing_dir(...)]`); that routes
## orientation through a render/derived view, the backward arrow ADR-0057 forbids.
##
## Godot world axes (CLAUDE.md): +X = NORTH, −X = SOUTH, +Z = EAST, −Z = WEST. Mapped onto
## the canonical wheel this is +X→0xC00(N), −X→0x400(S), +Z→0x000(E), −Z→0x800(W). A unit
## in |dx| vs |dz| (`|dx| >= |dz|` → X axis) matches `ScenarioDecode.heading_facing_dir`'s
## dominant-axis tie-break, so the 12-bit angle and the derived enum always agree.
static func heading_to_12bit(dx: float, dz: float) -> int:
	if absf(dx) >= absf(dz):
		return NORTH_12BIT if dx >= 0.0 else SOUTH_12BIT
	return EAST_12BIT if dz >= 0.0 else WEST_12BIT


## Unit Anim Rotate (0x47) `Direction` byte → 12-bit angle: `(dir << 8) & 0xF00`,
## i.e. the low nibble selects one of the 16 wheel steps.
static func direction_to_12bit(direction: int) -> int:
	return octant12(direction << 8)


## Rotate Unit (0x2D) absolute `Facing` byte → 12-bit angle: `(byte * 0x100) & 0xFFF`.
## This is the wheel-step form used by the absolute mode of the facing-byte dispatch
## (hacktics disasm 0x80148284); the camera-relative / relative / face-target modes
## are resolved by the caller.
static func facing_byte_to_12bit(byte: int) -> int:
	return wrap12((byte & 0xFF) * 0x100)


## Look-at: 12-bit facing from a PSX-space (Δx, Δy) where Δ = affected − faced.
## Reproduces evt0x53_face_unit's `(0x1400 − ratan2_12bit(Δx,Δy)) & 0xF00`, with the
## 12-bit clockwise arctangent (SUB_8001d8e8) 0 along +Δy and 0x400 along +Δx.
## Validated against the §8 controlled-call octant table — see ScenarioFaceUnitTest.
static func look_at_12bit(dx: int, dy: int) -> int:
	var atan12 := int(round(atan2(float(dx), float(dy)) / TAU * 4096.0)) & 0xFFF
	return octant12(0x1400 - atan12)


# ---------------------------------------------------------------------------
# Board geometry
# ---------------------------------------------------------------------------

const UNITS_PER_TILE := 28  ## PSX world units spanned by one map tile (Sprite Move scale)

## PSX world units spanned by ONE FFT ELEVATION HALF-STEP. Board geometry like
## `UNITS_PER_TILE`, and it arrives here for the same reason ADR-0091 gave for the 28:
## one fact, one home. It had THREE homes — `MapConstants.PSX_UNITS_PER_HALF_STEP`
## (float 12.0) and `RomWalkStepper.LEVEL_RENDER` (int 12), both `Battlefield`, plus this.
## ⚠️ Only the first is re-pointed here. Whether `LEVEL_RENDER` is the SAME fact or a
## render-unit coincidence is a `Battlefield` reading nobody has taken, and folding it on
## the strength of both being 12 is the guess this comment exists to refuse.
const UNITS_PER_HALF_STEP := 12.0


## Mirror a depth row about the map's far-Z edge (ADR-0052 chirality flip):
## `godot_z = size_z - 1 - psx_z`. Every placement opcode's Event-Y row passes
## through here to land on the flipped Godot map. Pure two-argument form; ScenarioVM
## owns the `size_z` source and the "unset" warning.
##
## This is THE scenario depth-flip chokepoint (ADR-0057, transitional Placement):
## the integer-row form for tile placement, and `flip_depth_continuous` its
## closed-form sibling for continuous coordinates — no scenario runtime flip is
## computed inline elsewhere.
static func flip_depth_row(z: int, size_z: int) -> int:
	return size_z - 1 - z


## Continuous sibling of `flip_depth_row` for a real-valued depth (the camera
## body's `opcode_Y/112`, not an integer tile row): `godot_z = size_z - psx_z`.
## Same ADR-0052 mirror, one map-Z later than the integer form: a unit row `r`
## sits at continuous `psx_z = r + 0.5` (tile centre) and flips to
## `(size_z-1-r) + 0.5 = size_z - psx_z`, so the +0.5 tile-centring absorbs the
## `-1`. Using `flip_depth_row` here would mis-flip a body sitting at the flip
## centre by one tile — this is the correct continuous chokepoint (ADR-0057).
static func flip_depth_continuous(z: float, size_z: int) -> float:
	return float(size_z) - z


# ---------------------------------------------------------------------------
# Sequencer ramp math — the sound opcodes latch fades in sequencer ticks
# ---------------------------------------------------------------------------

## {22} Switch Track volume curve (ROM FUN_8012db90): the operand Volume maps to a
## 0..127 sequencer volume as 0→0, ≥96→127, else `Volume·127/96` (integer division).
## The decompiler is authoritative over the wiki's naive-linear description.
static func track_volume_curve(volume: int) -> int:
	if volume <= 0:
		return 0
	if volume >= 96:
		return 127
	return (volume * 127) / 96


## {60} Fade Sound ramp length in sequencer ticks. The handler latches
## `Time << (16 + Shift)`; the flush extracts the ramp count as
## `(word >> 14) & 0x3FFC` = `(Time << (Shift + 2)) & 0x3FFC` (= Time·4 for Shift 0).
static func fade_ramp_ticks(time: int, shift: int) -> int:
	return (time << (shift + 2)) & 0x3FFC
