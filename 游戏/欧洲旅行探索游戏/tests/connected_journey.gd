extends SceneTree
## Continuous four-country walk using the released collision and controller.
## Only start_new_trip places the player; all waypoints use movement input.
var game: Node3D
var errors: Array[String] = []
var results := {"segments": [], "stations": [], "headless": true, "started_unix": Time.get_unix_time_from_system()}

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for _i in range(n):
		await physics_frame

func walk_to(point: Vector2, name: String) -> bool:
	var initial := Vector2(game.player.position.x, game.player.position.z)
	var budget := int(initial.distance_to(point) / 2.2 * 60 * 1.8) + 180
	var best := initial.distance_to(point)
	var last_progress := 0
	var supported := 0
	var ticks := 0
	var max_displacement := 0.0
	var previous: Vector3 = game.player.position
	var contacts := []
	Input.action_press("move_forward")
	while ticks < budget:
		var remaining := point - Vector2(game.player.position.x, game.player.position.z)
		if remaining.length() < 0.30:
			break
		if remaining.length() < best - 0.025:
			best = remaining.length()
			last_progress = ticks
		if ticks - last_progress > 120:
			for i in range(game.player.get_slide_collision_count()):
				var hit = game.player.get_slide_collision(i)
				contacts.append({"node": str(hit.get_collider().get_path()), "normal": str(hit.get_normal()), "point": str(hit.get_position())})
			break
		game.player.rotation.y = atan2(-remaining.x, -remaining.y)
		await physics_frame
		ticks += 1
		max_displacement = maxf(max_displacement, previous.distance_to(game.player.position))
		previous = game.player.position
		if game.player.is_on_floor():
			supported += 1
	Input.action_release("move_forward")
	await frames(16)
	var distance := Vector2(game.player.position.x, game.player.position.z).distance_to(point)
	var ok: bool = distance < 0.5 and game.player.is_on_floor() and max_displacement < 0.32
	results.segments.append({"name": name, "passed": ok, "distance_remaining": distance, "physics_ticks": ticks, "supported_ticks": supported, "max_tick_displacement_m": max_displacement, "finish": str(game.player.position), "contacts": contacts})
	print("CONNECTED_SEGMENT ", name, " ", ok, " ", distance)
	if not ok:
		errors.append(name + " could not be walked continuously")
	return ok

func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.automated_test = true
	game.save_path = "user://audit_connected_journey.json"
	root.gui_disable_input = true
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec() + 180000
	while not game.world_ready and not game.load_failed and Time.get_ticks_msec() < deadline:
		await process_frame
	if not game.world_ready:
		errors.append("World failed to load")
		await finish()
		return
	game.start_new_trip()
	await frames(60)
	results.stations.append("FR_Paris")
	var path := [
		[Vector2(-132,-47),"Paris quay approach"],
		[Vector2(-132,-20),"Seine bridge"],
		[Vector2(-132,0),"Paris central connection"],
		[Vector2(90,0),"Central west-east boulevard"],
		[Vector2(90,-36),"IT_Rome"],
		[Vector2(90,0),"Rome return"],
		[Vector2(0,0),"Central crossroads"],
		[Vector2(0,153),"Central south boulevard"],
		[Vector2(-90,153),"Southwest boulevard"],
		[Vector2(-90,136),"CH_Alps"],
		[Vector2(-90,153),"Swiss return"],
		[Vector2(73,153),"Southeast boulevard"],
		[Vector2(73,137),"DE_Bavaria"]
	]
	for waypoint in path:
		if not await walk_to(waypoint[0], waypoint[1]):
			break
		if waypoint[1] in ["IT_Rome","CH_Alps","DE_Bavaria"]:
			results.stations.append(waypoint[1])
	if results.stations.size() != 4:
		errors.append("Not all four stations reached on foot")
	await finish()

func finish() -> void:
	Input.action_release("move_forward")
	results["passed"] = errors.is_empty()
	results["errors"] = errors
	results["completed_unix"] = Time.get_unix_time_from_system()
	results["teleports_during_route"] = 0
	var file := FileAccess.open("res://tests/connected_journey_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	file.close()
	print("CONNECTED_JOURNEY_RESULT ", JSON.stringify(results))
	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0 if errors.is_empty() else 1)
