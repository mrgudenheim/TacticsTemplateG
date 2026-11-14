class_name CameraController
extends Node3D

@export var camera: Camera3D

signal zoom_changed(new_zoom: float)
signal rotated(new_rotation: Vector3)
signal camera_facing_changed(new_camera_facing_vector: Vector3)

@export var pan_speed_max: float = 10
@export var pan_accel: float = 10
@export var rotate_speed_max: float = 5
@export var rotate_accel: float = 5
@export var rotate_increment: float = 90.0 # degrees
@export var time_to_rotate: float = 0.5 # seconds

# https://ffhacktics.com/wiki/Camera
@export var low_angle: float = 26.54
@export var high_angle: float = 39.37

var zoom: float = 12:
	get:
		return zoom
	set(value):
		zoom = value
		zoom_changed.emit(zoom)
@export var zoom_out_max: float = 100
@export var zoom_in_max: float = 0.01

@export var follow_node: Node3D = null:
	get:
		return follow_node
	set(value):
		if value != follow_node:
			follow_node = value
			start_transitioning()
@export var time_to_transition: float = 0.35 # seconds
var is_transitioning: bool = false
@export var transition_curve: Curve
var transition_start_pos: Vector3
var transition_time: float = 0.0

var pan_direction: Vector2 = Vector2.ZERO

enum Direction {
	NORTHWEST,
	NORTHEAST,
	SOUTHWEST,
	SOUTHEAST,
	}

const CameraFacingVectors: Dictionary[Direction, Vector3] = {
	Direction.NORTHWEST: Vector3.LEFT + Vector3.FORWARD,
	Direction.NORTHEAST: Vector3.RIGHT + Vector3.FORWARD,
	Direction.SOUTHWEST: Vector3.LEFT + Vector3.BACK,
	Direction.SOUTHEAST: Vector3.RIGHT + Vector3.BACK,
	}

var is_rotating: bool = false
var camera_facing: Direction = Direction.NORTHWEST
var camera_facing_vector: Vector3:
	get: return CameraFacingVectors[camera_facing]


func _ready() -> void:
	camera.size = zoom


func _process(delta: float) -> void:
	if is_transitioning and follow_node != null:
		transition_time += delta
		var transition_percent: float = transition_time / time_to_transition
		var position_percent: float = transition_curve.sample(transition_percent)
		global_position = transition_start_pos.lerp(follow_node.global_position, position_percent)
		if transition_percent >= 1.0:
			is_transitioning = false
	elif follow_node != null:
		global_position = follow_node.global_position
	elif follow_node == null:
		var transform_basis: Basis = transform.basis
		transform_basis.y = Vector3.DOWN # camera should not move in/out of the direction it is facing
		position += (transform_basis * Vector3(pan_direction.x, pan_direction.y, 0)) * zoom * (pan_speed_max / 5.0) * delta


func start_transitioning() -> void:
	#if is_transitioning == true: # never reached it's previous target
		#pass # TODO keep momentum
	is_transitioning = true
	transition_start_pos = global_position
	transition_time = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"zoom_in", false, true):  # Wheel Up Event
		zoom_camera(1)
	elif event.is_action_pressed(&"zoom_out", false, true):  # Wheel Down Event
		zoom_camera(-1)
	if event.is_action_pressed(&"camera_rotate_left", true):
		start_rotating_camera(-1)
	elif event.is_action_pressed(&"camera_rotate_right", true):
		start_rotating_camera(1)
	elif follow_node == null:
		pan_direction = Input.get_vector(&"camera_left", &"camera_right", &"camera_up", &"camera_down")
		#var dir := Input.get_vector(&"camera_left", &"camera_right", &"camera_up", &"camera_down")
		#if dir != Vector2.ZERO:
			#pan_camera(dir)


func zoom_camera(dir: int) -> void:
	var zoom_margin: float = zoom * (-dir) / 5
	var new_zoom: float = zoom + zoom_margin
	if new_zoom < zoom_out_max and new_zoom > zoom_in_max:
		var tween: Tween = create_tween().set_parallel() # TODO use curve for camera zoom smoothing, similar to node following
		tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
		tween.tween_property(camera, "size", new_zoom, 0.05)
		await tween.finished
		update_distance()
		zoom = new_zoom
		


#func pan_camera(dir: Vector2) -> void:
	#var new_position: Vector3 = Vector3.ZERO
	#var offset: Vector2 = dir * zoom * pan_speed_max
	#
	#var new_x = self.position.x + offset.x
	#var new_y = self.position.y - offset.y
	#var new_z = self.position.z
	#new_position = Vector3(new_x, new_y, new_z)
	#
	#var tween := create_tween().set_parallel()
	#tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	#tween.tween_property(self, "position", new_position, 0.05)


func start_rotating_camera(dir: int) -> void:
	if is_rotating:
		return
	
	is_rotating = true
	var new_rotation: Vector3 = rotation_degrees
	var offset: float = dir * rotate_increment # * delta
	new_rotation.y = new_rotation.y + offset
	
	var tween: Tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.tween_method(rotate_camera, rotation_degrees, new_rotation, time_to_rotate)
	await tween.finished
	
	#push_warning(str(camera_facing))
	is_rotating = false

func rotate_camera(new_rotation_degrees: Vector3) -> void:
	rotation_degrees = new_rotation_degrees
	rotated.emit(Vector3(0, new_rotation_degrees.y, 0))
	
	var camera_angle: float = rotation_degrees.y
	#var target_angle = fposmod(new_rotation_degress.y, 360)
	var camera_angle_pos: float = fposmod(camera_angle, 360)
		
	var new_camera_facing: Direction = Direction.NORTHEAST
	if camera_angle_pos < 90:
		new_camera_facing = Direction.NORTHWEST
	elif camera_angle_pos < 180:
		new_camera_facing = Direction.SOUTHWEST
	elif camera_angle_pos < 270:
		new_camera_facing = Direction.SOUTHEAST
	elif camera_angle_pos < 360:
		new_camera_facing = Direction.NORTHEAST
	
	if new_camera_facing != camera_facing:
		camera_facing = new_camera_facing
		camera_facing_changed.emit(CameraFacingVectors[camera_facing])


func on_orthographic_toggled(toggled_on: bool) -> void:
	if toggled_on:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = camera.position.z * 12.0 / 8.0
		camera.position.z = 200
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position.z = camera.size * 8.0 / 12.0


func update_distance() -> void:
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		camera.position.z = camera.size * 8.0 / 12.0
