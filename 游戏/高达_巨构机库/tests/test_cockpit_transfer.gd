extends SceneTree

var failures := 0
var machine_id := "rx78"

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("TRANSFER_FAIL " + message)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("COCKPIT_TRANSFER requires --headless")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--machine="):
			machine_id = argument.trim_prefix("--machine=")
	var known_machine := false
	for info: Dictionary in load("res://scripts/catalog.gd").machines():
		if str(info.id) == machine_id:
			known_machine = true
	if not known_machine:
		check(false, "Unknown machine id: " + machine_id)
		print("COCKPIT_TRANSFER FAIL machine=", machine_id, " failures=", failures)
		quit(1)
		return
	var game = load("res://main.tscn").instantiate()
	game.automated_test = true
	root.add_child(game)
	game.audio.set_muted(true)
	game.start()
	var bay: Variant = null
	for candidate in game.bays:
		if str(candidate.info.id) == machine_id:
			bay = candidate
	if bay == null:
		check(false, "No bay for machine id: " + machine_id)
		game.queue_free()
		await process_frame
		quit(1)
		return
	bay.state.request_lift()
	bay.state.advance(100.0)
	bay.state.open_hatch()
	bay.set_access(true, true)
	bay.tick(2.0)
	game.player.set_view(bay.exit_position(), bay.rotation.y + PI)
	game.enter_cockpit(bay)
	await wait(0.7)
	check(bay.door_amount > 0.99, "Hatch stays open while pilot crosses threshold")
	await wait(2.6)
	check(game.seated_bay == bay and not game.transition, "Entry completes")
	check(bay.door_amount < 0.1, "Hatch closes after pilot is seated")
	var seated_position: Vector3 = game.player.global_position
	game.exit_cockpit()
	await wait(0.3)
	check(game.player.global_position.distance_to(seated_position) < 0.01, "Pilot waits in seat for hatch to open")
	await wait(3.3)
	check(game.seated_bay == null and not game.transition and game.player.enabled, "Exit completes after opening")
	# Recovery while waiting for the hatch must cancel the pending exit continuation.
	bay.state.hatch_open = true
	bay.state.board()
	bay.door_amount = 0.0
	game.seated_bay = bay
	game.player.enabled = false
	game.player.global_position = bay.seat_position()
	game.exit_cockpit()
	await wait(0.1)
	game.return_to_entry()
	await wait(3.5)
	check(game.player.global_position.z > 45.0 and game.seated_bay == null and not game.transition, "Home cancels pending hatch wait")
	game.queue_free()
	await process_frame
	await process_frame
	print("COCKPIT_TRANSFER ", "PASS" if failures == 0 else "FAIL", " machine=", machine_id, " failures=", failures)
	quit(0 if failures == 0 else 1)
