extends SceneTree
## Drives the real game with movement inputs and interactions; screenshots are actual GPU frames.

var game
var failures := 0
var checks := 0
var out_dir := "res://previews/walkthrough"
var selected_id := ""
var fps_samples: Array[float] = []
var started_at := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			selected_id = arg.trim_prefix("--only=")
		if arg.begins_with("--output="):
			out_dir = arg.trim_prefix("--output=")
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WALK_FAIL " + text)
	else:
		print("WALK_OK ", text)

func wait(seconds: float) -> void:
	await create_timer(seconds, true).timeout

func wait_for_lift(bay, timeout: float = 20.0) -> void:
	var elapsed := 0.0
	while bay.state.moving and elapsed < timeout:
		await wait(0.1)
		elapsed += 0.1
	await wait(0.15)

func walk_until(condition: Callable, timeout: float = 5.0) -> void:
	var elapsed := 0.0
	Input.action_press("forward")
	while not condition.call() and elapsed < timeout:
		await wait(0.05)
		elapsed += 0.05
	Input.action_release("forward")
	await wait(0.08)

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	var error := img.save_png(path)
	check(error == OK, "GPU screenshot " + name)
	fps_samples.append(float(Engine.get_frames_per_second()))

func run() -> void:
	started_at = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	game = load("res://main.tscn").instantiate()
	game.automated_test = true
	root.add_child(game)
	await wait(2.0)
	if "--low" in OS.get_cmdline_user_args():
		check(game.get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "Low mode disables main antialiasing")
		check(game.bays[0].monitor_viewport.size == Vector2i(384, 216), "Low mode reduces sensor resolution")
		var shadow_count := 0
		for light in game.world.find_children("*", "Light3D", true, false):
			if light.shadow_enabled:
				shadow_count += 1
		check(shadow_count == 0, "Low mode disables world shadows")
	game.profile.path = "user://walkthrough_test_profile.json"
	game.profile.completed = []
	await shot("00_menu")
	game.start()
	await wait(0.5)
	await shot("01_ground")
	check(game.player.camera.position.y > 1.64 and game.player.camera.position.y < 1.66, "Standing human eye height")
	for index in range(game.bays.size()):
		var bay = game.bays[index]
		if not selected_id.is_empty() and bay.info.id != selected_id:
			continue
		game.select_bay(index)
		game.player.set_view(bay.to_global(Vector3(0, 0.20, -10.6)), bay.rotation.y + PI, 0.48)
		await wait(0.3)
		Input.action_press("forward")
		await wait(1.9)
		Input.action_release("forward")
		await wait(0.2)
		print("PLATFORM_APPROACH ", bay.info.id, " local=", bay.to_local(game.player.global_position))
		check(bay.on_platform(game.player.global_position), bay.info.id + " physically walked onto platform")
		if not bay.on_platform(game.player.global_position):
			continue
		game.interact()
		check(bay.state.moving and game.riding == bay, bay.info.id + " platform activated")
		game.interact()
		await wait(2.8)
		await shot(bay.info.id + "_02_rising")
		var paused_height: float = bay.state.y
		game.pause_game()
		await wait(0.25)
		check(is_equal_approx(paused_height, bay.state.y), bay.info.id + " pause freezes physical platform")
		var escape := InputEventAction.new()
		escape.action = "pause"
		escape.pressed = true
		Input.parse_input_event(escape)
		await wait(0.1)
		check(not game.paused and not paused, bay.info.id + " Escape resumes paused game")
		if game.paused:
			game.resume()
		await wait_for_lift(bay)
		check(bay.state.at_top and not bay.state.moving and game.riding == null, bay.info.id + " arrival unlocks walking")
		check(absf(game.player.global_position.y - bay.top_y - 0.12) < 0.15, bay.info.id + " pilot stays on platform deck")
		if index == 0:
			game.player.rotation.y = bay.rotation.y
			Input.action_press("forward")
			await wait(1.6)
			Input.action_release("forward")
			check(bay.to_local(game.player.global_position).z > -9.05 and game.player.global_position.y > bay.top_y, "Top rear gate prevents backward fall")
		game.player.rotation.y = bay.rotation.y + PI
		game.player.camera.rotation.x = 0.0
		await walk_until(func(): return bay.near_hatch(game.player.global_position))
		print("HATCH_APPROACH ", bay.info.id, " local=", bay.to_local(game.player.global_position), " yaw=", game.player.rotation.y, " expected=", bay.rotation.y + PI)
		check(bay.near_hatch(game.player.global_position), bay.info.id + " physically walked across bridge")
		if not bay.near_hatch(game.player.global_position):
			game.return_to_entry()
			continue
		game.interact()
		await wait(1.5)
		check(bay.state.hatch_open and bay.door_collision.disabled, bay.info.id + " hatch visibly opens and unblocks")
		await shot(bay.info.id + "_03_hatch")
		game.interact()
		await wait(2.3)
		check(game.seated_bay == bay and bay.state.seated and not game.transition, bay.info.id + " seated at human scale")
		for stage in range(3):
			game.interact()
			await wait(0.35)
		check(bay.state.boot_stage == 3 and bay.info.id in game.profile.completed, bay.info.id + " complete startup recorded")
		check(bay.monitor_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, bay.info.id + " live exterior sensor enabled")
		await wait(0.8)
		await shot(bay.info.id + "_04_cockpit")
		game.interact()
		await wait(3.5)
		check(game.seated_bay == null and game.player.enabled and not bay.state.seated, bay.info.id + " leave cockpit restores walking")
		check(bay.monitor_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, bay.info.id + " inactive sensor stops rendering")
		game.player.rotation.y = bay.rotation.y
		await walk_until(func(): return bay.on_platform(game.player.global_position))
		check(bay.on_platform(game.player.global_position), bay.info.id + " physically returned to platform")
		game.interact()
		check(bay.state.moving and game.riding == bay, bay.info.id + " descent activated")
		await wait_for_lift(bay)
		check(not bay.state.moving and not bay.state.at_top and absf(game.player.global_position.y - 0.12) < 0.2, bay.info.id + " full boarding round trip")
		game.return_to_entry()
	# Recovery while an actual boarding animation is in progress.
	var b = game.bays[0]
	b.state.request_lift()
	b.state.advance(100.0)
	b.tick(2.0)
	b.state.open_hatch()
	b.tick(2.0)
	game.player.set_view(b.exit_position(), b.rotation.y + PI)
	game.enter_cockpit(b)
	await wait(0.25)
	game.pause_game()
	game.return_to_entry()
	await wait(2.3)
	check(game.seated_bay == null and not game.transition and game.player.global_position.z > 45, "Returning to entry cancels boarding animation")
	game.profile.read()
	check(game.profile.completed.size() == (1 if not selected_id.is_empty() else 6), "Visited records survive disk reload")
	var summary := {"checks": checks, "failures": failures, "gpu": DisplayServer.get_name() != "headless", "fps_samples": fps_samples, "elapsed_seconds": (Time.get_ticks_msec() - started_at) / 1000.0}
	var file := FileAccess.open(out_dir.path_join("walkthrough_result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print("WALKTHROUGH ", "PASS" if failures == 0 else "FAIL", " ", JSON.stringify(summary))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://walkthrough_test_profile.json"))
	quit(0 if failures == 0 else 1)
