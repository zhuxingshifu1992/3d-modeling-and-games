extends CharacterBody3D

var camera: Camera3D
var lamp: SpotLight3D
var enabled := false
var look_enabled := false
var sensitivity := 0.0021
var crouching := false
var step_distance := 0.0
signal footstep

func _ready() -> void:
	name = "Pilot"
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.875
	add_child(collision)
	camera = Camera3D.new()
	camera.name = "HumanEyes"
	camera.position.y = 1.65
	camera.fov = 65.0
	camera.near = 0.045
	camera.far = 250.0
	camera.current = true
	add_child(camera)
	lamp = SpotLight3D.new()
	lamp.light_color = Color(0.8, 0.9, 1.0)
	lamp.light_energy = 2.1
	lamp.spot_range = 18.0
	lamp.spot_angle = 32.0
	lamp.visible = false
	camera.add_child(lamp)
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(48)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and look_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * sensitivity
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sensitivity, deg_to_rad(-82), deg_to_rad(85))

func _physics_process(delta: float) -> void:
	if not enabled:
		velocity = Vector3.ZERO
		return
	var direction := Input.get_vector("left", "right", "forward", "back")
	crouching = Input.is_action_pressed("crouch")
	var speed := 1.6
	if Input.is_action_pressed("sprint"):
		speed = 3.2
	if crouching:
		speed = 0.85
	var move := transform.basis * Vector3(direction.x, 0, direction.y)
	velocity.x = move.x * speed
	velocity.z = move.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.2
	move_and_slide()
	camera.position.y = move_toward(camera.position.y, 1.05 if crouching else 1.65, delta * 3.5)
	var distance := Vector2(velocity.x, velocity.z).length() * delta
	if is_on_floor():
		step_distance += distance
		if step_distance > (0.95 if Input.is_action_pressed("sprint") else 0.8):
			step_distance = 0.0
			footstep.emit()

func set_view(at: Vector3, yaw: float, pitch: float = 0.0) -> void:
	position = at
	rotation.y = yaw
	camera.rotation.x = pitch
	camera.position = Vector3(0, 1.65, 0)
	velocity = Vector3.ZERO
