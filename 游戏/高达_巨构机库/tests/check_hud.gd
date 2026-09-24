extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.automated_test = true
	root.add_child(game)
	await process_frame
	game.audio.set_muted(true)
	game.start()
	await process_frame
	var bounds := Rect2(Vector2.ZERO, game.hud.root.size)
	for control in [game.hud.prompt, game.hud.cross, game.hud.progress, game.hud.altitude, game.hud.location_label]:
		assert(bounds.encloses(control.get_rect()), "HUD must remain inside viewport: " + str(control.get_rect()))
	game.hud.sync_settings({"fov": 72.0, "sensitivity": 1.6, "sound": false})
	assert(game.hud.settings_controls.fov.value == 72.0)
	assert(game.hud.settings_controls.sensitivity.value == 1.6)
	assert(not game.hud.settings_controls.sound.button_pressed)
	game.pause_game(true)
	await process_frame
	assert(game.hud.guide.visible and paused)
	game.resume()
	assert(not game.hud.guide.visible and not paused)
	print("HUD PASS screen bounds, restored settings and directory pause")
	game.queue_free()
	await process_frame
	await process_frame
	quit()
