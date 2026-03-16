class_name TrapChargeHandlerBase
extends RefCounted
## Base class for charge line handlers (spell charge, summon charge).
## Manages Gouraud-shaded line trails that converge toward a target point.

enum State { INIT, ACTIVE, ENDING, DONE }

class LineSlot:
	var alive: bool = false
	var history: Array[Vector3] = []  # 7 entries (ring buffer)
	var age: int = 0
	var spawn_position: Vector3 = Vector3.ZERO

const MAX_LINE_SLOTS: int = 16
const HISTORY_SIZE: int = 7  # 6 LINE_G2 segments per line
const MAX_CONCURRENT_LINES: int = 10
const LINE_MAX_LIFETIME: int = 32
const EXPIRATION_AGE: int = LINE_MAX_LIFETIME + HISTORY_SIZE
const SPAWN_CHANCE_DIVISOR: int = 2  # 50% spawn chance per tick
const GOLDEN_ANGLE_INCREMENT: int = 0x571  # 1393 PSX units = 122.4 degrees
const FULL_CIRCLE: int = VfxConstants.PSX_FULL_CIRCLE
const SPAWN_RADIUS: float = 6.0
const DEFAULT_HEIGHT: float = 24.0  # PSX units — fallback if no unit provided
const FADE_CURVE: PackedByteArray = [0, 25, 50, 75, 100, 125, 255]  # tail dim -> head bright

var state: State = State.INIT
var line_slots: Array[LineSlot] = []
var element_color: Color = Color.WHITE
var active_line_count: int = 0
var convergence_y: float = 0.0

var _spawn_angle_accumulator: int = 0


func start_fade() -> void:
	if state == State.ACTIVE:
		state = State.ENDING


func is_done() -> bool:
	return state == State.DONE


func restart() -> void:
	if line_slots.size() != MAX_LINE_SLOTS:
		line_slots.resize(MAX_LINE_SLOTS)
		for i in range(MAX_LINE_SLOTS):
			var slot := LineSlot.new()
			slot.history.resize(HISTORY_SIZE)
			line_slots[i] = slot
	for slot in line_slots:
		slot.alive = false
		slot.age = 0
		slot.spawn_position = Vector3.ZERO
		slot.history.fill(Vector3.ZERO)
	active_line_count = 0
	_spawn_angle_accumulator = 0
	state = State.ACTIVE
	_on_restart()


func get_brightness_index(slot: LineSlot) -> int:
	if slot.age <= LINE_MAX_LIFETIME:
		return HISTORY_SIZE - 1  # 6 visible segments
	return maxi(0, LINE_MAX_LIFETIME - (slot.age - (HISTORY_SIZE - 1)))


## Override to reset subclass-specific state on restart.
func _on_restart() -> void:
	pass


## Override to compute the spawn position from a spawn angle.
func _compute_spawn_position(theta: float) -> Vector3:
	return Vector3(cos(theta) * SPAWN_RADIUS, convergence_y, sin(theta) * SPAWN_RADIUS)


## Override to compute the interpolated Y during line convergence.
func _interpolate_y(_slot: LineSlot, _factor: float) -> float:
	return convergence_y


## Override to compute additional theta offset (e.g., per-frame ring rotation).
func _extra_theta_offset() -> int:
	return 0


func _try_spawn_line() -> void:
	if active_line_count >= MAX_CONCURRENT_LINES:
		return
	if randi() % SPAWN_CHANCE_DIVISOR != 0:
		return

	# Find first dead slot
	var slot_idx: int = -1
	for i in range(MAX_LINE_SLOTS):
		if not line_slots[i].alive:
			slot_idx = i
			break
	if slot_idx < 0:
		return

	# Compute spawn angle with golden angle distribution
	var theta_psx: int = (randi() & 0x1FF) + _spawn_angle_accumulator + _extra_theta_offset()
	_spawn_angle_accumulator += GOLDEN_ANGLE_INCREMENT
	var theta: float = float(theta_psx) * TAU / float(FULL_CIRCLE)

	var spawn_pos: Vector3 = _compute_spawn_position(theta)

	var slot: LineSlot = line_slots[slot_idx]
	slot.alive = true
	slot.age = 0
	slot.spawn_position = spawn_pos
	for i in range(HISTORY_SIZE):
		slot.history[i] = spawn_pos

	active_line_count += 1


func _update_lines() -> void:
	for slot in line_slots:
		if not slot.alive:
			continue

		slot.age += 1
		var write_index: int = slot.age % HISTORY_SIZE

		if slot.age <= LINE_MAX_LIFETIME:
			var t: float = float(slot.age) / float(LINE_MAX_LIFETIME)
			var factor: float = (1.0 - cos(t * PI)) / 2.0
			slot.history[write_index].x = slot.spawn_position.x * (1.0 - factor)
			slot.history[write_index].z = slot.spawn_position.z * (1.0 - factor)
			slot.history[write_index].y = _interpolate_y(slot, factor)
		else:
			slot.history[write_index] = Vector3(0.0, convergence_y, 0.0)

		if slot.age > EXPIRATION_AGE:
			slot.alive = false
			active_line_count -= 1
