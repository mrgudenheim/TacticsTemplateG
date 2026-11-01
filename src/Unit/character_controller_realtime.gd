class_name UnitControllerRT
extends Node3D


const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5

enum Directions {
	NORTHWEST,
	NORTHEAST,
	SOUTHWEST,
	SOUTHEAST,
	}

const CAMERA_FACING_VECTORS: Dictionary[Directions, Vector3] = {
	Directions.NORTHWEST: Vector3.LEFT + Vector3.FORWARD,
	Directions.NORTHEAST: Vector3.RIGHT + Vector3.FORWARD,
	Directions.SOUTHWEST: Vector3.LEFT + Vector3.BACK,
	Directions.SOUTHEAST: Vector3.RIGHT + Vector3.BACK,
	}


static var unit: UnitActor


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(unit):
		return
	
	# Add the gravity.
	#if not unit.char_body.is_on_floor():
		#unit.char_body.velocity += unit.char_body.get_gravity() * delta
	
	if not unit.can_move:
		return
	
	if get_viewport().is_input_handled() == true:
		return
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	var direction: Vector3 = (unit.char_body.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		unit.char_body.velocity.x = direction.x * SPEED
		unit.char_body.velocity.z = direction.z * SPEED
	elif not unit.is_traveling_path:
		unit.char_body.velocity.x = move_toward(unit.char_body.velocity.x, 0, SPEED)
		unit.char_body.velocity.z = move_toward(unit.char_body.velocity.z, 0, SPEED)
	
	if Input.is_action_just_pressed("secondary_action") and unit.char_body.is_on_floor():
		# https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html
		# get 3d click location based on raycast
		# TODO instead of manual raycast use CollisionObject3D.input_event signal on the map (similar to map_tile_hover): map_instance.input_event.connect(on_map_mesh_event)
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var cam: Camera3D = get_viewport().get_camera_3d()
		var mousepos: Vector2 = get_viewport().get_mouse_position()

		var origin: Vector3 = cam.project_ray_origin(mousepos)
		var end: Vector3 = origin + cam.project_ray_normal(mousepos) * 1000
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
		#query.collide_with_areas = true

		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			unit.use_ability(result["position"])


func _unhandled_input(event: InputEvent) -> void:
	if not RomReader.is_ready:
		return
	
	# Handle jump
	if event.is_action("ui_accept") and unit.char_body.is_on_floor() and unit.can_move:
		unit.char_body.velocity.y = JUMP_VELOCITY
	#elif Input.is_action_just_pressed("primary_action") and is_on_floor() and unit.can_move:
		#push_warning("primary_action_clicked")
		#unit.use_ability()
	
	# TODO implement a generic use_action system
	#if Input.is_action_just_pressed("primary_action") and unit.char_body.is_on_floor():
		#unit.use_attack()
