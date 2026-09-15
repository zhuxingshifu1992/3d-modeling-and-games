extends SceneTree

## Physical key events are injected only into this headless test process.
## Start with -- --benchmark so Main._ready never loads player progress;
## the in-memory Voyage replacement blocks all subsequent persistence.
const MainScene: Script = preload("res://scripts/main.gd")
const VoyageLogic: Script = preload("res://scripts/voyage.gd")
const STEP: float = 1.0 / 60.0
const BANKS: Array[Dictionary] = [
	{"name": "east bank", "pos": Vector3(-5.1, 0.25, 15.0), "out": Vector3.RIGHT, "inward": -PI / 2.0},
	{"name": "west bank", "pos": Vector3(-31.9, 0.25, 15.0), "out": Vector3.LEFT, "inward": PI / 2.0},
	{"name": "north bank", "pos": Vector3(-15.0, 0.25, 3.1), "out": Vector3.FORWARD, "inward": PI},
	{"name": "south bank", "pos": Vector3(-15.0, 0.25, 24.9), "out": Vector3.BACK, "inward": 0.0},
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
		printerr("Boat recovery tests require --headless and -- --benchmark; never run in a desktop game.")
		quit(2)
		return
	_game = MainScene.new()
	root.add_child(_game)
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.bench_done = true
	_game.muted = true
	_game.voyage = MemoryVoyage.new()
	_game.voyage.stage = "movement_test"
	_game.benchmark = false
	_test_physical_thrust()
	_test_turn_only()
	_test_turn_at_bank_then_reverse()
	_test_existing_overlap_recovery()
	_test_block_deeper_overlap()
	_test_safe_wall_contact()
	_test_diagonal_wall_sliding()
	_test_autopilot_from_bank()
	_test_all_dock_pairs(0)
	_test_all_dock_pairs(3)
	_release_keys()
	print("Boat recovery: %d checks, %d failures" % [_checks, _failures])
	_game.free()
	quit(0 if _failures == 0 else 1)


func _test_physical_thrust() -> void:
	_fixture(Vector3(0, 0.25, 15), 0.0)
	_hold(KEY_W, 120)
	_check(_game.boat.position.z < 10.0, "Physical W must advance the boat along its heading")
	_fixture(Vector3(0, 0.25, 15), 0.0)
	_hold(KEY_S, 120)
	_check(_game.boat.position.z > 17.0, "Physical S must reverse the boat along its heading")


func _test_turn_only() -> void:
	for key: Key in [KEY_A, KEY_D]:
		_fixture(Vector3(0, 0.25, 15), 0.0)
		_hold(key, 30)
		_check(absf(_game.heading) > 0.8, "A/D alone must change boat heading")
		_check(Vector2(_game.boat.position.x, _game.boat.position.z - 15.0).length() < 0.0001, "A/D alone must not generate forward or reverse thrust")


func _test_turn_at_bank_then_reverse() -> void:
	_fixture(Vector3(-5.1, 0.25, 15), 0.0)
	_hold(KEY_A, 52)
	_check(_game.heading < -1.5 and _game.heading > -1.6, "Physical A must turn the boat from an along-bank position toward the bank")
	var start: Vector3 = _game.boat.position
	_hold(KEY_S, 120)
	_check(_game.boat.position.x - start.x > 1.0, "After turning toward the bank, S must back out instead of deadlocking; " + _state())


func _test_existing_overlap_recovery() -> void:
	for bank: Dictionary in BANKS:
		for key: Key in [KEY_W, KEY_S]:
			var angle: float = bank.inward + (PI if key == KEY_W else 0.0)
			_fixture(bank.pos, angle)
			_key(key, true)
			var never_inward: bool = true
			var previous: Vector3 = bank.pos
			for frame: int in range(120):
				_step()
				var change: Vector3 = _game.boat.position - previous
				if change.dot(bank.out) < -0.0001:
					never_inward = false
				previous = _game.boat.position
			_key(key, false)
			var escaped: float = (_game.boat.position - bank.pos).dot(bank.out)
			_check(escaped > 1.0, "%s must permit %s to recover an already overlapping hull; %s" % [bank.name, "W" if key == KEY_W else "S", _state()])
			_check(never_inward, "Overlap recovery must never move further into " + bank.name)


func _test_block_deeper_overlap() -> void:
	for bank: Dictionary in BANKS:
		for key: Key in [KEY_W, KEY_S]:
			var angle: float = bank.inward + (PI if key == KEY_S else 0.0)
			_fixture(bank.pos, angle)
			_hold(key, 120)
			var change: Vector3 = _game.boat.position - bank.pos
			change.y = 0.0
			_check(change.length() < 0.001, "%s must reject %s that deepens an existing hull overlap" % [bank.name, "W" if key == KEY_W else "S"])


func _test_safe_wall_contact() -> void:
	for bank: Dictionary in BANKS:
		_fixture(bank.pos + bank.out * 1.5, bank.inward)
		_hold(KEY_W, 240)
		var gap: float = (_game.boat.position - bank.pos).dot(bank.out)
		# The fixture center is .9 from the solid bank. A full axial hull
		# requires 1.0 + .52 clearance, so the extra gap must remain >= .62.
		_check(gap >= 0.619 and gap < 0.9, "An initially safe hull must approach but never enter " + bank.name)


func _test_diagonal_wall_sliding() -> void:
	_fixture(Vector3(-4.6, 0.25, 15), -PI / 4.0)
	_hold(KEY_W, 120)
	_check(_game.boat.position.z < 14.0, "Diagonal thrust into the bank must retain motion along the bank; " + _state())
	_check(_game.boat.position.x >= -4.774, "Sliding must keep the leading hull tip outside the bank")


func _test_autopilot_from_bank() -> void:
	_fixture(Vector3(-5.1, 0.25, 15), -PI / 2.0)
	var goal: Vector3 = Vector3(0, 0.25, 0)
	_game._navigate_to(goal)
	for frame: int in range(60 * 30):
		_step()
		if Vector2(_game.boat.position.x, _game.boat.position.z).length() < 1.0:
			break
	_check(Vector2(_game.boat.position.x, _game.boat.position.z).length() < 1.0, "Autopilot must recover from a bank overlap and reach open water; " + _state())


func _test_all_dock_pairs(level: int) -> void:
	# Run the existing gameplay test's thirty routes with in-memory progress,
	# so even test setup never reads the player's save to take a snapshot.
	# Preserve its benchmark navigation mode, which retries an overshot final
	# waypoint. Physical keyboard movement is covered above without this mode.
	_game.benchmark = true
	_game.voyage.level = level
	for origin: Dictionary in VoyageLogic.DOCKS:
		for destination: Dictionary in VoyageLogic.DOCKS:
			if origin.id == destination.id:
				continue
			_fixture(origin.pos, 0.0)
			_game.voyage.target_id = int(destination.id)
			_game._navigate_to(destination.pos)
			var reached: bool = false
			for frame: int in range(60 * 150):
				_step()
				var difference: Vector3 = _game.boat.position - destination.pos
				difference.y = 0.0
				if difference.length() < 1.4 and absf(_game.speed) < 2.0:
					reached = true
					break
			_check(reached, "Level %d dock %d -> %d must still arrive through real steering and hull collision; %s" % [level, int(origin.id), int(destination.id), _state()])
	_game.benchmark = false


func _fixture(position: Vector3, angle: float) -> void:
	_release_keys()
	_game.boat.position = position
	_game.heading = angle
	_game.speed = 0.0
	_game.route_nodes.clear()
	_game.route_visual.visible = false
	_game.destination_marker.visible = false
	_game.voyage._dwell = -100000.0


func _hold(code: Key, frames: int) -> void:
	_key(code, true)
	for frame: int in range(frames):
		_step()
	_key(code, false)


func _step() -> void:
	_game._physics_process(STEP)


func _release_keys() -> void:
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key(code, false)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _state() -> String:
	return "position=%s heading=%.3f speed=%.3f" % [str(_game.boat.position), float(_game.heading), float(_game.speed)]


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL: " + description)
