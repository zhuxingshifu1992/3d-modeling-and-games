extends SceneTree
## Deterministic real-time motion review. Each image is an unedited engine frame.
var output := "res://previews/motion/before"
var detail := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--motion-out="): output = arg.trim_prefix("--motion-out=")
		if arg == "--detail": detail = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	var stage := Node3D.new()
	root.add_child(stage)
	var setup: Dictionary = load("res://scripts/lighting.gd").build(stage, false)
	setup.environment.background_mode = Environment.BG_COLOR
	setup.environment.background_color = Color("859396")
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4d585b")
	material.roughness = 0.95
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var rider: Node3D = load("res://scripts/rider.gd").new()
	stage.add_child(rider)
	rider.build()
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.position = Vector3(2.4, 1.6, 3.25)
	camera.look_at(Vector3(0, 0.82, 0))
	camera.fov = 31.0
	var label := Label.new()
	label.position = Vector2(28, 24)
	label.add_theme_font_size_override("font_size", 26)
	root.add_child(label)
	for frame in range(360):
		var t := float(frame) / 30.0
		var steer := 0.0
		var tuck := 0.0
		var brake := 0.0
		var speed := 15.0
		var push := false
		var phase := "COAST"
		if t >= 1.0 and t < 4.0:
			phase = "CARVE / BALANCE"
			steer = sin((t - 1.0) * TAU / 3.0) * 0.9
		elif t >= 4.0 and t < 7.0:
			phase = "TUCK / RECOVER"
			tuck = sin((t - 4.0) * PI / 3.0)
		elif t >= 7.0 and t < 9.0:
			phase = "BRAKE"
			brake = sin((t - 7.0) * PI / 2.0)
			steer = brake * 0.3
		elif t >= 9.0:
			phase = "PUSH"
			speed = 3.0
			push = true
		if rider.has_method("set_push_requested"): rider.set_push_requested(push)
		rider.animate(1.0 / 30.0, speed, steer, tuck, brake, t)
		label.text = "%s    %.2f s" % [phase, t]
		await process_frame
		RenderingServer.force_draw(false)
		var code := root.get_texture().get_image().save_png(output.path_join("frame_%04d.png" % frame))
		if code != OK:
			push_error("Motion capture failed: " + str(code))
			quit(1)
			return
	print("MOTION_CAPTURE_OK ", output, " frames=360 fps=30 duration=12")
	stage.queue_free()
	await process_frame
	quit()
