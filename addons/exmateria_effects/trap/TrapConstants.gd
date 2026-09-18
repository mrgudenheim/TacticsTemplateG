## Trap-effect timing. The PSX magnitude conversions that used to live here
## (PSX_SCALE = 1/28, FULL_CIRCLE_PSX = 4096) moved to the single PsxMagnitude seam
## (ADR-0091) — callers use PsxMagnitude.tile_to_game / angle_to_rad / FULL_TURN. Only
## the trap tick rate stays, since 30 Hz is a frame-rate fact, not a PSX unit.
## Vault: [[Embedded MIPS Effect Code]]
## Vault: [[Summon Orb Orbital System]]
## Vault: [[Unit Sprite Render Pipeline]]

const TICK_DURATION: float = 1.0 / 30.0
