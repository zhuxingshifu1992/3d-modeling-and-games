extends SceneTree
## Inspect the staged asset without changing the playable game's catalog or mouse state.

var errors: Array[String] = []
var measurements := {}

func require(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var path := "res://assets/models/nu_refined.glb"
	require(ResourceLoader.exists(path), "Optimized Nu GLB must import")
	if not errors.is_empty():
		quit(1)
		return
	var model := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var marker := model.find_child("HeadHeightReference", true, false) as Node3D
	require(marker != null, "Explicit non-antenna head reference must exist")
	if marker != null:
		measurements.head_height_m = marker.global_position.y
		require(absf(marker.global_position.y - 22.0) < 0.015, "Nu head reference must be 22 meters")
	var funnels := model.find_child("FinFunnels", true, false) as MeshInstance3D
	require(funnels != null and funnels.mesh != null, "Complete fin-funnel geometry must remain in its own identifiable mesh")
	if funnels != null and funnels.mesh != null:
		var fin_bounds: AABB = funnels.global_transform * funnels.get_aabb()
		measurements.fin_funnel_bounds = str(fin_bounds)
		require(fin_bounds.size.length() > 5.0 and fin_bounds.size.length() < 35.0, "Fin funnels have a plausible bounded physical size")
		require(fin_bounds.position.y >= -0.025 and fin_bounds.end.y < 33.0, "Fin funnels stay above ground and below the hangar ceiling")
	require(model.find_child("CockpitHatch", true, false) != null, "Original chest cover is retained as a separate hatch")
	var first := true
	var bounds := AABB()
	var surfaces := 0
	var triangles := 0
	var textured := 0
	var normal_mapped := 0
	var max_texture := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		require(mesh.skin == null, "Staged display mesh must use the evaluated static pose")
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for index in range(mesh.mesh.get_surface_count()):
			surfaces += 1
			var arrays := mesh.mesh.surface_get_arrays(index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
			var material := mesh.get_active_material(index) as BaseMaterial3D
			require(material != null, "Surface has an imported PBR material")
			if material != null:
				if material.albedo_texture != null:
					textured += 1
				if material.normal_enabled and material.normal_texture != null:
					normal_mapped += 1
				for texture in [material.albedo_texture, material.normal_texture, material.roughness_texture, material.metallic_texture, material.emission_texture]:
					if texture != null:
						max_texture = maxi(max_texture, maxi(texture.get_width(), texture.get_height()))
	require(not first and absf(bounds.position.y) < 0.025, "Feet rest at ground zero")
	require(triangles >= 110000 and triangles < 130000, "Authored detailed geometry is retained")
	require(surfaces <= 15, "Mesh batching stays within 15 material surfaces")
	require(textured >= 9 and normal_mapped >= 8, "Authored PBR color and normal maps survive import")
	require(max_texture <= 2048, "Game textures are limited to 2K")
	require(bounds.end.y < 33.0, "Equipment fits below hangar structural ceiling")
	measurements.merge({"bounds": str(bounds), "triangles": triangles, "surfaces": surfaces, "textured_surfaces": textured, "normal_mapped_surfaces": normal_mapped, "max_texture_dimension": max_texture})
	var output := {"source": path, "sha256": FileAccess.get_sha256(path), "measurements": measurements, "errors": errors,
		"passed": errors.is_empty(), "scope": "Staged static model only; no cockpit or playable catalog integration asserted."}
	var report_path := "res://previews/refined_nu/godot_asset_check.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	model.free()
	print("NU_ASSET ", "PASS" if errors.is_empty() else "FAIL", " ", JSON.stringify(measurements))
	quit(0 if errors.is_empty() else 1)
