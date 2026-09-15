extends SceneTree

var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not "--benchmark" in OS.get_cmdline_user_args() or DisplayServer.get_name() != "headless":
		quit(2)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.bench_done = true
	_test_blocked_follow()
	_test_modes_and_bow()
	print("CAMERA_TEST checks=", checks, " failures=", failures)
	game.free()
	quit(0 if failures == 0 else 1)

func _test_blocked_follow() -> void:
	# Hand-built opposite quay: the old y=16 camera clamp still looks through it.
	var block := AABB(Vector3(6,0,4), Vector3(25,18,20))
	if _has_property("camera_occluders"):
		game.camera_occluders.assign([block])
	game.overview = false
	game.boat.position = Vector3(-5.1,0.2,15)
	game.camera_yaw = PI/2
	game.camera_pitch = 0.7
	game.camera_distance = 28
	game.camera.position = Vector3.ZERO
	game.speed = 0
	game._update_camera(1.0)
	_check(_line_clear(game.boat.position+Vector3(0,1,0),game.camera.position,block), "Follow sightline must not pass through the opposite building")
	# Every interpolated frame matters, not only the final camera destination.
	game.camera_yaw = -PI/2
	for frame in range(25):
		game._update_camera(1.0/60.0)
		_check(_line_clear(game.boat.position+Vector3(0,1,0),game.camera.position,block), "Camera transition must retain an unobstructed boat sightline")

func _test_modes_and_bow() -> void:
	var supports: bool = game.has_method("_set_camera_mode")
	_check(supports, "A real bow first-person mode must be available")
	if not supports:
		return
	game._set_camera_mode("follow")
	_key(KEY_V)
	_check(game.camera_mode == "first_person", "V cycles follow to bow view")
	game._hud_action("view")
	_check(game.camera_mode == "overview", "HUD cycles bow to overview")
	_key(KEY_V)
	_check(game.camera_mode == "follow", "V cycles overview back to follow")
	game.boat.position = Vector3(0,0.2,15)
	for heading in [0.0,PI/2,PI,-PI/2]:
		game.heading = heading
		game._set_camera_mode("first_person")
		game._update_camera(1.0/60.0)
		var eye: Vector3 = game.camera.position-game.boat.position
		var view: Vector3 = -game.camera.global_basis.z
		var forward := Vector3(sin(heading),0,-cos(heading))
		_check(eye.y >= 1.0 and eye.y <= 2.1 and Vector2(eye.x,eye.z).length() < 1.5, "Bow camera stays at human eye height on the boat without aerial interpolation")
		_check(view.dot(forward) > 0.98, "Bow view faces the vessel heading")
	game._set_camera_mode("first_person")
	game._update_camera(0.1)
	var view_before: Vector3 = -game.camera.global_basis.z
	_button(MOUSE_BUTTON_RIGHT,true)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100,30)
	game._unhandled_input(motion)
	_button(MOUSE_BUTTON_RIGHT,false)
	game._update_camera(0.1)
	_check(view_before.distance_to(-game.camera.global_basis.z) > 0.1, "Right-drag really looks around in first person")
	var old_fov: float = game.camera.fov
	_button(MOUSE_BUTTON_WHEEL_UP,true)
	game._update_camera(0.1)
	_check(game.camera_mode == "first_person" and game.camera.fov < old_fov, "First-person zoom changes FOV without leaving the mode")
	game._set_camera_mode("follow")
	game._update_camera(0.1)
	_check(game.camera.position.y-game.boat.position.y > 14, "Returning to follow restores a high camera")

func _line_clear(a: Vector3,b: Vector3,box: AABB) -> bool:
	for i in range(1,301):
		if box.has_point(a.lerp(b,float(i)/300)):
			return false
	return true

func _has_property(name: String) -> bool:
	for item in game.get_property_list():
		if item.name == name: return true
	return false

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	game._unhandled_input(e)

func _button(button: MouseButton,pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	game._unhandled_input(e)

func _check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
