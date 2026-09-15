extends SceneTree
## Build a portable EXE + PCK using the installed Godot executable, without export templates.
## Run with -- --dry-run to validate the input inventory without writing release files.

const RELEASE_NAME: String = "最后一度电"
const ENGINE_RELATIVE: String = "../欧洲旅行探索游戏/runtime/Godot_v4.7.2-stable_win64.exe"
const INPUT_FOLDERS: Array[String] = ["assets", "scripts", ".godot/imported"]
const INPUT_FILES: Array[String] = ["project.godot", "main.tscn"]
const CACHE_FILES: Array[String] = [".godot/uid_cache.bin", ".godot/global_script_class_cache.cfg", ".godot/scene_groups_cache.cfg", ".godot/extension_list.cfg"]

var source_root: String
var entries: Array[String] = []
var error_count: int = 0

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	error_count += 1
	push_error(message)

func scan(relative: String) -> void:
	var path: String = source_root.path_join(relative)
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		fail("Required folder is missing: " + relative)
		return
	var children: PackedStringArray = directory.get_files()
	children.sort()
	for filename: String in children:
		if filename in [".DS_Store", "Thumbs.db", ".gdignore"] or filename.ends_with(".tmp") or filename.ends_with(".bak"):
			continue
		entries.append(relative.path_join(filename))
	var folders: PackedStringArray = directory.get_directories()
	folders.sort()
	for folder: String in folders:
		if folder in [".git", "__pycache__"]:
			continue
		scan(relative.path_join(folder))

func _file_size(path: String) -> int:
	var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
	return handle.get_length() if handle != null else -1

func run() -> void:
	source_root = ProjectSettings.globalize_path("res://").simplify_path()
	var dry_run: bool = "--dry-run" in OS.get_cmdline_user_args()
	var engine: String = source_root.path_join(ENGINE_RELATIVE).simplify_path()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--engine="):
			engine = argument.trim_prefix("--engine=").simplify_path()
	if not FileAccess.file_exists(engine):
		fail("Godot engine executable is missing: " + engine)
	for filename: String in INPUT_FILES:
		if not FileAccess.file_exists(source_root.path_join(filename)):
			fail("Required project file is missing: " + filename)
		else:
			entries.append(filename)
	for folder: String in INPUT_FOLDERS:
		scan(folder)
	for filename: String in CACHE_FILES:
		if FileAccess.file_exists(source_root.path_join(filename)):
			entries.append(filename)
	for required: String in ["assets/models/charging_yard.glb", "assets/models/charging_yard.glb.import", "assets/fonts/Chinese.ttc", "assets/fonts/Chinese.ttc.import", "scripts/game.gd", "scripts/player.gd", "scripts/hud.gd", "scripts/audio_bank.gd"]:
		if not required in entries:
			fail("Required runtime/import resource missing: " + required)
	entries.sort()
	var total_bytes: int = 0
	for filename: String in entries:
		var bytes: int = _file_size(source_root.path_join(filename))
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
		print("No EXE, PCK or manifest written. Await stable-code handoff before final pack.")
		quit(0)
		return
	var release: String = source_root.path_join("Windows游戏")
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(release)
	if mkdir_error != OK:
		fail("Cannot create release folder: " + error_string(mkdir_error))
		quit(1)
		return
	var pack_final: String = release.path_join(RELEASE_NAME + ".pck")
	var pack_temp: String = release.path_join(RELEASE_NAME + ".pck.pending")
	var exe_final: String = release.path_join(RELEASE_NAME + ".exe")
	var exe_temp: String = release.path_join(RELEASE_NAME + ".exe.pending")
	var packer: PCKPacker = PCKPacker.new()
	var pack_error: Error = packer.pck_start(pack_temp)
	if pack_error != OK:
		fail("Cannot open PCK output: " + error_string(pack_error))
		quit(1)
		return
	var inventory: Array[Dictionary] = []
	for filename: String in entries:
		var source: String = source_root.path_join(filename)
		var resource: String = "res://" + filename.replace("\\", "/")
		pack_error = packer.add_file(resource, source)
		if pack_error != OK:
			fail("Cannot add " + resource + ": " + error_string(pack_error))
			quit(1)
			return
		inventory.append({"resource": resource, "bytes": _file_size(source), "sha256": FileAccess.get_sha256(source)})
	pack_error = packer.flush()
	if pack_error != OK or _file_size(pack_temp) < 64:
		fail("PCK flush failed: " + error_string(pack_error))
		quit(1)
		return
	var copy_error: Error = DirAccess.copy_absolute(engine, exe_temp)
	if copy_error != OK:
		fail("Cannot copy runtime: " + error_string(copy_error))
		quit(1)
		return
	if FileAccess.get_sha256(engine) != FileAccess.get_sha256(exe_temp):
		fail("Runtime copy verification failed")
		quit(1)
		return
	# Only generated outputs in the explicitly named release directory are replaced.
	for pair: Array in [[pack_temp, pack_final], [exe_temp, exe_final]]:
		var destination: String = String(pair[1])
		if FileAccess.file_exists(destination):
			var remove_error: Error = DirAccess.remove_absolute(destination)
			if remove_error != OK:
				fail("Close any running release before repacking: " + destination)
				quit(1)
				return
		var rename_error: Error = DirAccess.rename_absolute(String(pair[0]), destination)
		if rename_error != OK:
			fail("Cannot publish output " + destination + ": " + error_string(rename_error))
			quit(1)
			return
	var manifest: Dictionary = {"title": "最后一度电：断电区", "packaged_at": Time.get_datetime_string_from_system(), "engine": "Godot 4.7.2 stable Windows x86_64", "source_files": entries.size(), "source_bytes": total_bytes, "files": inventory, "outputs": {RELEASE_NAME + ".exe": {"bytes": _file_size(exe_final), "sha256": FileAccess.get_sha256(exe_final)}, RELEASE_NAME + ".pck": {"bytes": _file_size(pack_final), "sha256": FileAccess.get_sha256(pack_final)}}}
	var manifest_file: FileAccess = FileAccess.open(release.path_join("打包清单.json"), FileAccess.WRITE)
	if manifest_file == null:
		fail("Cannot write packaging manifest")
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	print("PACK PASS files=", entries.size(), " pck_bytes=", _file_size(pack_final), " exe_bytes=", _file_size(exe_final))
	print("Portable release: ", exe_final)
	quit(0)
