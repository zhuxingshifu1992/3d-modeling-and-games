class_name Voyage
extends RefCounted

## Lightweight gameplay and canal navigation, independent of scene nodes.
const DOCKS: Array = [
	{"id": 0, "name": "潟湖码头", "pos": Vector3(0.0, 0.25, 29.5)},
	{"id": 1, "name": "彩屋码头", "pos": Vector3(-4.4, 0.25, 19.0)},
	{"id": 2, "name": "圣马可广场", "pos": Vector3(4.4, 0.25, -8.0)},
	{"id": 3, "name": "北岸花园", "pos": Vector3(-18.0, 0.25, -28.5)},
	{"id": 4, "name": "宫殿码头", "pos": Vector3(33.3, 0.25, 12.0)},
	{"id": 5, "name": "咖啡小港", "pos": Vector3(-33.3, 0.25, 10.0)},
]
const ISLANDS: Array[Rect2] = [
	Rect2(-31.0, -26.0, 25.0, 22.0),
	Rect2(6.0, -26.0, 25.0, 22.0),
	Rect2(-31.0, 4.0, 25.0, 20.0),
	Rect2(6.0, 4.0, 25.0, 20.0),
	Rect2(-27.25, 23.6, 8.5, 4.8),
]
const TRIP_ORDER: Array[int] = [0, 2, 3, 5, 1, 4]
const PASSENGERS: Array[String] = ["摄影师安娜", "画家卢卡", "花匠米娅", "咖啡师里奥", "旅行家艾拉", "乐手马可"]
const UPGRADE_COSTS: Array[int] = [60, 120, 180]
const BOAT_MARGIN: float = 0.8
const DOCK_RADIUS: float = 2.8
const DOCK_SPEED: float = 2.0
const DOCK_DWELL: float = 1.0
const FARE: int = 35
const DAY_BONUS: int = 60
const COIN_VALUE: int = 5
const MAX_WALLET: int = 10000000
const MAX_COMPLETED: int = 1000000

var wallet: int = 0
var completed: int = 0
var stage: String = "pickup"
var target_id: int = 0
var passenger_name: String = ""
var level: int = 0
var coin_bonus: int = 0

var _dwell: float = 0.0
var _collected_coins: Dictionary = {}


func _init() -> void:
	reset_trip()


func reset_trip() -> void:
	stage = "pickup"
	var trip_index: int = posmod(completed, TRIP_ORDER.size())
	target_id = TRIP_ORDER[trip_index]
	passenger_name = PASSENGERS[trip_index]
	_dwell = 0.0


func target() -> Dictionary:
	return DOCKS[clampi(target_id, 0, DOCKS.size() - 1)].duplicate()


func update_at_position(pos: Vector3, speed: float, delta: float) -> Dictionary:
	if not pos.is_finite() or not is_finite(speed) or not is_finite(delta) or delta <= 0.0:
		_dwell = 0.0
		return {}
	var destination: Vector3 = target()["pos"]
	var distance: float = Vector2(pos.x, pos.z).distance_to(Vector2(destination.x, destination.z))
	if distance >= DOCK_RADIUS or absf(speed) >= DOCK_SPEED:
		_dwell = 0.0
		return {}
	_dwell += delta
	if _dwell + 0.000001 < DOCK_DWELL:
		return {}
	_dwell = 0.0
	if stage == "pickup":
		stage = "delivery"
		target_id = TRIP_ORDER[posmod(completed + 1, TRIP_ORDER.size())]
		return {
			"type": "pickup", "reward": 0,
			"text": "%s上船了，前往%s吧。" % [passenger_name, String(target()["name"])],
			"target_id": target_id, "completed": completed,
		}
	if stage != "delivery":
		reset_trip()
		return {}
	completed = mini(completed + 1, MAX_COMPLETED)
	var milestone: bool = completed % 5 == 0
	var reward: int = FARE + (DAY_BONUS if milestone else 0)
	var awarded: int = mini(reward, MAX_WALLET - wallet)
	wallet += awarded
	var dock_name: String = String(target()["name"])
	reset_trip()
	var event_type: String = "day_complete" if milestone else "delivery"
	var event_text: String = "抵达%s，船费 +%d 金币。" % [dock_name, awarded]
	if milestone:
		event_text = "五次接送完成！船费与慢游奖励共 +%d 金币，继续自在航行吧。" % awarded
	return {"type": event_type, "text": event_text, "reward": awarded, "completed": completed, "target_id": target_id}


func status() -> Dictionary:
	return {
		"wallet": wallet, "completed": completed, "stage": stage,
		"target_id": target_id, "target_name": String(target()["name"]),
		"passenger_name": passenger_name, "level": level, "coin_bonus": coin_bonus,
		"day": floori(float(completed) / 5.0) + 1, "day_completed": completed % 5, "day_goal": 5,
		"dwell": _dwell, "dwell_progress": clampf(_dwell / DOCK_DWELL, 0.0, 1.0),
		"upgrade_cost": upgrade_cost(), "can_upgrade": level < UPGRADE_COSTS.size() and wallet >= upgrade_cost(),
		"speed": 5.0 + float(level) * 0.8, "next_fare": FARE,
	}


func upgrade_cost() -> int:
	if level >= UPGRADE_COSTS.size():
		return 0
	return UPGRADE_COSTS[maxi(level, 0)]


func purchase_upgrade() -> bool:
	if level < 0 or level >= UPGRADE_COSTS.size():
		return false
	var cost: int = upgrade_cost()
	if wallet < cost:
		return false
	wallet -= cost
	level += 1
	return true


func collect_coin(coin_id: int) -> int:
	if coin_id < 0 or _collected_coins.has(coin_id):
		return 0
	_collected_coins[coin_id] = true
	var awarded: int = mini(COIN_VALUE, MAX_WALLET - wallet)
	wallet += awarded
	coin_bonus += awarded
	return awarded


func save(path: String = "user://save.json") -> bool:
	if wallet < 0 or wallet > MAX_WALLET or completed < 0 or completed > MAX_COMPLETED or level < 0 or level > 3:
		return false
	var pending_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(pending_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "wallet": wallet, "completed": completed, "level": level}))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
		return false
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(pending_path), ProjectSettings.globalize_path(path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
		return false
	return true


func load_save(path: String = "user://save.json") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	# A progress file is tiny; avoid parsing unrelated or damaged large files.
	if file.get_length() > 4096:
		file.close()
		return false
	var contents: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(contents) != OK:
		return false
	var data: Variant = parser.data
	if not data is Dictionary:
		return false
	var record: Dictionary = data
	if not _valid_saved_integer(record.get("wallet"), 0, MAX_WALLET):
		return false
	if not _valid_saved_integer(record.get("completed"), 0, MAX_COMPLETED):
		return false
	if not _valid_saved_integer(record.get("level"), 0, UPGRADE_COSTS.size()):
		return false
	if record.has("version") and not _valid_saved_integer(record["version"], 1, 1):
		return false
	# Validation completes before touching any active gameplay state.
	wallet = int(record["wallet"])
	completed = int(record["completed"])
	level = int(record["level"])
	coin_bonus = 0
	_collected_coins.clear()
	reset_trip()
	return true


func _valid_saved_integer(value: Variant, lower: int, upper: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= float(lower) and number <= float(upper) and number == floor(number)


func is_water(pos: Vector3, margin: float = BOAT_MARGIN) -> bool:
	if not pos.is_finite() or not is_finite(margin):
		return false
	var padding: float = maxf(0.0, margin)
	if absf(pos.x) > 45.0 - padding or absf(pos.z) > 40.0 - padding:
		return false
	for island: Rect2 in ISLANDS:
		if pos.x > island.position.x - padding and pos.x < island.end.x + padding and pos.z > island.position.y - padding and pos.z < island.end.y + padding:
			return false
	return true


func constrain_motion(from: Vector3, to: Vector3) -> Vector3:
	var origin: Vector3 = from if from.is_finite() else Vector3(0.0, 0.25, 34.0)
	if not is_water(origin):
		origin = _nearest_safe_position(origin)
	if not to.is_finite():
		return origin
	var destination: Vector3 = Vector3(clampf(to.x, -44.2, 44.2), origin.y, clampf(to.z, -39.2, 39.2))
	var steps: int = maxi(1, int(ceil(origin.distance_to(destination) / 0.35)))
	var movement: Vector3 = (destination - origin) / float(steps)
	var position: Vector3 = origin
	for step_index: int in range(steps):
		var candidate: Vector3 = position + movement
		if is_water(candidate):
			position = candidate
			continue
		# Resolve each horizontal axis separately to retain wall-sliding motion.
		candidate = position + Vector3(movement.x, 0.0, 0.0)
		if is_water(candidate):
			position = candidate
		candidate = position + Vector3(0.0, 0.0, movement.z)
		if is_water(candidate):
			position = candidate
	return position


func _nearest_safe_position(pos: Vector3) -> Vector3:
	var bounded: Vector3 = Vector3(clampf(pos.x, -44.2, 44.2), pos.y, clampf(pos.z, -39.2, 39.2))
	if is_water(bounded):
		return bounded
	var candidates: Array[Vector3] = [Vector3(0.0, pos.y, 0.0)]
	for island: Rect2 in ISLANDS:
		candidates.append(Vector3(island.position.x - BOAT_MARGIN - 0.01, pos.y, bounded.z))
		candidates.append(Vector3(island.end.x + BOAT_MARGIN + 0.01, pos.y, bounded.z))
		candidates.append(Vector3(bounded.x, pos.y, island.position.y - BOAT_MARGIN - 0.01))
		candidates.append(Vector3(bounded.x, pos.y, island.end.y + BOAT_MARGIN + 0.01))
	var nearest: Vector3 = candidates[0]
	var best_distance: float = INF
	for candidate: Vector3 in candidates:
		var distance: float = candidate.distance_squared_to(bounded)
		if is_water(candidate) and distance < best_distance:
			nearest = candidate
			best_distance = distance
	return nearest


func route(start: Vector3, finish: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not is_water(start) or not is_water(finish):
		return result
	if Vector2(start.x, start.z).distance_to(Vector2(finish.x, finish.z)) < 0.0001:
		result.append(start)
		return result
	# Three canal center lines per axis plus the exact endpoints make a small
	# rectilinear graph. At most 25 nodes are built for a click-to-sail request.
	var xs: Array[float] = [-35.0, 0.0, 35.0]
	var zs: Array[float] = [-30.0, 0.0, 30.0]
	for x: float in [start.x, finish.x]:
		if not xs.has(x):
			xs.append(x)
	for z: float in [start.z, finish.z]:
		if not zs.has(z):
			zs.append(z)
	xs.sort()
	zs.sort()
	var graph: AStar2D = AStar2D.new()
	var width: int = xs.size()
	for zi: int in range(zs.size()):
		for xi: int in range(width):
			var point: Vector3 = Vector3(xs[xi], 0.25, zs[zi])
			if is_water(point):
				graph.add_point(zi * width + xi, Vector2(point.x, point.z))
	for zi: int in range(zs.size()):
		for xi: int in range(width):
			var current_id: int = zi * width + xi
			if not graph.has_point(current_id):
				continue
			if xi + 1 < width:
				_connect_safe_neighbors(graph, current_id, current_id + 1)
			if zi + 1 < zs.size():
				_connect_safe_neighbors(graph, current_id, current_id + width)
	var start_id: int = zs.find(start.z) * width + xs.find(start.x)
	var finish_id: int = zs.find(finish.z) * width + xs.find(finish.x)
	var flat_path: PackedVector2Array = graph.get_point_path(start_id, finish_id)
	for point: Vector2 in flat_path:
		var position: Vector3 = Vector3(point.x, start.y, point.y)
		if result.size() >= 2:
			var previous_direction: Vector3 = result[-1] - result[-2]
			var next_direction: Vector3 = position - result[-1]
			if previous_direction.cross(next_direction).length_squared() < 0.000001 and previous_direction.dot(next_direction) >= 0.0:
				result[-1] = position
				continue
		result.append(position)
	if not result.is_empty():
		result[0] = start
		result[-1] = finish
	return result


func _connect_safe_neighbors(graph: AStar2D, first_id: int, second_id: int) -> void:
	if not graph.has_point(second_id):
		return
	var first: Vector2 = graph.get_point_position(first_id)
	var second: Vector2 = graph.get_point_position(second_id)
	var steps: int = maxi(1, int(ceil(first.distance_to(second) / 0.4)))
	for step_index: int in range(1, steps):
		var sample: Vector2 = first.lerp(second, float(step_index) / float(steps))
		if not is_water(Vector3(sample.x, 0.25, sample.y)):
			return
	graph.connect_points(first_id, second_id)
