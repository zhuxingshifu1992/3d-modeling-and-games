extends SceneTree
## CPU-only geometry checks against the imported RX-78 mesh, not hangar proxy colliders.
## Camera spheres are sampled every <= 4 cm; this is not a full animated body/capsule proof.

const OUTPUT := "res://previews/refined_rx78/clearance_result.json"
const CAMERA_RADIUS := 0.08
const STEP := 0.04
const GRID := 0.50
const OPEN_DEGREES := 110.0
const WAIT_Z := -4.80

class Facet:
	extends RefCounted
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var lo: Vector3
	var hi: Vector3
	var source: String
	func _init(pa: Vector3, pb: Vector3, pc: Vector3, label: String) -> void:
		a = pa
		b = pb
		c = pc
		lo = a.min(b).min(c)
		hi = a.max(b).max(c)
		source = label

var report := {
	"status": "not_run", "checks": [], "failures": [], "measurements": {},
	"limitations": [
		"Uses actual imported mesh surface triangles, double-sided; does not use world proxy colliders.",
		"Samples an 8 cm camera sphere at <= 4 cm intervals plus exact segment/triangle crossings; not a complete animated human capsule clearance proof.",
		"Head/neck check detects non-coplanar triangle crossings at every fifth of 181 production door_amount samples. Coplanar contact, containment, and collisions between samples are not exhaustively proven absent.",
		"Hatch waiting-line envelope uses actual vertices at 181 production door_amount samples with 1 cm additional margin.",
		"Only exterior mesh intrusion is tested; cockpit furniture/body animation and visual finish require separate checks."
	]
}
var game
var bay
var model: Node3D
var hatch: Node3D
var mesh_count := 0
var skinned_count := 0
var wait_z := WAIT_Z

func _initialize() -> void:
	call_deferred("run")

func _check(ok: bool, name: String, detail: Variant = null) -> void:
	report.checks.append({"name": name, "passed": ok, "detail": detail})
	if not ok:
		report.failures.append(name)
		push_error("RX78_CLEARANCE_FAIL " + name)

func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.00001), snappedf(value.y, 0.00001), snappedf(value.z, 0.00001)]

func _asset_evidence() -> bool:
	var catalog: Array = load("res://scripts/catalog.gd").machines()
	var source_path: String = catalog[0].model_path
	var sidecar := source_path + ".import"
	var evidence := {"source_path": source_path, "source_sha256": FileAccess.get_sha256(source_path),
		"source_md5": FileAccess.get_md5(source_path), "source_modified_unix": FileAccess.get_modified_time(source_path),
		"import_sidecar_sha256": FileAccess.get_sha256(sidecar), "import_sidecar_modified_unix": FileAccess.get_modified_time(sidecar)}
	var config := ConfigFile.new()
	var scene_path := ""
	if config.load(sidecar) == OK:
		scene_path = str(config.get_value("remap", "path", ""))
	evidence["imported_scene_path"] = scene_path
	var source_matches := false
	if not scene_path.is_empty() and FileAccess.file_exists(scene_path):
		evidence["imported_scene_sha256"] = FileAccess.get_sha256(scene_path)
		evidence["imported_scene_modified_unix"] = FileAccess.get_modified_time(scene_path)
		var hash_path := scene_path.get_basename() + ".md5"
		if FileAccess.file_exists(hash_path):
			var hash_text := FileAccess.get_file_as_string(hash_path)
			evidence["import_hash_file"] = hash_path
			evidence["import_hash_text"] = hash_text
			var regex := RegEx.new()
			regex.compile('source_md5="([0-9a-f]+)"')
			var found := regex.search(hash_text)
			if found:
				evidence["cached_source_md5"] = found.get_string(1)
				source_matches = found.get_string(1) == evidence.source_md5
	evidence["cache_matches_current_source"] = source_matches
	report["asset_evidence"] = evidence
	return source_matches

func _finish() -> void:
	report.status = "passed_with_documented_limits" if report.failures.is_empty() else "failed"
	report.timestamp_utc = Time.get_datetime_string_from_system(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		push_error("Could not write " + OUTPUT)
		quit(2)
		return
	print("RX78_CLEARANCE ", report.status, " failures=", report.failures.size(), " output=", OUTPUT)
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	quit(0 if report.failures.is_empty() else 1)

func _facets(only_hatch: bool = false, omit_hatch: bool = false) -> Array:
	var facets: Array = []
	for item in model.find_children("*", "MeshInstance3D", true, false):
		var instance := item as MeshInstance3D
		var belongs: bool = instance == hatch or hatch.is_ancestor_of(instance)
		if (only_hatch and not belongs) or (omit_hatch and belongs):
			continue
		if instance.mesh == null:
			continue
		var transform_local: Transform3D = bay.global_transform.affine_inverse() * instance.global_transform
		for surface in range(instance.mesh.get_surface_count()):
			if instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index in range(0, count - 2, 3):
				var ia := indices[index] if not indices.is_empty() else index
				var ib := indices[index + 1] if not indices.is_empty() else index + 1
				var ic := indices[index + 2] if not indices.is_empty() else index + 2
				facets.append(Facet.new(transform_local * vertices[ia], transform_local * vertices[ib], transform_local * vertices[ic], str(instance.name)))
	return facets

func _boxes_overlap(lo_a: Vector3, hi_a: Vector3, lo_b: Vector3, hi_b: Vector3) -> bool:
	return lo_a.x <= hi_b.x and hi_a.x >= lo_b.x and lo_a.y <= hi_b.y and hi_a.y >= lo_b.y and lo_a.z <= hi_b.z and hi_a.z >= lo_b.z

func _near_facets(facets: Array, lo: Vector3, hi: Vector3) -> Array:
	var nearby: Array = []
	for facet: Facet in facets:
		if _boxes_overlap(facet.lo, facet.hi, lo, hi):
			nearby.append(facet)
	return nearby

func _segment_hit(from: Vector3, to: Vector3, facet: Facet, strict: bool = false) -> float:
	# Moller-Trumbore without backface culling. Returned value is distance along segment.
	var direction := to - from
	var edge_a := facet.b - facet.a
	var edge_b := facet.c - facet.a
	var p := direction.cross(edge_b)
	var determinant := edge_a.dot(p)
	if absf(determinant) < 0.00000001:
		return -1.0
	var inverse := 1.0 / determinant
	var relative := from - facet.a
	var u := relative.dot(p) * inverse
	var epsilon := 0.000001 if strict else -0.000001
	if u < epsilon or u > 1.0 - epsilon:
		return -1.0
	var q := relative.cross(edge_a)
	var v := direction.dot(q) * inverse
	if v < epsilon or u + v > 1.0 - epsilon:
		return -1.0
	var t := edge_b.dot(q) * inverse
	if t <= 0.000001 or t >= 0.999999:
		return -1.0
	return t * direction.length()

func _point_segment_sq(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.00000001:
		return point.distance_squared_to(a)
	return point.distance_squared_to(a + ab * clampf((point - a).dot(ab) / denom, 0.0, 1.0))

func _point_triangle_sq(point: Vector3, facet: Facet) -> float:
	# Closest point on triangle, including edges and degenerate triangles.
	var a := facet.a
	var b := facet.b
	var c := facet.c
	var ab := b - a
	var ac := c - a
	if ab.cross(ac).length_squared() < 0.0000000001:
		return minf(_point_segment_sq(point, a, b), minf(_point_segment_sq(point, b, c), _point_segment_sq(point, c, a)))
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return ap.length_squared()
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return bp.length_squared()
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return point.distance_squared_to(a + ab * (d1 / (d1 - d3)))
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return cp.length_squared()
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return point.distance_squared_to(a + ac * (d2 / (d2 - d6)))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return point.distance_squared_to(b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))))
	var denom := 1.0 / (va + vb + vc)
	return point.distance_squared_to(a + ab * (vb * denom) + ac * (vc * denom))

func _sphere_hits(point: Vector3, radius: float, facets: Array) -> Array:
	var hits: Array = []
	var spread := Vector3.ONE * radius
	for facet: Facet in facets:
		if not _boxes_overlap(point - spread, point + spread, facet.lo, facet.hi):
			continue
		var distance_sq := _point_triangle_sq(point, facet)
		if distance_sq < radius * radius:
			hits.append({"mesh": facet.source, "distance_m": sqrt(distance_sq), "point": _vec(point)})
			if hits.size() >= 8:
				break
	return hits

func _ray_hits(from: Vector3, to: Vector3, facets: Array) -> Array:
	var hits: Array = []
	var lo := from.min(to)
	var hi := from.max(to)
	for facet: Facet in facets:
		if not _boxes_overlap(lo, hi, facet.lo, facet.hi):
			continue
		var distance := _segment_hit(from, to, facet)
		if distance >= 0.0:
			hits.append({"mesh": facet.source, "distance_m": distance, "point": _vec(from.move_toward(to, distance))})
			if hits.size() >= 8:
				break
	return hits

func _cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / GRID), floori(point.y / GRID), floori(point.z / GRID))

func _make_grid(facets: Array) -> Dictionary:
	var grid := {}
	for index in range(facets.size()):
		var facet: Facet = facets[index]
		var lo := _cell(facet.lo)
		var hi := _cell(facet.hi)
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(index)
	return grid

func _triangle_crossings(a: Facet, b: Facet) -> Array:
	if not _boxes_overlap(a.lo, a.hi, b.lo, b.hi):
		return []
	var crossings: Array = []
	for edge in [[a.a, a.b, b], [a.b, a.c, b], [a.c, a.a, b], [b.a, b.b, a], [b.b, b.c, a], [b.c, b.a, a]]:
		var distance := _segment_hit(edge[0], edge[1], edge[2], true)
		if distance >= 0.0:
			var point: Vector3 = (edge[0] as Vector3).move_toward(edge[1], distance)
			# A long chest triangle's AABB may enter this region while its actual crossing does not.
			if point.y >= 15.58 and absf(point.x) <= 1.6:
				crossings.append(_vec(point))
	return crossings

func _head_conflicts(hatch_facets: Array, fixed_facets: Array, grid: Dictionary) -> Array:
	var conflicts: Array = []
	for facet: Facet in hatch_facets:
		var lo := _cell(facet.lo)
		var hi := _cell(facet.hi)
		var candidates := {}
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					for index in grid.get(Vector3i(x, y, z), []):
						candidates[index] = true
		for index in candidates:
			var fixed: Facet = fixed_facets[index]
			var points := _triangle_crossings(facet, fixed)
			if not points.is_empty():
				conflicts.append({"hatch_mesh": facet.source, "body_mesh": fixed.source, "crossing_points": points, "hatch_triangle": [_vec(facet.a), _vec(facet.b), _vec(facet.c)], "body_triangle": [_vec(fixed.a), _vec(fixed.b), _vec(fixed.c)]})
				if conflicts.size() >= 3:
					return conflicts
	return conflicts

func _apply_door_amount(amount: float) -> void:
	# Exercise the production motion, including its translation/rotation phases.
	bay.door_amount = amount
	bay.tick(0.0)

func _probe_forward_offset(offset: float, closed_transform: Transform3D, fixed_facets: Array, grid: Dictionary, max_angle: float = OPEN_DEGREES) -> Dictionary:
	# Diagnostic only: translate the whole hatch forward, then rotate. Does not assert game behavior.
	var displacement: Vector3 = (hatch.get_parent() as Node3D).global_transform.basis.inverse() * bay.global_transform.basis * Vector3(0, 0, -offset)
	var conflicts: Array = []
	var minimum_z := INF
	for step_index in range(11):
		hatch.transform = closed_transform
		hatch.rotation.x = 0.0
		hatch.position += displacement * (float(step_index) / 10.0)
		var crossing := _head_conflicts(_facets(true), fixed_facets, grid)
		if not crossing.is_empty():
			conflicts.append({"phase": "translate", "fraction": float(step_index) / 10.0, "first_conflict": crossing[0]})
	for angle in range(0, int(max_angle) + 1, 5):
		hatch.transform = closed_transform
		hatch.position += displacement
		hatch.rotation.x = deg_to_rad(float(angle))
		var moving := _facets(true)
		for facet: Facet in moving:
			minimum_z = minf(minimum_z, facet.lo.z)
		var crossing := _head_conflicts(moving, fixed_facets, grid)
		if not crossing.is_empty():
			conflicts.append({"phase": "rotate", "angle_degrees": angle, "first_conflict": crossing[0]})
	var seat_eye: Vector3 = bay.to_local(bay.seat_position()) + Vector3.UP * 1.16
	var entry_eye: Vector3 = bay.to_local(bay.exit_position()) + Vector3.UP * 1.65
	var all_open := _facets()
	var nearby := _near_facets(all_open, seat_eye.min(entry_eye) - Vector3.ONE * 0.12, seat_eye.max(entry_eye) + Vector3.ONE * 0.12)
	var steps := maxi(2, ceili(entry_eye.distance_to(seat_eye) / STEP))
	var camera_hits: Array = []
	for index in range(steps + 1):
		var sample := entry_eye.lerp(seat_eye, float(index) / steps)
		var hits := _sphere_hits(sample, CAMERA_RADIUS, nearby)
		if not hits.is_empty():
			camera_hits.append({"sample": _vec(sample), "hits": hits})
			break
	var camera_crossings := _ray_hits(entry_eye, seat_eye, nearby)
	hatch.transform = closed_transform
	return {"diagnostic_only": true, "forward_translation_m": offset, "open_degrees": max_angle, "conflicting_samples": conflicts, "head_neck_sampled_crossings_absent": conflicts.is_empty(), "sweep_min_z_5_degree_sampling": minimum_z, "wait_line_forward_margin_m": minimum_z - 0.01 - (wait_z + 0.28), "open_camera_path_clear": camera_hits.is_empty() and camera_crossings.is_empty(), "camera_hits": camera_hits, "camera_crossings": camera_crossings}

func run() -> void:
	if DisplayServer.get_name() != "headless":
		_check(false, "Must run with --headless; no interactive test was started")
		await _finish()
		return
	var cache_current := _asset_evidence()
	_check(cache_current, "Imported scene cache matches current GLB source hash")
	if not cache_current:
		await _finish()
		return
	game = load("res://main.tscn").instantiate()
	game.automated_test = true
	root.add_child(game)
	game.audio.set_muted(true)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	await process_frame
	bay = game.bays[0]
	model = game.world.get_node_or_null("rx78") as Node3D
	_check(model != null, "Imported RX78 model exists")
	if model == null:
		await _finish()
		return
	hatch = model.find_child("CockpitHatch", true, false) as Node3D
	_check(hatch != null, "Authentic CockpitHatch node exists")
	_check(absf(bay.top_y - 12.65) < 0.01 and absf(bay.portal_z + 2.5) < 0.01, "Compact RX78 cockpit interface is active", {"top_y": bay.top_y, "portal_z": bay.portal_z})
	if hatch == null or absf(bay.top_y - 12.65) >= 0.01:
		await _finish()
		return
	for item in model.find_children("*", "MeshInstance3D", true, false):
		mesh_count += 1
		if (item as MeshInstance3D).skin != null:
			skinned_count += 1
	_check(skinned_count == 0, "Imported geometry is static so mesh arrays match displayed positions", skinned_count)
	wait_z = float(bay.cockpit.get("wait_z", WAIT_Z))
	bay.state.at_top = true
	bay.state.y = bay.top_y
	bay.state.moving = false
	bay.state.hatch_open = true
	bay.state.seated = false
	var initial_hatch := hatch.transform
	_apply_door_amount(0.0)
	var closed_facets := _facets()
	var fixed_facets := _facets(false, true)
	var head_facets := _near_facets(fixed_facets, Vector3(-1.6, 15.58, -4.4), Vector3(1.6, 19.0, 2.0))
	var head_grid := _make_grid(head_facets)
	report.measurements.mesh_count = mesh_count
	report.measurements.triangle_count = closed_facets.size()
	report.measurements.head_neck_candidate_triangles = head_facets.size()
	_check(closed_facets.size() > 30000, "Test uses detailed imported mesh, not procedural substitute", closed_facets.size())

	var seat: Vector3 = bay.to_local(bay.seat_position())
	var exit_at: Vector3 = bay.to_local(bay.exit_position())
	var seated_eye := seat + Vector3.UP * 1.16
	var standing_eye := exit_at + Vector3.UP * 1.65
	report.measurements.seat_position = _vec(seat)
	report.measurements.exit_position = _vec(exit_at)
	report.measurements.seated_eye = _vec(seated_eye)
	report.measurements.standing_eye = _vec(standing_eye)
	var guard := bay.door_collision as CollisionShape3D
	var guard_shape := guard.shape as BoxShape3D
	var guard_lo := Vector3(INF, INF, INF)
	var guard_hi := -guard_lo
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var corner: Vector3 = bay.to_local(guard.to_global(Vector3(x, y, z) * guard_shape.size))
				guard_lo = guard_lo.min(corner)
				guard_hi = guard_hi.max(corner)
	var guard_margin := guard_lo.z - (exit_at.z + 0.28)
	report.measurements.actual_guard_bounds = {"min": _vec(guard_lo), "max": _vec(guard_hi)}
	report.measurements.exit_capsule_to_guard_margin_m = guard_margin
	_check(guard_margin >= 0.025, "Waiting/exit capsule is outside the actual safety barrier with 2.5 cm margin", guard_margin)
	var seat_hits := _sphere_hits(seated_eye, CAMERA_RADIUS, closed_facets)
	_check(seat_hits.is_empty(), "Closed hatch leaves seated camera sphere free of exterior", seat_hits)
	bay.set_access(false, true)
	var screen_hits: Array = []
	for screen: MeshInstance3D in bay.screens:
		var size := (screen.mesh as QuadMesh).size
		for offset in [Vector2.ZERO, Vector2(-0.35, -0.35), Vector2(-0.35, 0.35), Vector2(0.35, -0.35), Vector2(0.35, 0.35)]:
			var target: Vector3 = bay.to_local(screen.to_global(Vector3(offset.x * size.x, offset.y * size.y, 0.0)))
			var hits := _ray_hits(seated_eye, target, closed_facets)
			if not hits.is_empty():
				screen_hits.append({"target": _vec(target), "hits": hits})
	_check(screen_hits.is_empty(), "Closed hatch does not occlude screen centers or inner corners", screen_hits)
	var look_hits: Array = []
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var hits := _ray_hits(seated_eye, seated_eye + direction * 0.16, closed_facets)
		if not hits.is_empty():
			look_hits.append({"direction": _vec(direction), "hits": hits})
	_check(look_hits.is_empty(), "Closed hatch has no exterior surface within 16 cm along six local eye axes", look_hits)

	_apply_door_amount(1.0)
	report.measurements.hatch_open_rotation_degrees = rad_to_deg(hatch.rotation.x)
	report.measurements.hatch_closed_local_position = _vec(initial_hatch.origin)
	report.measurements.hatch_open_local_position = _vec(hatch.position)
	var open_facets := _facets()
	var nearby := _near_facets(open_facets, standing_eye.min(seated_eye) - Vector3.ONE * 0.12, standing_eye.max(seated_eye) + Vector3.ONE * 0.12)
	var samples := maxi(2, ceili(standing_eye.distance_to(seated_eye) / STEP))
	var path_hits: Array = []
	for index in range(samples + 1):
		var point := standing_eye.lerp(seated_eye, float(index) / samples)
		var hits := _sphere_hits(point, CAMERA_RADIUS, nearby)
		if not hits.is_empty():
			path_hits.append({"sample": index, "hits": hits})
			if path_hits.size() >= 12:
				break
	var crossings := _ray_hits(standing_eye, seated_eye, nearby)
	_check(path_hits.is_empty() and crossings.is_empty(), "Open-hatch bridge-to-seat camera path clears imported exterior", {"samples": samples + 1, "sphere_radius_m": CAMERA_RADIUS, "sample_hits": path_hits, "exact_centerline_crossings": crossings})

	var head_hits: Array = []
	var minimum_z := INF
	var sweep_amount := 0.0
	for step_index in range(181):
		var amount := float(step_index) / 180.0
		_apply_door_amount(amount)
		var moving := _facets(true)
		for facet: Facet in moving:
			if facet.lo.z < minimum_z:
				minimum_z = facet.lo.z
				sweep_amount = amount
		if step_index % 5 == 0:
			var conflicts := _head_conflicts(moving, head_facets, head_grid)
			if step_index == 0:
				report.measurements.closed_pose_head_neck_contacts = conflicts
			elif not conflicts.is_empty():
				head_hits.append({"door_amount": amount, "angle_degrees": rad_to_deg(hatch.rotation.x), "conflicts": conflicts})
		if step_index % 20 == 0:
			await process_frame
	var wait_margin := (minimum_z - 0.01) - (wait_z + 0.28)
	report.measurements.hatch_minimum_z = minimum_z
	report.measurements.hatch_furthest_door_amount = sweep_amount
	report.measurements.hatch_motion_source = "production bay.tick(0), 181 door_amount samples from closed to fully open"
	report.measurements.wait_point_z = wait_z
	report.measurements.wait_capsule_radius_m = 0.28
	report.measurements.wait_line_forward_margin_m = wait_margin
	_check(wait_margin > 0.10, "Waiting line lies behind hatch sweep with body radius and margin", {"margin_m": wait_margin, "wait_z": wait_z, "sweep_min_z": minimum_z})
	_check(head_hits.is_empty(), "No sampled hatch/head-neck triangle crossings", head_hits)
	if not head_hits.is_empty():
		report["diagnostic_hatch_motion_probes"] = [_probe_forward_offset(0.35, initial_hatch, head_facets, head_grid), _probe_forward_offset(0.55, initial_hatch, head_facets, head_grid), _probe_forward_offset(0.35, initial_hatch, head_facets, head_grid, 65.0), _probe_forward_offset(0.55, initial_hatch, head_facets, head_grid, 90.0)]
	hatch.transform = initial_hatch
	await _finish()
