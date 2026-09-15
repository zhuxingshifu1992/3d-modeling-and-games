extends SceneTree

## Run after GPU benchmarking finishes:
## godot --headless --path . --script res://tests/test_controls.gd -- --benchmark --low
## Calls the real input handlers with local event objects. Never injects system
## input, presses F11, changes window modes, or writes the player's save file.
const MainScene: Script = preload("res://scripts/main.gd")

var _game: Node3D
var _checks: int = 0
var _failures: int = 0
var _save_existed: bool = false
var _save_before: String = ""
var _window_mode_before: DisplayServer.WindowMode


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless" or not "--benchmark" in OS.get_cmdline_user_args():
		printerr("Controls test requires --headless and -- --benchmark; no desktop window or player save may be changed.")
		quit(2)
		return
	_save_existed = FileAccess.file_exists("user://save.json")
	if _save_existed:
		_save_before = FileAccess.get_file_as_string("user://save.json")
	_window_mode_before = DisplayServer.window_get_mode()
	_game = MainScene.new()
	root.add_child(_game)
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.bench_done = true
	_game.bench_seconds = 1000000000.0
	_game.muted = true
	_check(_game.started and _game.benchmark and _game.camera != null, "Controls fixture must use the real started main scene in benchmark mode")
	_test_right_drag()
	_test_zoom()
	_test_overview_key()
	_test_left_water_click()
	_test_pause_input()
	_test_quality_action()
	_check(DisplayServer.window_get_mode() == _window_mode_before, "Input tests must leave the desktop window mode unchanged")
	_check(FileAccess.file_exists("user://save.json") == _save_existed, "Input tests must not create or remove the player save")
	if _save_existed:
		_check(FileAccess.get_file_as_string("user://save.json") == _save_before, "Input tests must not alter the player save")
	print("Controls integration: %d checks, %d failures" % [_checks, _failures])
	_game.free()
	quit(0 if _failures == 0 else 1)


func _test_right_drag() -> void:
	_game.camera_yaw = 0.2
	_game.camera_pitch = 0.7
	var yaw_before: float = _game.camera_yaw
	var pitch_before: float = _game.camera_pitch
	_motion(Vector2(50.0, 30.0))
	_check(_game.camera_yaw == yaw_before and _game.camera_pitch == pitch_before, "Pointer motion without a right-button drag must not orbit the camera")
	_button(MOUSE_BUTTON_RIGHT, true)
	_check(_game.rotating_camera, "Right-button press must begin camera orbit")
	_motion(Vector2(50.0, 30.0))
	_check(_game.camera_yaw < yaw_before and _game.camera_pitch > pitch_before, "A held right-button drag must change both camera yaw and pitch")
	_check(_game.orbit_timeout > 0.0, "Manual orbit must temporarily preserve the user's camera angle")
	_motion(Vector2(0.0, 10000.0))
	_check(is_equal_approx(float(_game.camera_pitch), 1.3), "Camera pitch must stop at its upper viewing limit")
	_motion(Vector2(0.0, -10000.0))
	_check(is_equal_approx(float(_game.camera_pitch), 0.32), "Camera pitch must stop at its lower viewing limit")
	_button(MOUSE_BUTTON_RIGHT, false)
	_check(not _game.rotating_camera, "Right-button release must end camera orbit")
	yaw_before = _game.camera_yaw
	pitch_before = _game.camera_pitch
	_motion(Vector2(50.0, 30.0))
	_check(_game.camera_yaw == yaw_before and _game.camera_pitch == pitch_before, "Motion after releasing the right button must leave camera angles unchanged")


func _test_zoom() -> void:
	_game.camera_distance = 28.0
	_game.overview = true
	_button(MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(float(_game.camera_distance), 26.0), "An upward wheel step must bring the camera closer")
	_check(not _game.overview, "Zooming inward must return from overview to the boat camera")
	for wheel_index: int in range(60):
		_button(MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(float(_game.camera_distance), 11.0), "Repeated inward wheel input must clamp camera distance to 11")
	for wheel_index: int in range(60):
		_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_check(is_equal_approx(float(_game.camera_distance), 56.0), "Repeated outward wheel input must clamp camera distance to 56")
	_button(MOUSE_BUTTON_WHEEL_UP, false)
	_check(is_equal_approx(float(_game.camera_distance), 56.0), "Wheel release events must not apply an extra zoom step")


func _test_overview_key() -> void:
	_game.overview = false
	_key(KEY_V)
	_check(_game.camera_mode == "first_person", "V must switch follow to the requested bow first-person view")
	_key(KEY_V, true, true)
	_check(_game.camera_mode == "first_person", "Keyboard auto-repeat must not flicker the view")
	_key(KEY_V, false)
	_check(_game.camera_mode == "first_person", "V release must not cycle the view again")
	_key(KEY_V)
	_check(_game.overview, "A second distinct V press must enter overview")
	_key(KEY_V)
	_check(_game.camera_mode == "follow", "The third V press must return to high follow")


func _test_left_water_click() -> void:
	_game.camera_yaw = 0.0
	_game.camera_pitch = 0.7
	_game.camera_distance = 28.0
	_game.overview = false
	_game._update_camera(1.0)
	var water_point: Vector3 = Vector3(0.0, 0.25, 22.0)
	var pixel: Vector2 = _game.camera.unproject_position(water_point)
	_check(pixel.is_finite(), "The visible canal fixture must project to a finite screen position")
	_check(not _game.camera.is_position_behind(water_point), "The water click fixture must be in front of the active camera")
	_game.route_nodes.clear()
	_button(MOUSE_BUTTON_LEFT, false, pixel)
	_check(_game.route_nodes.is_empty(), "Left-button release must not create a navigation route")
	_button(MOUSE_BUTTON_LEFT, true, pixel)
	_check(not _game.route_nodes.is_empty(), "Left-clicking visible canal water must create a real navigation route")
	if _game.route_nodes.is_empty():
		return
	var last: Vector3 = _game.route_nodes[-1]
	_check(Vector2(last.x - water_point.x, last.z - water_point.z).length() < 0.05, "The input ray must navigate to the clicked water position")
	_check(_game.route_visual.visible and _game.destination_marker.visible, "A water click must display its route and destination")
	var previous: Vector3 = _game.boat.position
	var all_water: bool = true
	for waypoint: Vector3 in _game.route_nodes:
		var samples: int = maxi(1, int(ceil(previous.distance_to(waypoint) / 0.25)))
		for sample_index: int in range(samples + 1):
			if not _game.voyage.is_water(previous.lerp(waypoint, float(sample_index) / float(samples))):
				all_water = false
		previous = waypoint
	_check(all_water, "A route produced by the mouse input handler must remain on navigable water")


func _test_pause_input() -> void:
	_button(MOUSE_BUTTON_RIGHT, true)
	_key(KEY_ESCAPE)
	_check(_game.paused_game and not _game.rotating_camera, "Escape must pause the game and release an active camera drag")
	var yaw_before: float = _game.camera_yaw
	var pitch_before: float = _game.camera_pitch
	var distance_before: float = _game.camera_distance
	var route_before: Array[Vector3] = _game.route_nodes.duplicate()
	var boat_before: Vector3 = _game.boat.position
	_button(MOUSE_BUTTON_RIGHT, true)
	_motion(Vector2(120.0, 80.0))
	_button(MOUSE_BUTTON_WHEEL_UP, true)
	var paused_pixel: Vector2 = _game.camera.unproject_position(Vector3(0.0, 0.25, 15.0))
	_button(MOUSE_BUTTON_LEFT, true, paused_pixel)
	for tick_index: int in range(60):
		_game._physics_process(1.0 / 60.0)
	_check(not _game.rotating_camera and _game.camera_yaw == yaw_before and _game.camera_pitch == pitch_before, "Paused mouse drags must not change the camera orbit")
	_check(_game.camera_distance == distance_before and _game.route_nodes == route_before, "Paused zoom and water clicks must not change camera distance or the active route")
	_check(_game.boat.position == boat_before, "Pause entered through the real key handler must freeze navigation physics")
	_key(KEY_ESCAPE, true, true)
	_check(_game.paused_game, "Escape auto-repeat must not immediately resume a paused game")
	_key(KEY_ESCAPE)
	_check(not _game.paused_game, "A new Escape press must resume the game")
	_game._hud_action("pause")
	_check(_game.paused_game, "The HUD pause action must enter the same paused state")
	_game._hud_action("resume")
	_check(not _game.paused_game, "The HUD resume action must release pause")


func _test_quality_action() -> void:
	if _game.quality != "流畅":
		_game._hud_action("quality")
	var viewport: Viewport = _game.get_viewport()
	_check(_game.quality == "流畅" and is_equal_approx(viewport.scaling_3d_scale, 0.72), "Low quality must set the 3D rendering scale to 72 percent")
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED, "Low quality must disable multisample antialiasing")
	_game._hud_action("quality")
	_check(_game.quality == "标准" and is_equal_approx(viewport.scaling_3d_scale, 0.9), "The quality HUD action must switch to standard with 90 percent rendering scale")
	_check(viewport.msaa_3d == Viewport.MSAA_2X, "Standard quality must enable 2x multisample antialiasing")
	_check(viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "Compatibility rendering must keep unsupported screen-space antialiasing disabled")
	_game._hud_action("quality")
	_check(_game.quality == "流畅" and is_equal_approx(viewport.scaling_3d_scale, 0.72) and viewport.msaa_3d == Viewport.MSAA_DISABLED, "A second quality action must restore the complete low-quality configuration")


func _button(index: MouseButton, pressed: bool, position: Vector2 = Vector2.ZERO) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = position
	_game._unhandled_input(event)


func _motion(relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	_game._unhandled_input(event)


func _key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	_game._unhandled_input(event)


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL: " + description)
