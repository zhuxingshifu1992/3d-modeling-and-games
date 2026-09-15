extends SceneTree

func _initialize() -> void:
	if not "--benchmark" in OS.get_cmdline_user_args():
		quit(2)
		return
	call_deferred("_start")

func _start() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.bench_seconds = 60.0
