extends SceneTree
## Build a portable EXE + PCK without export templates.
## Run with -- --dry-run to validate all inputs without writing release files.

const RELEASE_NAME := "巨构机库"
const INPUT_FOLDERS: Array[String] = ["assets", "scripts", ".godot/imported"]
const INPUT_FILES: Array[String] = ["project.godot", "main.tscn"]
const CACHE_FILES: Array[String] = [
	".godot/uid_cache.bin",
	".godot/global_script_class_cache.cfg",
	".godot/scene_groups_cache.cfg",
	".godot/extension_list.cfg",
]

var source_root := ""
var entries: Array[String] = []
var error_count := 0


func _initialize() -> void:
	call_deferred("run")


func fail(message: String) -> void:
	error_count += 1
	push_error(message)


func scan(relative: String) -> void:
	var absolute := source_root.path_join(relative)
	var directory := DirAccess.open(absolute)
	if directory == null:
		fail("Required folder is missing: " + relative)
		return
	var files := directory.get_files()
	files.sort()
	for filename: String in files:
		if filename in [".DS_Store", "Thumbs.db", ".gdignore"] or filename.ends_with(".tmp") or filename.ends_with(".bak"):
			continue
		entries.append(relative.path_join(filename))
	var folders := directory.get_directories()
	folders.sort()
	for folder: String in folders:
		if folder in [".git", "__pycache__"]:
			continue
		scan(relative.path_join(folder))


func file_size(path: String) -> int:
	var handle := FileAccess.open(path, FileAccess.READ)
	return handle.get_length() if handle != null else -1


func resolve_engine(arguments: PackedStringArray) -> String:
	var engine := OS.get_environment("GODOT_BIN")
	if engine.is_empty():
		engine = OS.get_executable_path()
	for index: int in range(arguments.size()):
		var argument := arguments[index]
		if argument.begins_with("--engine="):
			engine = argument.trim_prefix("--engine=")
		elif argument == "--engine" and index + 1 < arguments.size():
			engine = arguments[index + 1]
	if engine.is_relative_path():
		engine = source_root.path_join(engine)
	return engine.simplify_path()


func run() -> void:
	source_root = ProjectSettings.globalize_path("res://").simplify_path()
	var arguments := OS.get_cmdline_user_args()
	var dry_run := "--dry-run" in arguments
	var engine := resolve_engine(arguments)
	if not FileAccess.file_exists(engine):
		fail("Godot engine executable is missing: " + engine)
	for filename: String in INPUT_FILES:
		if FileAccess.file_exists(source_root.path_join(filename)):
			entries.append(filename)
		else:
			fail("Required project file is missing: " + filename)
	for folder: String in INPUT_FOLDERS:
		scan(folder)
	for filename: String in CACHE_FILES:
		if FileAccess.file_exists(source_root.path_join(filename)):
			entries.append(filename)
	entries.sort()
	var total_bytes := 0
	for filename: String in entries:
		var bytes := file_size(source_root.path_join(filename))
		if bytes < 0:
			fail("Cannot read resource: " + filename)
		else:
			total_bytes += bytes
	if error_count > 0:
		print("PACK_PREFLIGHT FAIL errors=", error_count)
		quit(1)
		return
	if dry_run:
		print("PACK_DRY_RUN PASS files=", entries.size(), " bytes=", total_bytes, " engine=", engine)
		print("No EXE, PCK or manifest written.")
		quit(0)
		return
	pack(engine, total_bytes)


func pack(engine: String, total_bytes: int) -> void:
	var release := source_root.path_join("Windows游戏")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(release)
	if mkdir_error != OK:
		fail("Cannot create release folder: " + error_string(mkdir_error))
		quit(1)
		return
	var pack_final := release.path_join(RELEASE_NAME + ".pck")
	var pack_temp := release.path_join(RELEASE_NAME + ".pck.pending")
	var exe_final := release.path_join(RELEASE_NAME + ".exe")
	var exe_temp := release.path_join(RELEASE_NAME + ".exe.pending")
	var packer := PCKPacker.new()
	var pack_error := packer.pck_start(pack_temp)
	if pack_error != OK:
		fail("Cannot open PCK output: " + error_string(pack_error))
		quit(1)
		return
	var inventory: Array[Dictionary] = []
	for filename: String in entries:
		var source := source_root.path_join(filename)
		var resource := "res://" + filename.replace("\\", "/")
		pack_error = packer.add_file(resource, source)
		if pack_error != OK:
			fail("Cannot add " + resource + ": " + error_string(pack_error))
			quit(1)
			return
		inventory.append({"resource": resource, "bytes": file_size(source), "sha256": FileAccess.get_sha256(source)})
	pack_error = packer.flush()
	if pack_error != OK or file_size(pack_temp) < 64:
		fail("PCK flush failed: " + error_string(pack_error))
		quit(1)
		return
	var copy_error := DirAccess.copy_absolute(engine, exe_temp)
	if copy_error != OK:
		fail("Cannot copy runtime: " + error_string(copy_error))
		quit(1)
		return
	if FileAccess.get_sha256(engine) != FileAccess.get_sha256(exe_temp):
		fail("Runtime copy verification failed")
		quit(1)
		return
	for pair: Array in [[pack_temp, pack_final], [exe_temp, exe_final]]:
		var destination := String(pair[1])
		if FileAccess.file_exists(destination):
			var remove_error := DirAccess.remove_absolute(destination)
			if remove_error != OK:
				fail("Close any running release before repacking: " + destination)
				quit(1)
				return
		var rename_error := DirAccess.rename_absolute(String(pair[0]), destination)
		if rename_error != OK:
			fail("Cannot publish output " + destination + ": " + error_string(rename_error))
			quit(1)
			return
	var manifest := {
		"title": "GUNDAM · 巨构机库",
		"packaged_at": Time.get_datetime_string_from_system(),
		"engine_sha256": FileAccess.get_sha256(engine),
		"source_files": entries.size(),
		"source_bytes": total_bytes,
		"files": inventory,
		"outputs": {
			RELEASE_NAME + ".exe": {"bytes": file_size(exe_final), "sha256": FileAccess.get_sha256(exe_final)},
			RELEASE_NAME + ".pck": {"bytes": file_size(pack_final), "sha256": FileAccess.get_sha256(pack_final)},
		},
	}
	var manifest_path := release.path_join("打包清单.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		fail("Cannot write packaging manifest: " + manifest_path)
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	print("PACK PASS files=", entries.size(), " pck_bytes=", file_size(pack_final), " exe_bytes=", file_size(exe_final))
	print("Portable release: ", exe_final)
	quit(0)
