class_name TrapPaletteController
extends RefCounted
## Tick-based white flash state machine for TRAP particle effects.
## PSX timing: 8 interpolation steps at 60Hz = ~133ms. At 30Hz: 4 steps = ~133ms.

var _target_unit: Unit = null
var _step: int = -1
var _done: bool = true

const FADE_STEPS: int = 4
const TINT_PER_STEP: float = 1.0 / FADE_STEPS  # 0.25


func start(target_unit: Unit) -> void:
	_target_unit = target_unit
	_step = 0
	_done = false
	_target_unit.set_sprite_tint(Vector3.ONE)


func update() -> void:
	if _done or not is_instance_valid(_target_unit):
		return

	_step += 1
	if _step >= FADE_STEPS:
		_target_unit.set_sprite_tint(Vector3.ZERO)
		_done = true
		return

	var tint_value: float = 1.0 - (_step * TINT_PER_STEP)
	_target_unit.set_sprite_tint(Vector3.ONE * tint_value)


func is_done() -> bool:
	return _done


func reset() -> void:
	if is_instance_valid(_target_unit):
		_target_unit.set_sprite_tint(Vector3.ZERO)
	_target_unit = null
	_step = -1
	_done = true
