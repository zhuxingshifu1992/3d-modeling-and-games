extends SceneTree
## CPU-only geometry checks against the selected imported model, not proxy colliders.
## Camera spheres are sampled every <= 4 cm; this is not a full animated body/capsule proof.
## Usage: --headless --script res://tests/test_refined_clearance.gd -- --machine=rx78
## Region overrides: --head-min-y=, --head-max-y=, --head-half-width=, --head-min-z=, --head-max-z=.

const CAMERA_RADIUS := 0.08
const STEP := 0.04
const GRID := 0.50
const BODY_HEIGHT := 1.75
const BODY_RADIUS := 0.28
const RX78_HEAD_REGION := {"min_y": 15.58, "max_y": 19.0, "half_width": 1.6, "min_z": -4.4, "max_z": 2.0}

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
		"Only exterior mesh intrusion is tested; cockpit furniture/body animation and visual finish require separate checks.",
		"The fixture loads the selected production GLB and Bay.gd directly; it does not read or write pilot profiles or verify the main game integration."
	]
}
var fixture: Node3D
var bay
var model: Node3D
var hatch: Node3D
var mesh_count := 0
var skinned_count := 0
var machine_id := "rx78"
var machine_info: Dictionary = {}
var output := "res://previews/refined_rx78/clearance_generic_result.json"
var wait_z := 0.0
var head_region: Dictionary = {}
var head_lo := Vector3.ZERO
var head_hi := Vector3.ZERO
var cli_region: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func _check(ok: bool, name: String, detail: Variant = null) -> void:
	report.checks.append({"name": name, "passed": ok, "detail": detail})
	if not ok:
		report.failures.append(name)
		push_error("REFINED_CLEARANCE_FAIL " + machine_id + " " + name)

func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.00001), snappedf(value.y, 0.00001), snappedf(value.z, 0.00001)]

func _select_machine() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--machine="):
			machine_id = argument.trim_prefix("--machine=")
		for key in ["min_y", "max_y", "half_width", "min_z", "max_z"]:
			var prefix: String = "--head-" + str(key).replace("_", "-") + "="
			if argument.begins_with(prefix):
				var value: String = argument.trim_prefix(prefix)
				_check(value.is_valid_float(), "Head region CLI value is numeric: " + key, value)
				if value.is_valid_float():
					cli_region[key] = float(value)
	var supported := machine_id in ["rx78", "nu", "exia", "freedom", "unicorn", "wing"]
	output = "res://previews/refined_" + (machine_id if supported else "invalid") + "/clearance_generic_result.json"
	report["machine_id"] = machine_id
	_check(supported, "Machine selector is supported", machine_id)
	if not supported:
		return false
	var catalog: Array = load("res://scripts/catalog.gd").machines()
	for entry: Dictionary in catalog:
		if str(entry.get("id", "")) == machine_id:
			machine_info = entry
	_check(not machine_info.is_empty(), "Machine exists in production catalog", machine_id)
	if machine_info.is_empty():
		return false
	_check(bool(machine_info.get("refined", false)), "Catalog selects refined geometry", machine_info.get("model_path", ""))
	_check(not (machine_info.get("cockpit", {}) as Dictionary).is_empty(), "Catalog includes cockpit profile")
	return report.failures.is_empty()

func _configure_region() -> bool:
	# These catalog heights do not provide a measured head-crown landmark.
	# Require an explicit geometric region instead of deriving it from that height.
	var requires_measured_region := machine_id in ["exia", "freedom", "unicorn", "wing"]
	if requires_measured_region:
		for key in ["min_y", "max_y", "half_width", "min_z", "max_z"]:
			_check(bay.cockpit.has("head_clearance_" + key) or cli_region.has(key), machine_id + " head/neck region has explicit measured parameters: " + key)
		if not report.failures.is_empty():
			return false
	var head_height := float(machine_info.get("head_height", machine_info.height))
	var defaults := {"min_y": head_height * 0.86, "max_y": head_height + 1.0,
		"half_width": head_height * 0.09, "min_z": -head_height * 0.25, "max_z": head_height * 0.12}
	if machine_id == "rx78":
		defaults = RX78_HEAD_REGION.duplicate()
	var parameter_sources := {}
	for key in defaults:
		var profile_key: String = "head_clearance_" + str(key)
		head_region[key] = float(bay.cockpit.get(profile_key, defaults[key]))
		parameter_sources[key] = "cockpit." + profile_key if bay.cockpit.has(profile_key) else ("RX78 regression region" if machine_id == "rx78" else "head_height default")
		if cli_region.has(key):
			head_region[key] = cli_region[key]
			parameter_sources[key] = "CLI override"
	_check(float(head_region.half_width) > 0.0 and float(head_region.min_y) < float(head_region.max_y) and float(head_region.min_z) < float(head_region.max_z), "Head/neck region has positive dimensions", head_region)
	head_lo = Vector3(-float(head_region.half_width), float(head_region.min_y), float(head_region.min_z))
	head_hi = Vector3(float(head_region.half_width), float(head_region.max_y), float(head_region.max_z))
	report["head_neck_test_region"] = {"coordinate_space": "bay local meters", "min": _vec(head_lo), "max": _vec(head_hi),
		"catalog_height_m": float(machine_info.height), "catalog_height_note": str(machine_info.get("height_note", "")),
		"parameters": head_region.duplicate(), "parameter_sources": parameter_sources,
		"candidate_rule": "Fixed triangle AABB overlaps this box; accepted intersection points must lie inside the same box.",
		"scope": "A geometric candidate region, not a semantic or exhaustive identification of all head and neck surfaces."}
	if not requires_measured_region or machine_info.has("head_height"):
		report.head_neck_test_region["head_height_reference_m"] = head_height
	report["cockpit_profile"] = bay.cockpit.duplicate(true)
	return report.failures.is_empty()

func _asset_evidence() -> bool:
	var source_path: String = str(machine_info.get("model_path", ""))
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		push_error("Could not write " + output)
		quit(2)
		return
	print("REFINED_CLEARANCE ", machine_id, " ", report.status, " failures=", report.failures.size(), " output=", output)
	if is_instance_valid(fixture):
		fixture.queue_free()
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

func _transfer_eye(from_foot: Vector3, to_foot: Vector3, fraction: float, entering: bool) -> Vector3:
	# game.gd uses SINE/IN_OUT for position on both transfers. Entry eye height
	# uses SINE/IN_OUT too; exit eye height uses the Tween default LINEAR.
	var movement := 0.5 - 0.5 * cos(PI * fraction)
	var eye_fraction := movement if entering else fraction
	var eye_height := lerpf(1.65 if entering else 1.16, 1.16 if entering else 1.65, eye_fraction)
	return from_foot.lerp(to_foot, movement) + Vector3.UP * eye_height

func _check_narrow_entry(open_facets: Array, seat: Vector3, exit_at: Vector3) -> void:
	if not bay.cockpit.has("entry_half_width"):
		return
	var half_width := float(bay.cockpit.entry_half_width)
	var min_z := float(bay.cockpit.get("clearance_entry_min_z", bay.portal_z))
	var max_z := float(bay.cockpit.get("clearance_entry_max_z", bay.cockpit.get("interior_front_z", bay.portal_z + 0.4)))
	var valid := half_width > 0.0 and min_z < max_z
	_check(valid, "Narrow entry test width and shell region have positive dimensions", {"entry_half_width_m": half_width, "min_z": min_z, "max_z": max_z})
	if not valid:
		return
	report.limitations.append("Narrow-entry checks use three permitted lateral offsets, not every possible boarding origin. Exit center follows production; lateral exits are additional hypothetical clearance probes.")
	report.limitations.append("The 1.75 m / 0.28 m upright-body check samples capsule-axis spheres only in the configured entrance region. It does not test a seated body, articulated body motion, or cockpit furniture.")
	var routes: Array = []
	for offset in [-half_width, 0.0, half_width]:
		var standing_foot := exit_at + Vector3.RIGHT * float(offset)
		_check(bay.near_hatch(bay.to_global(standing_foot)), "Configured narrow entry boundary admits standing origin x=" + str(offset), _vec(standing_foot))
		for entering in [true, false]:
			var from_foot := standing_foot if entering else seat
			var to_foot := seat if entering else standing_foot
			# The SINE derivative is at most PI/2; this bounds distance between samples.
			var samples := maxi(2, ceili((from_foot.distance_to(to_foot) + 0.49) * PI * 0.5 / STEP))
			var lower := from_foot.min(to_foot) + Vector3.UP * 1.16 - Vector3.ONE * CAMERA_RADIUS
			var upper := from_foot.max(to_foot) + Vector3.UP * 1.65 + Vector3.ONE * CAMERA_RADIUS
			var nearby := _near_facets(open_facets, lower, upper)
			var sphere_hits: Array = []
			var segment_hits: Array = []
			var previous := _transfer_eye(from_foot, to_foot, 0.0, entering)
			var maximum_spacing := 0.0
			for index in range(samples + 1):
				var point := _transfer_eye(from_foot, to_foot, float(index) / samples, entering)
				if sphere_hits.size() < 12:
					var hits := _sphere_hits(point, CAMERA_RADIUS, nearby)
					if not hits.is_empty():
						sphere_hits.append({"sample": index, "hits": hits})
				if index > 0:
					maximum_spacing = maxf(maximum_spacing, previous.distance_to(point))
					if segment_hits.size() < 12:
						var crossings := _ray_hits(previous, point, nearby)
						if not crossings.is_empty():
							segment_hits.append({"segment_end_sample": index, "hits": crossings})
				previous = point
			var route := {"direction": "enter" if entering else "exit", "standing_offset_x_m": offset,
				"production_route": entering or is_zero_approx(float(offset)), "samples": samples + 1,
				"start_eye": _vec(_transfer_eye(from_foot, to_foot, 0.0, entering)),
				"end_eye": _vec(_transfer_eye(from_foot, to_foot, 1.0, entering)),
				"maximum_sample_spacing_m": maximum_spacing, "sample_hits": sphere_hits, "sample_segment_crossings": segment_hits}
			routes.append(route)
			_check(sphere_hits.is_empty() and segment_hits.is_empty() and maximum_spacing <= STEP + 0.00001,
				"Narrow entry " + str(route.direction) + " camera path clears exterior at x=" + str(offset), route)
	report["narrow_entry_camera_paths"] = {"coordinate_space": "bay local meters", "sphere_radius_m": CAMERA_RADIUS,
		"motion": "Production 2 s SINE/IN_OUT foot movement; SINE/IN_OUT eye height on entry and LINEAR eye height on exit.",
		"scope": "Production waiting/exit origin and seat endpoints at center and allowed lateral boundary origins. Curved routes use exact triangle crossings per sampled chord.", "routes": routes}
	# A capsule is the union of spheres along the vertical axis. Sampling that
	# axis avoids treating the capsule's rounded ends as a full-height cylinder.
	var body_low := Vector3(-half_width - BODY_RADIUS, exit_at.y, min_z - BODY_RADIUS)
	var body_high := Vector3(half_width + BODY_RADIUS, exit_at.y + BODY_HEIGHT, max_z + BODY_RADIUS)
	var body_facets := _near_facets(open_facets, body_low, body_high)
	var depth_steps := maxi(1, ceili((max_z - min_z) / STEP))
	var axis_steps := maxi(1, ceili((BODY_HEIGHT - 2.0 * BODY_RADIUS) / STEP))
	var body_hits: Array = []
	var tested_spheres := 0
	for offset in [-half_width, 0.0, half_width]:
		for depth_index in range(depth_steps + 1):
			var foot := Vector3(float(offset), exit_at.y, lerpf(min_z, max_z, float(depth_index) / depth_steps))
			for axis_index in range(axis_steps + 1):
				var point := foot + Vector3.UP * lerpf(BODY_RADIUS, BODY_HEIGHT - BODY_RADIUS, float(axis_index) / axis_steps)
				tested_spheres += 1
				var hits := _sphere_hits(point, BODY_RADIUS, body_facets)
				if not hits.is_empty() and body_hits.size() < 12:
					body_hits.append({"standing_foot": _vec(foot), "axis_sample": axis_index, "hits": hits})
	var body_region := {"coordinate_space": "bay local meters", "min_z": min_z, "max_z": max_z,
		"source": "cockpit.clearance_entry_min_z/max_z when supplied; otherwise portal_z to interior_front_z",
		"height_m": BODY_HEIGHT, "radius_m": BODY_RADIUS, "foot_y": exit_at.y,
		"lateral_offsets_m": [-half_width, 0.0, half_width], "maximum_axis_and_depth_spacing_m": STEP,
		"tested_spheres": tested_spheres, "candidate_triangles": body_facets.size(), "sample_hits": body_hits,
		"scope": "Upright capsule samples held at the three lateral offsets within the entrance shell only, with hatch fully open. No seated-body or furniture claim."}
	report["narrow_entry_body_region"] = body_region
	_check(body_hits.is_empty(), "Narrow entry upright body samples clear imported exterior", body_region)

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

func _triangle_crossings_in_box(a: Facet, b: Facet, region_lo: Vector3, region_hi: Vector3) -> Array:
	if not _boxes_overlap(a.lo, a.hi, b.lo, b.hi):
		return []
	var crossings: Array = []
	for edge in [[a.a, a.b, b], [a.b, a.c, b], [a.c, a.a, b], [b.a, b.b, a], [b.b, b.c, a], [b.c, b.a, a]]:
		var distance := _segment_hit(edge[0], edge[1], edge[2], true)
		if distance >= 0.0:
			var point: Vector3 = (edge[0] as Vector3).move_toward(edge[1], distance)
			# A long chest triangle's AABB may enter this region while its actual crossing does not.
			if point.x >= region_lo.x and point.x <= region_hi.x and point.y >= region_lo.y and point.y <= region_hi.y and point.z >= region_lo.z and point.z <= region_hi.z:
				crossings.append(_vec(point))
	return crossings

func _triangle_crossings(a: Facet, b: Facet) -> Array:
	return _triangle_crossings_in_box(a, b, head_lo, head_hi)

func _shell_contacts(moving: Array, fixed: Array, grid: Dictionary, region_lo: Vector3, region_hi: Vector3, baseline: Dictionary) -> Dictionary:
	# Triangle indices are stable across _facets(true) calls: only transforms change.
	# Keep every pair in the baseline, while bounding the verbose evidence.
	var pairs := {}
	var new_contacts: Array = []
	var baseline_contacts: Array = []
	var new_count := 0
	for moving_index in range(moving.size()):
		var facet: Facet = moving[moving_index]
		var lo := _cell(facet.lo)
		var hi := _cell(facet.hi)
		var candidates := {}
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					for index in grid.get(Vector3i(x, y, z), []):
						candidates[index] = true
		for index in candidates:
			var body: Facet = fixed[index]
			var crossings := _triangle_crossings_in_box(facet, body, region_lo, region_hi)
			if crossings.is_empty():
				continue
			var key := str(moving_index) + ":" + str(index)
			pairs[key] = true
			var contact := {"hatch_triangle_index": moving_index, "body_triangle_index": index,
				"hatch_mesh": facet.source, "body_mesh": body.source, "crossing_points": crossings}
			if baseline.has(key):
				if baseline_contacts.size() < 3:
					baseline_contacts.append(contact)
			else:
				new_count += 1
				if new_contacts.size() < 3:
					new_contacts.append(contact)
	return {"pairs": pairs, "total_pairs": pairs.size(), "new_pair_count": new_count,
		"new_contact_examples": new_contacts, "baseline_contact_examples": baseline_contacts}

func _configure_shell_diagnostic(closed_hatch: Array, fixed: Array) -> Dictionary:
	if not bay.cockpit.has("entry_half_width"):
		return {}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for facet: Facet in closed_hatch:
		lo = lo.min(facet.lo)
		hi = hi.max(facet.hi)
	var half_width := maxf(absf(lo.x), absf(hi.x)) + 0.4
	var region_lo := Vector3(-half_width, float(bay.cockpit.floor_y), lo.z - 0.10)
	var region_hi := Vector3(half_width, maxf(head_lo.y, hi.y + 0.10), hi.z + 0.40)
	var nearby := _near_facets(fixed, region_lo, region_hi)
	var grid := _make_grid(nearby)
	var baseline := _shell_contacts(closed_hatch, nearby, grid, region_lo, region_hi, {})
	report["chest_collar_sweep_diagnostic"] = {"diagnostic_only": true, "coordinate_space": "bay local meters",
		"region_min": _vec(region_lo), "region_max": _vec(region_hi), "fixed_candidate_triangles": nearby.size(),
		"region_rule": "Closed hatch lateral bounds plus 0.4 m; cockpit floor to head-region lower edge or hatch top plus 0.1 m; closed hatch depth minus 0.1 m / plus 0.4 m.",
		"closed_pose_crossing_pairs": baseline.total_pairs, "closed_pose_examples": baseline.new_contact_examples,
		"samples": [], "scope": "Non-coplanar triangle crossings every fifth of 181 production door samples. Closed assembly crossing pairs are tracked separately from newly encountered pairs.",
		"interpretation": "Diagnostic only: new pairs may include adjacent faces of the same authored assembly; baseline pairs may deepen during motion. No automatic chest/collar collision-free assertion is made."}
	report.limitations.append("Chest/collar sweep results are diagnostic: closed assembly triangle contacts are not automatic failures, and excluding baseline pairs does not prove those contacts never deepen.")
	return {"facets": nearby, "grid": grid, "lo": region_lo, "hi": region_hi, "baseline": baseline.pairs}

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

func _probe_forward_offset(offset: float, closed_transform: Transform3D, fixed_facets: Array, grid: Dictionary, max_angle: float) -> Dictionary:
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
	var selection_valid := _select_machine()
	if DisplayServer.get_name() != "headless":
		_check(false, "Must run with --headless; no interactive test was started")
		await _finish()
		return
	if not selection_valid:
		await _finish()
		return
	var cache_current := _asset_evidence()
	_check(cache_current, "Imported scene cache matches current GLB source hash")
	if not cache_current:
		await _finish()
		return
	# Only production model and bay are needed. Avoid main._ready(), which reads the pilot profile.
	fixture = Node3D.new()
	fixture.name = "RefinedClearanceFixture"
	root.add_child(fixture)
	var packed := load(str(machine_info.model_path)) as PackedScene
	model = packed.instantiate() as Node3D if packed != null else null
	_check(model != null, "Selected imported model exists", machine_info.model_path)
	if model == null:
		await _finish()
		return
	model.name = machine_id
	model.position = machine_info.position
	model.rotation.y = float(machine_info.yaw)
	fixture.add_child(model)
	bay = load("res://scripts/bay.gd").new()
	fixture.add_child(bay)
	bay.setup(machine_info)
	bay.bind_machine(model)
	await process_frame
	hatch = model.find_child("CockpitHatch", true, false) as Node3D
	_check(hatch != null, "Authentic CockpitHatch node exists")
	_check(bay.compact and absf(bay.top_y - float(bay.cockpit.floor_y)) < 0.01 and absf(bay.portal_z - float(bay.cockpit.portal_z)) < 0.01, "Production compact cockpit profile is active", {"top_y": bay.top_y, "portal_z": bay.portal_z})
	if hatch == null or not bay.compact:
		await _finish()
		return
	if not _configure_region():
		await _finish()
		return
	for item in model.find_children("*", "MeshInstance3D", true, false):
		mesh_count += 1
		if (item as MeshInstance3D).skin != null:
			skinned_count += 1
	_check(skinned_count == 0, "Imported geometry is static so mesh arrays match displayed positions", skinned_count)
	if skinned_count > 0:
		await _finish()
		return
	wait_z = float(bay.cockpit.get("wait_z", bay.portal_z - 0.8))
	bay.state.at_top = true
	bay.state.y = bay.top_y
	bay.state.moving = false
	bay.state.hatch_open = true
	bay.state.seated = false
	var initial_hatch := hatch.transform
	_apply_door_amount(0.0)
	var closed_facets := _facets()
	var closed_hatch_facets := _facets(true)
	var fixed_facets := _facets(false, true)
	var head_facets := _near_facets(fixed_facets, head_lo, head_hi)
	var head_grid := _make_grid(head_facets)
	report.measurements.mesh_count = mesh_count
	report.measurements.triangle_count = closed_facets.size()
	report.measurements.hatch_triangle_count = closed_hatch_facets.size()
	report.measurements.head_neck_candidate_triangles = head_facets.size()
	# The selected EW source is a textured game mesh with fewer polygons than
	# the other assets. Its source hash and semantic parts are checked separately
	# by test_wing_asset; a 30k gate would reject its genuine source geometry.
	var minimum_triangles := 6000 if machine_id == "wing" else 30000
	_check(closed_facets.size() > minimum_triangles, "Test uses imported mesh geometry within the selected source tier", {"triangles": closed_facets.size(), "minimum": minimum_triangles})
	_check(not closed_hatch_facets.is_empty(), "Hatch has actual moving mesh triangles", closed_hatch_facets.size())
	_check(not head_facets.is_empty(), "Head/neck region contains actual fixed mesh candidates", head_facets.size())
	if closed_hatch_facets.is_empty() or head_facets.is_empty():
		await _finish()
		return

	var seat: Vector3 = bay.to_local(bay.seat_position())
	var exit_at: Vector3 = bay.to_local(bay.exit_position())
	var seated_eye := seat + Vector3.UP * 1.16
	var standing_eye := exit_at + Vector3.UP * 1.65
	report.measurements.seat_position = _vec(seat)
	report.measurements.exit_position = _vec(exit_at)
	report.measurements.seated_eye = _vec(seated_eye)
	report.measurements.standing_eye = _vec(standing_eye)
	report["camera_path_test_region"] = {"coordinate_space": "bay local meters", "start_eye": _vec(standing_eye),
		"end_eye": _vec(seated_eye), "sphere_radius_m": CAMERA_RADIUS, "maximum_sample_spacing_m": STEP,
		"standing_eye_height_m": 1.65, "seated_eye_height_m": 1.16,
		"route": "Linear bridge waiting point to production seat_position; same geometric line checked for return."}
	var guard := bay.door_collision as CollisionShape3D
	_check(guard != null and guard.shape is BoxShape3D, "Production safety barrier has a box collision shape")
	if guard == null or not guard.shape is BoxShape3D:
		await _finish()
		return
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
	_check(not bay.screens.is_empty(), "Production cockpit contains display screens", bay.screens.size())
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
	_check_narrow_entry(open_facets, seat, exit_at)

	var head_hits: Array = []
	var shell_diagnostic := _configure_shell_diagnostic(closed_hatch_facets, fixed_facets)
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
			if not shell_diagnostic.is_empty():
				var shell := _shell_contacts(moving, shell_diagnostic.facets, shell_diagnostic.grid,
					shell_diagnostic.lo, shell_diagnostic.hi, shell_diagnostic.baseline)
				shell.erase("pairs")
				shell["door_amount"] = amount
				report.chest_collar_sweep_diagnostic.samples.append(shell)
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
		var travel := float(bay.cockpit.get("hatch_travel", 0.55))
		var angle := float(bay.cockpit.get("hatch_angle", 90.0))
		report["diagnostic_hatch_motion_probes"] = [_probe_forward_offset(travel, initial_hatch, head_facets, head_grid, angle),
			_probe_forward_offset(travel + 0.20, initial_hatch, head_facets, head_grid, angle),
			_probe_forward_offset(travel, initial_hatch, head_facets, head_grid, angle * 0.75),
			_probe_forward_offset(travel + 0.20, initial_hatch, head_facets, head_grid, angle * 0.75)]
	hatch.transform = initial_hatch
	await _finish()
