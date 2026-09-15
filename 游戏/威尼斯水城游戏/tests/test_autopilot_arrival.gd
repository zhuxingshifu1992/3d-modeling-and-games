extends SceneTree

## Normal player navigation, with real steering and collision. The benchmark
## argument protects Main._ready; navigation then runs with benchmark=false.
## Persistence is replaced before normal mode is enabled. No save is read.
const MainScene: Script = preload("res://scripts/main.gd")
const STEP: float = 1.0 / 60.0
const CASES: Array[Dictionary] = [
	{"name": "straight central canal", "start": Vector3(0, 0.25, 15), "goal": Vector3(0, 0.25, 0), "heading": 0.0},
	{"name": "north garden to lagoon dock", "start": Vector3(-18, 0.25, -28.5), "goal": Vector3(0, 0.25, 29.5), "heading": 0.0},
]

class MemoryVoyage:
	extends "res://scripts/voyage.gd"

	func save(_path: String = "") -> bool:
		return true

	func load_save(_path: String = "") -> bool:
		return false

var _game: Node3D
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless" or not "--benchmark" in OS.get_cmdline_user_args():
		printerr("Arrival tests require --headless and -- --benchmark; never run in a desktop game.")
		quit(2)
		return
	_game = MainScene.new()
	root.add_child(_game)
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.bench_done = true
	_game.muted = true
	_game.voyage = MemoryVoyage.new()
	_game.benchmark = false
	for fixture: Dictionary in CASES:
		_test_arrival(fixture)
	print("Autopilot arrival: %d checks, %d failures" % [_checks, _failures])
	_game.free()
	quit(0 if _failures == 0 else 1)


func _test_arrival(fixture: Dictionary) -> void:
	_game.boat.position = fixture.start
	_game.heading = fixture.heading
	_game.speed = 0.0
	_game.voyage.level = 3
	_game.voyage.stage = "pickup"
	_game.voyage.target_id = 0
	_game.voyage._dwell = 0.0
	_game.route_nodes.clear()
	_game._navigate_to(fixture.goal)
	print("ARRIVAL_START name=%s start=%s goal=%s heading=%.3f speed=%.3f level=%d stage=%s route=%s" % [fixture.name, str(fixture.start), str(fixture.goal), float(_game.heading), float(_game.speed), int(_game.voyage.level), str(_game.voyage.stage), str(_game.route_nodes)])
	var reported_route_end: bool = false
	for frame: int in range(60 * 90):
		_game._physics_process(STEP)
		if not reported_route_end and _game.route_nodes.is_empty():
			reported_route_end = true
			print("ARRIVAL_ROUTE_EMPTY name=%s time=%.3f %s" % [fixture.name, float(frame + 1) * STEP, _state()])
		if reported_route_end and absf(_game.speed) < 0.001:
			break
	var offset: Vector3 = _game.boat.position - fixture.goal
	offset.y = 0.0
	print("ARRIVAL_FINAL name=%s distance=%.3f %s" % [fixture.name, offset.length(), _state()])
	_check(reported_route_end, "Normal autopilot must finish its route within 90 seconds: " + fixture.name)
	_check(offset.length() < 1.4 and absf(_game.speed) < 2.0, "Normal autopilot must stop at its selected destination instead of coasting past it: " + fixture.name)


func _state() -> String:
	return "position=%s heading=%.3f speed=%.3f stage=%s route=%s" % [str(_game.boat.position), float(_game.heading), float(_game.speed), str(_game.voyage.stage), str(_game.route_nodes)]


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL: " + description)
