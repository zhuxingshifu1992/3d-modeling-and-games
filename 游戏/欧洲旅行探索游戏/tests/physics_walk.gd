extends SceneTree
## Real Traveler capsule tests against the installed main-scene collision.
## Teleports are used only to set up independent cases and by actual lifts.
## Door/stair distances are produced exclusively by move_forward physics input.

var game: Node3D
var errors: Array[String] = []
var results: Dictionary = {"doors": [], "lifts": [], "stairs": [], "assertions": 0, "started_unix": Time.get_unix_time_from_system()}
var stairs_only: bool = "--stairs-only" in OS.get_cmdline_user_args() or "--all-stairs" in OS.get_cmdline_user_args()
var all_stairs: bool = "--all-stairs" in OS.get_cmdline_user_args()

func result_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):
			return arg.trim_prefix("--result=")
	return "res://tests/physics_walk_result.json"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	results["assertions"] = int(results["assertions"]) + 1
	if not ok:
		errors.append(label)
		print("PHYSICS_WALK_FAIL ", label)

func frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func point_data(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func yaw_to(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

func release_input() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "run", "jump"]:
		Input.action_release(action)

func setup_at(p: Vector3, toward: Vector3) -> void:
	release_input()
	game.player.teleport(p + Vector3.UP * 0.13, yaw_to(toward - p))
	game.player.enabled = true
	await frames(35)

func walk_to(target: Vector3, max_frames: int = 360) -> Dictionary:
	var start: Vector3 = game.player.global_position
	var previous: Vector3 = start
	var traveled: float = 0.0
	var ticks: int = 0
	var grounded_ticks: int = 0
	var last_progress: int = 0
	var best_distance: float = horizontal_distance(start, target)
	var contacts: Array = []
	Input.action_press("move_forward")
	while ticks < max_frames:
		var now: Vector3 = game.player.global_position
		var remaining: float = horizontal_distance(now, target)
		if remaining < 0.38:
			break
		if remaining < best_distance - 0.025:
			best_distance = remaining
			last_progress = ticks
		if ticks - last_progress > 100:
			contacts.append({"velocity": point_data(game.player.velocity),
				"real_velocity": point_data(game.player.get_real_velocity()),
				"floor_normal": point_data(game.player.get_floor_normal())})
			for collision_index: int in range(game.player.get_slide_collision_count()):
				var contact: KinematicCollision3D = game.player.get_slide_collision(collision_index)
				var collider: Object = contact.get_collider()
				contacts.append({"collider": str(collider.get_path()) if collider is Node else str(collider),
					"normal": point_data(contact.get_normal()), "position": point_data(contact.get_position())})
			break
		game.player.rotation.y = yaw_to(target - now)
		await physics_frame
		ticks += 1
		var current: Vector3 = game.player.global_position
		traveled += horizontal_distance(previous, current)
		previous = current
		if game.player.is_on_floor():
			grounded_ticks += 1
	Input.action_release("move_forward")
	# Let real acceleration/braking settle; never place the capsule at target.
	await frames(18)
	var finish: Vector3 = game.player.global_position
	traveled += horizontal_distance(previous, finish)
	return {"start": point_data(start), "target": point_data(target),
		"finish": point_data(finish), "walked_m": traveled, "physics_ticks": ticks,
		"remaining_m": horizontal_distance(finish, target), "height_error_m": absf(finish.y - target.y),
		"grounded": game.player.is_on_floor(), "grounded_ticks": grounded_ticks,
		"stalled_contacts": contacts,
		"reached": horizontal_distance(finish, target) < 0.46 and absf(finish.y - target.y) < 0.32}

func run() -> void:
	var packed: PackedScene = load("res://main.tscn")
	if packed == null:
		check(false, "Main playable scene is unavailable")
		await finish()
		return
	game = packed.instantiate()
	game.automated_test = true
	game.save_path = "user://physics_walk_isolated_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene = game
	var deadline: int = Time.get_ticks_msec() + 180000
	while not game.world_ready and not game.load_failed and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.world_ready, "Main scene and shipped collision assets load")
	if not game.world_ready:
		results["load_errors"] = game.load_errors
		await finish()
		return
	game.start_new_trip()
	results["scope"] = "all-stairs-up-down" if all_stairs else ("stairs-only" if stairs_only else "full")
	results["safe_margin_m"] = game.player.safe_margin
	await frames(30)
	results["capsule_radius_m"] = 0.28
	results["capsule_height_m"] = 1.8
	results["teleport_policy"] = "One setup teleport per independent case; door and stair traversal use only real forward input. Lifts use main.activate_interaction."
	for building: Dictionary in game.manifest.get("buildings", []):
		if stairs_only:
			break
		if str(building.get("access", "walk")) != "walk":
			continue
		var id: String = str(building.id)
		var outside: Vector3 = game.vector(building.entrance)
		var inside: Vector3 = game.vector(building.inside)
		await setup_at(outside, inside)
		check(game.player.is_on_floor(), id + " doorway approach settles on collision")
		var movement: Dictionary = await walk_to(inside)
		movement["building"] = id
		var direction: Vector3 = inside - outside
		direction.y = 0
		direction = direction.normalized()
		var plane: Vector3 = (outside + inside) * 0.5
		movement["crossed_door_plane"] = (game.player.global_position - plane).dot(direction) > 0.3
		results["doors"].append(movement)
		check(bool(movement.reached) and bool(movement.crossed_door_plane), id + " actual capsule walks through doorway")
		check(float(movement.walked_m) > horizontal_distance(outside, inside) * 0.65, id + " doorway distance is produced by walking")
		print("PHYSICS_DOOR ", id, " ", movement.reached, " ", movement.remaining_m)

	for action: Dictionary in game.manifest.get("interactions", []):
		if stairs_only:
			break
		if str(action.get("kind", "")) != "lift":
			continue
		var source: Vector3 = game.vector(action.position)
		var target: Vector3 = game.vector(action.target)
		await setup_at(source, source + Vector3.FORWARD)
		var source_floor: bool = game.player.is_on_floor()
		var activated: bool = game.activate_interaction(action)
		await frames(45)
		var now: Vector3 = game.player.global_position
		var supported: bool = game.player.is_on_floor()
		var stable: bool = horizontal_distance(now, target) < 0.50 and absf(now.y - target.y) < 0.30
		results["lifts"].append({"id": action.id, "activated": activated, "source_supported": source_floor,
			"target_supported": supported, "target_stable": stable, "target": point_data(target), "settled": point_data(now)})
		check(source_floor and activated and supported and stable, str(action.id) + " main-scene lift landing settles safely")

	# The steep square keep is the German representative. Its stairs use the
	# ordinary facade orientation; Palas interior circulation is intentionally
	# mirrored to avoid an attached round tower and is covered by the BVH suite.
	if all_stairs:
		var stair_buildings: int = 0
		var expected_pairs: int = 0
		var tested_regions: Dictionary = {}
		for building: Dictionary in game.manifest.get("buildings", []):
			if building.get("stair_landings", []).is_empty():
				continue
			stair_buildings += 1
			tested_regions[str(building.region)] = true
			for floor_index: int in range(building.stair_landings.size()):
				expected_pairs += 1
				await test_stairs(building, floor_index)
		results["stair_buildings"] = stair_buildings
		results["expected_stair_pairs"] = expected_pairs
		check(tested_regions.size() == 4 and results.stairs.size() == expected_pairs, "Every exported staircase floor pair is walked up and down in all regions")
		await finish()
		return
	var selected: Dictionary = {}
	for building: Dictionary in game.manifest.get("buildings", []):
		var region: String = str(building.region)
		if building.get("stair_landings", []).is_empty():
			continue
		if region == "DE_Bavaria" and str(building.id) != "DE_KEEP":
			continue
		if not selected.has(region):
			selected[region] = building
	for region: String in selected:
		await test_stairs(selected[region])
	check(selected.size() == 4, "One complete switchback staircase is physically walked in each region")
	await finish()

func stair_angle(building: Dictionary) -> float:
	# Local top-landing coordinates are shared-kit geometry. The exported
	# world landing resolves rotation even when the facade faces another way.
	var w: float = float(building.size[0])
	var d: float = float(building.size[1])
	var sw: float = minf(2.65, w * 0.30)
	var lane: float = (sw - 0.15) / 2.0
	var local_landing := Vector2(w / 2.0 - 0.35 - lane / 2.0, d / 2.0 - 0.35 - minf(5.35, d * 0.48) - 0.25)
	var center: Vector3 = game.vector(building.center)
	var landing: Vector3 = game.vector(building.stair_landings[0])
	var exported_landing := Vector2(landing.x - center.x, center.z - landing.z)
	return exported_landing.angle() - local_landing.angle()

func local_stair_point(building: Dictionary, u: float, v: float, height: float) -> Vector3:
	var center: Vector3 = game.vector(building.center)
	var angle: float = stair_angle(building)
	var x: float = u * cos(angle) - v * sin(angle)
	var y: float = u * sin(angle) + v * cos(angle)
	return Vector3(center.x + x, height, center.z - y)

func test_stairs(building: Dictionary, floor_index: int = 0) -> void:
	var sizes: Array = building["size"]
	var levels: Array = building.floor_levels
	var w: float = float(sizes[0])
	var d: float = float(sizes[1])
	var fh: float = float(levels[floor_index + 1]) - float(levels[floor_index])
	var stair_w: float = minf(2.65, w * 0.30)
	var stair_run: float = minf(5.35, d * 0.48)
	var right: float = w / 2.0 - 0.35
	var rear: float = d / 2.0 - 0.35
	var bottom: float = rear - stair_run
	var end: float = bottom + stair_run - 0.9
	var lane: float = (stair_w - 0.15) / 2.0
	var xa: float = right - stair_w + lane / 2.0
	var xb: float = right - lane / 2.0
	var base: float = float(levels[floor_index]) + 0.045
	var beginning: Vector3 = local_stair_point(building, xa, bottom - 0.5, base)
	var first: Vector3 = local_stair_point(building, xa, end + 0.46, base + fh / 2.0)
	var turn: Vector3 = local_stair_point(building, xb, end + 0.46, base + fh / 2.0)
	var last: Vector3 = local_stair_point(building, xb, bottom - 0.45, base + fh)
	await setup_at(beginning, first)
	var first_walk: Dictionary = await walk_to(first)
	var turn_walk: Dictionary = await walk_to(turn)
	var last_walk: Dictionary = await walk_to(last)
	var climbed: float = game.player.global_position.y - beginning.y
	var descent: Dictionary = {}
	if all_stairs:
		descent["first_flight"] = await walk_to(turn)
		descent["landing_turn"] = await walk_to(first)
		descent["return_flight"] = await walk_to(beginning)
	results["stairs"].append({"building": building.id, "region": building.region,
		"lower_floor": floor_index, "upper_floor": floor_index + 1, "interior_angle": stair_angle(building),
		"first_flight": first_walk, "landing_turn": turn_walk, "return_flight": last_walk,
		"descent": descent,
		"climbed_m": climbed, "expected_climb_m": fh})
	var label: String = str(building.id) + " floor " + str(floor_index)
	check(bool(first_walk.reached), label + " first flight climbs with actual capsule")
	check(bool(turn_walk.reached), label + " capsule turns on intermediate landing")
	check(bool(last_walk.reached) and absf(climbed - fh) < 0.32, label + " full U staircase reaches upper floor")
	var down_ok := true
	var down_status := "not-run"
	if all_stairs:
		down_ok = bool(descent.first_flight.reached) and bool(descent.landing_turn.reached) and bool(descent.return_flight.reached)
		down_status = str(down_ok)
		check(down_ok, label + " full U descent returns to lower floor")
	print("PHYSICS_STAIRS ", label, " up ", first_walk.reached, " ", turn_walk.reached, " ", last_walk.reached, " down ", down_status)

func finish() -> void:
	release_input()
	# Quit only after the procedural ambience and final footstep have released
	# their audio-thread playback references. Abrupt SceneTree.quit previously
	# left three AudioStream resources alive at process teardown.
	if is_instance_valid(game):
		if is_instance_valid(game.player):
			game.player.enabled = false
		if is_instance_valid(game.ambience):
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
		var release_deadline: int = Time.get_ticks_msec() + 180
		while Time.get_ticks_msec() < release_deadline:
			await process_frame
	results["passed"] = errors.is_empty()
	results["errors"] = errors
	results["headless"] = DisplayServer.get_name() == "headless"
	results["completed_unix"] = Time.get_unix_time_from_system()
	results["coverage_limits"] = ["All walk entrances and lift landings; one first-floor U staircase per region. Does not traverse every upper floor, arbitrary interior route, outdoor edge, or every movement direction."]
	if all_stairs:
		results["coverage_limits"] = ["Every exported stair floor pair up/down. Setup teleport before each independent pair; no teleport during ascent/descent. Does not connect every building's entire vertical route in one uninterrupted walk or cover arbitrary furniture routes and OS input delivery."]
	var file: FileAccess = FileAccess.open(result_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(results, "\t"))
		file.close()
	print("PHYSICS_WALK_RESULT ", JSON.stringify({"passed": results.passed, "doors": results.doors.size(), "lifts": results.lifts.size(), "stairs": results.stairs.size(), "errors": errors}))
	quit(0 if errors.is_empty() else 1)
