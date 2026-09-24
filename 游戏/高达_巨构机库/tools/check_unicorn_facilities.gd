extends SceneTree
## Headless audit of every final UnicornBody triangle against production world
## primitives and neighboring imported models. No player/game/input instance.

const CELL := 2.0
const REFINE_DISTANCE := 1.0

class AuditWorld:
	extends "res://scripts/world.gd"
	var records: Array = []
	var group := "architecture"
	var fixture_z := 4.5
	var berth_height := 0.0
	func _berth(info: Dictionary) -> void:
		group = str(info.bay) + "_facilities"
		fixture_z = float(info.get("work_fixture_z", 4.5))
		berth_height = float(info.height)
		super._berth(info)
		group = "architecture"
	func _person(pos: Vector3, yaw: float) -> void:
		var saved_group := group
		group += "/technician_at_" + str(pos)
		super._person(pos, yaw)
		group = saved_group
	func _cart(pos: Vector3) -> void:
		var saved_group := group
		group += "/maintenance_cart_at_" + str(pos)
		super._cart(pos)
		group = saved_group
	func _tool_cabinet(pos: Vector3) -> void:
		var saved_group := group
		group += "/tool_cabinet_at_" + str(pos)
		super._tool_cabinet(pos)
		group = saved_group
	func _part(mesh: Mesh, pos: Vector3, key: String, rotation: Basis = Basis.IDENTITY) -> void:
		var pose := _frame * Transform3D(rotation, pos)
		var bounds: AABB = pose * mesh.get_aabb()
		var label := group
		if group == "A2_facilities":
			if absf(pos.z - 7.0) < 0.01 and absf(absf(pos.x) - 7.8) < 0.01:
				label += "/rear_mast"
			elif absf(pos.z - 6.6) < 0.01:
				label += "/work_platform_or_rail"
			elif pos.y > berth_height + 1.0 and pos.z > 6.9:
				label += "/header_sign"
			elif absf(absf(pos.x) - 6.0) < 0.01 and pos.y < 7.0 and (absf(pos.z - fixture_z) < 0.01 or absf(pos.z - fixture_z + 0.37) < 0.01):
				label += "/work_light"
		var ground := ""
		if mesh is BoxMesh and key == "floor" and bounds.end.y <= 0.0001:
			ground = "Production floor slab: expected sole contact"
		elif mesh is BoxMesh and key in ["pad", "dark", "amber", "paint", "cyan"] and bounds.size.y <= 0.05 and bounds.position.y >= -0.001 and bounds.end.y <= 0.061:
			ground = "Production floor pad/paint/seam only: flat <= 5 cm and entirely below 6.1 cm"
		records.append({"id": records.size(), "label": label + "/" + key, "bounds": bounds, "local_center": pos, "primitive_type": mesh.get_class(), "primitive_bounds": mesh.get_aabb(), "primitive_pose": pose, "ground_exclusion": ground})
		super._part(mesh, pos, key, rotation)

var report := {"status": "not_run", "failures": [], "groups": {}, "excluded_ground": [], "limitations": [
	"All final imported UnicornBody triangles are tested, excluding the separate moving CockpitHatch. Own bay cabin/boarding equipment and hatch motion are covered by separate root checks, not this world-facility audit.",
	"Actual production world primitives are intercepted at the same transform passed to the production geometry builder; they are not collision proxies. Other machines and labels use their full rendered mesh bounds conservatively.",
	"Continuous triangle/solid-box separation uses the complete triangle/box separating-axis family in each primitive's local frame. AABB broad phase and a 2 m spatial index only prune pairs with a proven >= 1 m distance; no surface point sampling is used.",
	"Reported positive distances are conservative lower bounds, not closest-point distances. For non-box primitives a zero distance is an unresolved enclosing-box candidate, never labeled a proven mesh collision.",
	"This is a static surface audit; it does not reconstruct watertight body solid volumes or classify an entire small object fully enclosed within a model shell. Other bays' dynamic cabin equipment is outside scope."
]}
var world
var fixture: Node3D
var machine: Node3D
var body_boxes: Array[AABB] = []
var body_triangles: Array[PackedVector3Array] = []
var triangle_sources: Array[String] = []
var grid := {}
var body_bounds: AABB
var have_bounds := false
var minimum := INF
var nearest := {}

func _initialize() -> void:
	call_deferred("run")

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func triangle_json(triangle: PackedVector3Array, pose := Transform3D.IDENTITY) -> Array:
	return [vec(pose * triangle[0]), vec(pose * triangle[1]), vec(pose * triangle[2])]

func cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / CELL), floori(point.y / CELL), floori(point.z / CELL))

func add_grid(index: int, bounds: AABB) -> void:
	var lo := cell(bounds.position)
	var hi := cell(bounds.end)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				if not grid.has(key):
					grid[key] = []
				grid[key].append(index)

func nearby_indices(bounds: AABB) -> Dictionary:
	var lo := cell(bounds.position - Vector3.ONE * REFINE_DISTANCE)
	var hi := cell(bounds.end + Vector3.ONE * REFINE_DISTANCE)
	var indices := {}
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				for index in grid.get(Vector3i(x, y, z), []):
					indices[index] = true
	return indices

func separation(a: AABB, b: AABB) -> float:
	var gap := Vector3(maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x)), maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y)), maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z)))
	return gap.length()

func triangle_box_lower(triangle: PackedVector3Array, box: AABB) -> float:
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

func describe(record: Dictionary) -> Dictionary:
	var bounds: AABB = record.bounds
	var result := {"primitive_id": record.id, "label": record.label, "primitive_type": record.get("primitive_type", "rendered_bounds"), "bounds_min_world": vec(bounds.position), "bounds_max_world": vec(bounds.end)}
	if record.has("local_center"):
		result["center_in_authored_facility_frame"] = vec(record.local_center)
		var pose: Transform3D = record.primitive_pose
		result["center_in_A2_local"] = vec(machine.to_local(pose.origin))
	return result

func test_record(record: Dictionary) -> void:
	if not str(record.get("ground_exclusion", "")).is_empty():
		var excluded := describe(record)
		excluded["reason"] = record.ground_exclusion
		report.excluded_ground.append(excluded)
		return
	var bounds: AABB = record.bounds
	var lower := separation(body_bounds, bounds)
	var hits: Array = []
	var hit_count := 0
	var tested := 0
	if lower < REFINE_DISTANCE:
		lower = REFINE_DISTANCE
		var inverse: Transform3D = record.primitive_pose.affine_inverse() if record.has("primitive_pose") else Transform3D.IDENTITY
		var primitive_bounds: AABB = record.get("primitive_bounds", bounds)
		for index: int in nearby_indices(bounds):
			var distance := separation(body_boxes[index], bounds)
			if distance >= lower and distance > 0.0:
				continue
			tested += 1
			if distance == 0.0:
				var triangle := body_triangles[index]
				var local_triangle := PackedVector3Array([inverse * triangle[0], inverse * triangle[1], inverse * triangle[2]])
				distance = triangle_box_lower(local_triangle, primitive_bounds)
			lower = minf(lower, distance)
			if distance <= 0.00001:
				hit_count += 1
				if hits.size() < 8:
					hits.append({"triangle_index": index, "mesh_surface": triangle_sources[index], "world": triangle_json(body_triangles[index]), "A2_local": triangle_json(body_triangles[index], machine.global_transform.affine_inverse()), "primitive_local": triangle_json(body_triangles[index], inverse), "projected_gap_m": distance})
	var label: String = record.label
	var group: String = label.get_slice("/", 0)
	if label.begins_with("A2_facilities/") and label.get_slice_count("/") > 2:
		group += "/" + label.get_slice("/", 1)
	if not report.groups.has(group):
		report.groups[group] = {"objects": 0, "tested_triangle_pairs": 0, "minimum_conservative_separation_m": INF}
	report.groups[group].objects += 1
	report.groups[group].tested_triangle_pairs += tested
	if lower < float(report.groups[group].minimum_conservative_separation_m):
		report.groups[group].minimum_conservative_separation_m = lower
		report.groups[group]["nearest"] = describe(record)
	if lower < minimum:
		minimum = lower
		nearest = describe(record)
	if hit_count > 0:
		var failure := describe(record)
		failure["reason"] = "Body triangle intersects actual oriented solid BoxMesh" if record.get("primitive_type", "") == "BoxMesh" else "Enclosing-box candidate; exact non-box geometry follow-up required"
		failure["triangle_count"] = hit_count
		failure["first_triangles"] = hits
		report.failures.append(failure)

func collect_meshes(node: Node, label: String) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		world.records.append({"id": world.records.size(), "label": label + "/" + str(mesh.name), "bounds": mesh.global_transform * mesh.mesh.get_aabb()})

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
	machine = world.get_node("unicorn")
	var model_path := "res://assets/models/unicorn_refined.glb"
	var conversion_path := "res://source/external/unicorn_sketchfab/derived/conversion_report.json"
	var conversion: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(conversion_path))
	var config := ConfigFile.new()
	config.load(model_path + ".import")
	var imported_path: String = config.get_value("remap", "path", "")
	var hashes := FileAccess.get_file_as_string(imported_path.get_basename() + ".md5")
	var source_md5 := FileAccess.get_md5(model_path)
	report["evidence"] = {"model_path": model_path, "model_sha256": FileAccess.get_sha256(model_path), "imported_scene_sha256": FileAccess.get_sha256(imported_path), "import_hash_record": hashes, "source_md5": source_md5, "world_script_sha256": FileAccess.get_sha256("res://scripts/world.gd"), "catalog_sha256": FileAccess.get_sha256("res://scripts/catalog.gd"), "conversion_report_sha256": FileAccess.get_sha256(conversion_path), "audit_script_sha256": FileAccess.get_sha256("res://tools/check_unicorn_facilities.gd"), "source_obj_sha256": FileAccess.get_sha256("res://source/external/unicorn_sketchfab/author_source/UNICORN_GUNDAM_OBJ.obj")}
	if not hashes.contains('source_md5="' + source_md5 + '"') or report.evidence.model_sha256 != conversion.target_sha256:
		report.failures.append("Imported cache/conversion report does not match the current model")
	var mesh_triangles := {}
	var excluded_meshes := []
	for mesh: MeshInstance3D in machine.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name) != "UnicornBody":
			excluded_meshes.append(str(mesh.name))
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			mesh_triangles[str(mesh.name)] = int(mesh_triangles.get(str(mesh.name), 0)) + count / 3
			for i in range(0, count, 3):
				var a: Vector3 = mesh.global_transform * vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = mesh.global_transform * vertices[indices[i + 1] if not indices.is_empty() else i + 1]
				var c: Vector3 = mesh.global_transform * vertices[indices[i + 2] if not indices.is_empty() else i + 2]
				var lo := a.min(b).min(c)
				var box := AABB(lo, a.max(b).max(c) - lo)
				add_grid(body_boxes.size(), box)
				body_boxes.append(box)
				body_triangles.append(PackedVector3Array([a, b, c]))
				triangle_sources.append(str(mesh.name) + "/surface_" + str(surface))
				body_bounds = body_bounds.merge(box) if have_bounds else box
				have_bounds = true
	report["selected_mesh_triangles"] = mesh_triangles
	report["excluded_meshes"] = excluded_meshes
	report["body_triangle_count"] = body_boxes.size()
	var expected := -1
	for info: Dictionary in conversion.meshes:
		if info.name == "UnicornBody":
			expected = int(info.triangles)
	if mesh_triangles.get("UnicornBody", 0) != expected or expected <= 0 or excluded_meshes != ["CockpitHatch"]:
		report.failures.append("Actual imported mesh selection/count does not match conversion report")
	report["body_world_bounds"] = [vec(body_bounds.position), vec(body_bounds.end)]
	var local_bounds: AABB = machine.global_transform.affine_inverse() * body_bounds
	report["body_A2_local_bounds"] = [vec(local_bounds.position), vec(local_bounds.end)]
	for info: Dictionary in catalog:
		if info.id != "unicorn":
			collect_meshes(world.get_node(info.id), str(info.bay) + "_machine")
	for info: Dictionary in load("res://scripts/catalog.gd").exhibits():
		collect_meshes(world.get_node(info.id), "other_exhibit")
	await process_frame
	for label: Label3D in fixture.find_children("*", "Label3D", true, false):
		world.records.append({"id": world.records.size(), "label": "sign_text/" + label.text.replace("\n", " "), "bounds": label.global_transform * label.get_aabb()})
	for record: Dictionary in world.records:
		test_record(record)
	report["actual_facility_and_neighbor_objects"] = world.records.size()
	report["excluded_ground_objects"] = report.excluded_ground.size()
	report["minimum_conservative_separation_m"] = minimum
	report["nearest"] = nearest
	report["timestamp_utc"] = Time.get_datetime_string_from_system(true)
	report.status = "passed_static_conservative_clearance" if report.failures.is_empty() else "failed_clearance_or_evidence"
	var output := "res://previews/refined_unicorn/facilities_clearance.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("UNICORN_FACILITIES ", report.status, " triangles=", body_boxes.size(), " objects=", world.records.size(), " ground_exclusions=", report.excluded_ground.size(), " lower_bound_m=", minimum, " failures=", report.failures.size())
	fixture.queue_free()
	await process_frame
	quit(0 if report.failures.is_empty() else 1)
