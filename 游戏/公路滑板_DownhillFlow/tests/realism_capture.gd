extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1100, 900)
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var illumination: Dictionary = load("res://scripts/lighting.gd").build(stage, false)
	illumination.environment.background_mode = Environment.BG_COLOR
	illumination.environment.background_color = Color("768489")
	var rider: Node3D = load("res://scripts/rider.gd").new()
	stage.add_child(rider)
	rider.build()
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor_mesh.mesh = plane
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("434e50")
	material.roughness = 0.9
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var camera: Camera3D = Camera3D.new()
	stage.add_child(camera)
	camera.fov = 34
	camera.current = true
	var positions: Array[Vector3] = [Vector3(2.3,1.7,3.4),Vector3(-3.2,1.6,0.5),Vector3(1.8,1.65,-3.3)]
	for index: int in range(3):
		camera.position = positions[index]
		camera.look_at(Vector3(0,0.84,0))
		for frame: int in range(45):
			rider.animate(1.0/60.0, 18.0, 0.0, 0.65 if index == 1 else 0.25, 0.0, 1.0)
			await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://previews/realism/rider_%d.png" % index)
	print("REALISTIC_RIDER_CAPTURE_OK")
	quit()
