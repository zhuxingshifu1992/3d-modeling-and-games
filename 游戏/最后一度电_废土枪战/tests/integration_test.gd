extends SceneTree
## Full mission against main.tscn, imported GLB physics, real player and E input.
## Run with --headless --fixed-fps 60 --script res://tests/integration_test.gd
## Only the long charge wait is accelerated; objectives use the normal input loop.

var game: Node3D
var failures: Array[String] = []
var checks: int = 0
var profile_existed: bool = false
var profile_before: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("INTEGRATION_OK ", label)
	else:
		failures.append(label)
		push_error("INTEGRATION_FAIL " + label)

func _run() -> void:
	profile_existed = FileAccess.file_exists("user://profile.json")
	if profile_existed:
		profile_before = FileAccess.get_file_as_string("user://profile.json")
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	if packed == null or not packed.can_instantiate():
		_check(false, "main.tscn loads")
		_finish()
		return
	game = packed.instantiate() as Node3D
	root.add_child(game)
	# _ready has finished here. Suppress profile writes and built-in timed QA.
	game.set("qa", true)
	game.set("qa_mode", "integration")
	_check(game.get("world") != null and game.get("world").has_node("ReferenceYard"), "main uses imported reference world")
	game.call("_start_from_menu", "standard")
	await _frames(12)
	_check(game.get("running") and game.get("state").phase == "power", "menu start enters power mission")
	_check(game.get("player").is_on_floor(), "real player settles on physical yard floor")
	if "--exit-probe" in OS.get_cmdline_user_args():
		game.call("_begin", "extract")
		await _frames(12)
		await _hold_objective("exit", Vector3(0, 0.13, 20.35), "victory")
		_check(not game.get("running"), "exit victory transition stops running and presents the end screen")
		_check(game.get("hud").mode == "victory" and game.get("hud").panel.visible, "exit victory panel is actually visible")
		_finish()
		return

	# Restore power from an actual supported point on the office terrace.
	if not await _hold_objective("power_console", Vector3(11.0, 3.13, 3.02), "connect", true):
		_finish()
		return
	_check(game.get("player").global_position.y > 2.95, "power console works while standing on upstairs terrace")
	_check(game.get("checkpoint_data").get("phase", "") == "connect", "power interaction saves connect checkpoint")
	_check(bool(game.get("world").get("_power")), "power interaction lights the original yard")
	game.call("_save_screenshot", "mission_power.png")

	# A real player death uses the connected died signal and retry handler.
	game.get("player").take_damage(500.0, game.get("player").global_position + Vector3(0, 0, 2))
	await _frames(3)
	_check(game.get("state").phase == "dead" and not game.get("running"), "fatal damage opens defeat state")
	game.call("_retry")
	await _frames(15)
	_check(game.get("state").phase == "connect" and game.get("running"), "retry resumes saved connect phase")
	_check(game.get("player").is_alive() and game.get("player").health == 100.0, "retry restores a live player")
	_check(game.get("player").global_position.y > 2.95 and game.get("player").is_on_floor(), "connect checkpoint respawns safely on terrace")

	if not await _hold_objective("charge_terminal", Vector3(-8.4, 0.13, -5.95), "charge"):
		_finish()
		return
	await _frames(12)
	_check(game.get("state").charge > 0.0, "charging advances in normal game process")
	game.call("_save_screenshot", "mission_charge.png")
	_send_key(KEY_ESCAPE, true)
	await _frames(2)
	_send_key(KEY_ESCAPE, false)
	_check(paused, "Escape pauses the real scene tree")
	_check(game.get("hud").mode == "pause" and game.get("hud").panel.visible, "pause menu is visible")
	var paused_charge: float = game.get("state").charge
	await _frames(20)
	_check(is_equal_approx(game.get("state").charge, paused_charge), "pause freezes charge timer")
	_send_key(KEY_ESCAPE, true)
	await _frames(2)
	_send_key(KEY_ESCAPE, false)
	_check(not paused and game.call("can_fight"), "Escape resumes gameplay")

	# Cross the actual one-time trip threshold; game processes phase_changed.
	game.get("state").advance(35.05 - float(game.get("state").charge))
	await _frames(4)
	_check(game.get("state").phase == "reset" and is_equal_approx(game.get("state").charge, 35.0), "charge trips once at 35 seconds and keeps progress")
	_check(bool(game.get("world").get("_alarm")) and not bool(game.get("world").get("_power")), "trip changes world power and warning beacon")
	if not await _hold_objective("reset_breaker", Vector3(-7.50, 0.13, 0.55), "charge"):
		_finish()
		return
	_check(game.get("state").tripped and game.get("state").charge >= 35.0, "breaker retains charge and suppresses repeat trip")
	_check(bool(game.get("world").get("_power")) and not bool(game.get("world").get("_alarm")), "breaker restores cyan lighting and clears warning")
	game.get("state").advance(80.0)
	await _frames(4)
	_check(game.get("state").phase == "collect" and is_equal_approx(game.get("state").charge, 75.0), "charge completes at 75 seconds")
	_check(game.get("visuals").get("battery").visible, "charged battery appears in the actual scene")
	if not await _hold_objective("battery", Vector3(-8.4, 0.13, -5.95), "extract"):
		_finish()
		return
	_check(game.get("state").carrying, "battery input grants carrying state")
	_check(game.get("checkpoint_data").get("phase", "") == "extract", "battery input saves extraction checkpoint")
	_check(game.get("visuals").get("exit").visible, "extraction area becomes visible")
	game.call("_save_screenshot", "mission_extract.png")

	# The second checkpoint must preserve the objective after another death.
	game.get("player").take_damage(500.0, game.get("player").global_position + Vector3(0, 0, 2))
	await _frames(3)
	game.call("_retry")
	await _frames(15)
	_check(game.get("state").phase == "extract" and game.get("state").carrying, "retry extraction preserves completed battery")
	_check(game.get("player").is_alive() and game.get("player").is_on_floor(), "extraction checkpoint is safe and alive")
	if not await _hold_objective("exit", Vector3(0, 0.13, 20.35), "victory", true):
		_finish()
		return
	_check(not game.get("running"), "completed extraction ends combat loop")
	_check(game.get("hud").mode == "victory" and game.get("hud").panel.visible, "victory statistics panel is actually displayed")
	_check(game.get("state").stats().has("accuracy"), "victory statistics include accuracy")
	game.call("_save_screenshot", "mission_victory.png")
	_finish()

func _suppress_combat() -> void:
	if not is_instance_valid(game):
		return
	for enemy: Node in get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	game.get("wave_queue").clear()

func _frames(count: int) -> void:
	for index: int in range(count):
		_suppress_combat()
		await physics_frame
		await process_frame

func _find_target(id: String) -> Dictionary:
	for target: Dictionary in game.get("targets"):
		if str(target.get("id", "")) == id:
			return target
	return {}

func _aim_at(point: Vector3) -> void:
	var player: CharacterBody3D = game.get("player")
	var direction: Vector3 = (point - player.camera.global_position).normalized()
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.look_pitch = asin(clampf(direction.y, -1.0, 1.0))
	player.camera.rotation.x = player.look_pitch

func _hold_objective(id: String, feet: Vector3, expected_phase: String, test_release: bool = false) -> bool:
	_send_key(KEY_E, false)
	var target: Dictionary = _find_target(id)
	_check(not target.is_empty(), id + " target exists")
	if target.is_empty():
		return false
	var player: CharacterBody3D = game.get("player")
	player.global_position = feet
	player.velocity = Vector3.ZERO
	await _frames(15)
	_check(player.is_on_floor(), id + " inspection position has physical floor support")
	_aim_at(target.position)
	await _frames(4)
	var actual_id: String = str(game.get("active_target").get("id", ""))
	_check(actual_id == id, id + " selected by real camera cone/range/occlusion check; selected=" + actual_id)
	if actual_id != id:
		_report_obstruction(id, target.position)
		return false
	if id == "reset_breaker":
		game.call("_save_screenshot", "mission_reset.png")
	var original_phase: String = game.get("state").phase
	if test_release:
		_send_key(KEY_E, true)
		await _frames(18)
		_check(Input.is_action_pressed("interact"), id + " E key maps to held interact action")
		_check(float(game.get("interaction_progress")) > 0.02, id + " hold progress advances before activation")
		_send_key(KEY_E, false)
		await _frames(3)
		_check(is_zero_approx(float(game.get("interaction_progress"))) and game.get("state").phase == original_phase, id + " releasing E cancels incomplete hold")
	_send_key(KEY_E, true)
	var max_frames: int = ceili(float(target.hold) * 60.0) + 35
	for frame: int in range(max_frames):
		await _frames(1)
		if game.get("state").phase == expected_phase:
			break
	_send_key(KEY_E, false)
	if not _targets_intact():
		_check(false, id + " interaction must not clear a shared objective Dictionary")
		return false
	await _frames(3)
	var success: bool = game.get("state").phase == expected_phase
	_check(success, id + " held E transitions to " + expected_phase + "; actual=" + str(game.get("state").phase))
	if not success:
		_report_obstruction(id, target.position)
	return success

func _targets_intact() -> bool:
	for item: Dictionary in game.get("targets"):
		if not item.has_all(["id", "kind", "used", "position"]):
			print("INTEGRATION_DIAGNOSTIC corrupted target keys=", item.keys())
			return false
	return true

func _report_obstruction(id: String, target_position: Vector3) -> void:
	var player: CharacterBody3D = game.get("player")
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.camera.global_position, target_position, 1)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	var blocker: String = String(hit["collider"].name) if hit.has("collider") else "none"
	print("INTEGRATION_DIAGNOSTIC ", JSON.stringify({"objective":id,"phase":game.get("state").phase,"player":str(player.global_position),"camera":str(player.camera.global_position),"target":str(target_position),"distance":player.camera.global_position.distance_to(target_position),"forward_dot":(-player.camera.global_basis.z).dot((target_position-player.camera.global_position).normalized()),"blocker":blocker,"hit":str(hit.get("position",Vector3.INF)),"active":game.get("active_target").get("id", ""),"progress":game.get("interaction_progress")}))

func _send_key(key: Key, down: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = down
	event.echo = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _finish() -> void:
	_send_key(KEY_E, false)
	_send_key(KEY_ESCAPE, false)
	paused = false
	var unchanged: bool = FileAccess.file_exists("user://profile.json") == profile_existed
	if unchanged and profile_existed:
		unchanged = FileAccess.get_file_as_string("user://profile.json") == profile_before
	_check(unchanged, "integration does not write or change real player profile")
	if is_instance_valid(game):
		game.set("running", false)
		_stop_test_audio(game)
		game.queue_free()
	call_deferred("_quit_with_result")

func _stop_test_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.stop()
		node.stream = null
	for child: Node in node.get_children():
		_stop_test_audio(child)

func _quit_with_result() -> void:
	await process_frame
	await process_frame
	# Fixed-fps simulation can outrun the real-time audio mixer. Let stopped
	# playbacks retire before destroying the audio server at test exit.
	if DisplayServer.get_name() == "headless":
		OS.delay_msec(150)
	await process_frame
	if failures.is_empty():
		var description: String = "exit checkpoint E interaction and victory panel" if "--exit-probe" in OS.get_cmdline_user_args() else "real world E interactions complete POWER > CONNECT > CHARGE > RESET > COLLECT > EXTRACT > VICTORY"
		print("INTEGRATION_TEST PASS ", checks, " checks; ", description)
		quit(0)
	else:
		print("INTEGRATION_TEST FAIL ", failures.size(), " / ", checks, " checks")
		quit(1)
