extends SceneTree

const MainScene: Script = preload("res://scripts/main.gd")
const VoyageLogic: Script = preload("res://scripts/voyage.gd")
const STEP: float = 1.0 / 60.0
const ISLANDS: Array[Rect2] = [
	Rect2(-31.0, -26.0, 25.0, 22.0), Rect2(6.0, -26.0, 25.0, 22.0),
	Rect2(-31.0, 4.0, 25.0, 20.0), Rect2(6.0, 4.0, 25.0, 20.0),
	Rect2(-27.25, 23.6, 8.5, 4.8),
]

var _game: Node3D
var _checks: int = 0
var _failures: int = 0
var _simulated_seconds: float = 0.0
var _save_before: String = ""
var _save_existed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not "--benchmark" in OS.get_cmdline_user_args():
		printerr("Run this test with -- --benchmark to prohibit player save loading/writing.")
		quit(2)
		return
	_save_existed = FileAccess.file_exists("user://save.json")
	if _save_existed:
		_save_before = FileAccess.get_file_as_string("user://save.json")
	_game = MainScene.new()
	root.add_child(_game)
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.bench_done = true
	_game.bench_seconds = 1000000000.0
	_game.muted = true
	_check(_game.benchmark and _game.started and _game.boat != null, "The real main scene must start in benchmark mode")
	_test_stationary_navigation()
	_test_pause()
	_test_trip_cycles()
	_test_all_dock_pairs()
	_check(FileAccess.file_exists("user://save.json") == _save_existed, "Gameplay integration must not create or remove the player save")
	if _save_existed:
		_check(FileAccess.get_file_as_string("user://save.json") == _save_before, "Gameplay integration must not change the player save contents")
	print("Gameplay integration: %d checks, %d failures, %.1f simulated seconds, %d deliveries, upgrade level %d" % [_checks, _failures, _simulated_seconds, int(_game.voyage.completed), int(_game.voyage.level)])
	_game.free()
	quit(0 if _failures == 0 else 1)


func _test_stationary_navigation() -> void:
	_game._navigate_to(_game.boat.position)
	_check(_game.route_nodes.is_empty() and not _game.route_visual.visible, "Navigating to the boat's current position must produce no travel route")
	_check(not _game.destination_marker.visible, "An already reached destination must not leave an active destination marker")
	_game._navigate_to(_game.voyage.target().pos)


func _test_pause() -> void:
	_step(30)
	var before_position: Vector3 = _game.boat.position
	var before_completed: int = _game.voyage.completed
	var before_wallet: int = _game.voyage.wallet
	_game._set_pause(true)
	_step(180)
	_check(_game.boat.position == before_position, "Pausing must freeze boat position even with an active navigation route")
	_check(_game.voyage.completed == before_completed and _game.voyage.wallet == before_wallet, "Pausing must freeze trip and coin progress")
	_game._set_pause(false)
	_step(30)
	_check(_game.boat.position.distance_to(before_position) > 0.01, "Resuming must continue the selected navigation route")


func _test_trip_cycles() -> void:
	var previous_completed: int = _game.voyage.completed
	var frames_without_delivery: int = 0
	var visited: Dictionary = {}
	var failure_reported: bool = false
	for frame_index: int in range(60 * 1500):
		var old_target: int = _game.voyage.target_id
		_step(1)
		frames_without_delivery += 1
		if _game.voyage.completed > previous_completed:
			visited[old_target] = true
			print("DELIVERY %d target=%d pos=%s wallet=%d level=%d" % [int(_game.voyage.completed), old_target, str(_game.boat.position), int(_game.voyage.wallet), int(_game.voyage.level)])
			previous_completed = _game.voyage.completed
			frames_without_delivery = 0
			if _game.voyage.level < 3 and _game.voyage.wallet >= _game.voyage.upgrade_cost():
				var old_level: int = _game.voyage.level
				var old_wallet: int = _game.voyage.wallet
				var displayed_cost: int = _game.voyage.upgrade_cost()
				_game._hud_action("upgrade")
				_check(_game.voyage.level == old_level + 1 and _game.voyage.wallet == old_wallet - displayed_cost, "The real HUD upgrade action must purchase its advertised level and cost")
		if _game.voyage.completed >= 12:
			break
		if frames_without_delivery >= 60 * 150:
			_check(false, "Autopilot must finish each trip within 150 simulated seconds; " + _state())
			failure_reported = true
			break
	_check(_game.voyage.completed >= 12, "Real steering and docking must complete two full six-dock circuits" + (" (stuck above)" if failure_reported else ""))
	_check(visited.size() == 6, "The mission circuit must deliver to every dock")
	_check(_game.voyage.level == 3, "Earned fares and collected coins must fund three real upgrades")
	if _game.voyage.level == 3:
		var wallet_before: int = _game.voyage.wallet
		_game._hud_action("upgrade")
		_check(_game.voyage.wallet == wallet_before and _game.voyage.level == 3, "A fourth HUD upgrade action must not charge or exceed the cap")


func _test_all_dock_pairs() -> void:
	# Each fixture starts at a dock; every subsequent movement goes through the
	# production steering, speed integration, and hull collision checks.
	var saved_stage: String = _game.voyage.stage
	_game.voyage.stage = "navigation_test"
	for origin: Dictionary in VoyageLogic.DOCKS:
		for destination: Dictionary in VoyageLogic.DOCKS:
			if origin.id == destination.id:
				continue
			_game.boat.position = origin.pos
			_game.speed = 0.0
			_game.heading = 0.0
			_game.voyage.target_id = int(destination.id)
			_game.route_nodes.clear()
			_game._navigate_to(destination.pos)
			var reached: bool = false
			var unsafe: bool = false
			for frame_index: int in range(60 * 150):
				# Prevent the unrelated mission target from boarding during this
				# navigation-only fixture; this does not replace boat physics.
				_game.voyage._dwell = -100000.0
				_step(1, false)
				if not _safe_center(_game.boat.position):
					unsafe = true
					break
				var distance: float = Vector2(_game.boat.position.x - destination.pos.x, _game.boat.position.z - destination.pos.z).length()
				if distance < 1.4 and absf(_game.speed) < 2.0:
					reached = true
					break
			_check(reached and not unsafe, "Dock %d -> %d must arrive without collision deadlock; %s" % [int(origin.id), int(destination.id), _state()])
	_game.voyage.stage = saved_stage


func _step(frames: int, with_process: bool = true) -> void:
	for frame_index: int in range(frames):
		_game._physics_process(STEP)
		if with_process:
			_game._process(STEP)
		_simulated_seconds += STEP


func _safe_center(point: Vector3) -> bool:
	if absf(point.x) > 44.2001 or absf(point.z) > 39.2001:
		return false
	for island: Rect2 in ISLANDS:
		if island.grow(0.7999).has_point(Vector2(point.x, point.z)):
			return false
	return true


func _state() -> String:
	return "position=%s speed=%.3f heading=%.3f target=%d stage=%s nodes=%s" % [str(_game.boat.position), float(_game.speed), float(_game.heading), int(_game.voyage.target_id), str(_game.voyage.stage), str(_game.route_nodes)]


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL: " + description)
