extends SceneTree

var report: Array[Dictionary] = []

func _initialize() -> void:
	for filename in ["city.glb", "gondola.glb"]:
		var packed: PackedScene = load("res://assets/" + filename)
		var instance := packed.instantiate()
		print("ASSET ", filename)
		inspect_node(instance)
		instance.free()
	var file := FileAccess.open("res://assets/godot_material_diagnosis.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"godot": Engine.get_version_info().string, "observed_materials": report, "root_cause": "COLOR_0 vertex data survives import but vertex_color_use_as_albedo is false.", "minimal_runtime_fix": "Enable BaseMaterial3D.vertex_color_use_as_albedo on imported mesh surface materials. Keep vertex_color_is_srgb=false because exported GLB colors are linear."}, "  "))
	quit()

func inspect_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		print(" MESH ", node.name, " surfaces ", mesh.get_surface_count())
		for i in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(i)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			print("  VERTICES ", arrays[Mesh.ARRAY_VERTEX].size(), " COLOR_COUNT ", colors.size())
			if not colors.is_empty():
				print("  FIRST_COLORS ", colors.slice(0, 12))
			var material := mesh.surface_get_material(i)
			print("  MATERIAL ", material)
			if material is BaseMaterial3D:
				print("  vertex_color_use_as_albedo=", material.vertex_color_use_as_albedo, " vertex_color_is_srgb=", material.vertex_color_is_srgb, " shading_mode=", material.shading_mode, " albedo=", material.albedo_color, " cull=", material.cull_mode)
				report.append({"mesh": str(node.name), "color_count": colors.size(), "sample_color": str(colors[0]), "vertex_color_use_as_albedo": material.vertex_color_use_as_albedo, "vertex_color_is_srgb": material.vertex_color_is_srgb, "shading_mode": material.shading_mode, "cull_mode": material.cull_mode})
	for child in node.get_children():
		inspect_node(child)
