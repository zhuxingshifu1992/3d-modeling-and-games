extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var errors: Array[String] = []
	var packed = load("res://main.tscn")
	if not packed is PackedScene:
		print("PACKAGED_FAIL main scene missing")
		quit(1)
		return
	var game = packed.instantiate()
	game.automated_test = true
	root.gui_disable_input = true
	game.set_process_unhandled_input(false)
	game.save_path = "user://packaged_verification.json"
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec()+60000
	while not game.world_ready and not game.load_failed and Time.get_ticks_msec()<deadline:
		await process_frame
	if not game.world_ready:
		errors.append_array(game.load_errors)
		if errors.is_empty():errors.append("World load timeout")
	else:
		print("PACK_STAGE loaded")
		game.start_new_trip()
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			errors.append("Mouse cursor is not free after starting the game")
		for region: Dictionary in game.manifest.regions:
			print("PACK_STAGE ",region.id)
			game.travel_to(region)
			if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				errors.append("Mouse cursor is not free after travel")
			game.player.eye.rotation.x = 0.09
			for tick: int in range(60):
				await physics_frame
			if not game.player.is_on_floor():
				errors.append(str(region.id) + " missing packaged floor")
			if region.id == "FR_Paris" and DisplayServer.get_name() != "headless":
				game.ui.toast_remaining = 0.01
				await process_frame
				# Off-screen Windows windows may stop automatic swaps; explicitly
				# render our own viewport for this image without flashing the desktop.
				RenderingServer.force_draw(false)
				var image := root.get_texture().get_image()
				image.save_png(ProjectSettings.globalize_path("user://packaged_final_paris.png"))
	var result := {"passed":errors.is_empty(),"errors":errors,"regions":game.manifest.get("regions",[]).size(),"buildings":game.manifest.get("buildings",[]).size(),"loaded_from":OS.get_executable_path(),"raw_glb_omitted":not FileAccess.file_exists("res://assets/models/FR_Paris.glb"),"headless":DisplayServer.get_name()=="headless","completed_unix":Time.get_unix_time_from_system()}
	var result_path := "user://packaged_smoke_result.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):
			result_path = arg.trim_prefix("--result=")
	var output := FileAccess.open(result_path,FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"  "))
	output.close()
	print("PACKAGED_SMOKE_RESULT ",JSON.stringify(result))
	game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0 if errors.is_empty() else 1)
