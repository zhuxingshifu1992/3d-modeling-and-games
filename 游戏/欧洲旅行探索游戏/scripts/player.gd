extends CharacterBody3D

signal footstep
var enabled: bool = false:
	set(value):
		enabled = value
		if not value:
			velocity = Vector3.ZERO
var sensitivity: float = 0.0018
var eye: Node3D
var camera: Camera3D
var walked: float = 0.0
var previous_position: Vector3
var gait_phase := 0.0

func _ready() -> void:
	name = "Traveler"
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(45.0)
	floor_stop_on_slope = true
	safe_margin = 0.001
	collision_layer = 2
	collision_mask = 1
	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.91
	add_child(collision)
	eye = Node3D.new()
	eye.position.y = 1.65
	add_child(eye)
	camera = Camera3D.new()
	camera.fov = 76.0
	camera.near = 0.07
	camera.far = 1000.0
	camera.current = true
	eye.add_child(camera)
	previous_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	# Keep the pointer visible and free to leave the window. Camera motion
	# requires the user to deliberately hold the right mouse button.
	if enabled and event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and get_viewport().get_visible_rect().has_point(event.position):
		rotate_y(-event.relative.x * sensitivity)
		eye.rotation.x = clampf(eye.rotation.x - event.relative.y * sensitivity, -1.35, 1.35)

func teleport(destination: Vector3, facing: float = 0.0) -> void:
	global_position = destination
	rotation.y = facing
	velocity = Vector3.ZERO
	previous_position = destination
	walked = 0.0
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed: float = 4.3 if Input.is_action_pressed("run") else 2.2
	velocity.x = move_toward(velocity.x, direction.x * speed, 18.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 18.0 * delta)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = 5.1
	else:
		velocity.y = -0.15
	# Lift the capsule only over a confirmed low obstruction, never through a
	# full wall or ceiling. A downward test requires a supporting tread.
	if is_on_floor() and direction.length_squared() > 0.1 and velocity.y <= 0.0:
		var forward: Vector3 = direction * 0.34
		if test_move(global_transform, forward):
			var raised: Transform3D = global_transform
			raised.origin += Vector3.UP * 0.26
			if not test_move(global_transform, Vector3.UP * 0.26) and not test_move(raised, forward):
				raised.origin += forward
				if test_move(raised, Vector3.DOWN * 0.30):
					global_position.y += 0.26
	move_and_slide()
	var horizontal_speed := Vector2(velocity.x,velocity.z).length()
	gait_phase += horizontal_speed * delta * 6.0
	var bob := sin(gait_phase)*0.012 if is_on_floor() and horizontal_speed>0.2 else 0.0
	eye.position.y = lerpf(eye.position.y,1.65+bob,minf(1.0,delta*12.0))
	if is_on_floor():
		walked += Vector2(global_position.x, global_position.z).distance_to(Vector2(previous_position.x, previous_position.z))
		if walked > 1.8:
			walked = 0.0
			footstep.emit()
	previous_position = global_position
