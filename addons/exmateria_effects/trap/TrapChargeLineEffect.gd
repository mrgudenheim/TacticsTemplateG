extends Node3D
## Spell charge line effect (PSX TRAP handler 4).
##
## Spawns glowing lines that contract from a ring toward the caster's head,
## with a 7-segment trail rendered as camera-facing billboard strips.
## Also spawns sparkle particles (emitter 12) via a TrapEffect instance.
## Vault: [[Display Space Blend Fold]]
## Vault: [[Effect Callback Mesh]]
## Vault: [[Embedded MIPS Effect Code]]
## Vault: [[Spell Charge Lines System]]
## Vault: [[Summon Charge Lines System]]
## Vault: [[Unit Sprite Height Table]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const TrapConstants = preload("res://addons/exmateria_effects/trap/TrapConstants.gd")

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


signal animation_finished

# Constants matching PSX handler 4
const MAX_LINE_SLOTS: int = 16
const HISTORY_SIZE: int = 7
const MAX_CONCURRENT_LINES: int = 10
const LINE_MAX_LIFETIME: int = 32
const EXPIRATION_AGE: int = LINE_MAX_LIFETIME + HISTORY_SIZE  # 39
const SPAWN_CHANCE_DIVISOR: int = 2  # 50% spawn chance per tick
const GOLDEN_ANGLE_INCREMENT: int = 1393  # 0x571 = 122.4 degrees in PSX 4096-unit circle
const SPAWN_RADIUS: float = 6.0  # Ring radius in Godot units
const DEFAULT_HEIGHT: float = 24.0  # PSX sprite height fallback
const HEIGHT_OVERSHOOT: float = 8.0  # PSX adds 8 units above head
const CYLINDER_RADIUS: float = 0.016
const CYLINDER_SIDES: int = 6  # Sides per cylinder segment

# Brightness fade curve per segment: tail dim → head bright
const FADE_CURVE: PackedByteArray = [0, 25, 50, 75, 100, 125, 255]

# Sparkle particle config
const SPARKLE_EMITTER_INDEX: int = 12
const SPARKLE_PALETTE_ID: int = 15

# Element colors for line rendering
const ELEMENT_COLORS: Array = [
	Color(0.627, 0.627, 0.627),  # 0: None (0xA0,0xA0,0xA0 Grey)
	Color(1.000, 0.314, 0.251),  # 1: Fire (0xFF,0x50,0x40 Red-Orange)
	Color(0.251, 0.753, 0.753),  # 2: Lightning (0x40,0xC0,0xC0 Cyan)
	Color(0.878, 0.533, 0.188),  # 3: Ice (0xE0,0x88,0x30 Amber)
	Color(0.251, 1.000, 0.314),  # 4: Wind (0x40,0xFF,0x50 Green)
	Color(0.627, 0.627, 0.627),  # 5: Earth (0xA0,0xA0,0xA0 Grey)
	Color(0.753, 0.251, 0.753),  # 6: Water (0xC0,0x40,0xC0 Purple)
	Color(0.251, 0.314, 1.000),  # 7: Holy (0x40,0x50,0xFF Blue)
	Color(0.753, 0.753, 0.251),  # 8: Dark (0xC0,0xC0,0x40 Yellow)
]

enum State { INIT, ACTIVE, ENDING, DONE }

class LineSlot:
	var active: bool = false
	var age: int = 0
	var spawn_position: Vector3 = Vector3.ZERO
	var history: Array = []  # Array of Vector3, size HISTORY_SIZE
	var write_index: int = 0

	func _init() -> void:
		history.resize(HISTORY_SIZE)
		for i in range(HISTORY_SIZE):
			history[i] = Vector3.ZERO

# State
var _state: int = State.INIT
var _tick_counter: int = 0
var _tick_timer: float = 0.0
var _spawn_angle_accumulator: int = 0
var _convergence_y: float = 0.0
var _element_color: Color = Color.WHITE
var _line_slots: Array = []  # Array of LineSlot
var _anchor_position: Vector3 = Vector3.ZERO
var _target_unit: Node = null

# Rendering
var _immediate_mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _shader_material: ShaderMaterial

# Sparkle particles (optional TrapEffect instance)
var _sparkle_effect: Node = null
const TrapEffectClass = preload("res://addons/exmateria_effects/trap/TrapEffect.gd")


func _ready() -> void:
	# ADR-0037: combat-visual — rides combat domain's pause axis via process_mode
	add_to_group("combat_visuals")
	# Create ImmediateMesh for line rendering
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Load shader material
	var shader = load("res://addons/exmateria_effects/trap/trap_charge_line.gdshader")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	_mesh_instance.material_override = _shader_material

	add_child(_mesh_instance)

	# Initialize line slots
	_line_slots.resize(MAX_LINE_SLOTS)
	for i in range(MAX_LINE_SLOTS):
		_line_slots[i] = LineSlot.new()


func start(world_position: Vector3, unit: Node = null, element_id: int = 0) -> void:
	"""Begin spawning charge lines at the given position."""
	_anchor_position = world_position
	global_position = world_position
	_target_unit = unit
	_convergence_y = PsxMagnitude.tile_to_game(DEFAULT_HEIGHT + HEIGHT_OVERSHOOT)
	_state = State.ACTIVE
	_tick_counter = 0
	_tick_timer = 0.0
	_spawn_angle_accumulator = randi() % PsxMagnitude.FULL_TURN

	# Color is explicit; a spatial anchor need not implement a game actor API.
	element_id = clampi(element_id, 0, ELEMENT_COLORS.size() - 1)
	_element_color = ELEMENT_COLORS[element_id]

	# Create sparkle particle effect
	_sparkle_effect = TrapEffectClass.new()
	add_child(_sparkle_effect)
	if _sparkle_effect.initialize(7, 0):
		_sparkle_effect.play_handler(4, 0, world_position,
			Vector3.ZERO, null)
		_sparkle_effect.animation_finished.connect(_on_sparkles_finished)
	else:
		_sparkle_effect.queue_free()
		_sparkle_effect = null

	if EffectsDebug.particle():
		print("[TrapChargeLine] Started at %s, convergence_y=%.3f" % [world_position, _convergence_y])


func start_fade() -> void:
	"""Stop spawning new lines; existing lines finish naturally, then auto-cleanup."""
	if _state == State.ACTIVE:
		_state = State.ENDING
		# Stop sparkle effect
		if _sparkle_effect and is_instance_valid(_sparkle_effect):
			_sparkle_effect.stop()
			_sparkle_effect.queue_free()
			_sparkle_effect = null
		if EffectsDebug.particle():
			print("[TrapChargeLine] Starting fade")


func _on_sparkles_finished() -> void:
	"""When sparkle particles finish, restart them if still active."""
	if _state == State.ACTIVE:
		_restart_sparkles()
	else:
		_sparkle_effect = null


func _restart_sparkles() -> void:
	"""Free old sparkle effect and create a new one to loop continuously."""
	if _sparkle_effect and is_instance_valid(_sparkle_effect):
		_sparkle_effect.queue_free()
		_sparkle_effect = null

	_sparkle_effect = TrapEffectClass.new()
	add_child(_sparkle_effect)
	if _sparkle_effect.initialize(7, 0):
		_sparkle_effect.play_handler(4, 0, _anchor_position,
			Vector3.ZERO, null)
		_sparkle_effect.animation_finished.connect(_on_sparkles_finished)
	else:
		_sparkle_effect.queue_free()
		_sparkle_effect = null


func stop() -> void:
	"""Stop immediately without emitting signal."""
	_state = State.DONE
	if _sparkle_effect and is_instance_valid(_sparkle_effect):
		_sparkle_effect.stop()
		_sparkle_effect.queue_free()
		_sparkle_effect = null
	_immediate_mesh.clear_surfaces()


func _process(delta: float) -> void:
	if _state == State.INIT or _state == State.DONE:
		return

	# Update anchor from unit position if available
	if _target_unit and is_instance_valid(_target_unit):
		_anchor_position = _target_unit.global_position
		global_position = _anchor_position

	_tick_timer += delta
	while _tick_timer >= TrapConstants.TICK_DURATION:
		_tick_timer -= TrapConstants.TICK_DURATION
		_process_tick()

	# Render lines every frame for smooth visuals
	_render_lines()


func _process_tick() -> void:
	"""Process one tick (1/30th second)."""
	# Spawn new lines if active
	if _state == State.ACTIVE:
		_try_spawn_line()

	# Update existing lines
	var any_active := false
	for slot in _line_slots:
		if not slot.active:
			continue
		slot.age += 1

		# Update position via cosine ease-in-out contraction
		var write_idx = slot.write_index
		if slot.age <= LINE_MAX_LIFETIME:
			var t: float = float(slot.age) / float(LINE_MAX_LIFETIME)
			var factor: float = (1.0 - cos(t * PI)) / 2.0
			slot.history[write_idx] = Vector3(
				slot.spawn_position.x * (1.0 - factor),
				_convergence_y,
				slot.spawn_position.z * (1.0 - factor)
			)
		else:
			slot.history[write_idx] = Vector3(0.0, _convergence_y, 0.0)

		# Advance write head
		slot.write_index = (slot.write_index + 1) % HISTORY_SIZE

		# Expire old lines
		if slot.age >= EXPIRATION_AGE:
			slot.active = false
		else:
			any_active = true

	_tick_counter += 1

	# Check for completion when ending
	if _state == State.ENDING and not any_active:
		_state = State.DONE
		_immediate_mesh.clear_surfaces()
		animation_finished.emit()
		queue_free()


func _try_spawn_line() -> void:
	"""Try to spawn a new line with 50% chance."""
	if randi() % SPAWN_CHANCE_DIVISOR != 0:
		return

	# Count active lines
	var active_count: int = 0
	for slot in _line_slots:
		if slot.active:
			active_count += 1
	if active_count >= MAX_CONCURRENT_LINES:
		return

	# Find free slot
	var free_slot: LineSlot = null
	for slot in _line_slots:
		if not slot.active:
			free_slot = slot
			break
	if not free_slot:
		return

	# Calculate spawn position on ring using golden angle
	var theta_psx: int = (randi() & 0x1FF) + _spawn_angle_accumulator
	_spawn_angle_accumulator += GOLDEN_ANGLE_INCREMENT
	var theta: float = PsxMagnitude.angle_to_rad(theta_psx)
	var spawn_pos := Vector3(cos(theta) * SPAWN_RADIUS, _convergence_y, sin(theta) * SPAWN_RADIUS)

	# Initialize slot
	free_slot.active = true
	free_slot.age = 0
	free_slot.spawn_position = spawn_pos
	free_slot.write_index = 0
	for i in range(HISTORY_SIZE):
		free_slot.history[i] = spawn_pos


func _render_lines() -> void:
	"""Render all active line trails as cylinder tubes.

	Each segment is a cylinder connecting two history positions, giving
	consistent thickness from all camera angles (matching PSX screen-space lines).
	"""
	_immediate_mesh.clear_surfaces()

	# Defer surface_begin until we know at least one segment will push vertices —
	# newly-spawned slots' first-frame contraction can be sub-epsilon and skip
	# the whole inner loop, which would make surface_end error on zero verts.
	var surface_open := false

	for slot in _line_slots:
		if not slot.active:
			continue

		# Determine how many visible segments
		var visible_segments: int
		if slot.age <= LINE_MAX_LIFETIME:
			visible_segments = mini(slot.age, HISTORY_SIZE - 1)
		else:
			visible_segments = maxi(0, HISTORY_SIZE - 1 - (slot.age - LINE_MAX_LIFETIME))
		if visible_segments < 1:
			continue

		# Walk backwards through history: newest to oldest
		var read_idx = (slot.write_index - 1 + HISTORY_SIZE) % HISTORY_SIZE
		for seg in range(visible_segments):
			var next_idx = (read_idx - 1 + HISTORY_SIZE) % HISTORY_SIZE

			var seg_start: Vector3 = slot.history[read_idx]
			var seg_end: Vector3 = slot.history[next_idx]

			var seg_dir: Vector3 = seg_end - seg_start
			if seg_dir.length_squared() < 0.0001:
				read_idx = next_idx
				continue

			if not surface_open:
				_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _shader_material)
				surface_open = true

			# Brightness from fade curve (gouraud: start and end colors differ)
			var start_bright_idx = clampi(HISTORY_SIZE - 1 - seg, 0, FADE_CURVE.size() - 1)
			var end_bright_idx = clampi(HISTORY_SIZE - 2 - seg, 0, FADE_CURVE.size() - 1)
			var start_alpha = float(FADE_CURVE[start_bright_idx]) / 255.0
			var end_alpha = float(FADE_CURVE[end_bright_idx]) / 255.0
			var col_start = Color(
				_element_color.r * start_alpha,
				_element_color.g * start_alpha,
				_element_color.b * start_alpha, 1.0)
			var col_end = Color(
				_element_color.r * end_alpha,
				_element_color.g * end_alpha,
				_element_color.b * end_alpha, 1.0)

			# Build cylinder basis perpendicular to segment direction
			var forward: Vector3 = seg_dir.normalized()
			var perp: Vector3
			if absf(forward.y) < 0.99:
				perp = forward.cross(Vector3.UP).normalized()
			else:
				perp = forward.cross(Vector3.RIGHT).normalized()
			var perp2: Vector3 = forward.cross(perp).normalized()

			# Generate ring vertices at start and end
			for i in range(CYLINDER_SIDES):
				var angle0: float = float(i) / float(CYLINDER_SIDES) * TAU
				var angle1: float = float(i + 1) / float(CYLINDER_SIDES) * TAU
				var off0: Vector3 = (perp * cos(angle0) + perp2 * sin(angle0)) * CYLINDER_RADIUS
				var off1: Vector3 = (perp * cos(angle1) + perp2 * sin(angle1)) * CYLINDER_RADIUS

				# Two triangles per quad face
				_immediate_mesh.surface_set_color(col_start)
				_immediate_mesh.surface_add_vertex(seg_start + off0)
				_immediate_mesh.surface_set_color(col_start)
				_immediate_mesh.surface_add_vertex(seg_start + off1)
				_immediate_mesh.surface_set_color(col_end)
				_immediate_mesh.surface_add_vertex(seg_end + off1)

				_immediate_mesh.surface_set_color(col_start)
				_immediate_mesh.surface_add_vertex(seg_start + off0)
				_immediate_mesh.surface_set_color(col_end)
				_immediate_mesh.surface_add_vertex(seg_end + off1)
				_immediate_mesh.surface_set_color(col_end)
				_immediate_mesh.surface_add_vertex(seg_end + off0)

			read_idx = next_idx

	if surface_open:
		_immediate_mesh.surface_end()
