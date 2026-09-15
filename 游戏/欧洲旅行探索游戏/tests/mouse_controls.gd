extends SceneTree
## Headless regression: the visible desktop pointer is never captured.
## Events are synthesized inside this Viewport; no OS mouse input is sent.

var game: Node3D
var errors: Array[String] = []
var results: Dictionary = {"checks": [], "started_unix": Time.get_unix_time_from_system(), "dispatch": "Viewport.push_input in headless process; no desktop pointer events"}

func result_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):
			return arg.trim_prefix("--result=")
	return "res://tests/mouse_controls_result.json"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	results["checks"].append({"name": label, "passed": ok, "mouse_mode": Input.mouse_mode})
	if not ok:
		errors.append(label)
		print("MOUSE_CONTROL_FAIL ", label)

func frames(count: int = 2) -> void:
	for _i: int in range(count):
		await physics_frame

func view_angles() -> Vector2:
	return Vector2(game.player.rotation.y, game.player.eye.rotation.x)

func visible_pointer(label: String) -> void:
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, label)

func motion(relative: Vector2, buttons: int, at: Vector2 = Vector2(-1, -1)) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_visible_rect().size * 0.5 if at == Vector2(-1, -1) else at
	event.global_position = event.position
	event.relative = relative
	event.button_mask = buttons
	root.push_input(event, true)
	await frames()

func right_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_visible_rect().size * 0.5
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
	root.push_input(event, true)
	await frames()

func run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	game = scene.instantiate()
	game.automated_test = true
	game.save_path = "user://mouse_controls_isolated_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec() + 180000
	while not game.world_ready and not game.load_failed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.world_ready, "Actual main scene loads")
	if not game.world_ready:
		results["load_errors"] = game.load_errors
		await finish()
		return
	visible_pointer("Startup leaves pointer visible and uncaptured")
	game.start_new_trip()
	await frames(15)
	visible_pointer("Starting a trip leaves pointer visible and uncaptured")
	var original := view_angles()
	await motion(Vector2(85, -34), 0)
	check(view_angles().is_equal_approx(original), "Motion with no button does not move camera")
	visible_pointer("Ordinary mouse motion does not capture pointer")
	await motion(Vector2(-62, 24), MOUSE_BUTTON_MASK_LEFT)
	check(view_angles().is_equal_approx(original), "Left-button motion does not move camera")
	await right_button(true)
	await motion(Vector2(80, -25), MOUSE_BUTTON_MASK_RIGHT)
	var dragged := view_angles()
	var expected: Vector2 = original + Vector2(-80, 25) * float(game.player.sensitivity)
	check(dragged.distance_to(expected) < 0.0002, "Holding right button rotates yaw and pitch by expected motion")
	visible_pointer("Right-button look never captures or confines pointer")
	await right_button(false)
	await motion(Vector2(90, 50), 0)
	check(view_angles().is_equal_approx(dragged), "Releasing right button stops camera rotation")
	visible_pointer("Released pointer remains visible and free")
	game.pause_game()
	await motion(Vector2(110, 45), MOUSE_BUTTON_MASK_RIGHT)
	check(view_angles().is_equal_approx(dragged), "Paused player ignores right-button motion")
	visible_pointer("Pause leaves pointer visible")
	game.resume_game()
	await frames()
	visible_pointer("Resume leaves pointer visible without capture")
	await motion(Vector2(75, -10), 0)
	check(view_angles().is_equal_approx(dragged), "Resume does not turn ordinary pointer motion into look")
	await right_button(true)
	var before_edge := view_angles()
	await motion(Vector2(40, 12), MOUSE_BUTTON_MASK_RIGHT, root.get_visible_rect().size + Vector2(25, 25))
	check(view_angles().is_equal_approx(before_edge), "Dragging outside viewport does not rotate the camera")
	await right_button(false)
	await right_button(true)
	game.pause_game()
	game.resume_game()
	var before_resume := view_angles()
	await right_button(false)
	await motion(Vector2(70, 20), 0)
	check(view_angles().is_equal_approx(before_resume), "Released drag stays stopped after pause and resume")
	await right_button(false)
	await right_button(true)
	await motion(Vector2(10, 5), MOUSE_BUTTON_MASK_RIGHT)
	check(not view_angles().is_equal_approx(before_resume), "A new press enables look after pause")
	await right_button(false)
	Input.action_press("move_forward")
	await frames(30)
	game.pause_game()
	Input.action_release("move_forward")
	var paused_position: Vector3 = game.player.global_position
	await frames(15)
	check(game.player.global_position.distance_to(paused_position) < 0.0001, "Paused avatar does not move")
	game.resume_game()
	await frames(15)
	check(Vector2(game.player.global_position.x, game.player.global_position.z).distance_to(Vector2(paused_position.x, paused_position.z)) < 0.01, "Resume after releasing movement does not revive old momentum")
	await right_button(true)
	game.automated_test = false
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.automated_test = true
	await frames()
	check(game.modal == "pause" and not game.player.enabled, "Application focus loss pauses gameplay")
	var unfocused_angles := view_angles()
	await motion(Vector2(80, 30), MOUSE_BUTTON_MASK_RIGHT)
	check(view_angles().is_equal_approx(unfocused_angles), "Unfocused avatar ignores dragging")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	visible_pointer("Focus return leaves pointer visible")
	check(game.modal == "pause" and not game.player.enabled, "Focus return does not resume gameplay automatically")
	game.resume_game()
	await right_button(false)
	await motion(Vector2(30, 15), 0)
	check(view_angles().is_equal_approx(unfocused_angles), "Releasing right button while unfocused does not cause resumed look")
	await right_button(false)
	results["headless"] = DisplayServer.get_name() == "headless"
	results["initial_angles"] = [original.x, original.y]
	results["dragged_angles"] = [dragged.x, dragged.y]
	await finish()

func finish() -> void:
	if is_instance_valid(game):
		game.player.enabled = false
		game.ambience.set_process(false)
		game.ambience.active = false
		game.ambience.player.stop()
		game.ambience.steps.stop()
		game.ambience.playback = null
		game.ambience.player.stream = null
		game.ambience.steps.stream = null
		current_scene = null
		game.queue_free()
		game = null
		var deadline := Time.get_ticks_msec() + 180
		while Time.get_ticks_msec() < deadline:
			await process_frame
	results["passed"] = errors.is_empty()
	results["errors"] = errors
	results["completed_unix"] = Time.get_unix_time_from_system()
	results["coverage_limits"] = ["Headless viewport event dispatch and notification simulation only; no OS focus, cursor position, window manager, DPI, or multi-monitor integration exercised."]
	var file := FileAccess.open(result_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(results, "\t"))
		file.close()
	print("MOUSE_CONTROLS_RESULT ", JSON.stringify(results))
	quit(0 if errors.is_empty() else 1)
