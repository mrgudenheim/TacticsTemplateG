class_name TrapSummonChargeHandler
extends TrapChargeHandlerBase
## PSX Handler 18 — Plain charge lines.
## Gouraud-shaded line trails converge from a 3D-oriented spawn ring toward the target's torso.
## Same render approach as handler 4 but with directional ring, per-frame rotation, no sparkles,
## and self-managed duration.

const RING_ROTATION_RATE: int = 128  # PSX: frame_counter << 7

var _axis_basis: Basis = Basis.IDENTITY  # rotation from Y-up to caster→target axis
var _frame_counter: int = 0
var _duration: int = 30


func start(p_element_id: int, p_sprite_height: float = DEFAULT_HEIGHT,
		p_direction: Vector3 = Vector3.ZERO, p_initial_frame: int = 0) -> void:
	convergence_y = (p_sprite_height / 2.0) / VfxEmitter.POSITION_DIVISOR

	element_color = TrapEffectData.get_element_color(p_element_id)

	# Compute axis basis from caster→target direction
	if p_direction.length_squared() > 0.001:
		var yaw: float = atan2(p_direction.x, p_direction.z)
		var horizontal_dist: float = sqrt(p_direction.x * p_direction.x + p_direction.z * p_direction.z)
		var pitch: float = atan2(p_direction.y, horizontal_dist)
		_axis_basis = Basis.from_euler(Vector3(pitch, yaw, 0))
	else:
		_axis_basis = Basis.IDENTITY

	_duration = maxi(p_initial_frame + 4, 30)

	restart()


func tick() -> void:
	match state:
		State.ACTIVE:
			_try_spawn_line()
			_update_lines()
			_frame_counter += 1
			if _frame_counter >= _duration:
				start_fade()
		State.ENDING:
			_update_lines()
			_frame_counter += 1
			if active_line_count == 0:
				state = State.DONE
		State.DONE, State.INIT:
			return


func _on_restart() -> void:
	_frame_counter = 0


func _extra_theta_offset() -> int:
	return _frame_counter * RING_ROTATION_RATE


func _compute_spawn_position(theta: float) -> Vector3:
	# Local spawn on XZ ring, then rotate by axis basis for 3D orientation
	var local_spawn := Vector3(cos(theta) * SPAWN_RADIUS, 0.0, sin(theta) * SPAWN_RADIUS)
	var rotated_spawn: Vector3 = _axis_basis * local_spawn
	return Vector3(rotated_spawn.x, rotated_spawn.y + convergence_y, rotated_spawn.z)


func _interpolate_y(slot: LineSlot, factor: float) -> float:
	return slot.spawn_position.y * (1.0 - factor) + convergence_y * factor
