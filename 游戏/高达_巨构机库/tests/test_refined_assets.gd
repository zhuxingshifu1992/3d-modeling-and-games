extends SceneTree
## Validate imported geometry in meters, including equipped bounds and human scale.

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("REFINED_FAIL " + message)

func _initialize() -> void:
	call_deferred("run")

func inspect_asset(path: String, reference_height: float, marker_name: String = "HeadHeightReference", min_triangles: int = 40000, max_triangles: int = 200000, requires_textures: bool = true) -> void:
	check(ResourceLoader.exists(path), "Imported GLB exists: " + path)
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path)
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	var marker := model.find_child(marker_name, true, false) as Node3D
	check(marker != null, "Explicit scale landmark " + marker_name + ": " + path)
	if marker != null:
		check(absf(marker.global_position.y - reference_height) < 0.015, "Scale landmark meters: " + path)
	var bounds := AABB()
	var first := true
	var triangles := 0
	var material_count := 0
	var textured_surfaces := 0
	var material_colors := {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for s in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
			check(mesh.get_active_material(s) != null, "Material assigned: " + mesh.name + "/" + str(s))
			var material := mesh.get_active_material(s) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				textured_surfaces += 1
			if material != null:
				material_colors[material.albedo_color.to_html()] = true
			material_count += 1
	check(not first, "Visible geometry: " + path)
	check(absf(bounds.position.y) < 0.025, "Feet rest on zero: " + path)
	check(bounds.end.y >= reference_height - 0.02, "Scale landmark within complete equipment bounds: " + path)
	check(triangles > min_triangles and triangles < max_triangles, "Detailed but bounded geometry: " + path)
	if requires_textures:
		check(textured_surfaces > 0, "Authored color textures imported: " + path)
	else:
		check(absf(bounds.end.y - reference_height) < 0.025, "Exia actual geometry matches total height")
		check(material_colors.size() >= 5, "Authored multi-color materials retained: " + path)
		check(model.find_child("ExiaBody", true, false) != null, "Exia static body exists")
		check(model.find_child("CockpitHatch", true, false) != null, "Exia original chest cover separated")
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			check(mesh.skin == null, "Exia geometry uses its baked static pose: " + mesh.name)
	print("REFINED_ASSET ", path, " triangles=", triangles, " surfaces=", material_count, " bounds=", bounds)
	model.free()

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Refined asset tests require --headless.")
		quit(2)
		return
	inspect_asset("res://assets/models/rx78_refined.glb", 18.0)
	inspect_asset("res://assets/models/zaku_desert_refined.glb", 17.5)
	inspect_asset("res://assets/models/nu_refined.glb", 22.0)
	# This author supplies PBR color materials without image textures. 18.3 m is total height.
	inspect_asset("res://assets/models/exia_refined.glb", 18.3, "TotalHeightReference", 200000, 350000, false)
	var game = load("res://main.tscn").instantiate()
	game.automated_test = true
	root.add_child(game)
	check(game.catalog[0].model_path == "res://assets/models/rx78_refined.glb", "A1 uses refined RX78")
	check(game.catalog[2].model_path == "res://assets/models/nu_refined.glb", "A3 uses refined Nu")
	check(game.bays[2].exterior_hatch != null, "A3 binds the original Nu chest cover")
	check(game.catalog[5].model_path == "res://assets/models/exia_refined.glb", "B3 uses refined Exia")
	check(game.bays[5].exterior_hatch != null, "B3 binds the original Exia chest cover")
	check(game.bays[5].compact, "B3 uses an adapted cockpit")
	check(game.bays.size() == 6, "Six boarding stations retained")
	check(is_equal_approx(game.player.camera.position.y, 1.65), "Human eye height retained")
	var nu := game.world.get_node_or_null("nu") as Node3D
	check(nu != null, "Nu machine exists in A3")
	if nu != null:
		for mesh: MeshInstance3D in nu.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			check(box.position.z > -54.0 and box.end.z < 54.0 and box.position.x > -41.5 and box.end.x < 41.5 and box.end.y < 33.0, "Nu and its equipment stay inside hangar walls and roof")
	var exia := game.world.get_node_or_null("exia") as Node3D
	check(exia != null, "Exia machine exists in B3")
	if exia != null:
		for mesh: MeshInstance3D in exia.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			check(box.position.z > -54.0 and box.end.z < 54.0 and box.position.x > -41.5 and box.end.x < 41.5 and box.end.y < 33.0, "Exia and its equipment stay inside hangar walls and roof")
	var exhibit := game.world.get_node_or_null("zaku_desert") as Node3D
	check(exhibit != null, "Zaku exhibit in hangar")
	if exhibit != null:
		for mesh: MeshInstance3D in exhibit.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			check(box.position.z > -54.0 and box.end.z < 54.0 and box.position.x > -41.5 and box.end.x < 41.5, "Exhibit equipment inside hangar walls")
	game.queue_free()
	await process_frame
	await process_frame
	print("REFINED_ASSETS ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
