extends SceneTree

# Generate a game-rendered preview asset, without loading or writing player saves.
func _initialize() -> void:
	if not "--benchmark" in OS.get_cmdline_user_args():
		push_error("Preview rendering requires -- --benchmark to isolate saves")
		quit(1)
		return
	call_deferred("_render_preview")

func _render_preview() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game._process(1.0/60.0)
	game.set_process(false)
	game.set_physics_process(false)
	game.route_visual.hide()
	game.destination_marker.hide()
	game.route_nodes.clear()
	var first_person: bool = "--first-person" in OS.get_cmdline_user_args()
	if first_person:
		game.boat.position = Vector3(0,0.2,22)
		game._set_camera_mode("first_person")
		game._update_camera(1.0/60.0)
	else:
		game.boat.position = Vector3(0,0.2,14)
		game._set_camera_mode("overview")
		game.camera.position = Vector3(40,51,61)
		game.camera.look_at(Vector3(0,2,0),Vector3.UP)
	game.hud.hide_start()
	await create_timer(5.0).timeout
	game._update_hud()
	await RenderingServer.frame_post_draw
	var path: String = "res://船头第一人称.png" if first_person else "res://游戏画面.png"
	var err: Error = root.get_texture().get_image().save_png(path)
	print("PREVIEW_SAVED ",err)
	quit(0 if err==OK else 1)
