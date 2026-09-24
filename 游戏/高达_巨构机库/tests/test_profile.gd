extends SceneTree

func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/profile.gd"):
		push_error("Missing real save profile")
		quit(1)
		return
	var Profile = load("res://scripts/profile.gd")
	var p = Profile.new("user://profile_test.json")
	p.completed = []
	p.mark_complete("rx78")
	p.mark_complete("rx78")
	p.mark_complete("invalid-machine")
	assert(p.completed == ["rx78"], "Only valid unique visits persist")
	p.settings.fov = 72.0
	assert(p.write(), "Profile must write successfully")
	var q = Profile.new("user://profile_test.json")
	q.read()
	assert(q.completed == ["rx78"] and is_equal_approx(q.settings.fov, 72.0), "Progress and settings survive reload")
	var f := FileAccess.open("user://profile_test.json", FileAccess.WRITE)
	f.store_string('{"completed":["nu","nu",3,"oops"],"settings":{"fov":200,"sensitivity":-1,"sound":"oops"}}')
	f.close()
	q.read()
	assert(q.completed == ["nu"], "Corrupt input filters IDs and duplicates")
	assert(q.settings.fov == 80.0 and q.settings.sensitivity == 0.5 and q.settings.sound == true, "Settings validate ranges and types")
	f = FileAccess.open("user://profile_test.json", FileAccess.WRITE)
	f.store_string("not valid json")
	f.close()
	q.read()
	assert(q.completed.is_empty(), "Malformed profile recovers safely")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://profile_test.json"))
	print("PROFILE PASS valid unique visits, durable settings, corrupt recovery")
	quit(0)
