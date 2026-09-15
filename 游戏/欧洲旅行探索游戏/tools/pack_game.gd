extends SceneTree

var packed_count := 0
var packed_bytes := 0
var packer := PCKPacker.new()
var failures: Array[String] = []

func _initialize() -> void:
	var output := ProjectSettings.globalize_path("res://Windows游戏/欧洲漫游.pck")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var temporary := output + ".tmp"
	var err := packer.pck_start(temporary)
	if err != OK:
		push_error("Could not start PCK: %s" % err)
		quit(1)
		return
	for folder in ["assets/models", "assets/fonts", "scripts", ".godot/imported"]:
		add_folder(folder)
	for path in ["project.godot", "main.tscn", "assets/world_manifest.json"]:
		if not FileAccess.file_exists("res://" + path):
			failures.append("Missing required release file " + path)
		else:
			add_file(path)
	for path in [".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin"]:
		if FileAccess.file_exists("res://" + path):
			add_file(path)
	if not failures.is_empty():
		print("PACK_FAILED ",JSON.stringify(failures))
		quit(1)
		return
	err = packer.flush()
	if err == OK:
		err = DirAccess.rename_absolute(temporary,output)
	print("PACK_RESULT ", JSON.stringify({"error":err, "files":packed_count, "source_bytes":packed_bytes, "output":output}))
	quit(0 if err == OK else 1)

func add_folder(path: String) -> void:
	var dir := DirAccess.open("res://" + path)
	if dir == null:
		failures.append("Missing release directory " + path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			add_folder(path.path_join(entry))
		else:
			# Imported scene binaries are included below; the editable raw GLBs
			# remain in the separate source project instead of duplicating the PCK.
			if path != "assets/models" or entry.ends_with(".import"):
				add_file(path.path_join(entry))
		entry = dir.get_next()

func add_file(path: String) -> void:
	var file := FileAccess.open("res://" + path, FileAccess.READ)
	if file == null:
		failures.append("Cannot read " + path)
		return
	packed_bytes += file.get_length()
	file.close()
	var err := packer.add_file("res://" + path, ProjectSettings.globalize_path("res://" + path))
	if err != OK:
		failures.append("Cannot pack " + path)
	packed_count += 1
