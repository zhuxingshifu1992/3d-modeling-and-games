extends SceneTree
## Headless continuous static clearance using final imported wing triangles.
## World primitives are captured at their actual production emission transform.
## AABB separation is a conservative LOWER bound, not closest surface distance.

class AuditWorld:
	extends "res://scripts/world.gd"
	var records: Array = []
	var group := "architecture"
	var fixture_z := 4.5
	func _berth(info: Dictionary) -> void:
		group = str(info.bay) + "_facilities"
		fixture_z = float(info.get("work_fixture_z", 4.5))
		super._berth(info)
		group = "architecture"
	func _part(mesh: Mesh, pos: Vector3, key: String, rotation: Basis = Basis.IDENTITY) -> void:
		var bounds: AABB = (_frame * Transform3D(rotation, pos)) * mesh.get_aabb()
		var label := group
		if group == "B1_facilities":
			if absf(pos.z - 7.0) < 0.01 and absf(absf(pos.x) - 7.8) < 0.01:
				label += "/rear_mast"
			elif absf(pos.z - 6.6) < 0.01:
				label += "/work_platform_or_rail"
			elif pos.y > 19.5 and pos.z > 6.9:
				label += "/header_sign"
			elif absf(absf(pos.x) - 6.0) < 0.01 and pos.y < 7.0 and (absf(pos.z - fixture_z) < 0.01 or absf(pos.z - fixture_z + 0.37) < 0.01):
				label += "/work_light"
		records.append({"label": label + "/" + key, "bounds": bounds, "local_center": pos})
		super._part(mesh, pos, key, rotation)

var report := {"status": "not_run", "failures": [], "groups": {}, "limitations": [
	"Static authored wing pose only; no wing deployment animation is claimed.",
	"Every actual imported wing triangle is enclosed by its world-space AABB. Each actual facility primitive is enclosed by its transformed AABB. Overlapping triangle boxes are refined with the full triangle/box separating-axis family. Positive distance is a conservative lower bound for continuous wing surfaces against facility solid boxes; no spatial point sampling is used.",
	"This is a surface-clearance audit; it does not reconstruct watertight wing solid volumes or separately classify a whole fixture fully enclosed inside a wing shell.",
	"Label3D rendered bounds and B2 mesh bounds are included; transparent pixels remain conservatively enclosed.",
	"Own boarding infrastructure includes all MeshInstance3D geometry; lift bounds include their full vertical travel. Other bays' world facilities and machines are included, but their dynamic cockpit interiors are omitted."
]}
var world
var fixture: Node3D
var wing_boxes: Array[AABB] = []
var wing_triangles: Array[PackedVector3Array] = []
var wing_bounds: AABB
var have_bounds := false
var minimum := INF
var nearest := {}

func _initialize() -> void:
	call_deferred("run")

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func separation(a: AABB, b: AABB) -> float:
	var gap := Vector3(maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x)), maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y)), maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z)))
	return gap.length()

func triangle_box_lower(triangle: PackedVector3Array, box: AABB) -> float:
	# Complete triangle/AABB separating-axis family. A positive projected gap
	# is a conservative Euclidean lower bound. Zero means a real triangle/box
	# intersection (up to floating point), not merely overlapping AABBs.
	var a := triangle[0] - box.get_center()
	var b := triangle[1] - box.get_center()
	var c := triangle[2] - box.get_center()
	var half := box.size * 0.5
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK, (b - a).cross(c - a)]
	for edge: Vector3 in [b - a, c - b, a - c]:
		for coordinate: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			axes.append(edge.cross(coordinate))
	var lower := 0.0
	for axis: Vector3 in axes:
		if axis.length_squared() < 1e-18:
			continue
		axis = axis.normalized()
		var radius := half.dot(axis.abs())
		var p := a.dot(axis)
		var q := b.dot(axis)
		var r := c.dot(axis)
		lower = maxf(lower, maxf(minf(p, minf(q, r)) - radius, -radius - maxf(p, maxf(q, r))))
	return lower

func test_record(record: Dictionary) -> void:
	var bounds: AABB = record.bounds
	var lower := separation(wing_bounds, bounds)
	# Refine close aggregate bounds with ALL wing triangle bounds. The union of
	# these boxes contains all continuous wing surfaces, including triangle edges.
	if lower < 1.0:
		lower = INF
		for index in range(wing_boxes.size()):
			var distance := separation(wing_boxes[index], bounds)
			if distance == 0.0:
				distance = triangle_box_lower(wing_triangles[index], bounds)
			lower = minf(lower, distance)
			if lower == 0.0:
				break
	var label: String = record.label
	var group: String = label.get_slice("/", 0)
	if label.begins_with("B1_facilities/") and label.get_slice_count("/") > 2:
		group += "/" + label.get_slice("/", 1)
	if not report.groups.has(group):
		report.groups[group] = {"objects": 0, "minimum_conservative_separation_m": INF}
	report.groups[group].objects += 1
	if lower < float(report.groups[group].minimum_conservative_separation_m):
		report.groups[group].minimum_conservative_separation_m = lower
		report.groups[group]["nearest"] = {"label": label, "bounds_min": vec(bounds.position), "bounds_max": vec(bounds.end)}
	if lower < minimum:
		minimum = lower
		nearest = {"label": label, "bounds_min": vec(bounds.position), "bounds_max": vec(bounds.end)}
	if lower <= 0.00001:
		report.failures.append({"label": label, "reason": "Wing triangle intersects the actual primitive's enclosing solid box under full triangle/box SAT; exact for axis-aligned BoxMesh primitives", "bounds_min": vec(bounds.position), "bounds_max": vec(bounds.end)})

func collect_meshes(node: Node, label: String, sweep_lift: bool = false) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		if sweep_lift and node.platform.is_ancestor_of(mesh):
			bounds = bounds.merge(AABB(bounds.position + Vector3.UP * node.top_y, bounds.size))
		world.records.append({"label": label + "/" + str(mesh.name), "bounds": bounds})

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Facility audit requires --headless")
		quit(2)
		return
	fixture = Node3D.new()
	root.add_child(fixture)
	var unit := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var sat_crossing := triangle_box_lower(PackedVector3Array([Vector3(-2, 0, 0), Vector3(2, 0, 0), Vector3(0, 2, 0)]), unit)
	var sat_diagonal := triangle_box_lower(PackedVector3Array([Vector3(0.9, 1.5, 0), Vector3(1.5, 0.9, 0), Vector3(1.5, 1.5, 0)]), unit)
	var sat_contact := triangle_box_lower(PackedVector3Array([Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 0, 1)]), unit)
	report["separating_axis_self_checks"] = {"crossing_gap": sat_crossing, "diagonal_separation_gap": sat_diagonal, "coplanar_contact_gap": sat_contact}
	if sat_crossing != 0.0 or sat_contact != 0.0 or absf(sat_diagonal - sqrt(0.08)) > 0.00001:
		report.failures.append("Triangle/box SAT reference fixtures failed")
	var catalog: Array = load("res://scripts/catalog.gd").machines()
	world = AuditWorld.new()
	fixture.add_child(world)
	world.build(catalog)
	var machine: Node3D = world.get_node("freedom")
	var model_path := "res://assets/models/freedom_refined.glb"
	var config := ConfigFile.new()
	config.load(model_path + ".import")
	var imported_path: String = config.get_value("remap", "path", "")
	var hashes := FileAccess.get_file_as_string(imported_path.get_basename() + ".md5")
	var source_md5 := FileAccess.get_md5(model_path)
	report["evidence"] = {"model_path": model_path, "model_sha256": FileAccess.get_sha256(model_path), "imported_scene_sha256": FileAccess.get_sha256(imported_path), "import_hash_record": hashes, "source_md5": source_md5, "world_script_sha256": FileAccess.get_sha256("res://scripts/world.gd"), "catalog_sha256": FileAccess.get_sha256("res://scripts/catalog.gd"), "bay_script_sha256": FileAccess.get_sha256("res://scripts/bay.gd")}
	report.evidence["audit_script_sha256"] = FileAccess.get_sha256("res://tools/check_freedom_facilities.gd")
	report.evidence["immutable_source_sha256"] = FileAccess.get_sha256("res://source/external/strike_freedom_sketchfab/strike_freedom_gundam_2k.glb")
	if not hashes.contains('source_md5="' + source_md5 + '"'):
		report.failures.append("Imported cache does not match the current model")
	var material_triangles := {}
	for mesh: MeshInstance3D in machine.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.mesh.surface_get_material(surface)
			if material == null or material.resource_name not in ["right_wing_up", "mini_bim"]:
				continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			material_triangles[material.resource_name] = int(material_triangles.get(material.resource_name, 0)) + count / 3
			for i in range(0, count, 3):
				var a: Vector3 = mesh.global_transform * vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = mesh.global_transform * vertices[indices[i + 1] if not indices.is_empty() else i + 1]
				var c: Vector3 = mesh.global_transform * vertices[indices[i + 2] if not indices.is_empty() else i + 2]
				var lo := a.min(b).min(c)
				var box := AABB(lo, a.max(b).max(c) - lo)
				wing_boxes.append(box)
				wing_triangles.append(PackedVector3Array([a, b, c]))
				wing_bounds = wing_bounds.merge(box) if have_bounds else box
				have_bounds = true
	report["wing_material_triangles"] = material_triangles
	report["wing_triangle_count"] = wing_boxes.size()
	report["selection_basis"] = "Immutable source Object_13/14/15/16 use right_wing_up; Object_25/26/27 use mini_bim. Final imported surfaces preserve those names."
	report["source_original_triangle_counts"] = {"right_wing_up": 147232, "mini_bim": 18976}
	report["triangulation_note"] = "Converter bisect planes subdivide the entire joined body before removing cockpit faces. Wings keep their shape but gain triangles. Selection checks both source material surfaces have at least their original triangle counts."
	if material_triangles.get("right_wing_up", 0) < 147232 or material_triangles.get("mini_bim", 0) < 18976:
		report.failures.append("Wing surface triangle counts are lower than the source objects")
	report["wing_world_bounds"] = [vec(wing_bounds.position), vec(wing_bounds.end)]
	for info: Dictionary in catalog:
		if info.id != "freedom":
			collect_meshes(world.get_node(info.id), str(info.bay) + "_machine")
		else:
			var bay = load("res://scripts/bay.gd").new()
			fixture.add_child(bay)
			bay.setup(info)
			collect_meshes(bay, "B1_boarding_infrastructure", true)
	for info: Dictionary in load("res://scripts/catalog.gd").exhibits():
		collect_meshes(world.get_node(info.id), "other_exhibit")
	await process_frame
	for label: Label3D in fixture.find_children("*", "Label3D", true, false):
		world.records.append({"label": "sign_text/" + label.text.replace("\n", " "), "bounds": label.global_transform * label.get_aabb()})
	for record: Dictionary in world.records:
		test_record(record)
	report["actual_facility_and_neighbor_objects"] = world.records.size()
	report["minimum_conservative_separation_m"] = minimum
	report["nearest"] = nearest
	report["timestamp_utc"] = Time.get_datetime_string_from_system(true)
	report.status = "passed_static_conservative_clearance" if report.failures.is_empty() else "failed_clearance_or_evidence"
	var output := "res://previews/refined_freedom/facilities_clearance.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FREEDOM_FACILITIES ", report.status, " triangles=", wing_boxes.size(), " objects=", world.records.size(), " lower_bound_m=", minimum, " failures=", report.failures.size())
	fixture.queue_free()
	await process_frame
	quit(0 if report.failures.is_empty() else 1)
