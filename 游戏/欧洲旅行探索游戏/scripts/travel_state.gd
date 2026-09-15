extends RefCounted

var stamps: Array[String] = []
var visited: Array[String] = []
var photos: Array[String] = []
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var elapsed: float = 0.0
var last_warning: String = ""
var settings: Dictionary = {"sensitivity": 0.0018, "volume": 0.55, "quality": 1, "resolution": 0, "fullscreen": false}
var known_landmarks: Array[String] = []
var known_buildings: Array[String] = []

func configure(landmark_ids: Array, building_ids: Array) -> void:
	known_landmarks.assign(landmark_ids)
	known_buildings.assign(building_ids)

func reset(spawn: Vector3) -> void:
	stamps.clear()
	visited.clear()
	photos.clear()
	position = spawn
	yaw = 0.0
	pitch = 0.0
	elapsed = 0.0
	last_warning = ""

func collect_stamp(id: String) -> bool:
	if id not in known_landmarks or id in stamps:
		return false
	stamps.append(id)
	return true

func visit_building(id: String) -> bool:
	if id not in known_buildings or id in visited:
		return false
	visited.append(id)
	return true

func journey_complete() -> bool:
	if known_landmarks.is_empty():
		return false
	for id: String in known_landmarks:
		if id not in stamps:
			return false
	return true

func nearest_interaction(actions: Array, from: Vector3, radius: float) -> Dictionary:
	var nearest: Dictionary = {}
	var distance_squared: float = radius * radius
	for item: Variant in actions:
		if not item is Dictionary or not valid_vector(item.get("position", null)):
			continue
		var point: Vector3 = to_vector(item["position"])
		var distance: float = from.distance_squared_to(point)
		if distance <= distance_squared:
			nearest = item
			distance_squared = distance
	return nearest

func valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)):
			return false
		if absf(float(component)) > 100000:
			return false
	return true

func to_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _valid_payload(data: Dictionary) -> bool:
	var version: Variant = data.get("version", null)
	return (version is int or version is float) and is_finite(float(version)) and float(version) == 1.0 and valid_vector(data.get("position", null)) and data.get("stamps", null) is Array

func apply_save(data: Dictionary) -> bool:
	if not _valid_payload(data):
		return false
	var clean_stamps: Array[String] = []
	var clean_visited: Array[String] = []
	for value: Variant in data.get("stamps", []):
		if value is String and value in known_landmarks and value not in clean_stamps:
			clean_stamps.append(value)
	var visit_data: Variant = data.get("visited", [])
	if visit_data is Array:
		for value: Variant in visit_data:
			if value is String and value in known_buildings and value not in clean_visited:
				clean_visited.append(value)
	stamps = clean_stamps
	visited = clean_visited
	position = to_vector(data["position"])
	yaw = _number(data.get("yaw", 0.0), 0.0, -1000, 1000)
	pitch = _number(data.get("pitch", 0.0), 0.0, -1.35, 1.35)
	elapsed = _number(data.get("elapsed", 0.0), 0.0, 0, 100000000)
	photos.clear()
	var photo_data: Variant = data.get("photos", [])
	if photo_data is Array:
		for value: Variant in photo_data:
			if value is String and value.begins_with("user://photos/"):
				photos.append(value)
	var options: Variant = data.get("settings", {})
	if options is Dictionary:
		settings["sensitivity"] = _number(options.get("sensitivity", 0.0018), 0.0018, 0.0005, 0.006)
		settings["volume"] = _number(options.get("volume", 0.55), 0.55, 0.0, 1.0)
		settings["quality"] = int(_number(options.get("quality", 1), 1, 0, 2))
		settings["resolution"] = int(_number(options.get("resolution", 0), 0, 0, 2))
		var fullscreen_value: Variant = options.get("fullscreen", false)
		settings["fullscreen"] = fullscreen_value is bool and fullscreen_value
	return true

func _number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value), minimum, maximum)
	return fallback

func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		return {}
	return parser.data

func load_from(path: String) -> bool:
	last_warning = ""
	if apply_save(_read_dictionary(path)):
		return true
	if apply_save(_read_dictionary(path + ".bak")):
		last_warning = "最近的存档无法读取，已恢复上一份旅行备份。"
		return true
	if FileAccess.file_exists(path):
		last_warning = "旅行存档已损坏，可开始新的旅行；原文件仍保留。"
	return false

func save_to(path: String) -> bool:
	var data: Dictionary = {"version": 1, "position": [position.x, position.y, position.z], "yaw": yaw, "pitch": pitch,
		"stamps": stamps, "visited": visited, "photos": photos, "elapsed": elapsed, "settings": settings,
		"saved_unix": Time.get_unix_time_from_system()}
	if not _valid_payload(data):
		last_warning = "当前位置无效，未覆盖已有存档。"
		return false
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_warning = "存档目录无法写入。"
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if not _valid_payload(_read_dictionary(temporary)):
		last_warning = "存档校验失败，已有进度已保留。"
		return false
	if _valid_payload(_read_dictionary(path)):
		var backup_error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
		if backup_error != OK:
			last_warning = "无法更新旅行备份，已有进度已保留。"
			return false
	var result: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if result != OK:
		last_warning = "无法完成存档写入。"
	return result == OK
