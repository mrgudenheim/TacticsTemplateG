class_name VfxConstants
## Shared constants and enums for the VFX subsystems (E###.BIN, TRAP, projectile).

const TICK_RATE: float = 30.0
const TICK_DURATION: float = 1.0 / TICK_RATE
const PSX_FULL_CIRCLE: int = 4096
const PSX_ANGLE_TO_RAD: float = TAU / 4096.0
const PSX_FIXED_POINT_ONE: float = 4096.0  ## PSX fixed-point 1.0 — used as acceleration scale & inertia base

const NO_CHILD_EMITTER: int = -1
const TIMELINE_EMITTER_DURATION: int = 10000  ## Long duration for timeline-driven emitters
const TICKS_PER_TILE: float = 5.0  ## Projectile flight duration per tile of distance

enum AnchorMode { WORLD = 0, CURSOR = 1, ORIGIN = 2, TARGET = 3, PARENT = 4 }

# Target anchor uses different encoding than emitter anchor (verified from PSX disassembly)
const TARGET_ANCHOR_MAP: Array[int] = [
	AnchorMode.WORLD,   # 0 (0x00)
	AnchorMode.WORLD,   # 1 (0x20) — same as 0x00
	AnchorMode.WORLD,   # 2 (0x40) — CAMERA, not yet implemented
	AnchorMode.ORIGIN,  # 3 (0x60)
	AnchorMode.TARGET,  # 4 (0x80)
	AnchorMode.PARENT,  # 5 (0xA0)
	AnchorMode.WORLD,   # 6 (0xC0) — unknown
	AnchorMode.WORLD,   # 7 (0xE0) — unknown
]
enum SpreadMode { SPHERE = 0, BOX = 1 }
enum AnimOpcode { LOOP = 0x81, SET_OFFSET = 0x82, ADD_OFFSET = 0x83 }
const MAX_FRAMESET_ID: int = 0x7F  ## frameset_id <= this is a frame; above is an opcode

## Depth bias: shifts depth sampling point toward camera by N world units.
## All use the same formula: compute depth from (position + camera_dir * bias).
##
## PSX OT: 383 buckets (0=near, 382=far). Base depth = GTE_SZ >> 2.
## Relative modes offset from base depth, fixed modes use absolute bucket positions.
## DEPTH_BIAS_SCALE converts PSX OT bucket offsets to world units (empirically tuned).
const DEPTH_BIAS_SCALE: float = 0.375        ## World units per OT bucket (tuned to match PSX sorting)
const DEPTH_BIAS_PULL_8: float = 8.0 * DEPTH_BIAS_SCALE    ## 3.0 world units (PSX: base - 8 buckets)
const DEPTH_BIAS_PULL_16: float = 16.0 * DEPTH_BIAS_SCALE  ## 6.0 world units (PSX: base - 16 buckets)
const DEPTH_BIAS_FIXED_FRONT: float = 100.0  ## Large forward shift — always near camera (PSX: bucket 8)
const DEPTH_BIAS_FIXED_BACK: float = -100.0  ## Large backward shift — always far (PSX: bucket 382)
const DEPTH_BIAS_FIXED_16: float = 80.0      ## Near front but behind FIXED_FRONT (PSX: bucket 16)
const DEPTH_BIAS_UNIT: float = 0.1           ## Unit sprite: slightly in front of its tile
const DEPTH_BIAS_SHADOW: float = 0.1         ## Shadow: slightly in front of its tile
const DEPTH_BIAS_TILE_OVERLAY: float = 0.05  ## Tile highlights: between tile and unit

enum DepthMode {
	STANDARD = 0,        ## No bias — sorts at natural depth
	PULL_FORWARD_8 = 1,  ## PSX: base - 8 OT buckets (~3 world units forward)
	FIXED_FRONT = 2,     ## Always near camera (100 world units forward)
	FIXED_BACK = 3,      ## Always far from camera (100 world units backward)
	FIXED_16 = 4,        ## Near front, behind FIXED_FRONT (80 world units forward)
	PULL_FORWARD_16 = 5, ## PSX: base - 16 OT buckets (~6 world units forward)
	UNIT = 6,            ## Small forward bias for units/shadows (0.1 world units)
	TILE_OVERLAY = 7,    ## Tile highlights — between tile surface and unit (0.05 world units)
}

enum SemiTransMode {
	HALF_BACK_HALF_FORE = 0, ## 50% back + 50% fore (blend_mix, alpha=0.5)
	BACK_PLUS_FORE = 1,      ## back + fore (blend_add)
	BACK_MINUS_FORE = 2,     ## back - fore (blend_sub)
	BACK_PLUS_QUARTER = 3,   ## back + 25% fore (blend_add, color*0.25)
}

static func resolve_anchor(mode: int, world: Vector3, cursor: Vector3,
		origin: Vector3, target: Vector3, parent: Vector3 = Vector3.ZERO) -> Vector3:
	match mode:
		AnchorMode.CURSOR: return cursor
		AnchorMode.ORIGIN: return origin
		AnchorMode.TARGET: return target
		AnchorMode.PARENT: return parent
		_: return world


enum CurveParam {
	POSITION,
	PARTICLE_SPREAD,
	VELOCITY_ANGLE,
	VELOCITY_ANGLE_SPREAD,
	INERTIA,
	WEIGHT,
	RADIAL_VELOCITY,
	ACCELERATION,
	DRAG,
	PARTICLE_LIFETIME,
	TARGET_OFFSET,
	PARTICLE_COUNT,
	SPAWN_INTERVAL,
	HOMING_STRENGTH,
	HOMING_CURVE,
	COLOR_R,
	COLOR_G,
	COLOR_B,
}
