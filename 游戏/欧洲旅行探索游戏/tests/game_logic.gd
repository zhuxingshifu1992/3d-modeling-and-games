extends SceneTree

# Regression targets: duplicate/unknown stamps must not complete a journey;
# corrupted primary saves must recover the last verified backup; floor-to-floor
# interactions must use full 3D distance rather than only the ground plane.
var failures: Array[String] = []
var assertions: int = 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not FileAccess.file_exists("res://scripts/travel_state.gd"):
		check(false, "Travel progression/save implementation is missing")
		finish()
		return
	var state_script: Script = load("res://scripts/travel_state.gd")
	var state: RefCounted = state_script.new()
	state.configure(["fr", "it", "ch", "de"], ["cafe"])
	check(state.collect_stamp("fr"), "First known landmark awards a stamp")
	check(not state.collect_stamp("fr"), "Duplicate landmark never awards twice")
	check(not state.collect_stamp("unknown"), "Unknown landmark never advances journey")
	check(state.stamps.size() == 1 and not state.journey_complete(), "Duplicates cannot complete the passport")
	state.collect_stamp("it")
	state.collect_stamp("ch")
	check(not state.journey_complete(), "Three countries cannot complete four-country journey")
	state.collect_stamp("de")
	check(state.journey_complete(), "Four distinct known landmarks complete the journey")
	check(state.visit_building("cafe") and not state.visit_building("cafe"), "Building visit is idempotent")
	var actions: Array = [{"id": "above", "position": [0, 5, 0]}, {"id": "edge", "position": [3, 0, 0]}]
	check(state.nearest_interaction(actions, Vector3.ZERO, 3.0).get("id", "") == "edge", "Exact interaction radius includes edge but excludes upstairs")
	check(state.nearest_interaction(actions, Vector3.ZERO, 2.99).is_empty(), "Outside interaction radius cannot activate")
	var audit_directory: String = OS.get_environment("EUROPE_AUDIT_TEST_DIR")
	var path: String = audit_directory.path_join("game_logic_test.json") if not audit_directory.is_empty() else "user://game_logic_test.json"
	state.position = Vector3(12, 1.7, -4)
	check(state.save_to(path), "First save writes verified JSON")
	state.position = Vector3(18, 2, -7)
	check(state.save_to(path), "Second save keeps a backup")
	var restored: RefCounted = state_script.new()
	restored.configure(["fr", "it", "ch", "de"], ["cafe"])
	check(restored.load_from(path), "Saved journey reloads")
	check(restored.position.is_equal_approx(Vector3(18, 2, -7)) and restored.journey_complete(), "Position and full passport survive save roundtrip")
	var broken: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{corrupt-primary")
	broken.close()
	check(restored.load_from(path), "Corrupted primary falls back to the backup")
	check(restored.position.is_equal_approx(Vector3(12, 1.7, -4)), "Recovery returns previous verified position")
	check(not restored.last_warning.is_empty(), "Save recovery is visible to the player")
	var invalid: Dictionary = {"version": 1, "position": [0, "bad", 3], "stamps": ["fr"]}
	check(not restored.apply_save(invalid), "Invalid vector data is rejected rather than becoming a zero position")
	check(restored.journey_complete(), "Rejected save must not erase existing progression")
	# A partially corrupted but syntactically valid save must not call int() on
	# container values, throw, or bypass the backup-recovery path.
	for bad_version: Variant in [[], {"unexpected": 1}]:
		var malformed: Dictionary = {"version": bad_version, "position": [0, 0, 0], "stamps": []}
		check(not restored.apply_save(malformed), "Array/object save version is rejected without a type error")
		check(restored.journey_complete(), "Malformed version must preserve the current passport")
	var clean_options: RefCounted = state_script.new()
	clean_options.configure(["fr"], [])
	check(clean_options.apply_save({"version": 1, "position": [0, 0, 0], "stamps": ["fr"],
		"settings": {"sensitivity": [], "volume": {}, "quality": NAN, "resolution": INF, "fullscreen": {}}}),
		"Malformed option values do not reject otherwise valid travel progress")
	check(is_equal_approx(clean_options.settings.sensitivity, 0.0018) and is_equal_approx(clean_options.settings.volume, 0.55),
		"Malformed numeric options fall back to usable defaults")
	check(clean_options.settings.quality == 1 and clean_options.settings.resolution == 0 and clean_options.settings.fullscreen == false,
		"Nonfinite discrete options and malformed fullscreen values are sanitized")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	finish()

func finish() -> void:
	print("GAME_LOGIC_RESULT ", JSON.stringify({"assertions": assertions, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
