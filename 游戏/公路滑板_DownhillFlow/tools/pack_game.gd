extends SceneTree

# Run after Godot has imported the project. Only runtime resources enter the PCK.
const OUTPUT := "res://Windows游戏/DownhillFlow.pck.tmp"
const REQUIRED_FILES := ["project.godot", "main.tscn"]
const REQUIRED_FOLDERS := ["scripts", "assets"]
const OPTIONAL_FOLDERS := ["shaders", ".godot/imported"]
const OPTIONAL_FILES := [".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin"]
const SOURCE_EXTENSIONS := ["blend", "blend1", "blend2", "fbx", "zip", "7z", "rar"]

var packer := PCKPacker.new()
var failures: Array[String] = []
var packed_files := 0
var packed_bytes := 0


func _initialize() -> void:
	var output := ProjectSettings.globalize_path(OUTPUT)
	var result := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if result != OK:
		fail("Cannot create package directory: %s" % result)
		return
	result = packer.pck_start(output)
	if result != OK:
		fail("Cannot start package: %s" % result)
		return
	for path: String in REQUIRED_FILES:
		add_file(path)
	for path: String in REQUIRED_FOLDERS:
		add_folder(path)
	for path: String in OPTIONAL_FOLDERS:
		if DirAccess.dir_exists_absolute("res://" + path):
			add_folder(path)
	for path: String in OPTIONAL_FILES:
		if FileAccess.file_exists("res://" + path):
			add_file(path)
	if not failures.is_empty():
		fail(JSON.stringify(failures))
		return
	result = packer.flush()
	if result != OK:
		fail("Cannot finish package: %s" % result)
		return
	print("PACK_RESULT ", JSON.stringify({"passed": true, "files": packed_files,
		"source_bytes": packed_bytes, "output": output}))
	quit(0)


func add_folder(path: String) -> void:
	var directory := DirAccess.open("res://" + path)
	if directory == null:
		failures.append("Missing runtime directory: " + path)
		return
	directory.include_hidden = true
	directory.include_navigational = false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.is_link(entry):
			failures.append("Runtime resource must be a real file or directory: " + child)
		elif directory.current_is_dir():
			add_folder(child)
		elif is_runtime_file(child):
			add_file(child)
		entry = directory.get_next()
	directory.list_dir_end()


func is_runtime_file(path: String) -> bool:
	var lower := path.to_lower()
	if lower.ends_with(".tmp") or lower.ends_with(".log"):
		return false
	# Imported binary resources are required by Godot at runtime.
	if lower.begins_with(".godot/imported/"):
		return true
	# Source files belong under source/, including their accidental import sidecars.
	if lower.ends_with(".import"):
		lower = lower.trim_suffix(".import")
	return not lower.get_extension() in SOURCE_EXTENSIONS


func add_file(path: String) -> void:
	var source := FileAccess.open("res://" + path, FileAccess.READ)
	if source == null:
		failures.append("Cannot read runtime resource: " + path)
		return
	var size := source.get_length()
	source.close()
	var result := packer.add_file("res://" + path, ProjectSettings.globalize_path("res://" + path))
	if result != OK:
		failures.append("Cannot pack runtime resource: " + path)
		return
	packed_files += 1
	packed_bytes += size


func fail(message: String) -> void:
	push_error("PACK_FAILED " + message)
	quit(1)
