class_name VfxConstants
## Shared constants and enums for the VFX subsystems (E###.BIN, TRAP, projectile).

const TICK_RATE: float = 30.0
const TICK_DURATION: float = 1.0 / TICK_RATE
const PSX_FULL_CIRCLE: int = 4096
const PSX_ANGLE_TO_RAD: float = TAU / 4096.0
const PSX_FIXED_POINT_ONE: float = 4096.0  ## PSX fixed-point 1.0 — used as acceleration scale & inertia base

const NO_CHILD_EMITTER: int = -1
const TIMELINE_EMITTER_DURATION: int = 10000  ## Long duration for timeline-driven emitters
const CHANNEL_SORT_SPACING: float = 1000.0  ## Sort key spacing between channels
const TICKS_PER_TILE: float = 5.0  ## Projectile flight duration per tile of distance

enum AnchorMode { WORLD = 0, CURSOR = 1, ORIGIN = 2, TARGET = 3, PARENT = 4 }
enum SpreadMode { SPHERE = 0, BOX = 1 }
enum AnimOpcode { LOOP = 0x81, SET_OFFSET = 0x82, ADD_OFFSET = 0x83 }

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
