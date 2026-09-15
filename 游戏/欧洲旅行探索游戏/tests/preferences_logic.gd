extends SceneTree

func _initialize() -> void:
	var scene = load("res://scripts/main.gd").new()
	var audit_directory: String = OS.get_environment("EUROPE_AUDIT_TEST_DIR")
	scene.save_path = audit_directory.path_join("preferences_regression.json") if not audit_directory.is_empty() else "user://preferences_regression.json"
	if not scene.has_method("save_preferences"):
		print("PREFERENCES_FAIL Missing independent preference persistence")
		scene.free()
		quit(1)
		return
	scene.state.settings.sensitivity = 0.004
	scene.state.settings.quality = 2
	scene.save_preferences()
	scene.state.settings.sensitivity = 0.001
	scene.state.settings.quality = 0
	scene.load_preferences()
	var persistence_passed: bool = is_equal_approx(scene.state.settings.sensitivity,0.004) and scene.state.settings.quality == 2 and not scene.can_continue
	var config: ConfigFile = ConfigFile.new()
	config.set_value("preferences", "sensitivity", [])
	config.set_value("preferences", "volume", {"damaged": true})
	config.set_value("preferences", "quality", 500)
	config.set_value("preferences", "resolution", -200)
	config.set_value("preferences", "fullscreen", [1])
	config.save(scene.save_path + ".settings.cfg")
	scene.load_preferences()
	var damaged_options_passed: bool = is_equal_approx(scene.state.settings.sensitivity,0.0018) and is_equal_approx(scene.state.settings.volume,0.55) and scene.state.settings.quality == 2 and scene.state.settings.resolution == 0 and scene.state.settings.fullscreen == false
	var journey_untouched: bool = not FileAccess.file_exists(scene.save_path)
	var passed: bool = persistence_passed and damaged_options_passed and journey_untouched
	print("PREFERENCES_RESULT ", JSON.stringify({"passed":passed,"before_journey":not scene.can_continue,"persistence":persistence_passed,"damaged_options":damaged_options_passed,"journey_untouched":journey_untouched}))
	if FileAccess.file_exists(scene.save_path + ".settings.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(scene.save_path + ".settings.cfg"))
	scene.free()
	quit(0 if passed else 1)
