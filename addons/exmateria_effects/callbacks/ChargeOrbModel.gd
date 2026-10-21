extends RefCounted
## The summon charge orbs' per-tick state, in the ROM's own integer maths: handler 22,
## `battle_effect_summon_charge_secondary_handler` 0x801b4234 (SUMMON_CHARGE_ORBS.md §2–§4,
## branch research/spell-charge-lines). Pure — no nodes: TrapOrbitalCallback ticks it and
## places its sprites from `offset()` / `grey()`; TrapLiftTest replays the PCSX capture.
##
## Offsets are PSX world units relative to the centre, on the flat XZ ring (y is never
## written). One `step()` = one handler call = one VSYNC (60 Hz); `start()` is tick 1.
##   phase 2: ramp — radius = t, spin = 3t for t < 24; brightness (t+1)·16 for t < 8.
##   phase 3 (`finalize()`): the fixed 61-tick finale — brightness 240 falling 4 a tick,
##            spin +1 a tick, radius +1 on the ticks where finish_timer & 8; then all
##            thirty sprites are freed together (`is_done()`).

const RINGS := 3
const SLOTS := 10
const RING_PHASE := 0x555
const RAMP_TICKS := 24
const BRIGHT_RAMP_TICKS := 8
const FINALE_TICKS := 61
## 0x801b88f4: slot 0 is the head, slots 1..9 the trail oldest → newest.
const WEIGHTS: PackedInt32Array = [128, 2, 6, 8, 10, 12, 16, 20, 24, 28]

var timer := 0
var finish_timer := 0
var finalized := false
## The handler tick the finalize came after (-1 until it does).
var finalized_at := -1
var radius := 0
var step_size := 0
var angle := 0
var brightness := 0
## The ring-buffer cell the NEXT tick writes (the ROM's `index`).
var index := 0
var points: Array = []  # [ring][cell] -> Vector2i (x, z)
## Handler calls so far, init included.
var ticks := 0


static func rcos(a: int) -> int:
	return roundi(4096.0 * cos(float(a & 4095) * TAU / 4096.0))


static func rsin(a: int) -> int:
	return roundi(4096.0 * sin(float(a & 4095) * TAU / 4096.0))


## C division: truncates toward zero.
static func _tdiv(a: int, b: int) -> int:
	var q := absi(a) / b
	return q if a >= 0 else -q


## Tick 1 (phase 1).
func start() -> void:
	timer = 0
	finish_timer = 0
	finalized = false
	finalized_at = -1
	radius = 0
	step_size = 0
	angle = 0
	brightness = 0
	index = 0
	points.clear()
	for r in range(RINGS):
		var ring: Array[Vector2i] = []
		ring.resize(SLOTS)
		ring.fill(Vector2i.ZERO)
		points.append(ring)
	ticks = 1


func finalize() -> void:
	if not finalized:
		finalized_at = ticks
	finalized = true


func is_done() -> bool:
	return finish_timer >= FINALE_TICKS


## One handler call in phase 2 or 3. False once the finale's last tick has run (the
## handler returns 0 and frees every sprite on that same tick).
func step() -> bool:
	if is_done():
		return false
	ticks += 1
	if not finalized:
		if timer < RAMP_TICKS:
			radius = timer
			step_size = timer * 3
		if timer < BRIGHT_RAMP_TICKS:
			brightness = (timer + 1) * 16
		if timer < 0x100:
			timer += 1
	elif finish_timer < FINALE_TICKS:
		if finish_timer & 8:
			radius += 1
		step_size += 1
		brightness = (60 - finish_timer) * 4
		finish_timer += 1
	angle += step_size
	for r in range(RINGS):
		var a := r * RING_PHASE + angle
		points[r][index] = Vector2i(_tdiv(rcos(a) * radius, 4096), _tdiv(rsin(a) * radius, 4096))
	index = (index + 1) % SLOTS
	return not is_done()


## Slot `j` of ring `r` as this tick placed it: slot 0 = the newest point, slot 1 the
## oldest, rising to slot 9 one tick behind the head.
func offset(r: int, j: int) -> Vector2i:
	var newest := (index - 1 + SLOTS) % SLOTS
	return points[r][(newest + j) % SLOTS]


## Slot `j`'s grey level (0–255, 128 = the texture's own colour).
func grey(j: int) -> int:
	return WEIGHTS[j] * brightness / 128
