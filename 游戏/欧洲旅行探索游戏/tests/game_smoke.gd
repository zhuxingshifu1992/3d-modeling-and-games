extends SceneTree

var game: Node3D
var errors: Array[String] = []
var results: Dictionary = {"route": [], "screenshots": [], "assertions": 0, "interiors": [], "benchmarks": [], "door_walks": [], "stairs": []}
var frame_times: Array[float] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	results["assertions"] = int(results["assertions"]) + 1
	if not value:
		errors.append(label)
		print("SMOKE FAIL: ", label)

func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame

func run() -> void:
	if not FileAccess.file_exists("res://main.tscn"):
		check(false, "Playable scene implementation is missing")
		finish()
		return
	var packed: PackedScene = load("res://main.tscn")
	# A preexisting save deliberately differs from the title-screen camera spawn.
	# Settings/quit from the title must not overwrite the continuation position.
	var state_script: Script = load("res://scripts/travel_state.gd")
	var fixture: RefCounted = state_script.new()
	fixture.position = Vector3(-90, 0.26, -52)
	fixture.save_to("user://game_smoke_journey.json")
	game = packed.instantiate()
	game.automated_test = true
	root.gui_disable_input = true
	game.set_process_unhandled_input(false)
	game.save_path = "user://game_smoke_journey.json"
	root.add_child(game)
	current_scene = game
	var deadline: int = Time.get_ticks_msec() + 180000
	while not game.world_ready and not game.load_failed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.world_ready, "Manifest and region visuals/collisions load")
	if not game.world_ready:
		results["load_errors"] = game.load_errors
		finish()
		return
	await screenshot("title")
	var continuation: Vector3 = game.state.position
	game.handle_action("settings", game.state.settings.duplicate(true))
	var title_save: RefCounted = state_script.new()
	title_save.configure(game.state.known_landmarks, game.state.known_buildings)
	check(title_save.load_from(game.save_path) and title_save.position.is_equal_approx(continuation), "Title settings must preserve saved continuation position")
	game.start_new_trip()
	await frames(90)
	check(game.player.is_on_floor(), "Initial spawn settles on an actual collision floor")
	for region: Dictionary in game.manifest.get("regions", []):
		game.travel_to(region)
		await frames(45)
		look_at_region(region)
		game.ui.toast_remaining = 0.01
		await frames(3)
		await screenshot("station_" + str(region.get("id", "")))
		await benchmark(str(region.get("id", "")), 5.0)
		var start: Vector3 = game.player.global_position
		check(game.player.is_on_floor(), str(region.get("id", "")) + " station has supporting collision")
		Input.action_press("move_forward")
		await frames(36)
		Input.action_release("move_forward")
		var movement: float = Vector2(start.x, start.z).distance_to(Vector2(game.player.global_position.x, game.player.global_position.z))
		check(movement > 0.25, str(region.get("id", "")) + " station permits forward walking")
		results["route"].append({"region": region.get("id", ""), "walked_m": movement, "grounded": game.player.is_on_floor()})
		for building: Dictionary in game.manifest.get("buildings", []):
			if building.get("region", "") == region.get("id", "") and building.get("access", "walk") == "walk":
				await doorway_walk(building)
				break
	for landmark: Dictionary in game.manifest.get("landmarks", []):
		var action: Dictionary = landmark.duplicate(true)
		action["kind"] = "stamp"
		game.player.teleport(game.vector(action["position"]) + Vector3(50, 0, 0))
		check(not game.activate_interaction(action), "Distant landmark cannot award a stamp")
		game.player.teleport(game.vector(action["position"]) + Vector3(0.15, 0.10, 0.15))
		await frames(8)
		check(game.activate_interaction(action), "Nearby landmark awards its passport stamp")
	check(game.state.journey_complete(), "All four distinct landmarks complete the journey")
	var visits: int = 0
	var photographed: Array[String] = []
	for building: Dictionary in game.manifest.get("buildings", []):
		if building.has("inside"):
			game.player.teleport(game.vector(building["inside"]) + Vector3(0, 0.18, 0))
			await frames(20)
			game.update_proximity()
			var grounded: bool = game.player.is_on_floor()
			check(grounded, str(building["id"]) + " inside position rests on a real floor")
			var visible_parts := 0
			for item: Dictionary in game.interiors:
				if str(item.building.id) == str(building.id) and item.node.is_visible_in_tree():
					visible_parts += 1
			check(visible_parts > 0, str(building.id) + " actual interior geometry is visible after entering")
			if str(building["id"]) in game.state.visited:
				visits += 1
			results["interiors"].append({"id": building["id"], "grounded": grounded,
				"visited": str(building["id"]) in game.state.visited,
				"visible_interior_meshes": visible_parts,
				"foot_y": game.player.global_position.y,
				"expected_floor_y": building.get("floor_levels", [game.player.global_position.y])[0]})
			var region_id: String = str(building.get("region", ""))
			if region_id not in photographed:
				photographed.append(region_id)
				face_point(game.vector(building["bounds"]["center"]))
				game.player.eye.rotation.x = -0.07
				game.ui.toast_remaining = 0.01
				await frames(5)
				await screenshot("interior_" + region_id)
	results["building_inside_probes"] = visits
	check(visits == game.manifest.get("buildings", []).size(), "Every manifest building registers an interior visit")
	for building: Dictionary in game.manifest.get("buildings", []):
		if int(building.get("floors", 1)) > 1 and building.get("access", "walk") == "walk" and building.get("stair_landings", []).size() > 0:
			await stair_walk(building)
			break
	game.save_progress()
	var script: Script = load("res://scripts/travel_state.gd")
	var restored: RefCounted = script.new()
	restored.configure(game.state.known_landmarks, game.state.known_buildings)
	check(restored.load_from(game.save_path) and restored.journey_complete(), "Runtime autosave preserves completed passport")
	game.travel_to(game.manifest["regions"][0])
	await frames(30)
	game.show_map()
	await screenshot("passport_map")
	game.resume_game()
	finish()

func face_point(target: Vector3) -> void:
	var direction: Vector3 = target - game.player.global_position
	if Vector2(direction.x, direction.z).length() > 0.01:
		game.player.rotation.y = atan2(-direction.x, -direction.z)

func look_at_region(region: Dictionary) -> void:
	var target: Vector3 = game.vector(region.get("position", [0, 0, 0]))
	for landmark: Dictionary in game.manifest.get("landmarks", []):
		if landmark.get("region", "") == region.get("id", ""):
			target = game.vector(landmark["position"])
			break
	face_point(target)
	game.player.eye.rotation.x = 0.09

func drive_to(target: Vector3, maximum_seconds: float = 4.0) -> float:
	var deadline: int = Time.get_ticks_msec() + int(maximum_seconds * 1000.0)
	game.resume_game()
	while Time.get_ticks_msec() < deadline:
		var difference: Vector2 = Vector2(target.x - game.player.global_position.x, target.z - game.player.global_position.z)
		if difference.length() < 0.27:
			break
		face_point(target)
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	await frames(10)
	return Vector2(target.x - game.player.global_position.x, target.z - game.player.global_position.z).length()

func doorway_walk(building: Dictionary) -> void:
	var outside: Vector3 = game.vector(building["entrance"])
	var inside: Vector3 = game.vector(building["inside"])
	game.player.teleport(outside + Vector3(0, 0.15, 0))
	await frames(25)
	var in_distance: float = await drive_to(inside, 4.5)
	game.update_proximity()
	var arrived: bool = in_distance < 0.85 and str(building["id"]) in game.state.visited
	check(arrived, str(building["id"]) + " doorway permits actual outside-to-inside walking")
	var out_distance: float = await drive_to(outside, 4.5)
	check(out_distance < 0.85, str(building["id"]) + " doorway permits walking back outside")
	results["door_walks"].append({"id": building["id"], "entry_distance_to_goal_m": in_distance,
		"return_distance_to_goal_m": out_distance, "entry_passed": arrived, "return_passed": out_distance < 0.85})

func local_point(building: Dictionary, x: float, depth: float, floor_y: float) -> Vector3:
	var center: Vector3 = game.vector(building["bounds"]["center"])
	var angle: float = float(building.get("front_angle", 0.0))
	return Vector3(center.x + x * cos(angle) - depth * sin(angle), floor_y,
		center.z - x * sin(angle) - depth * cos(angle))

func stair_walk(building: Dictionary) -> void:
	# Route follows the documented switchback footprint; movement and elevation
	# come entirely from the real player controller against exported collisions.
	var size: Vector3 = game.vector(building["bounds"]["size"])
	var width: float = minf(2.65, size.x * 0.30)
	var stair_run: float = minf(5.35, size.z * 0.48)
	var right: float = size.x / 2.0 - 0.35
	var start: float = size.z / 2.0 - 0.35 - stair_run
	var end: float = start + stair_run - 0.9
	var lane: float = (width - 0.15) / 2.0
	var left_x: float = right - width + lane / 2.0
	var right_x: float = right - lane / 2.0
	var levels: Array = building["floor_levels"]
	var lower: float = float(levels[0])
	var upper: float = float(levels[1])
	var midpoint: float = (lower + upper) / 2.0
	game.player.teleport(local_point(building, left_x, start - 0.7, lower + 0.18))
	await frames(25)
	await drive_to(local_point(building, left_x, end + 0.32, midpoint), 5.0)
	var middle_y: float = game.player.global_position.y
	check(absf(middle_y - midpoint) < 0.4, "First stair flight reaches the intermediate landing without teleporting")
	await drive_to(local_point(building, right_x, end + 0.32, midpoint), 2.5)
	await drive_to(local_point(building, right_x, start - 0.50, upper), 5.0)
	var upper_y: float = game.player.global_position.y
	check(absf(upper_y - upper) < 0.4, "Return stair flight reaches the upper floor without teleporting")
	game.update_proximity()
	face_point(local_point(building, 0.0, 0.0, upper))
	await screenshot("stairs_upper_floor")
	await drive_to(local_point(building, right_x, end + 0.32, midpoint), 5.0)
	await drive_to(local_point(building, left_x, end + 0.32, midpoint), 2.5)
	await drive_to(local_point(building, left_x, start - 0.70, lower), 5.0)
	var return_y: float = game.player.global_position.y
	check(absf(return_y - lower) < 0.4, "Both stair flights permit returning to the original floor")
	results["stairs"].append({"id": building["id"], "expected_lower": lower, "expected_middle": midpoint,
		"expected_upper": upper, "actual_middle": middle_y, "actual_upper": upper_y, "actual_return": return_y})

func benchmark(region_id: String, seconds: float) -> void:
	var samples: Array[float] = []
	var begin: int = Time.get_ticks_usec()
	var previous: int = begin
	while Time.get_ticks_usec() - begin < int(seconds * 1000000.0):
		await process_frame
		var now: int = Time.get_ticks_usec()
		var milliseconds: float = float(now - previous) / 1000.0
		previous = now
		samples.append(milliseconds)
		frame_times.append(milliseconds)
	if samples.is_empty():
		return
	samples.sort()
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	var mean: float = total / samples.size()
	results["benchmarks"].append({"region": region_id, "samples": samples.size(), "frame_ms_mean": mean,
		"fps_average": 1000.0 / maxf(mean, 0.0001), "frame_ms_p95": samples[int(float(samples.size() - 1) * 0.95)],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"quality": game.state.settings.get("quality", 1)})

func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "res://previews/game_" + label + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews"))
	var error: Error = image.save_png(ProjectSettings.globalize_path(path))
	check(error == OK, "Viewport screenshot saved: " + label)
	if error == OK:
		results["screenshots"].append(path)

func finish() -> void:
	results["passed"] = errors.is_empty()
	results["errors"] = errors
	results["headless"] = DisplayServer.get_name() == "headless"
	results["renderer"] = RenderingServer.get_current_rendering_method()
	results["completed_unix"] = Time.get_unix_time_from_system()
	results["static_memory_mb"] = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	if not frame_times.is_empty():
		frame_times.sort()
		var total: float = 0.0
		for value: float in frame_times:
			total += value
		results["frame_samples"] = frame_times.size()
		results["frame_ms_mean"] = total / frame_times.size()
		results["frame_ms_p95"] = frame_times[int(float(frame_times.size() - 1) * 0.95)]
		results["fps_average"] = 1000.0 / float(results["frame_ms_mean"])
		results["performance_scope"] = "Headless timing is logic throughput, not rendered FPS." if results["headless"] else "Five-second rendered sample at each of four stations, balanced settings; not a whole-game frame-rate guarantee."
	# Preserve the actual rendered benchmark when rerunning logic headlessly.
	var output_path := "res://tests/game_headless_result.json" if results["headless"] else "res://tests/game_smoke_result.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):
			output_path = arg.trim_prefix("--result=")
	var report: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify(results, "\t"))
		report.close()
	print("GAME_SMOKE_RESULT ", JSON.stringify(results))
	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0 if errors.is_empty() else 1)
