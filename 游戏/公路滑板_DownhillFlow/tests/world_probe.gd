extends SceneTree

func _initialize() -> void:
	var route_script: Script = load("res://scripts/route.gd")
	if route_script == null:
		push_error("Route module is missing")
		quit(1)
		return
	var route: RefCounted = route_script.new()
	var previous: Vector3 = route.sample(0.0).position
	for index: int in range(1, 2601):
		var point: Dictionary = route.sample(float(index))
		var location: Vector3 = point.position
		assert(location.is_finite(), "Route position must be finite")
		assert(location.distance_to(previous) < 1.4, "Route continuity")
		assert(location.y < previous.y, "The route must always descend")
		assert(absf(point.forward.dot(point.right)) < 0.00001, "Orthogonal frame")
		assert(point.right.x > 0.7, "Consistent road orientation")
		assert(point.forward.z < -0.7, "Route moves toward -Z")
		var before: Dictionary = route.sample(float(index) - 0.1)
		var after: Dictionary = route.sample(float(index) + 0.1)
		var finite_tangent: Vector3 = (Vector3(after.position) - Vector3(before.position)).normalized()
		assert(finite_tangent.dot(point.forward) > 0.999999, "Analytic tangent matches road geometry")
		var dx: float = point.forward.x / -point.forward.z
		var ddx: float = (after.forward.x / -after.forward.z - before.forward.x / -before.forward.z) / 0.2
		var finite_curvature: float = ddx / pow(1.0 + dx * dx, 1.5)
		assert(absf(finite_curvature - point.curvature) < 0.000001, "Analytic curvature matches tangent derivative")
		previous = location
	var world_script: Script = load("res://scripts/world.gd")
	assert(world_script != null, "World module must load")
	var world: Node3D = world_script.new()
	root.add_child(world)
	world.build(route)
	assert(world.get_child_count() > 20, "Landscape should have complete geometry")
	var asphalt_count: int = 0
	var terrain_count: int = 0
	var triangle_count: int = 0
	var minimum_rock_clearance: float = 1000.0
	var closest_rock_point: Vector3 = Vector3.ZERO
	for mesh_node: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mesh_node.mesh
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangle_count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
		if mesh_node.name == "ContinuousAsphalt":
			var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			print("ASPHALT_NORMAL ", normals[0]) if asphalt_count == 0 else null
			assert(normals[0].y > 0.9, "Road normals point skyward")
			asphalt_count += 1
		if String(mesh_node.name).begins_with("DistantHeadland_"):
			var arrays: Array = mesh.surface_get_arrays(0)
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for normal: Vector3 in normals:
				assert(normal.y > 0.0, "Distant coast normals face skyward")
			for triangle: int in range(0, indices.size(), 3):
				var a: Vector3 = vertices[indices[triangle]]
				var b: Vector3 = vertices[indices[triangle + 1]]
				var c: Vector3 = vertices[indices[triangle + 2]]
				assert((c - a).cross(b - a).y > 0.0, "Distant coast winding agrees with surface normals")
		if mesh_node.name == "SandstoneHeadland":
			var arrays: Array = mesh.surface_get_arrays(0)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for triangle: int in range(0, indices.size(), 3):
				var a: Vector3 = vertices[indices[triangle]]
				var b: Vector3 = vertices[indices[triangle + 1]]
				var c: Vector3 = vertices[indices[triangle + 2]]
				assert((c - a).cross(b - a).y > 0.00001, "Terrain projection has no folds")
			terrain_count += 1
	assert(asphalt_count == terrain_count, "Each road chunk has fitted terrain")
	for mesh_node: MultiMeshInstance3D in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh: Mesh = mesh_node.multimesh.mesh
		var instance_triangles: int = 0
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			instance_triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
		triangle_count += instance_triangles * mesh_node.multimesh.instance_count
		if mesh_node.name == "WeatheredBoulders":
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			assert(vertices.size() >= 500, "Boulder silhouette must have a curved eroded surface")
			for pole_vertex: int in range(29):
				assert(vertices[pole_vertex].distance_to(vertices[0]) < 0.00001, "Rock north pole is continuous")
				assert(vertices[vertices.size() - 1 - pole_vertex].distance_to(vertices[-1]) < 0.00001, "Rock south pole is continuous")
			for ring: int in range(19):
				assert(vertices[ring * 29].distance_to(vertices[ring * 29 + 28]) < 0.00001, "Rock longitude seam is continuous")
			for vertex_index: int in range(vertices.size()):
				assert(vertices[vertex_index].is_finite(), "Rock positions are finite")
				assert(normals[vertex_index].dot(vertices[vertex_index].normalized()) > 0.05, "Rock normals point outward")
			for instance_index: int in range(mesh_node.multimesh.instance_count):
				var transform: Transform3D = mesh_node.get_meta("placement_transforms")[instance_index]
				for vertex: Vector3 in vertices:
					var point: Vector3 = transform * vertex
					var s: float = -point.z
					for iteration: int in range(4):
						var frame: Dictionary = route.sample(s)
						var derivative: Vector3 = Vector3(frame.forward) / -frame.forward.z
						derivative.y = 0.0
						s += (point - Vector3(frame.position)).dot(derivative) / derivative.length_squared()
					if s < 0.0 or s > 2600.0:
						continue
					var frame: Dictionary = route.sample(s)
					var clearance: float = absf((point - Vector3(frame.position)).dot(frame.right)) - 4.8
					if clearance < minimum_rock_clearance:
						minimum_rock_clearance = clearance
						closest_rock_point = point
	print("ROCK_CLEARANCE ", minimum_rock_clearance, " at ", closest_rock_point)
	assert(minimum_rock_clearance > 0.2, "Visible rocks must stay outside the asphalt")
	assert(world.find_children("CoastalCloud_*", "MeshInstance3D", true, false).is_empty(), "No flat synthetic cloud billboards")
	assert(world.find_children("TreeTrunksAndBranches", "MultiMeshInstance3D", true, false).size() == asphalt_count, "Every chunk has branched tree geometry")
	var asphalt_material: ShaderMaterial = world.get("_asphalt_material")
	assert(asphalt_material.get_shader_parameter("asphalt_diff") is Texture2D, "Photographic asphalt map is loaded")
	assert(asphalt_material.get_shader_parameter("asphalt_nor") is Texture2D, "Asphalt PBR normal is loaded")
	var terrain_material: ShaderMaterial = world.get("_terrain_material")
	assert(terrain_material.get_shader_parameter("rock_diff") is Texture2D, "Photographic rock map is loaded")
	var foliage_material: ShaderMaterial = world.get("_foliage_material")
	assert(foliage_material.get_shader_parameter("leaf_alpha") is Texture2D, "Leaf silhouettes use photographic alpha")
	assert(triangle_count < 1500000, "Whole route remains within the environment triangle budget")
	world.update_view(0.0)
	world.update_view(1300.0)
	world.update_view(2600.0)
	print("WORLD_PROBE_OK samples=2601 nodes=", world.get_child_count(), " triangles=", triangle_count, " min_rock_clearance=", snappedf(minimum_rock_clearance, 0.001), "m")
	if "--visual" in OS.get_cmdline_user_args():
		var environment: Environment = Environment.new()
		environment.background_mode = Environment.BG_SKY
		var sky: Sky = Sky.new()
		var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("1765ba")
		sky_material.sky_horizon_color = Color("b3dbe5")
		sky_material.sky_curve = 0.18
		sky.sky_material = sky_material
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("b6d6ee")
		environment.ambient_light_energy = 0.65
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 1.1
		environment.fog_enabled = true
		environment.fog_light_color = Color("a6cad7")
		environment.fog_density = 0.0004
		var env: WorldEnvironment = WorldEnvironment.new()
		env.environment = environment
		world.add_child(env)
		var sun: DirectionalLight3D = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-46.0, -36.0, 0.0)
		sun.light_color = Color("fff3d8")
		sun.light_energy = 1.6
		sun.shadow_enabled = true
		world.add_child(sun)
		var camera: Camera3D = Camera3D.new()
		camera.far = 8000.0
		camera.fov = 77.0
		world.add_child(camera)
		var frame: Dictionary = route.sample(130.0)
		camera.position = frame.position - frame.forward * 4.8 + Vector3.UP * 1.9
		await process_frame
		camera.look_at(frame.position + frame.forward * 22.0 + Vector3.UP * 0.2)
		camera.current = true
		world.update_view(130.0)
		for count: int in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://previews/world_probe.png")
		print("WORLD_VISUAL_CAPTURED")
	world.queue_free()
	quit(0)
