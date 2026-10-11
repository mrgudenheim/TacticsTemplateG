extends RefCounted
## Simple object pool for particles

const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")

var _pool: Array[Particle] = []
var _active: Array[Particle] = []
var _capacity: int = 256


func _init(capacity: int = 256) -> void:
	_capacity = capacity
	_pool.resize(capacity)
	for i in range(capacity):
		_pool[i] = Particle.new()


func acquire() -> Particle:
	"""Get a particle from pool, or null if exhausted"""
	if _pool.is_empty():
		return null

	var particle: Particle = _pool.pop_back()
	_active.append(particle)
	return particle


func release(particle: Particle) -> void:
	"""Return particle to pool"""
	particle.deactivate()
	var idx = _active.find(particle)
	if idx >= 0:
		_active.remove_at(idx)
	_pool.append(particle)


func get_active_particles() -> Array[Particle]:
	"""Get all active particles"""
	return _active


func cleanup_dead() -> Array[Particle]:
	"""Release dead particles, return list of those that died"""
	var dead: Array[Particle] = []
	var still_active: Array[Particle] = []

	for particle in _active:
		if particle.is_dead() or not particle.active:
			dead.append(particle)
			_pool.append(particle)
			particle.deactivate()
		else:
			still_active.append(particle)

	_active = still_active
	return dead


func get_active_count() -> int:
	return _active.size()


func get_available_count() -> int:
	return _pool.size()


func clear() -> void:
	"""Return all active particles to pool"""
	for particle in _active:
		particle.deactivate()
		_pool.append(particle)
	_active.clear()
