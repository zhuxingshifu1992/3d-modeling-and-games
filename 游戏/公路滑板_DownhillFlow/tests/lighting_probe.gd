extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var setup: Dictionary = preload("res://scripts/lighting.gd").build(stage, false)
	var plane: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(14,14)
	plane.mesh = pm
	var ground: StandardMaterial3D = StandardMaterial3D.new()
	ground.albedo_color = Color(0.2,0.22,0.22)
	ground.roughness = 0.9
	plane.material_override = ground
	stage.add_child(plane)
	for i in 3:
		var ball: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 0.55
		mesh.height = 1.1
		ball.mesh = mesh
		ball.position = Vector3(float(i-1)*1.5,0.56,0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = [Color(0.8,0.48,0.3),Color(0.85,0.85,0.85),Color(0.48,0.52,0.57)][i]
		mat.roughness = [0.55,0.8,0.24][i]
		mat.metallic = 0.8 if i==2 else 0.0
		ball.material_override = mat
		stage.add_child(ball)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(2.1,2.5,5)
	stage.add_child(camera)
	camera.look_at(Vector3(0,0.55,0))
	for i in 120: await process_frame
	RenderingServer.force_draw(false)
	var img: Image = root.get_texture().get_image()
	var result: Error = img.save_png(ProjectSettings.globalize_path("res://previews/realism/lighting_probe.png"))
	print("REALISM_LIGHTING_PROBE renderer=",RenderingServer.get_current_rendering_method()," ssao=",setup.environment.ssao_enabled," ssil=",setup.environment.ssil_enabled," capture=",result)
	setup.sun.shadow_enabled = false
	for i in 12: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://previews/realism/lighting_no_shadow.png"))
	setup.sun.shadow_enabled = true
	setup.sun.shadow_bias = 0.08
	setup.sun.shadow_normal_bias = 2.5
	for i in 12: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://previews/realism/lighting_bias_corrected.png"))
	setup.environment.ssao_enabled = false
	setup.environment.ssil_enabled = false
	for i in 12: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://previews/realism/lighting_no_ao.png"))
	stage.queue_free()
	await process_frame
	quit()
