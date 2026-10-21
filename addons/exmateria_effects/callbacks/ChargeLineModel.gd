extends RefCounted
## The spell charge lines' per-tick state, in the ROM's own integer maths: handler 4,
## `battle_effect_spell_charge_secondary_handler` 0x801b1c04 (SPELL_CHARGE_LINES.md §3–§7,
## branch research/spell-charge-lines). Pure — no nodes: TrapChargeLineCallback ticks it
## and draws `prims()`; TrapLiftTest replays the PCSX captures through it.
##
## Everything is in SCREEN pixels RELATIVE TO THE CENTRE (the caster's head, projected once
## at init). The ROM works in absolute view-space x,y, but every step is translation-exact:
## the spawn is `(rcos(k)·radius + (cx<<12)) >> 12` = `(rcos(k)·radius >> 12) + cx`, the ease
## truncates a DIFFERENCE, and the nudge reads a direction — so the centre drops out.
##
## One `step()` = one handler call = one VSYNC (60 Hz). `start()` is tick 1 (init: no
## spawn). `finalize()` is the loader's phase 3: spawning stops and every line runs out its
## own life (≤ 39 ticks); `is_done()` then says the handler has returned 0.

const MAX_SLOTS := 16
const HISTORY := 7
const SEGMENTS := 6
## params row 0 (0x801b8880): duration 32, radius 256, spawn_interval 2, max_trails 10.
const DURATION := 32
const RADIUS := 256
const SPAWN_INTERVAL := 2
const MAX_TRAILS := 10
## spread_range 512 / spread_offset 128: the velocity angle's spread. Speed is 0, so the
## velocity is inert — but the rand() it draws is not, so it is drawn.
const SPREAD_RANGE := 512
const ANGLE_STEP := 0x571
## fade row 0 (0x801b88c0), tail → head.
const FADE_LEVELS: PackedInt32Array = [0, 25, 50, 75, 100, 125, 255]
## 0x801b889c: the 1-px ANTI-parallel nudge, indexed by (ratan2(v1−v0) + 0x900) / 512.
const NUDGE: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)]
## 0x801b8544: `battle_effect_get_ninja_ball` (the element → colour index) takes the FIRST
## set bit in this order — Fire, Water, Earth, Wind, Holy, Dark, Ice, Lightning — as index
## 1..8; no bit is 0.
const ELEMENT_MASKS: PackedInt32Array = [0x80, 0x04, 0x08, 0x10, 0x02, 0x01, 0x20, 0x40]
## 0x801b84c0, by colour index: none, Fire, Water, Earth, Wind, Holy, Dark, Ice, Lightning.
const ELEMENT_RGB: Array = [[160, 160, 160], [255, 80, 64], [64, 192, 192], [224, 136, 48],
	[64, 255, 80], [160, 160, 160], [192, 64, 192], [64, 80, 255], [192, 192, 64]]


class Trail:
	var active := false
	var age := 0
	## The line's own 20.12 position >> 12 — its spawn point, since the speed is 0.
	var origin := Vector2i.ZERO
	var points: Array[Vector2i] = []

	func _init() -> void:
		points.resize(7)
		points.fill(Vector2i.ZERO)


var trails: Array[Trail] = []
var rgb: PackedInt32Array = [160, 160, 160]
var radius := RADIUS
var duration := DURATION
var max_trails := MAX_TRAILS
var angle := 0
var finalized := false
## The handler tick the finalize came after (-1 until it does).
var finalized_at := -1
## Handler calls so far, init included.
var ticks := 0


## The element byte (the ability's, `range_data.element`) → colour index 0..8.
static func colour_index(element_byte: int) -> int:
	if element_byte == 0:
		return 0
	for i in range(ELEMENT_MASKS.size()):
		if element_byte & ELEMENT_MASKS[i]:
			return i + 1
	return 0


static func colour_rgb(index: int) -> PackedInt32Array:
	var c: Array = ELEMENT_RGB[clampi(index, 0, ELEMENT_RGB.size() - 1)]
	return PackedInt32Array(c)


## libgte rcos / rsin: 4096 = 1.0, 4096 per turn.
static func rcos(a: int) -> int:
	return roundi(4096.0 * cos(float(a & 4095) * TAU / 4096.0))


static func rsin(a: int) -> int:
	return roundi(4096.0 * sin(float(a & 4095) * TAU / 4096.0))


static func ratan2(y: int, x: int) -> int:
	return floori(atan2(float(y), float(x)) * 4096.0 / TAU + 0.5)


## `battle_effect_interpolate_s32_cos` 0x801a8834: a cosine ease-in-out from `s` to `e`
## over `d` ticks, at tick `c`; the division truncates toward zero.
static func ease_cos(s: int, e: int, d: int, c: int) -> int:
	var v := (e - s) * (4096 - rcos((c << 11) / d))
	var q := absi(v) / 0x2000
	return s + (q if v >= 0 else -q)


## Tick 1 (phase 1): clear every slot, the angle accumulator starts at 0.
func start(colour: PackedInt32Array, p_radius: int = RADIUS, p_duration: int = DURATION,
		p_max_trails: int = MAX_TRAILS) -> void:
	rgb = colour
	radius = p_radius
	duration = maxi(1, p_duration)
	max_trails = p_max_trails
	trails.clear()
	for i in range(MAX_SLOTS):
		trails.append(Trail.new())
	angle = 0
	finalized = false
	finalized_at = -1
	ticks = 1


## Phase 3 (`battle_effect_finalize_secondary`): no more spawns.
func finalize() -> void:
	if not finalized:
		finalized_at = ticks
	finalized = true


func count() -> int:
	var n := 0
	for t in trails:
		if t.active:
			n += 1
	return n


func is_done() -> bool:
	return finalized and count() == 0


## One handler call in phase 2 or 3. `rand` is the ROM's rand(): a non-negative int.
func step(rand: Callable) -> void:
	ticks += 1
	if not finalized and count() < max_trails and int(rand.call()) % SPAWN_INTERVAL == 0:
		for t in trails:
			if t.active:
				continue
			var k := (int(rand.call()) & 0x1FF) + angle
			angle += ANGLE_STEP
			var p := Vector2i((rcos(k) * radius) >> 12, (rsin(k) * radius) >> 12)
			rand.call()  # the velocity's spread: inert (speed 0), but it advances the stream
			t.active = true
			t.age = 0
			t.origin = p
			t.points.fill(p)
			break
	for t in trails:
		if not t.active:
			continue
		t.age += 1
		var head := t.age % HISTORY
		if t.age <= duration:
			t.points[head] = Vector2i(ease_cos(t.origin.x, 0, duration, t.age),
				ease_cos(t.origin.y, 0, duration, t.age))
		else:
			t.points[head] = Vector2i.ZERO
		if t.age >= duration + HISTORY:
			t.active = false


## The LINE_G2s this tick draws — the ones the handler LINKS into the OT (a zero-length
## segment is built but never linked).
func prims() -> Array:
	var out: Array = []
	for t in trails:
		if t.active:
			for p in trail_prims(t):
				if p.linked:
					out.append(p)
	return out


## One trail's six LINE_G2s, head backwards, exactly as the handler builds them:
## `[{xy0, rgb0, xy1, rgb1, linked}]` (rgb as [r,g,b] ints; xy centre-relative, the far end
## nudged 1 px back toward the near one when the two differ).
func trail_prims(t: Trail) -> Array:
	var out: Array = []
	var age := t.age
	var head := age % HISTORY
	var fade := 6 if age <= duration else maxi(0, duration - (age - 6))
	for _k in range(SEGMENTS):
		var v0: Vector2i = t.points[head]
		var c0 := _shade(fade)
		head = HISTORY - 1 if head == 0 else head - 1
		age -= 1
		if fade != 0:
			fade -= 1
		if age < 0:
			fade = 0
		var v1: Vector2i = t.points[head]
		var linked := v0 != v1
		if linked:
			var d := v1 - v0
			v1 += NUDGE[(ratan2(d.y, d.x) + 0x900) / 512]
		out.append({"xy0": v0, "rgb0": c0, "xy1": v1, "rgb1": _shade(fade), "linked": linked})
	return out


func _shade(fade: int) -> Array:
	var f := FADE_LEVELS[fade]
	return [(rgb[0] * f) >> 8, (rgb[1] * f) >> 8, (rgb[2] * f) >> 8]
