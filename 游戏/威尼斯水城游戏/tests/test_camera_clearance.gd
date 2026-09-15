extends SceneTree

## Exercise the real follow-camera integration against the actual city boxes.
## Godot's built-in segment/AABB query is the independent geometry oracle;
## this test does not call CameraRig.line_clear or CameraRig.safe_follow.
## No user save is read, written, or snapshotted by this test process.
const MainScene: Script = preload("res://scripts/main.gd")
const VoyageLogic: Script = preload("res://scripts/voyage.gd")
const CAMERA_CLEARANCE: float = 0.25
const STEP: float = 1.0 / 60.0
const HEADINGS: Array[float] = [0.0, PI / 2.0, PI, -PI / 2.0]
const YAW_OFFSETS: Array[float] = [0.20, PI / 2.0, PI, -PI / 2.0]
const DISTANCES: Array[float] = [11.0, 30.0, 56.0]
const PITCHES: Array[float] = [0.32, 1.10, 1.30]

class MemoryVoyage:
	extends "res://scripts/voyage.gd"

	func save(_path: String = "") -> bool:
		return true

	func load_save(_path: String = "") -> bool:
		return false


var _game: Node3D
var _boxes: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _sample_positions: Dictionary = {}
var _checks: int = 0
var _failures: int = 0
var _camera_updates: int = 0
var _obstructed_desires: int = 0
var _focus_conflicts: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless" or not "--benchmark" in OS.get_cmdline_user_args():
		printerr("Camera clearance tests require --headless and -- --benchmark; no desktop game or player save may be used.")
		quit(2)
		return
	_game = MainScene.new()
	root.add_child(_game)
	_game.set_process(false)
	_game.set_physics_process(false)
	_game.bench_done = true
	_game.bench_seconds = 1000000000.0
	_game.muted = true
	_game.voyage = MemoryVoyage.new()
	_game.voyage.stage = "camera_clearance_test"
	_game.camera_mode = "follow"
	_check(_game.benchmark, "Main must remain in benchmark mode throughout camera testing")
	_load_independent_boxes()
	_build_water_samples()
	_check(_samples.size() > 200, "Camera coverage must include a substantial water and shoreline sample set")
	for sample: Dictionary in _samples:
		var focus: Vector3 = sample.pos + Vector3.UP
		var containing: String = _first_focus_container(focus)
		if not containing.is_empty():
			_focus_conflicts += 1
			_check(false, "Legal water focus falls inside building proxy: sample=%s boat=%s focus=%s box=%s" % [sample.name, sample.pos, focus, containing])
			continue
		_test_follow_at_sample(sample)
	_check(_focus_conflicts == 0, "No navigable-water focus may be enclosed by an architectural proxy")
	_check(_obstructed_desires > 100, "The scenario set must exercise actual building occlusions")
	_check(_camera_updates > 10000, "Both snapped and interpolated follow poses must receive broad coverage")
	print("Camera clearance: %d checks, %d failures; %d water samples, %d camera updates, %d obstructed desired poses, %d focus/proxy conflicts" % [_checks, _failures, _samples.size(), _camera_updates, _obstructed_desires, _focus_conflicts])
	_game.free()
	quit(0 if _failures == 0 else 1)


func _load_independent_boxes() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/camera_occluders.json"))
	_check(data is Dictionary, "Architectural proxy JSON must parse")
	if not data is Dictionary:
		return
	for entry: Dictionary in data.get("boxes", []):
		var low: Array = entry.min
		var high: Array = entry.max
		var origin := Vector3(float(low[0]), float(low[1]), float(low[2]))
		var end := Vector3(float(high[0]), float(high[1]), float(high[2]))
		_boxes.append({"name": String(entry.name), "bounds": AABB(origin, end - origin).grow(CAMERA_CLEARANCE)})
	_check(_boxes.size() == 26, "Independent oracle must load all 26 actual building groups")
	_check(_game.camera_occluders.size() == _boxes.size(), "Production integration must load the complete proxy set")


func _build_water_samples() -> void:
	for dock: Dictionary in VoyageLogic.DOCKS:
		_check(_game.voyage.is_water(dock.pos), "Dock fixture must be navigable: " + dock.name)
		_add_water_sample("dock " + dock.name, dock.pos)
	# Main north/south canal, cross canal, and open-water grid.
	for x: float in [-5.199, -4.4, 0.0, 4.4, 5.199]:
		for z: int in range(-36, 37, 3):
			_add_water_sample("main canal", Vector3(x, 0.25, float(z)))
	for z: float in [-3.199, 0.0, 3.199]:
		for x: int in range(-40, 41, 4):
			_add_water_sample("cross canal", Vector3(float(x), 0.25, z))
	for x: int in range(-44, 45, 4):
		for z: int in range(-36, 37, 4):
			_add_water_sample("water grid", Vector3(float(x), 0.25, float(z)))
	# Sample just outside every solid bank with the actual .8m boat margin,
	# and a second strip where a full-length hull can also turn freely.
	for index: int in range(VoyageLogic.ISLANDS.size()):
		var island: Rect2 = VoyageLogic.ISLANDS[index]
		for bank_gap: float in [0.801, 1.60]:
			for step_index: int in range(11):
				var t: float = float(step_index) / 10.0
				var x: float = lerpf(island.position.x, island.end.x, t)
				var z: float = lerpf(island.position.y, island.end.y, t)
				var label: String = "island %d bank %.3fm" % [index, bank_gap]
				_add_water_sample(label + " west", Vector3(island.position.x - bank_gap, 0.25, z))
				_add_water_sample(label + " east", Vector3(island.end.x + bank_gap, 0.25, z))
				_add_water_sample(label + " north", Vector3(x, 0.25, island.position.y - bank_gap))
				_add_water_sample(label + " south", Vector3(x, 0.25, island.end.y + bank_gap))


func _add_water_sample(label: String, position: Vector3) -> void:
	if not _game.voyage.is_water(position):
		return
	var key := Vector2(position.x, position.z)
	if _sample_positions.has(key):
		return
	_sample_positions[key] = true
	_samples.append({"name": label, "pos": position})


func _test_follow_at_sample(sample: Dictionary) -> void:
	_game.boat.position = sample.pos
	var focus: Vector3 = sample.pos + Vector3.UP
	for heading: float in HEADINGS:
		_game.heading = heading
		for offset: float in YAW_OFFSETS:
			for distance: float in DISTANCES:
				for pitch: float in PITCHES:
					var yaw: float = -heading + offset
					_game.camera_yaw = yaw
					_game.camera_pitch = pitch
					_game.camera_distance = distance
					_game.rotating_camera = true
					_game.orbit_timeout = 2.0
					_game.speed = 0.0
					_game.camera_snap = true
					var desired := focus + Vector3(sin(yaw) * cos(pitch) * distance, sin(pitch) * distance, cos(yaw) * cos(pitch) * distance)
					if not _first_occluder(focus, desired).is_empty():
						_obstructed_desires += 1
					_game._update_camera(STEP)
					_assert_actual_clear(sample, "snap", heading, yaw, distance, pitch)
					# Emulate a previous camera on the other side of the orbit;
					# the rendered interpolated pose must be rechecked as well.
					_game.camera.position = focus + Vector3(-sin(yaw) * distance, 3.0, -cos(yaw) * distance)
					_game.camera_snap = false
					_game.rotating_camera = false
					_game.orbit_timeout = 0.0
					_game.speed = 4.0
					_game._update_camera(STEP)
					_assert_actual_clear(sample, "interpolation + automatic heading", heading, yaw, distance, pitch)


func _assert_actual_clear(sample: Dictionary, phase: String, heading: float, yaw: float, distance: float, pitch: float) -> void:
	_camera_updates += 1
	var focus: Vector3 = _game.boat.global_position + Vector3.UP
	var camera: Vector3 = _game.camera.global_position
	var blocker: String = _first_occluder(focus, camera)
	_check(camera.is_finite() and blocker.is_empty(), "%s: sample=%s boat=%s camera=%s heading=%.3f yaw=%.3f distance=%.1f pitch=%.2f blocker=%s" % [phase, sample.name, sample.pos, camera, heading, yaw, distance, pitch, blocker])


func _first_focus_container(focus: Vector3) -> String:
	for entry: Dictionary in _boxes:
		var bounds: AABB = entry.bounds
		if bounds.has_point(focus):
			return String(entry.name)
	return ""


func _first_occluder(focus: Vector3, camera: Vector3) -> String:
	for entry: Dictionary in _boxes:
		var bounds: AABB = entry.bounds
		if bounds.has_point(focus) or bounds.has_point(camera) or bounds.intersects_segment(focus, camera) != null:
			return String(entry.name)
	return ""


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		if _failures <= 30:
			printerr("FAIL: " + description)
