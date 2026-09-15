extends SceneTree

const VOYAGE_PATH: String = "res://scripts/voyage.gd"
const SAVE_PATH: String = "user://voyage_self_test.json"
const ISLANDS: Array[Rect2] = [
	Rect2(-31.0, -26.0, 25.0, 22.0),
	Rect2(6.0, -26.0, 25.0, 22.0),
	Rect2(-31.0, 4.0, 25.0, 20.0),
	Rect2(6.0, 4.0, 25.0, 20.0),
	Rect2(-27.25, 23.6, 8.5, 4.8),
]

var _script: Script
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	if not ResourceLoader.exists(VOYAGE_PATH):
		_check(false, "Voyage gameplay implementation must exist")
		_finish()
		return
	_script = load(VOYAGE_PATH) as Script
	if _script == null or not _script.can_instantiate():
		_check(false, "Voyage gameplay implementation must compile")
		_finish()
		return
	_test_dwell_and_trip_cycle()
	_test_coins_and_upgrades()
	_test_routes()
	_test_motion()
	_test_save_validation()
	_finish()


func _test_dwell_and_trip_cycle() -> void:
	var game: RefCounted = _script.new()
	var event: Dictionary = game.update_at_position(Vector3(0, 0.25, 29.5), 2.1, 2.0)
	_check(event.is_empty(), "Passing a dock too fast must not board a passenger")
	event = game.update_at_position(Vector3(0, 0.25, 29.5), 0.0, 0.6)
	_check(event.is_empty(), "Boarding must wait for one second of stopped dwell")
	game.update_at_position(Vector3(0, 0.25, 34), 0.0, 0.1)
	event = game.update_at_position(Vector3(0, 0.25, 29.5), 0.0, 0.6)
	_check(event.is_empty(), "Leaving a dock must reset its dwell timer")
	event = game.update_at_position(Vector3(0, 0.25, 29.5), 0.0, 0.4)
	_check(event.get("type") == "pickup", "Stopped dwell must board a passenger")
	_check(game.target_id == 2, "The first passenger must travel to Saint Mark's dock")
	_check(game.wallet == 0, "A pickup must not pay a delivery reward")
	for delivery_index: int in range(5):
		var destination: Dictionary = game.target()
		var destination_pos: Vector3 = destination["pos"]
		event = game.update_at_position(destination_pos, 0.0, 1.0)
		var expected_event: String = "day_complete" if delivery_index == 4 else "delivery"
		_check(event.get("type") == expected_event, "Every fifth completed delivery must emit the day milestone")
		_check(int(event.get("reward", 0)) > 0, "A completed delivery must award coins")
		var paid_wallet: int = game.wallet
		for hold_frame: int in range(20):
			game.update_at_position(destination_pos, 0.0, 0.1)
		_check(game.wallet == paid_wallet, "Holding at a delivered dock must not repeat its fare")
		if delivery_index < 4 and game.stage == "pickup":
			var pickup: Dictionary = game.target()
			game.update_at_position(pickup["pos"], 0.0, 1.0)
	_check(game.completed == 5, "Five deliveries must remain recorded across the milestone")
	_check(game.wallet > 0, "A milestone must preserve the wallet")
	_check(game.stage == "pickup" or game.stage == "delivery", "Milestones must permit continued play")
	game.reset_trip()
	_check(game.completed == 5 and game.wallet > 0, "Resetting the current trip must preserve progress")
	var summary: Dictionary = game.status()
	_check(int(summary.get("completed", -1)) == 5, "Status must expose saved delivery progress")


func _test_coins_and_upgrades() -> void:
	var game: RefCounted = _script.new()
	_check(not game.purchase_upgrade(), "An empty wallet must not buy an upgrade")
	var bonus: int = game.collect_coin(42)
	_check(bonus > 0 and game.wallet == bonus, "A travel coin must credit its bonus")
	_check(game.collect_coin(42) == 0 and game.wallet == bonus, "Collecting the same coin must not credit it twice")
	_check(game.collect_coin(-1) == 0, "Invalid coin IDs must not generate rewards")
	game.wallet = 10000
	for upgrade_index: int in range(3):
		var before: int = game.wallet
		var cost: int = game.upgrade_cost()
		_check(cost > 0 and game.purchase_upgrade(), "A funded available upgrade must succeed")
		_check(game.wallet == before - cost and game.level == upgrade_index + 1, "Upgrades must deduct exactly their displayed cost")
	var final_wallet: int = game.wallet
	_check(not game.purchase_upgrade() and game.wallet == final_wallet, "Maximum-level upgrades must not charge again")
	_check(game.level == 3, "Boat upgrades must stop at level three")
	var poor_game: RefCounted = _script.new()
	poor_game.wallet = poor_game.upgrade_cost() - 1
	_check(not poor_game.purchase_upgrade() and poor_game.level == 0, "One coin below the cost must not buy an upgrade")


func _test_routes() -> void:
	var game: RefCounted = _script.new()
	var positions: Array[Vector3] = [
		Vector3(0, 0.25, 29.5), Vector3(-4.4, 0.25, 19),
		Vector3(4.4, 0.25, -8), Vector3(-18, 0.25, -28.5),
		Vector3(33.3, 0.25, 12), Vector3(-33.3, 0.25, 10),
		Vector3(-22, 0.25, 31), Vector3(42, 0.25, 35),
	]
	for origin: Vector3 in positions:
		for destination: Vector3 in positions:
			var points: Array[Vector3] = game.route(origin, destination)
			_check(not points.is_empty(), "Water positions must have a navigable canal route")
			if points.is_empty():
				continue
			_check(points[0].distance_to(origin) < 0.01, "Routes must begin at the requested boat position")
			_check(points[-1].distance_to(destination) < 0.01, "Routes must finish at the requested water position")
			for segment_index: int in range(1, points.size()):
				var segment_start: Vector3 = points[segment_index - 1]
				var segment_end: Vector3 = points[segment_index]
				var samples: int = maxi(1, int(ceil(segment_start.distance_to(segment_end) / 0.25)))
				for sample_index: int in range(samples + 1):
					var sample: Vector3 = segment_start.lerp(segment_end, float(sample_index) / float(samples))
					_check(_independent_water(sample), "Route segments must avoid island interiors including the cafe terrace")
	var blocked: Array[Vector3] = game.route(Vector3(0, 0.25, 0), Vector3(18, 0.25, 12))
	_check(blocked.is_empty(), "A destination inside a building island must not produce an unsafe route")


func _test_motion() -> void:
	var game: RefCounted = _script.new()
	var stopped: Vector3 = game.constrain_motion(Vector3(0, 0.25, 12), Vector3(40, 0.25, 12))
	_check(stopped.x <= 5.21 and _independent_water(stopped), "Large moves must not tunnel across an island")
	var sliding: Vector3 = game.constrain_motion(Vector3(5.0, 0.25, 10), Vector3(7.0, 0.25, 14))
	_check(sliding.z > 13.5 and sliding.x <= 5.21, "Diagonal contact must preserve motion along the canal wall")
	var bounded: Vector3 = game.constrain_motion(Vector3(35, 0.25, 30), Vector3(100, 0.25, 100))
	_check(absf(bounded.x) <= 44.2 and absf(bounded.z) <= 39.2, "World edges must retain the boat within a safe water margin")
	var terrace: Vector3 = game.constrain_motion(Vector3(-22, 0.25, 31), Vector3(-22, 0.25, 22))
	_check(terrace.z >= 29.19, "The cafe terrace must stop a boat as a solid obstruction")
	_check(not game.is_water(Vector3(20, 0.25, 14)), "Island interiors must not be navigable water")
	_check(game.is_water(Vector3(0, 0.25, 0)), "The central canal intersection must be navigable")


func _test_save_validation() -> void:
	var game: RefCounted = _script.new()
	game.wallet = 321
	game.completed = 7
	game.level = 2
	_check(game.save(SAVE_PATH), "A progress save must write successfully")
	game.wallet = 322
	_check(game.save(SAVE_PATH), "Autosaving must replace an existing progress file")
	game.wallet = 321
	_check(game.save(SAVE_PATH), "Repeated autosaves must remain writable")
	var restored: RefCounted = _script.new()
	_check(restored.load_save(SAVE_PATH), "A valid progress save must load")
	_check(restored.wallet == 321 and restored.completed == 7 and restored.level == 2, "Save/load must preserve wallet, deliveries, and upgrades")
	_check(restored.stage == "pickup", "Loading progress must start a fresh playable pickup")
	_write_fixture("{this is corrupt")
	_check(not restored.load_save(SAVE_PATH), "Malformed JSON must be rejected safely")
	_check(restored.wallet == 321 and restored.completed == 7 and restored.level == 2, "Rejected saves must preserve the active game")
	_write_fixture('{"wallet": -80, "completed": "broken", "level": 9999}')
	_check(not restored.load_save(SAVE_PATH), "Corrupted or out-of-range save fields must be rejected")
	_check(restored.wallet == 321 and restored.completed == 7 and restored.level == 2, "Invalid field validation must be atomic")
	_write_fixture('{"wallet": 12.5, "completed": 1, "level": 1}')
	_check(not restored.load_save(SAVE_PATH), "Fractional currency must not be silently accepted")
	_write_fixture('{"wallet": 12, "completed": 1, "level": true}')
	_check(not restored.load_save(SAVE_PATH), "Boolean values must not be silently interpreted as upgrade levels")
	_write_fixture('{"wallet": 12, "completed": 1, "level": 1, "version": 999}')
	_check(not restored.load_save(SAVE_PATH), "Unknown save versions must preserve the current game")
	_write_fixture('{"wallet": 12, "completed": 1, "level": 1}')
	_check(restored.load_save(SAVE_PATH), "A legacy save without optional metadata must still load")
	_check(restored.wallet == 12 and restored.completed == 1 and restored.level == 1, "Legacy saves must restore valid values")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _independent_water(point: Vector3) -> bool:
	if absf(point.x) > 44.2001 or absf(point.z) > 39.2001:
		return false
	for island: Rect2 in ISLANDS:
		var expanded: Rect2 = island.grow(0.7999)
		if expanded.has_point(Vector2(point.x, point.z)):
			return false
	return true


func _write_fixture(contents: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_check(false, "Save test fixture must be writable")
		return
	file.store_string(contents)
	file.close()


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL: " + description)


func _finish() -> void:
	print("Voyage tests: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
