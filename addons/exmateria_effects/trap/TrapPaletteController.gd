extends RefCounted
## White flash palette controller for TRAP hit effects
##
## Implements the PSX TRAP handler's inline palette behavior for physical attacks.
## Unlike the E### palette subsystem (keyframe interpolation), TRAP uses a simple 2-phase
## tick-based state machine:
##
## Tick 0: Snap to white immediately (mode 5 = param + original/2)
## Tick 1+: Animated fade back to original (mode 8, speed 2)
##
## Mode Details:
## - Mode 5: result = param_RGB + original_bgr555 / 2 -> brightens toward white
## - Mode 8: result = original (restore)
## - Sub_mode 0: Immediate snap
## - Sub_mode 2: Animated, 2 frames per interpolation step
##
## PSX runs palette at 60 Hz (vblank). Fast mode (speed<4) = 8 steps = 8/60 = ~133ms.
## We run at 30 FPS, so 4 steps at 30 FPS = 4/30 = ~133ms to match.
## Vault: [[TRAP Hit Effect Particle System]]
## Vault: [[Unit White Flash Reaction Handler]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")

## The tint registry reached through its PORT rather than through the bare
## `TintedSurfaces` autoload identifier — a member may name no autoload at all
## (ADR-0308 dec. 1). This file's four reaches were one of the three
## `known_failures.tsv` rows, and the row's own note is why it took a port and not a
## ticket: it had been re-ticketed twice, to `#1223` and then `#1224`, and neither
## could ever pay it, because *"a rename moves the identifier this row names, and a
## merge reduces how many identifiers there are, and the row is about whether ANY of
## them exists in a project that declared none."*
const TintedSurfacesPort = preload("res://addons/exmateria_effects/install/TintedSurfacesPort.gd")

var _target_unit: WeakRef
var _tick: int = 0
var _owner_id: int  # For TintedSurfaces layer tracking
var _finished: bool = false

# Interpolation state (for mode 8 fade-back)
var _current_tint: Vector3 = Vector3.ZERO
var _target_tint: Vector3 = Vector3.ZERO
var _speed: int = 0  # Ticks per interpolation step (0 = no animation, 1 = every tick)
var _step_counter: int = 0


func initialize(target_unit: Node) -> void:
	"""Initialize the controller with a target unit.

	Args:
		target_unit: The Unit node to apply the white flash effect to
	"""
	_target_unit = weakref(target_unit)
	_owner_id = get_instance_id()
	_tick = 0
	_finished = false
	_current_tint = Vector3.ZERO
	_target_tint = Vector3.ZERO
	_speed = 0
	_step_counter = 0


func update() -> void:
	"""Process one tick of the palette effect.

	Call this once per TRAP tick (1/30th second) to advance the white flash.
	"""
	if _finished:
		return

	# Tick 0: Snap to white (mode 5 = +31 + original/2 -> bright white)
	if _tick == 0:
		_current_tint = Vector3(1.0, 1.0, 1.0)  # Full white delta
		_target_tint = _current_tint
		_speed = 0  # Immediate

	# Tick 1: Begin animated fade to original (mode 8, fast mode)
	# PSX: 8 steps at 60 Hz = 133ms. We run at 30 Hz, so 4 steps = 133ms.
	elif _tick == 1:
		_target_tint = Vector3.ZERO  # Target = no tint (original)
		_speed = 1  # Step every tick (30 FPS)
		_step_counter = 0

	# Interpolate toward target if animating
	if _speed > 0:
		_step_counter += 1
		if _step_counter >= _speed:
			_step_counter = 0
			_interpolate_step()

	# Apply tint to unit
	_apply_tint()

	# Check if finished (reached target after tick 1)
	if _tick > 1 and _current_tint.is_equal_approx(_target_tint):
		_cleanup()

	_tick += 1


func _interpolate_step() -> void:
	"""Move one step toward target tint.

	PSX: 8 steps at 60 Hz = 133ms fade.
	We run at 30 FPS, so 4 steps = 133ms to match.
	"""
	var diff = _target_tint - _current_tint
	var step_size = 1.0 / 4.0  # 4 steps at 30 FPS = ~133ms

	# Move each component one step toward target
	if absf(diff.x) > 0.001:
		var step_x = sign(diff.x) * step_size
		_current_tint.x += step_x
		# Clamp to not overshoot
		if sign(_target_tint.x - _current_tint.x) != sign(diff.x):
			_current_tint.x = _target_tint.x

	if absf(diff.y) > 0.001:
		var step_y = sign(diff.y) * step_size
		_current_tint.y += step_y
		if sign(_target_tint.y - _current_tint.y) != sign(diff.y):
			_current_tint.y = _target_tint.y

	if absf(diff.z) > 0.001:
		var step_z = sign(diff.z) * step_size
		_current_tint.z += step_z
		if sign(_target_tint.z - _current_tint.z) != sign(diff.z):
			_current_tint.z = _target_tint.z


func _apply_tint() -> void:
	"""Apply current tint to the target unit via TintedSurfaces."""
	var unit = _target_unit.get_ref()
	if not unit:
		_cleanup()
		return

	var unit_id = unit.get_instance_id()
	if not TintedSurfacesPort.is_surface_registered(unit_id):
		if EffectsDebug.iteration():
			print("[TrapPaletteController] Unit %d not registered for tinting" % unit_id)
		return

	var tint_color = Color(_current_tint.x, _current_tint.y, _current_tint.z, 1.0)
	TintedSurfacesPort.update_layer(unit_id, _owner_id, tint_color)

	if EffectsDebug.iteration():
		print("[TrapPaletteController] Tick %d: tint=(%.2f, %.2f, %.2f)" % [
			_tick, _current_tint.x, _current_tint.y, _current_tint.z])


func _cleanup() -> void:
	"""Remove tint layer and mark as finished."""
	var unit = _target_unit.get_ref()
	if unit:
		var unit_id = unit.get_instance_id()
		if TintedSurfacesPort.is_surface_registered(unit_id):
			TintedSurfacesPort.remove_layer(unit_id, _owner_id)

	_finished = true

	if EffectsDebug.iteration():
		print("[TrapPaletteController] Cleanup complete, effect finished")


func is_finished() -> bool:
	"""Check if the effect has completed."""
	return _finished


func get_current_tint() -> Vector3:
	"""Get current tint value (for debugging)."""
	return _current_tint
