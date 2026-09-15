extends SceneTree

# Exercises the real imported assets. Catches missing vertex-color activation,
# source resource mutation, changed colors/material settings, and repeat copies.
var failures: Array[String] = []
var results: Array[Dictionary] = []

func _initialize() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	for filename in ["city.glb", "gondola.glb"]:
		var packed: PackedScene = load("res://assets/" + filename)
		var instance := packed.instantiate()
		var mesh_node := find_mesh(instance)
		check(mesh_node != null, filename + " has mesh")
		if mesh_node == null:
			instance.free()
			continue
		var original: BaseMaterial3D = mesh_node.get_active_material(0)
		var colors_before: PackedColorArray = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(not original.vertex_color_use_as_albedo, filename + " originally reproduces disabled vertex colors")
		check(colors_before.size() > 100, filename + " retains COLOR_0 data")
		check(colors_before[0].r > colors_before[0].b, filename + " retains authored warm palette")
		if baseline:
			print("BASELINE ", filename, " colors=", colors_before.size(), " vertex_color_use_as_albedo=", original.vertex_color_use_as_albedo)
			instance.free()
			continue
		var fixed_count := 0
		# Before implementation, this follows the unchanged runtime path and
		# fails on the actual imported material flag, rather than a parse error.
		if ResourceLoader.exists("res://scripts/vertex_palette.gd"):
			var utility: GDScript = load("res://scripts/vertex_palette.gd")
			fixed_count = utility.apply(instance)
		var corrected: BaseMaterial3D = mesh_node.get_active_material(0)
		check(corrected.vertex_color_use_as_albedo, filename + " enables vertex colors in the active material")
		check(not corrected.vertex_color_is_srgb, filename + " keeps GLB linear vertex colors")
		check(fixed_count == 1, filename + " repairs exactly one material")
		check(not original.vertex_color_use_as_albedo, filename + " leaves cached imported material untouched")
		for property in ["albedo_color", "shading_mode", "cull_mode", "roughness", "metallic", "transparency", "no_depth_test", "render_priority"]:
			check(corrected.get(property) == original.get(property), filename + " preserves " + property)
		var colors_after: PackedColorArray = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(colors_before == colors_after, filename + " preserves all vertex-color values")
		if ResourceLoader.exists("res://scripts/vertex_palette.gd"):
			var utility: GDScript = load("res://scripts/vertex_palette.gd")
			check(utility.apply(instance) == 0, filename + " repeat call makes no changes")
			check(mesh_node.get_active_material(0) == corrected, filename + " repeat call retains material instance")
		results.append({"asset": filename, "color_count": colors_after.size(), "vertex_color_use_as_albedo": corrected.vertex_color_use_as_albedo, "vertex_color_is_srgb": corrected.vertex_color_is_srgb, "fixed_material_count": fixed_count})
		instance.free()
	for failure in failures:
		print("FAIL: ", failure)
	if failures.is_empty():
		print("PASS: ", "original import baseline" if baseline else "both assets repaired; colors/properties/source resources unchanged; idempotent")
	if not baseline:
		var file := FileAccess.open("res://assets/vertex_palette_validation.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "results": results, "failures": failures}, "  "))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := find_mesh(child)
		if found != null:
			return found
	return null
