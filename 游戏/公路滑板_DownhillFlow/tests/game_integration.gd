extends SceneTree

var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func press_key(key: int) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	game._unhandled_key_input(event)

func run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	game = scene.instantiate()
	# Isolate the harness even when it is run directly without a --test flag.
	# Set this before add_child triggers _ready and loads persisted records.
	game.settings_path = "user://test_settings.cfg"
	root.add_child(game)
	await process_frame
	check(game.settings_path == "user://test_settings.cfg", "Integration harness must isolate player settings")
	check(game.ride.phase == "menu" and game.hud.menu.visible, "Game must open on visible menu")
	game.hud.start_requested.emit("challenge")
	await process_frame
	check(game.ride.phase == "riding" and game.hud.riding.visible, "Menu action must start run and show HUD")
	check(game.camera.position.distance_to(game.rider.position) < 10.0, "Follow camera must stay with rider")
	press_key(KEY_P)
	var old_time: float = game.ride.elapsed
	var old_distance: float = game.ride.distance
	for i in 5: await physics_frame
	check(game.ride.phase == "paused" and game.hud.pause_panel.visible, "P must open pause panel")
	check(game.ride.elapsed == old_time and game.ride.distance == old_distance, "Pause freezes real physics updates")
	game.hud.resume_requested.emit()
	for i in 5: await physics_frame
	check(game.ride.distance > old_distance, "Resume button must advance run")
	press_key(KEY_C)
	check(game.camera_mode == 1, "Camera cycles to wide follow")
	press_key(KEY_C)
	await process_frame
	await process_frame
	check(game.camera_mode == 2 and not game.rider.visible, "First person hides rider geometry")
	press_key(KEY_C)
	await process_frame
	await process_frame
	check(game.camera_mode == 0 and game.rider.visible, "Camera cycles back to visible skater")
	game.ride.distance = 1000.0
	press_key(KEY_R)
	check(game.ride.distance < 1.0 and game.ride.hits == 0, "R restarts run")
	game.ride.distance = 2599.95
	game.ride.elapsed = 125.0
	game.ride.speed = 15.0
	for i in 5: await physics_frame
	await process_frame
	check(game.ride.phase == "finished" and game.hud.result_panel.visible, "Crossing finish must show results")
	check(game.best_time > 0.0, "Completed run must record best time")
	var saved: ConfigFile = ConfigFile.new()
	check(saved.load(game.settings_path) == OK, "Best time must persist on disk")
	check(is_equal_approx(float(saved.get_value("records","best_time",0.0)), game.best_time), "Saved best time must match completed run to float serialization precision")
	game.hud.start_requested.emit("free")
	game.ride.distance = 2599.95
	for i in 5: await physics_frame
	check(game.ride.phase == "riding" and game.ride.laps == 1, "Free mode must loop to next lap")
	check(game.camera.position.distance_to(game.rider.position) < 10.0, "Free loop must snap camera to start instead of travelling through landscape")
	game.ride.drifting = true
	game.skid_points.assign([Vector3.ZERO,Vector3.ONE])
	press_key(KEY_P)
	game.hud.menu_requested.emit()
	await process_frame
	check(game.ride.phase == "menu" and game.hud.menu.visible, "Free ride pause must allow return to menu")
	check(game.skid_points.is_empty() and not game.ride.drifting, "Returning to menu must break drift trail continuity")
	game.hud.start_requested.emit("challenge")
	check(game.ride.mode == "challenge", "User can switch from free ride back to challenge")
	print("INTEGRATION_TESTS ", JSON.stringify({"passed":failures.is_empty(),"failures":failures,"nodes":root.get_child_count()}))
	if game.settings_path == "user://test_settings.cfg":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game.settings_path))
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
