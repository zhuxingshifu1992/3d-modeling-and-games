extends RefCounted

const VALID_IDS := ["rx78", "unicorn", "nu", "freedom", "wing", "exia"]
var path: String
var completed: Array = []
var settings := {"fov": 65.0, "sensitivity": 1.0, "sound": true}

func _init(save_path: String = "user://pilot_profile.json") -> void:
	path = save_path

func mark_complete(id: String) -> void:
	if id in VALID_IDS and not id in completed:
		completed.append(id)

func read() -> void:
	completed = []
	settings = {"fov": 65.0, "sensitivity": 1.0, "sound": true}
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or not json.data is Dictionary:
		return
	var data: Dictionary = json.data
	if data.get("completed") is Array:
		for id in data.completed:
			if id is String:
				mark_complete(id)
	if data.get("settings") is Dictionary:
		var s: Dictionary = data.settings
		if s.get("fov") is float or s.get("fov") is int:
			settings.fov = clampf(float(s.fov), 55.0, 80.0)
		if s.get("sensitivity") is float or s.get("sensitivity") is int:
			settings.sensitivity = clampf(float(s.sensitivity), 0.5, 2.0)
		if s.get("sound") is bool:
			settings.sound = s.sound

func write() -> bool:
	var pending := path + ".pending"
	var f := FileAccess.open(pending, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": 1, "completed": completed, "settings": settings}, "\t"))
	f.flush()
	var result := f.get_error()
	f.close()
	if result != OK:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(pending), ProjectSettings.globalize_path(path)) == OK
