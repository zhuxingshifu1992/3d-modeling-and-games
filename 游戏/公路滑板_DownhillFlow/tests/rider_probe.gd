extends SceneTree
## CPU-only GLB regression probe. Posed bounds use weighted skeleton global
## pose * Skin inverse bind * vertex, never the undeformed rest vertices.

const POSE_NAMES := ["Ride", "Tuck", "Brake", "Push"]
const EXPECTED_MESHES := {
	"AnatomicalSkin": ["Skin", "Face"],
	"CapPonytailAndSocks": ["CapCotton", "RedStitch", "DarkChestnut", "HairFineStrands", "SockCotton"],
	"CroppedCottonTee": ["CottonTee"],
	"PhotographicCanvasSneakers": ["CanvasSneakers"],
	"TailoredGreenShorts": ["GreenDenim"],
}
const LIMBS := [
	["L Thigh", "L Calf", 0.30, 0.55], ["R Thigh", "R Calf", 0.30, 0.55],
	["L Calf", "L Foot", 0.30, 0.55], ["R Calf", "R Foot", 0.30, 0.55],
	["L UpperArm", "L Forearm", 0.20, 0.40], ["R UpperArm", "R Forearm", 0.20, 0.40],
	["L Forearm", "L Hand", 0.17, 0.36], ["R Forearm", "R Hand", 0.17, 0.36],
]

var failures: Array[String] = []
var rider: Node3D
var human: Node3D
var board: Node3D
var skeleton: Skeleton3D
var records: Array[Dictionary] = []
var segments: Array[Dictionary] = []
var limb_ranges: Dictionary = {}
var bounds_samples := 0
var max_rest_error := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rider_script: Script = load("res://scripts/rider.gd") as Script
	if rider_script == null or not rider_script.can_instantiate():
		_check(false, "rider.gd must load and instantiate")
		_finish()
		return
	rider = rider_script.new() as Node3D
	root.add_child(rider)
	rider.call("build")
	human = rider.find_child("AnatomicalRider", true, false) as Node3D
	board = rider.find_child("Longboard", true, false) as Node3D
	var skeletons := rider.find_children("*", "Skeleton3D", true, false)
	_check(human != null and board != null, "anatomical GLB and longboard are instantiated")
	_check(skeletons.size() == 1, "one skeleton; no hidden donor rigs")
	if human == null or board == null or skeletons.size() != 1:
		_finish()
		return
	skeleton = skeletons[0] as Skeleton3D
	_check(skeleton.get_bone_count() == 80, "Rocketbox rig retains all 80 bones")
	var before := rider.find_children("*", "MeshInstance3D", true, false).size()
	rider.call("build")
	_check(before == rider.find_children("*", "MeshInstance3D", true, false).size(), "build is idempotent")
	_check(rider.find_children("WheelSpin*", "Node3D", true, false).size() == 4, "four skateboard wheel pivots")
	_validate_poses()
	_collect_meshes()
	_prepare_limbs()
	if not failures.is_empty():
		_finish()
		return
	_validate_rest_coverage()
	var poses: Dictionary = rider.get("_poses")
	for label: String in POSE_NAMES:
		for bone: int in range(skeleton.get_bone_count()):
			skeleton.set_bone_pose(bone, poses[label][bone])
		_check_limbs("pose " + label)
		_validate_bounds("pose " + label, label != "Push")
	var nodes := rider.find_children("*", "Node3D", true, false)
	var scenarios := [Vector4(0, 0, 0, 0), Vector4(12, 0, 0, 0),
		Vector4(23, -1, 1, 0), Vector4(18, 1, 0.5, 0.8), Vector4(3, 0.4, 0, 1)]
	var total_frames := 0
	for scenario: Vector4 in scenarios:
		for frame: int in range(120):
			rider.call("animate", 1.0 / 60.0, scenario.x, scenario.y, scenario.z, scenario.w, float(total_frames) / 60.0)
			for node: Node3D in nodes:
				_check(node.transform.is_finite(), "finite animated node: " + str(node.name))
			for bone: int in range(skeleton.get_bone_count()):
				_check(skeleton.get_bone_pose(bone).is_finite(), "finite local bone pose: " + str(skeleton.get_bone_name(bone)))
				_check(skeleton.get_bone_global_pose(bone).is_finite(), "finite global bone pose: " + str(skeleton.get_bone_name(bone)))
			_check_limbs("runtime")
			var left_planted := scenario.x >= 4.5 or (scenario.w > 0.99 and frame > 90)
			_check_foot_bones(left_planted)
			if frame % 30 == 0 or frame == 119:
				_validate_bounds("runtime frame " + str(total_frames), left_planted)
			total_frames += 1
	print("RIDER_PROBE_STATS ", JSON.stringify({"bones": skeleton.get_bone_count(), "frames": total_frames,
		"mesh_components": before, "deformed_bounds_samples": bounds_samples, "rest_bind_error_m": max_rest_error}))
	print("RIDER_LIMB_RANGES ", JSON.stringify(limb_ranges))
	_finish()


func _validate_poses() -> void:
	var poses: Dictionary = rider.get("_poses")
	for label: String in POSE_NAMES:
		_check(poses.has(label), "animation pose captured: " + label)
		if not poses.has(label):
			continue
		var pose: Array = poses[label]
		_check(pose.size() == skeleton.get_bone_count(), "complete bone pose: " + label)
		for transform: Transform3D in pose:
			_check(transform.is_finite(), "finite captured pose: " + label)
	if not failures.is_empty():
		return
	for a: int in range(POSE_NAMES.size()):
		for b: int in range(a + 1, POSE_NAMES.size()):
			var difference := 0.0
			for index: int in range(skeleton.get_bone_count()):
				var left: Transform3D = poses[POSE_NAMES[a]][index]
				var right: Transform3D = poses[POSE_NAMES[b]][index]
				difference += left.origin.distance_to(right.origin)
				difference += left.basis.get_rotation_quaternion().angle_to(right.basis.get_rotation_quaternion())
			_check(difference > 0.03, "distinct poses: " + POSE_NAMES[a] + " / " + POSE_NAMES[b])


func _collect_meshes() -> void:
	var meshes := human.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() == EXPECTED_MESHES.size(), "five semantic character meshes; no hidden donor bodies")
	var material_counts: Dictionary = {}
	for expected: String in EXPECTED_MESHES:
		_check(human.find_children(expected, "MeshInstance3D", true, false).size() == 1, "one character component: " + expected)
	for node: MeshInstance3D in rider.find_children("*", "MeshInstance3D", true, false):
		_check(node.mesh != null, "mesh resource exists: " + str(node.name))
		if node.mesh == null:
			continue
		var is_human := human.is_ancestor_of(node)
		var skin: Skin = node.skin
		var bone_map := PackedInt32Array()
		var inverse_binds: Array[Transform3D] = []
		if is_human:
			_check(node.visible and node.is_visible_in_tree(), "character component visible: " + str(node.name))
			_check(EXPECTED_MESHES.has(str(node.name)), "no unexpected donor mesh: " + str(node.name))
			_check(skin != null, "character mesh has Skin: " + str(node.name))
			_check(node.get_node_or_null(node.skeleton) == skeleton, "mesh bound to rider skeleton: " + str(node.name))
		if skin != null:
			for bind: int in range(skin.get_bind_count()):
				var name: StringName = skin.get_bind_name(bind)
				var bone := skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)
				_check(bone >= 0 and bone < skeleton.get_bone_count(), "valid skin binding: " + str(node.name))
				bone_map.append(bone)
				inverse_binds.append(skin.get_bind_pose(bind))
		for surface: int in range(node.mesh.get_surface_count()):
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var material := node.get_active_material(surface)
			var label := str(material.resource_name) if material != null else "<missing>"
			_check(vertices.size() > 0, "nonempty surface: " + str(node.name))
			var joints := PackedInt32Array()
			var weights := PackedFloat32Array()
			var stride := 0
			if skin != null:
				if arrays[Mesh.ARRAY_BONES] != null:
					joints = arrays[Mesh.ARRAY_BONES]
				if arrays[Mesh.ARRAY_WEIGHTS] != null:
					weights = arrays[Mesh.ARRAY_WEIGHTS]
				stride = joints.size() / maxi(vertices.size(), 1)
				_check(stride in [4, 8] and joints.size() == weights.size(), "four or eight influences per vertex: " + str(node.name))
				for vertex: int in range(vertices.size()):
					var total := 0.0
					for influence: int in range(stride):
						var slot := vertex * stride + influence
						if slot >= weights.size():
							break
						var weight := weights[slot]
						_check(is_finite(weight) and weight >= 0, "finite nonnegative weights: " + str(node.name))
						if weight > 0.00001:
							_check(joints[slot] >= 0 and joints[slot] < bone_map.size(), "vertex joint indexes Skin bind: " + str(node.name))
						total += weight
					_check(absf(total - 1) < 0.02, "normalized skin weights: " + str(node.name))
			if is_human:
				material_counts[label] = int(material_counts.get(label, 0)) + 1
				if EXPECTED_MESHES.has(str(node.name)):
					_check(label in EXPECTED_MESHES[str(node.name)], "material routing: " + str(node.name) + " / " + label)
				if label in ["Skin", "Face", "CottonTee", "GreenDenim", "CanvasSneakers"]:
					var pbr := material as BaseMaterial3D
					_check(pbr != null and pbr.albedo_texture != null, "character albedo texture: " + label)
			records.append({"node": node, "vertices": vertices, "joints": joints, "weights": weights,
				"stride": stride, "skin": skin, "bone_map": bone_map, "inverse_binds": inverse_binds, "material": label})
	for label: String in ["Skin", "Face", "CottonTee", "GreenDenim", "CanvasSneakers"]:
		_check(int(material_counts.get(label, 0)) == 1, "one body/garment material surface: " + label)
	print("RIDER_MATERIAL_COUNTS ", JSON.stringify(material_counts))


func _prepare_limbs() -> void:
	for spec: Array in LIMBS:
		var start := _bone(spec[0])
		var end := _bone(spec[1])
		_check(start >= 0 and end >= 0, "limb bones exist: " + spec[0] + " / " + spec[1])
		if start < 0 or end < 0:
			continue
		var length := skeleton.get_bone_global_rest(start).origin.distance_to(skeleton.get_bone_global_rest(end).origin)
		_check(length >= spec[2] and length <= spec[3], "human-scale rest limb: " + spec[0] + " = " + str(length))
		segments.append({"start": start, "end": end, "length": length, "label": spec[0]})
		limb_ranges[spec[0]] = {"rest": length, "min": INF, "max": 0.0}
	for name: String in ["Spine", "Spine2", "Head", "L Hand", "R Hand", "L Foot", "R Foot"]:
		_check(_bone(name) >= 0, "body landmark exists: " + name)


func _check_limbs(context: String) -> void:
	for segment: Dictionary in segments:
		var length := skeleton.get_bone_global_pose(segment["start"]).origin.distance_to(skeleton.get_bone_global_pose(segment["end"]).origin)
		limb_ranges[segment["label"]]["min"] = minf(limb_ranges[segment["label"]]["min"], length)
		limb_ranges[segment["label"]]["max"] = maxf(limb_ranges[segment["label"]]["max"], length)
		# 3% + 3 mm permits import/animation precision but detects donor scale,
		# stretched IK targets and materially shortened/elongated limbs.
		_check(absf(length - segment["length"]) <= segment["length"] * 0.03 + 0.003,
			"limb length preserved in " + context + ": " + segment["label"])
		if context.begins_with("pose ") and absf(length - segment["length"]) > segment["length"] * 0.03 + 0.003:
			print("RIDER_LIMB_ERROR ", context, " ", segment["label"], " rest=", segment["length"], " actual=", length)


func _validate_rest_coverage() -> void:
	var counts := {"Face": 0, "L Hand": 0, "R Hand": 0, "tee_front": 0, "tee_back": 0, "green_arm_vertices": 0}
	var chest := (skeleton.get_bone_global_rest(_bone("Spine")).origin + skeleton.get_bone_global_rest(_bone("Spine2")).origin) * 0.5
	for record: Dictionary in records:
		if record["skin"] == null:
			continue
		var matrices := _bind_matrices(record, true)
		var vertices: PackedVector3Array = record["vertices"]
		for index: int in range(vertices.size()):
			var skinned := _skin_vertex(record, matrices, index)
			var expected: Vector3 = record["node"].global_transform * vertices[index]
			max_rest_error = maxf(max_rest_error, skinned.distance_to(expected))
			var point := skeleton.global_transform.affine_inverse() * skinned
			var weights := _semantic_weights(record, index)
			if record["material"] == "Face" and float(weights["head"]) > 0.5:
				counts["Face"] += 1
			if record["material"] == "Skin":
				for side: String in ["L", "R"]:
					if float(weights[side + " hand"]) > 0.5:
						counts[side + " Hand"] += 1
			if record["material"] == "GreenDenim" and float(weights["upper_limb"]) > 0.02:
				counts["green_arm_vertices"] += 1
			if record["material"] == "CottonTee" and absf(point.y - chest.y) < 0.06 and absf(point.x - chest.x) < 0.20:
				if point.z < chest.z - 0.02:
					counts["tee_front"] += 1
				if point.z > chest.z + 0.02:
					counts["tee_back"] += 1
	_check(max_rest_error < 0.004, "inverse-bind reconstruction matches rest mesh; error " + str(max_rest_error))
	_check(counts["Face"] >= 32, "face material covers actual head vertices")
	_check(counts["L Hand"] >= 32 and counts["R Hand"] >= 32, "both original skin hands remain")
	_check(counts["green_arm_vertices"] == 0, "shorts contain no retained green donor hands/arms")
	_check(counts["tee_front"] >= 8 and counts["tee_back"] >= 8, "shirt covers both front and back of chest")
	print("RIDER_REST_COVERAGE ", JSON.stringify(counts))


func _bind_matrices(record: Dictionary, rest: bool = false) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bind: int in range(record["bone_map"].size()):
		var bone: int = record["bone_map"][bind]
		var pose := skeleton.get_bone_global_rest(bone) if rest else skeleton.get_bone_global_pose(bone)
		result.append(skeleton.global_transform * pose * record["inverse_binds"][bind])
	return result


func _skin_vertex(record: Dictionary, matrices: Array[Transform3D], index: int) -> Vector3:
	var vertex: Vector3 = record["vertices"][index]
	if record["skin"] == null:
		return record["node"].global_transform * vertex
	var result := Vector3.ZERO
	for influence: int in range(record["stride"]):
		var slot: int = index * record["stride"] + influence
		var weight: float = record["weights"][slot]
		if weight > 0.00001:
			result += (matrices[record["joints"][slot]] * vertex) * weight
	return result


func _semantic_weights(record: Dictionary, index: int) -> Dictionary:
	var result := {"L": 0.0, "R": 0.0, "L hand": 0.0, "R hand": 0.0, "head": 0.0, "upper_limb": 0.0}
	for influence: int in range(record["stride"]):
		var slot: int = index * record["stride"] + influence
		var weight: float = record["weights"][slot]
		if weight <= 0.00001:
			continue
		var bone: int = record["bone_map"][record["joints"][slot]]
		var name := str(skeleton.get_bone_name(bone)).replace("_", " ")
		for side: String in ["L", "R"]:
			if name.begins_with("Bip01 " + side + " "):
				result[side] += weight
				if name.contains("Hand") or name.contains("Finger"):
					result[side + " hand"] += weight
		if name.contains("Head"):
			result["head"] += weight
		if name.contains("Hand") or name.contains("Finger") or name.contains("Forearm") or name.contains("UpperArm") or name.contains("Head"):
			result["upper_limb"] += weight
	return result


func _validate_bounds(context: String, left_planted: bool) -> void:
	var bounds := AABB()
	var first := true
	var soles := {"L": INF, "R": INF}
	var board_inverse := board.global_transform.affine_inverse()
	for record: Dictionary in records:
		var matrices: Array[Transform3D] = []
		if record["skin"] != null:
			matrices = _bind_matrices(record)
		var vertices: PackedVector3Array = record["vertices"]
		for index: int in range(vertices.size()):
			var point := _skin_vertex(record, matrices, index)
			_check(point.is_finite(), "finite deformed vertices: " + str(record["node"].name))
			bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
			first = false
			if record["material"] == "CanvasSneakers":
				var weights := _semantic_weights(record, index)
				var local := board_inverse * point
				for side: String in ["L", "R"]:
					if float(weights[side]) > 0.75:
						soles[side] = minf(soles[side], local.y)
	_check(not first and bounds.end.y <= 1.80, "posed height <= 1.80 m in " + context + ": " + str(bounds))
	_check(bounds.position.y >= -0.035, "skin/wheels stay above road in " + context + ": " + str(bounds.position.y))
	_check(bounds.size.x <= 1.8 and bounds.size.z <= 1.8, "no exploded donor limbs in " + context + ": " + str(bounds.size))
	# Grip is 0.168 m in the standing area: 25 mm below / 45 mm above allows
	# sole tread and truck lean while detecting floating feet or deck clipping.
	_check(soles["R"] >= 0.143 and soles["R"] <= 0.213, "right/front sole contacts deck in " + context + ": " + str(soles["R"]))
	if left_planted:
		_check(soles["L"] >= 0.143 and soles["L"] <= 0.213, "left/rear sole contacts deck in " + context + ": " + str(soles["L"]))
	else:
		_check(soles["L"] >= -0.025 and soles["L"] <= 0.23, "push sole between road and deck in " + context + ": " + str(soles["L"]))
	bounds_samples += 1
	if context.begins_with("pose "):
		print("RIDER_POSED_BOUNDS ", context, " ", bounds, " soles=", soles)


func _check_foot_bones(left_planted: bool) -> void:
	for side: String in ["L", "R"]:
		var point: Vector3 = board.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(_bone(side + " Foot")).origin)
		if side == "R" or left_planted:
			_check(absf(point.x) <= 0.14 and absf(point.z) <= 0.48 and point.y >= 0.20 and point.y <= 0.35,
				"planted foot bone above board: " + side)
			_check(point.z < -0.10 if side == "R" else point.z > 0.10, "uncrossed front/rear foot assignment: " + side)


func _bone(suffix: String) -> int:
	var index := skeleton.find_bone("Bip01 " + suffix)
	return skeleton.find_bone(("Bip01 " + suffix).replace(" ", "_")) if index < 0 else index


func _check(condition: bool, description: String) -> void:
	if not condition and not failures.has(description) and failures.size() < 40:
		failures.append(description)


func _finish() -> void:
	if not failures.is_empty():
		for failure: String in failures:
			printerr("RIDER_PROBE_FAILED " + failure)
		quit(1)
		return
	print("RIDER_PROBE_OK: anatomical GLB, four distinct poses, valid inverse-bind skinning, complete materials, 600 finite frames, preserved limbs and grounded feet")
	quit(0)
