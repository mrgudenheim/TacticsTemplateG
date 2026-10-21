extends "res://addons/exmateria_effects/callbacks/EffectCallback.gd"
## E077 CB37 @0x801C5174. Four internal projectiles, NO GPU primitives.
## Their 17-position history feeds child emitter_control calls at 0x801C6650/66A0.
## This is not CB91's eight-projectile/nine-point ribbon renderer.
## Vault: [[Embedded MIPS Effect Code]]

const LIMIT := 4
const HISTORY := 17
var _projectiles: Array = []
var _cleanup_pending := false

func _on_init(_emitter_index: int, _spawn_counter: int, _channel_index: int) -> void:
	_projectiles.resize(LIMIT)
	_projectiles.fill(null)
	_cleanup_pending = false
	state = State.ANIMATE

func _value(a: String, b: String, index: int, word: int, nibble: int) -> int:
	var raw: Dictionary = emitter_config.raw_data
	var start: int = _ri(raw, a, index) if raw.has(a) else int(emitter_config.get(a))
	var end: int = _ri(raw, b, index) if raw.has(b) else int(emitter_config.get(b))
	return start + (((end - start) * roundi(_curve_t_nibble(word, nibble) * 255.0)) >> 8)

func _vector(a: String, b: String, word: int, nibble: int) -> Vector3i:
	return Vector3i(_value(a, b, 0, word, nibble), _value(a, b, 1, word, nibble), _value(a, b, 2, word, nibble))

func _random() -> int:
	# The instance's PCG stream guarantees Godot seek/replay, NOT PSX RNG parity.
	# The ROM returns a 15-bit rand() value. Equal endpoints consume no draw.
	assert(rng != null, "Fairy CB37 requires the owning effect RNG")
	return int(rng.randi() & 32767)

func _range(a: int, b: int) -> int:
	return a if a == b else mini(a, b) + _random() % absi(b - a)

static func _sin(a: int) -> int:
	return roundi(sin(float(a & 4095) * TAU / 4096.0) * 4096.0)

static func _cos(a: int) -> int:
	return _sin(a + 1024)

static func _rotate(v: Vector3i, a: Vector3i) -> Vector3i:
	# RotMatrix @0x8001D658: preserve its intermediate >>12 operations.
	var sx := _sin(a.x)
	var cx := _cos(a.x)
	var sy := _sin(a.y)
	var cy := _cos(a.y)
	var sz := _sin(a.z)
	var cz := _cos(a.z)
	var nsycz := (-sy * cz) >> 12
	var nsysz := (-sy * sz) >> 12
	var r0 := Vector3i((cz * cy) >> 12, (-sz * cy) >> 12, sy)
	var r1 := Vector3i(((sz * cx) >> 12) - ((nsycz * sx) >> 12),
		((cz * cx) >> 12) + ((nsysz * sx) >> 12), (-cy * sx) >> 12)
	var r2 := Vector3i(((sz * sx) >> 12) + ((nsycz * cx) >> 12),
		((cz * sx) >> 12) - ((nsysz * cx) >> 12), (cy * cx) >> 12)
	return Vector3i((r0.x * v.x + r0.y * v.y + r0.z * v.z) >> 12,
		(r1.x * v.x + r1.y * v.y + r1.z * v.z) >> 12,
		(r2.x * v.x + r2.y * v.y + r2.z * v.z) >> 12)

func _scatter(spread: Vector3i) -> Vector3i:
	var length := int(Vector3(spread).length())
	if length == 0:
		return Vector3i.ZERO
	var a := Vector3i(_random(), _random(), _random())
	var rotated := _rotate(Vector3i(length, 0, 0), a)
	return Vector3i(rotated.x * spread.x / length, rotated.y * spread.y / length, rotated.z * spread.z / length)

static func _psx(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 28.0), roundi(-v.y * 28.0), roundi(-v.z * 28.0))

static func _world(v: Vector3i) -> Vector3:
	return Vector3(v.x, -v.y, -v.z) / 28.0

func _anchor(mode: int) -> Vector3i:
	match mode:
		0x200: return _psx(anchor_world)
		0x400: return _psx(anchor_origin)
		0x600: return _psx(anchor_target)
		0xa00: return _psx(Vector3(anchor_cursor.x, 0, anchor_cursor.z))
	return Vector3i.ZERO

func _spawn() -> void:
	var slot := _projectiles.find(null)
	if slot < 0:
		return
	var raw: Dictionary = emitter_config.raw_data
	var flags := int(raw.get("emitter_flags_lo", 0)) | (int(raw.get("emitter_flags_hi", 0)) << 8)
	var center := _vector("position_start", "position_end", 0, 0) + _anchor((int(raw.get("animation_target_flag", 0)) & 14) << 8)
	var position := center + _scatter(_vector("spread_start", "spread_end", 0, 1))
	var target := _vector("target_start", "target_end", 1, 3)
	match int(raw.get("motion_type_flag", 0)) & 224:
		0x40: target += _psx(Vector3(anchor_cursor.x, 0, anchor_cursor.z))
		0x60: target += _psx(anchor_origin)
		0x80: target += _psx(anchor_target)
		0xa0: target += _psx(anchor_world)
	target += _scatter(_vector("drag_min_start", "drag_min_end", 1, 1))
	var speed := _range(_value("radial_min_start", "radial_min_end", -1, 0, 7),
		_value("radial_max_start", "radial_max_end", -1, 0, 7))
	var velocity := Vector3i.ZERO
	if (flags & 0x410) == 0x10:
		var delta := center - position
		var length := int(Vector3(delta).length())
		if length == 0:
			velocity.y = speed << 3
		else:
			var unit := Vector3i(delta.x * 4096 / length, delta.y * 4096 / length, delta.z * 4096 / length)
			velocity = Vector3i((speed * unit.x) >> 9, (speed * unit.y) >> 9, (speed * unit.z) >> 9)
	else:
		var angles := _vector("angle_start", "angle_end", 0, 2)
		var spread := _vector("vel_spread_start", "vel_spread_end", 0, 3)
		angles += Vector3i(_range(-spread.x, spread.x), _range(-spread.y, spread.y), _range(-spread.z, spread.z))
		velocity = _rotate(Vector3i(0, speed, 0), angles)
		if (flags & 0x410) == 0x410:
			velocity = _rotate(velocity, Vector3i(0, roundi(caster_facing_angle / ANGLE_SCALE), 0))
		velocity *= 8
	var life := _range(_value("lifetime_min_start", "lifetime_min_end", -1, 1, 2),
		_value("lifetime_max_start", "lifetime_max_end", -1, 1, 2))
	var history: Array[Vector3i] = []
	history.resize(HISTORY)
	history.fill(position)
	_projectiles[slot] = {"position": position * 4096, "velocity": velocity, "target": target,
		"age": 0, "life": life, "history": history}

static func _ease(start: int, end: int, duration: int, age: int) -> int:
	if duration <= 0:
		return end
	# 0x801A8834 divides toward zero (including negative interpolation deltas).
	return start + (end - start) * (4096 - _cos((age << 11) / duration)) / 8192

func _on_animate(_emitter_index: int, spawn_counter: int, _channel_index: int) -> void:
	_frame_counter = spawn_counter % 160
	var interval := _value("spawn_interval_start", "spawn_interval_end", -1, 1, 6)
	if interval > 0 and (spawn_counter - 1) % interval == 0:
		var count := _value("particle_count_start", "particle_count_end", -1, 1, 5)
		for i in mini(count, LIMIT):
			_spawn()
	var flags := int(emitter_config.raw_data.get("emitter_flags_lo", 0))
	for slot in _projectiles.size():
		var p = _projectiles[slot]
		if p == null:
			continue
		p["position"] += p["velocity"]
		p["age"] += 1
		var age: int = p["age"]
		var life: int = p["life"]
		var position: Vector3i = p["position"]
		var target: Vector3i = p["target"]
		var head := age % HISTORY
		var sample := target
		if age <= life:
			sample = Vector3i(_ease(position.x >> 12, target.x, life, age),
				_ease(position.y >> 12, target.y, life, age), _ease(position.z >> 12, target.z, life, age))
		p["history"][head] = sample
		if age > life:
			head = posmod(head - 16 + maxi(0, life - (age - 16)), HISTORY)
		var child_position := _world(p["history"][head])
		if flags & 12 and emitter_config.child_emitter_mid_life >= 0:
			child_spawn_requested.emit(emitter_config.child_emitter_mid_life, child_position, age)
		if age == life + 16 and flags & 3 and emitter_config.child_emitter_on_death >= 0:
			child_spawn_requested.emit(emitter_config.child_emitter_on_death, child_position, age)
		if age == life + 16:
			_projectiles[slot] = null

func cleanup() -> void:
	if _cleanup_pending:
		_projectiles.clear()
	else:
		_cleanup_pending = true
	state = State.CLEANUP

func force_cleanup() -> void:
	_projectiles.clear()
	_cleanup_pending = false
	state = State.INACTIVE
