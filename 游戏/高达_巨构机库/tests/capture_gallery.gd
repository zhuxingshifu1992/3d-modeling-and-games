extends SceneTree

var game
var path := "res://previews/gallery"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			path = arg.trim_prefix("--output=")
	call_deferred("run")

func shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join(filename + ".png"))

func wait(time: float) -> void:
	await create_timer(time).timeout

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	game = load("res://main.tscn").instantiate()
	game.automated_test = true
	root.add_child(game)
	await wait(1.0)
	game.start()
	game.hud.game_ui.hide()
	for bay in game.bays:
		var at: Vector3 = bay.to_global(Vector3(6, 0.15, -16.5))
		var aim: Vector3 = bay.to_global(Vector3(0, float(bay.info.height) * 0.5, 0))
		var dir := aim - (at + Vector3.UP * 1.65)
		game.player.set_view(at, atan2(-dir.x, -dir.z), atan2(dir.y, Vector2(dir.x, dir.z).length()))
		await wait(1.0)
		await shot(bay.info.id + "_ground")
	game.hud.game_ui.show()
	game.pause_game(true)
	await wait(0.4)
	await shot("directory")
	game.resume()
	game.pause_game()
	await wait(0.4)
	await shot("pause")
	print("GALLERY_COMPLETE")
	quit()
