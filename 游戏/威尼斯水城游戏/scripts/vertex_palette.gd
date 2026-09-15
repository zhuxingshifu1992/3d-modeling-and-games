class_name VertexPalette
extends RefCounted

## Activate the linear COLOR_0 palette on imported mesh materials.
## Return the number of materials repaired. Repeated calls are safe.
static func apply(root: Node) -> int:
	if root == null:
		return 0
	var repaired := 0
	if root is MeshInstance3D and root.mesh != null:
		for surface in root.mesh.get_surface_count():
			var material: Material = root.get_active_material(surface)
			if not material is BaseMaterial3D:
				continue
			if material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb:
				continue
			var arrays: Array = root.mesh.surface_get_arrays(surface)
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			if colors == null or colors.is_empty():
				continue
			# Keep cached GLB resources and unrelated instances unchanged. Resource
			# duplication preserves every other authored material property.
			var corrected := material.duplicate() as BaseMaterial3D
			corrected.vertex_color_use_as_albedo = true
			corrected.vertex_color_is_srgb = false
			if root.material_override != null:
				root.material_override = corrected
			else:
				root.set_surface_override_material(surface, corrected)
			repaired += 1
	for child in root.get_children():
		repaired += apply(child)
	return repaired
